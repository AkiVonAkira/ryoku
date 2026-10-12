#!/usr/bin/env bash
# hermetic test for ryoku-wayland-session, the SDDM [Wayland] SessionCommand
# wrapper that prepares graphics before the session compositor starts.
#
# Nothing here starts weston or a compositor. A fake pgrep on PATH reports weston
# "present" for a controlled number of polls, a fake session records its argv and
# render environment, and RYOKU_DRI_DIR supplies KMS-only and accelerated DRM
# fixtures.
#
# The load-bearing assertions: the wrapper does NOT hand off while weston is
# still present, always hands off eventually (login never hangs), passes the
# session arguments through untouched, and selects llvmpipe only when a DRM card
# has no render node.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
wrapper="$here/../ryoku/lockscreen/sddm/ryoku-wayland-session"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
fail() { echo "FAIL: $1" >&2; exit 1; }

bin="$tmp/bin"; mkdir -p "$bin"

# fake pgrep: reports weston present until it has been polled "$tmp/pglimit"
# times, then gone. Every call bumps "$tmp/pgcount" so the test can see whether
# the wrapper actually waited.
cat >"$bin/pgrep" <<EOF
#!/bin/sh
c=\$(cat "$tmp/pgcount" 2>/dev/null || echo 0); c=\$((c + 1)); echo "\$c" >"$tmp/pgcount"
limit=\$(cat "$tmp/pglimit" 2>/dev/null || echo 0)
[ "\$c" -le "\$limit" ] && exit 0   # weston present
exit 1                              # weston gone
EOF
chmod +x "$bin/pgrep"
export PATH="$bin:$PATH"

# fake session: records the arguments it was handed and that it ran at all.
cat >"$bin/fake-session" <<EOF
#!/bin/sh
printf '%s' "\$*" >"$tmp/session-args"
{
  printf 'LIBGL_ALWAYS_SOFTWARE=%s\n' "\${LIBGL_ALWAYS_SOFTWARE:-}"
  printf 'MESA_LOADER_DRIVER_OVERRIDE=%s\n' "\${MESA_LOADER_DRIVER_OVERRIDE:-}"
  printf 'GALLIUM_DRIVER=%s\n' "\${GALLIUM_DRIVER:-}"
  printf 'WLR_RENDERER_ALLOW_SOFTWARE=%s\n' "\${WLR_RENDERER_ALLOW_SOFTWARE:-}"
} >"$tmp/session-env"
: >"$tmp/session-ran"
EOF
chmod +x "$bin/fake-session"
export RYOKU_WAYLAND_SESSION_DEFAULT="$bin/fake-session"

reset() { rm -f "$tmp/pgcount" "$tmp/session-ran" "$tmp/session-args" "$tmp/session-env"; }
polls() { cat "$tmp/pgcount" 2>/dev/null || echo 0; }
env_value() { sed -n "s/^$1=//p" "$tmp/session-env"; }

# ---- greeter still up: wait for it, then hand off with args intact -----------
reset
echo 3 >"$tmp/pglimit"   # weston present for the first three polls
RYOKU_SESSION_SETTLE_DEADLINE=10 "$wrapper" Hyprland --foo
[[ -e "$tmp/session-ran" ]] || fail "wrapper never handed off to the session"
[[ "$(cat "$tmp/session-args")" == "Hyprland --foo" ]] \
  || fail "session arguments were not passed through: '$(cat "$tmp/session-args")'"
(( "$(polls)" >= 2 )) || fail "wrapper handed off without waiting for weston (polled $(polls)x)"

# ---- no greeter: hand off at once, no wasted polling -------------------------
reset
echo 0 >"$tmp/pglimit"   # weston already gone
"$wrapper" Hyprland
[[ -e "$tmp/session-ran" ]] || fail "wrapper did not hand off when weston was absent"
(( "$(polls)" == 1 )) || fail "wrapper polled $(polls)x when weston was already gone; expected 1"

# ---- KMS-only card: force Mesa's software GBM path before compositor start ---
dri_2d="$tmp/dri-2d"
mkdir -p "$dri_2d"
: >"$dri_2d/card0"
reset
echo 0 >"$tmp/pglimit"
env -u LIBGL_ALWAYS_SOFTWARE -u MESA_LOADER_DRIVER_OVERRIDE \
  -u GALLIUM_DRIVER -u WLR_RENDERER_ALLOW_SOFTWARE \
  RYOKU_DRI_DIR="$dri_2d" "$wrapper" niri-session
[[ "$(env_value LIBGL_ALWAYS_SOFTWARE)" == 1 ]] \
  || fail "2D-only DRM card did not select software GL"
[[ "$(env_value MESA_LOADER_DRIVER_OVERRIDE)" == llvmpipe ]] \
  || fail "2D-only DRM card did not select Mesa llvmpipe"
[[ "$(env_value GALLIUM_DRIVER)" == llvmpipe ]] \
  || fail "2D-only DRM card did not select the Gallium llvmpipe driver"
[[ "$(env_value WLR_RENDERER_ALLOW_SOFTWARE)" == 1 ]] \
  || fail "2D-only DRM card did not allow a software compositor renderer"

# ---- render node: keep VM 3D acceleration instead of forcing llvmpipe --------
dri_3d="$tmp/dri-3d"
mkdir -p "$dri_3d"
: >"$dri_3d/card0"
: >"$dri_3d/renderD128"
reset
echo 0 >"$tmp/pglimit"
env -u LIBGL_ALWAYS_SOFTWARE -u MESA_LOADER_DRIVER_OVERRIDE \
  -u GALLIUM_DRIVER -u WLR_RENDERER_ALLOW_SOFTWARE \
  RYOKU_DRI_DIR="$dri_3d" "$wrapper" niri-session
[[ -z "$(env_value LIBGL_ALWAYS_SOFTWARE)" ]] \
  || fail "render-capable VM was forced onto software GL"
[[ -z "$(env_value MESA_LOADER_DRIVER_OVERRIDE)" ]] \
  || fail "render-capable VM was forced onto llvmpipe"

# ---- no DRM card: leave the environment alone; software cannot create KMS ----
dri_empty="$tmp/dri-empty"
mkdir -p "$dri_empty"
reset
echo 0 >"$tmp/pglimit"
env -u LIBGL_ALWAYS_SOFTWARE -u MESA_LOADER_DRIVER_OVERRIDE \
  -u GALLIUM_DRIVER -u WLR_RENDERER_ALLOW_SOFTWARE \
  RYOKU_DRI_DIR="$dri_empty" "$wrapper" Hyprland
[[ -z "$(env_value LIBGL_ALWAYS_SOFTWARE)" ]] \
  || fail "a machine with no KMS card was forced onto software GL"

# ---- greeter never exits: the deadline caps the wait so login never hangs ----
reset
echo 100000 >"$tmp/pglimit"   # weston "present" forever
start=$SECONDS
RYOKU_SESSION_SETTLE_DEADLINE=1 "$wrapper" Hyprland
[[ -e "$tmp/session-ran" ]] || fail "wrapper hung on a greeter that never exits (must cap and hand off)"
(( SECONDS - start <= 4 )) || fail "wrapper waited past its deadline"

echo "wayland-session-settle: all checks passed"
