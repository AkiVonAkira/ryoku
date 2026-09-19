# Issue triage & build plan (2026-09-19)

Every open issue read with its full thread, cross-checked against the current
unstable-dev source and the served packages, then split into: build here (fix
landed in this repo), respond (needs reporter input or is external), or
by-design. One commit per fix with a `Note:` trailer; push only after the
item's prove phase is green. Ordered easiest to hardest.

## 211 - Material cursor never recolors (reads retired hypr.json) - build

Confirmed both bugs still present on unstable-dev:
`release/packages/ryoku-cursor-material/ryoku-cursor-material-recolor`
reads `~/.config/ryoku/hypr.json` (`.cursor.*`), but the store moved to
`desktop.json` (`.desktop.cursor.theme` / `.desktop.cursor.size`) and doctor
deletes hypr.json, so the matugen post-hook is a permanent no-op and a forced
recolor resets the size to 24. Second bug: `accent()` scans every argv token
through `hexval`, and `--full` is six characters, so `int("--",16)` raises
ValueError before the palette is even read - the documented escape hatch
crashes too.

- [x] P1 fix: read `desktop.json` `.desktop.cursor.{theme,size}`; the
      retired `material` key is dropped from stores by a doctor reconciler.
- [x] P2 fix: `accent()` skips `-`-prefixed tokens; a hex arg still overrides.
- [x] P3 prove: `tests/cursor-recolor.sh` (store shape, DYNAMIC role, flag
      scan, fallback) + Go tests in the seam, both providers, and doctor.
- [ ] P4 ship: commit, push, comment + close with the release note.

## 207 - Touchpad off-state not re-applied at boot - build

