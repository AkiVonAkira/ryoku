#!/usr/bin/env bash
# Regression test for ryoku-cmd-brightness: the DDC/CI branch must not walk
# every i2c bus when no external monitor is connected. `ddcutil detect` is the
# freeze (#176): on a hybrid laptop it touches 28 i2c buses for over 11s, and
# i2c traffic on the display controller is what locks the whole session on a
# brightness keypress. Gate it on a connected non-panel DRM connector (a sysfs
# read), the same protection 755ed028 added to the sidebar but not to this key
# handler. RYOKU_DRM_PATH lets the connector set be faked.
set -euo pipefail

here="$(cd "$(dirname "$0")/.." && pwd)"
script="$here/ryoku/hyprland/scripts/ryoku-cmd-brightness"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# A fake ddcutil that records whether detect ran (the i2c walk).
mkdir -p "$tmp/bin"
cat >"$tmp/bin/ddcutil" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == detect ]]; then echo ran >"$DDC_RAN"; fi
exit 0
EOF
chmod +x "$tmp/bin/ddcutil"

# Fake the panel side too, so the test never touches a real backlight.
printf '#!/usr/bin/env bash\nexit 0\n' >"$tmp/bin/brightnessctl"
printf '#!/usr/bin/env bash\nexit 1\n' >"$tmp/bin/ryoku-hw-backlight"
chmod +x "$tmp/bin/brightnessctl" "$tmp/bin/ryoku-hw-backlight"

run_case() { # name -- sets up a connector set, runs the script, echoes ddc state
  local name="$1"
  : >"$tmp/ddc_ran"
  rm -rf "$tmp/drm"; mkdir -p "$tmp/drm"
  case "$name" in
    panel-only)
      mkdir -p "$tmp/drm/card0-eDP-1"; echo connected >"$tmp/drm/card0-eDP-1/status" ;;
    external)
      mkdir -p "$tmp/drm/card0-eDP-1" "$tmp/drm/card1-HDMI-A-1"
      echo connected >"$tmp/drm/card0-eDP-1/status"
      echo connected >"$tmp/drm/card1-HDMI-A-1/status" ;;
    disconnected-external)
      mkdir -p "$tmp/drm/card0-eDP-1" "$tmp/drm/card1-HDMI-A-1"
      echo connected >"$tmp/drm/card0-eDP-1/status"
      echo disconnected >"$tmp/drm/card1-HDMI-A-1/status" ;;
  esac
  PATH="$tmp/bin:$PATH" DDC_RAN="$tmp/ddc_ran" RYOKU_DRM_PATH="$tmp/drm" \
    "$script" +5 >/dev/null 2>&1 || true
  [[ -s "$tmp/ddc_ran" ]] && echo "ran" || echo "skipped"
}

got="$(run_case panel-only)"
[[ $got == skipped ]] || { echo "FAIL: panel-only walked i2c ($got); want skipped" >&2; exit 1; }

got="$(run_case disconnected-external)"
[[ $got == skipped ]] || { echo "FAIL: disconnected external walked i2c ($got); want skipped" >&2; exit 1; }

got="$(run_case external)"
[[ $got == ran ]] || { echo "FAIL: connected external did not walk i2c ($got); want ran" >&2; exit 1; }

echo "PASS: ryoku-cmd-brightness gates the i2c walk on a connected external"