Reporter confirmed the maintainer's check: after a fresh boot
`ryoku-cmd-touchpad status` says "off" (the flag file) but the pad still
moves - the intended state is never pushed to the device at login.
- [ ] P1 fix: re-apply the flag at session start on both compositors'
      autostart (the script's own `restore`-style verb, mirroring
      nightlight's restore pattern), so the device matches the flag.
- [ ] P2 prove: nested-session or scripted check that the flip command runs
      with the flag set; status and device state agree after "boot".
- [ ] P3 ship: commit, push, comment + close.

## 218 - Lockscreen dies on uinput hotplug; daemon did not restart the shell - investigate

On stable 0.63.1 the shell aborted (SIGSEGV/SI_TKILL inside a QML
Repeater/Loader regeneration, five seconds after RustDesk created uinput
devices) and never came back, leaving the session un-unlockable. Two halves:

- [ ] P1 audit: does the current daemon supervisor (`ryoku/shell/ipc`
      ensure()/sup map, added after 0.63.1) actually respawn a crashed
      `qs -c shell`, and does the lock re-arm after the respawn? Test by
      killing the child on a nested session.
- [ ] P2 hunt: which surface rebuilds a Repeater on input-device change
      (the crash frame is a Loader->Repeater regenerate from a property
      binding); if it is ours, make the rebuild crash-safe (settled
      snapshots, the Audio.qml precedent).
- [ ] P3 decide: if the abort is a quickshell/Qt defect, harden our side
      (supervision + re-lock) and report upstream with the coredump trace.
- [ ] P4 ship/respond with findings either way.

## 215 - Hidden Wi-Fi network support - build (feature)

The deck's Wi-Fi page lists APs; a hidden SSID never appears. NetworkManager
supports it (`wifi.hidden` in the profile; `nmcli device wifi connect …
hidden yes`). The daemon already owns NM (`ryoku/shell/ipc/network.go`).

- [ ] P1 daemon: extend `network.wifiConnect` with a `hidden` flag (profile
      setting on create/update).
- [ ] P2 QML: a "Connect to hidden network" row on the Wi-Fi page opening
      SSID + security + password fields, calling the same intent.
- [ ] P3 prove: connect to a hidden AP on a test rig or unit-test the
      settings dict shape (`wifi.hidden=true`); live check if hardware allows.
- [ ] P4 ship.

## 214 - CachyOS prebuilt NVIDIA modules ignored by the driver setup - build

The reporter diagnosed the strict `uname -r == linux*` style check: on
`linux-cachyos` kernels the flow falls to `nvidia-open-dkms` instead of
`linux-cachyos-nvidia-open`. In `system/hardware/gpu/ryoku-gpu` (and the
installer's nvidia.sh path).

- [ ] P1 fix: map known distro kernels to their repo's prebuilt module
      packages (cachyos first: `linux-cachyos` -> `linux-cachyos-nvidia-open`
      / `linux-cachyos-nvidia` for Kepler-and-older), DKMS only as fallback.
- [ ] P2 prove: the resolver's kernel->package table unit-tested; dry-run on
      a cachyos-like uname string.
- [ ] P3 ship.

## 212 - Power profile stuck on performance - respond

The paste shows the real cause: `powerprofilesctl set balanced` fails in
`intel_pstate` with EBUSY writing `energy_performance_preference` ("Device or
resource busy") - a kernel/driver contention, not the Ryoku fold. Ryoku's
daemon follows ppd's own active profile, so it honestly reports what ppd
holds. Needs the reporter's kernel version and whether a plain
`sudo systemctl restart power-profiles-daemon` (which they found) is enough
to unstick it; if it recurs on current kernels, it is an intel_pstate bug to
point them at.

- [ ] P1 respond with the diagnosis + the two questions; leave open for their
      reply.

## 199 - Brightness/volume not restored after reboot - investigate

Two halves. Brightness: the compositor/udev sets the level at boot; a
persisted user level should be re-applied at session start (we own
`ryoku-hw-backlight`). Volume-per-device: PipeWire's role/card-volume
storage should already do this; a headset resetting to 90 on reconnect is
usually the device's own USB HID volume, which pw cannot override.

- [ ] P1 check: does anything persist + restore the backlight level across
      reboot on unstable-dev today? If not, add the restore to the boot path.
- [ ] P2 respond on the volume half (device-side volume, not ours) unless the
      brightness fix covers the report.

## 201 - Wallpaper transition tears a patch of the previous image (Iris / Inkwell Drop) - investigate

Reporter is 1920x1080 60Hz AMD iGPU; the maintainer could not reproduce at
2560x1600. The transition shaders (ryostage / livewall) may sample the old
texture beyond its geometry on some aspect ratios, or the poster-frame path
regressed for those two transitions specifically.

- [ ] P1 repro: run the Iris and Inkwell Drop transitions at 1920x1080 in a
      nested session or the livewall test rig; diff the shader's UV clamping.
- [ ] P2 fix if reproduced; else ask for a short screen recording of the
      first second of the transition.

## 208 - "update issue" with no failure output - blocked on reporter

Maintainer already asked for the printed failure before the summary line.
Nothing to do until they reply.

- [ ] P1 leave open; no action.

## 196 / 193 - Ryotunes resize stutter / blank pages under Reduce motion - external

The ryotunes QML client is not in this repo (shipped by the `ryotunes`
package). #193 carries a verified root cause (zero-duration OpacityAnimator
never applies its `to`) and a working patch; #196 is a polish() loop in
NowPlaying.qml.

- [ ] P1 respond pointing at the upstream client repo with the #193 fix
      (the reporter's patch is correct); confirm the ryotunes package source
      location and whether we vendor it.

## 187 - Wallpaper Engine support - in flight by design

Maintainer already stated it is unfinished and deliberately open.

- [ ] P1 no action.

## 206 - Sleep in the power menu - product call, community PR welcome

Maintainer ruled: raise in Discussions; open to a PR. Not ours to build
unasked.

- [ ] P1 no action.

## 176 - Whole-system freeze on brightness change - external

Full machine lockup (input + BT drop) on an RTX 5060: kernel/GPU driver
hang, not the OSD. Maintainer already asked for the previous-boot kernel
journal.

- [ ] P1 leave open for their kernel log; nothing in our code to fix.

## Verification gate (all items)

- Python: throwaway HOME runs for 211; `shellcheck -x` on touched scripts;
  `go test` for the daemon (215); live nested-session probes where the fix
  is behavioural (207, 218).
- Each fix: one commit with a `Note:` trailer, pushed to unstable-dev, then
  the issue commented and closed pointing at the next release.
