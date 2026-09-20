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
- [x] P1 fix: a `restore` verb re-asserts the stored off, and a config module
      calls it on `hyprland.start` and `config.reloaded`.
- [x] P2 prove: `tests/touchpad-restore.sh` (silent no-op with no state, flips
      only the touchpad, honest no-op without the live-toggle capability).
- [x] P3 ship: committed, pushed, issue closed.

## 218 - Lockscreen dies on uinput hotplug; daemon did not restart the shell - investigate

On stable 0.63.1 the shell aborted (SIGSEGV/SI_TKILL inside a QML
Repeater/Loader regeneration, five seconds after RustDesk created uinput
devices) and never came back, leaving the session un-unlockable. Two halves:

Audit on the current build (unstable-dev), this box:
- [x] P1 respawn: the daemon DOES respawn a crashed `qs -c shell`. Sent
      SIGSEGV to the live shell (pid 3248518); the supervisor brought back a
      new one (pid 3904070) in 4s. stable 0.63.1's supervise loop is
      byte-identical, and the synchronous keypress.configure on the respawn
      path only cancels a context + a local publish (cannot block), so the
      "daemon never restarted the shell" half does not reproduce on this code
      and its cause is unproven (the daemon itself being wedged is the only
      candidate left). The lock CLIENT is the process that genuinely had no
      supervisor: see P2.
- [x] P2 re-lock: the real remaining defect. `lockSession` spawned qylock and
      discarded its exit (fire-and-reap), so a locker that dies by signal
      leaves Hyprland failed-closed at "lockscreen app died :(" with nothing
      to authenticate against - the brick. The reaper is now a supervisor: a
      clean exit 0 (an unlock) stays down, a signal death re-locks, bounded to
      `lockRetries` inside `lockRetryWindow` so a crash loop gives up rather
      than spins. Tests: TestSuperviseLockerRelocksOnCrash / StaysDownOnUnlock.
- [x] P3 abort root cause: the crash frame is `QQuickLoader.setActive ->
      QQuickRepeater.regenerate -> abort` from a QML signal handler, five
      seconds after RustDesk created uinput devices. No shell surface binds a
      Repeater to a live input-device list (the Audio.qml settled-snapshot
      rule holds everywhere); the abort is quickshell/Qt treating a QML create
      error as fatal. That is an upstream defect we cannot fix in QML and
      cannot reproduce without bricking the session. Our side is hardened: the
      crash now self-heals (respawn) and the lock comes back (P2).
- [ ] P4 respond with findings; leave open for the upstream report.

## 215 - Hidden Wi-Fi network support - build (feature)

The deck's Wi-Fi page lists APs; a hidden SSID never appears. NetworkManager
supports it (`wifi.hidden` in the profile; `nmcli device wifi connect …
hidden yes`). The daemon already owns NM (`ryoku/shell/ipc/network.go`).

- [x] P1 daemon: `network.wifiConnect` takes `hidden`; a fresh profile carries
      `802-11-wireless.hidden=true` (no AP resolves, so no band pin).
- [x] P2 QML: a "Connect to a hidden network" form on all four live Wi-Fi
      surfaces (qsbar NetworkPanel = the shipped default, the framebar
      MenuNetwork, the popout NetworkPopout, kairos WifiPage), each opening
      SSID + optional password fields and joining through the intent.
- [x] P3 prove: `TestWifiConnectSettings` pins the `hidden` shape (open and
      WPA2 hidden); all four surfaces pass qmllint with no syntax/property
      errors; the daemon's full `go test` suite is green. A live join needs a
      hidden AP, which this box cannot offer.
- [x] P4 ship: `cab7f6ca2`, pushed, issue closed.

## 214 - CachyOS prebuilt NVIDIA modules ignored by the driver setup - build

Confirmed in `system/hardware/drivers/nvidia.sh`: only the exact pkgbase
`linux` got the prebuilt `nvidia-open`; every other kernel (including
`linux-cachyos`, whose repo ships `linux-cachyos-nvidia-open`) fell to
`nvidia-open-dkms` and a per-kernel compile.

- [x] P1 fix: `prebuilt_for <pkgbase>` maps stock `linux` to `nvidia-open`
      and any other kernel to `<pkgbase>-nvidia-open`, but only when a
      synced repo actually carries that package (the query rides the same
      pacman config the install uses); DKMS stays the fallback for a kernel
      nothing publishes for.
- [x] P2 prove: `tests/nvidia-driver-selection.sh` gained an RTX 2070 SUPER
      CachyOS case (selects `linux-cachyos-nvidia-open`) and a custom-kernel
      case (still falls to `nvidia-open-dkms`); shellcheck clean.
- [x] P3 ship: `108919071`, pushed, issue closed.

## 212 - Power profile stuck on performance - respond

The paste shows the real cause: `powerprofilesctl set balanced` fails in
`intel_pstate` with EBUSY writing `energy_performance_preference` ("Device or
resource busy") - a kernel/driver contention, not the Ryoku fold. Ryoku's
daemon follows ppd's own active profile, so it honestly reports what ppd
holds. Needs the reporter's kernel version and whether a plain
`sudo systemctl restart power-profiles-daemon` (which they found) is enough
to unstick it; if it recurs on current kernels, it is an intel_pstate bug to
point them at.

- [x] P1 responded with the pinned mechanism (intel_pstate locks EPP while a
      policy sits on the `performance` governor; ppd re-forces powersave only
      at probe, hence the restart cure) + four separating questions (live
      governor readback, whether the Hub CPU page's governor knob was ever
      set, battery-only Dell quirk, current unstable). Left open for reply.

## 199 - Brightness/volume not restored after reboot - investigate

Two halves. Brightness: the compositor/udev sets the level at boot; a
persisted user level should be re-applied at session start (we own
`ryoku-hw-backlight`). Volume-per-device: PipeWire's role/card-volume
storage should already do this; a headset resetting to 90 on reconnect is
usually the device's own USB HID volume, which pw cannot override.

- [x] P1 fix: the brightness OSD watcher (the one place every writer
      converges, both compositors) now saves the panel's writable
      `brightness` attribute on every change and re-applies it before its
      first read at session start; range-guarded, write-refusal-safe.
      `TestBacklight*` pins the round trip; live proof on this box: set 40%
      -> reset device to max with the daemon down -> restart -> panel back
      at 40%.
- [x] P2 respond: brightness half fixed and shipped; volume half is the
      USB headset's own hardware volume (WirePlumber restore-stream already
      persists per-device volumes; snd-usb-audio resets the device's on
      reconnect, which the desktop cannot override). Commented, closed.

## 201 - Wallpaper transition tears a patch of the previous image (Iris / Inkwell Drop) - build

Reporter is 1920x1080 60Hz AMD iGPU; the maintainer could not reproduce at
2560x1600. The transition shaders (ryostage / livewall) may sample the old
texture beyond its geometry on some aspect ratios, or the poster-frame path
regressed for those two transitions specifically.

- [x] P1 root cause: the reveal ShaderEffect is the surface's persistent
      painter, so at rest (progress 0) it must show the committed image.
      Three circular-reveal presets (iris, inkwell-drop, ink-splash) start
      their front at the centre/impact point, so their feathered edge straddles
      that point at progress 0 and blends toward newTex -- the stale buffer
      still holding the previous wallpaper -- freezing a patch after every
      switch. Not resolution- or driver-dependent (the maintainer's 0.2% centre
      disc sat under the clock/bar noise floor in the sweep).
- [x] P2 fix: each paints oldTex and returns while progress is 0; the reversed
      smoothsteps (edge0 > edge1, undefined in GLSL) rewritten as the
      conforming descending ramp. Proven by a faithful CPU model of the
      fragment maths: iris centre 125/255 -> 0, circle still animates.
      `9f8a8a104`, shipped, issue closed.

## 208 - "update issue" with no failure output - blocked on reporter

Maintainer already asked for the printed failure before the summary line.
Nothing to do until they reply.

- [ ] P1 leave open; no action.

## 196 / 193 - Ryotunes resize stutter / blank pages under Reduce motion - build (client repo)

Both live in the ryotunes client (`ryoku-dev/ryotunes`, issues disabled there
so they were filed in the arch repo). I have ADMIN on it and fixed both in the
client, which cuts its own releases.

- [x] P1 #193: the page-stack enter is a ParallelAnimation of OpacityAnimator +
      YAnimator timed by `Tokens.durFastEffects`, which zeroes under Reduce
      motion; a zero-duration render-thread Animator never applies `to`, so
      pageStack stranded at opacity 0. `reenter()` lands the end state when the
      duration is 0. Client commit `32f564e`, released v1.0.7.
- [x] P2 #196: the now-playing cover sized from the column's assigned width and
      the body's assigned height (layout outputs) fed back into preferred
      sizes -- the `polish() inside updatePolish()` loop. Resized from the root
      + header implicit height (inputs), pixel-identical. Client commit
      `a8ab3d6`, releasing v1.0.8.

## 187 - Wallpaper Engine support - in flight by design

Maintainer already stated it is unfinished and deliberately open.

- [ ] P1 no action.

## 176 - Whole-system freeze on brightness change - build (reclassified from external)

The reporter (simplyamir) later pinned three concrete Ryoku defects with
evidence, so this is largely ours, not a kernel hang:
1. `ryoku-cmd-brightness` ran `ddcutil detect` on every keypress with no
   connector gate -- the 28-bus i2c walk that froze the session (the same
   stall 755ed028 gated out of the sidebar). Fixed: gate on a connected
   non-panel connector (sysfs read), and cache the bus list per dock set so a
   docked user does not re-walk every press. `ea8898593` + `f87763d61`.
   Proven live: old script walked i2c once, new walks zero on my panel-only box.
2. `acpi_backlight=native` freezes the panel on the ASUS FA507NV (EC-driven).
   Fixed: a DMI board denylist that skips the quirk and removes a drop-in an
   earlier release wrongly added. `278af7352`.
3. The OSD published `actual_brightness/max` (nonlinear on amdgpu's custom
   curve -> 7-88% for a 1-100% request). Fixed: publish/save the linear
   `brightness`. `0066b4e58`. Proven live: 50% request now reads 50%, not 25%.
   Plus: the daemon watcher picked the first /sys/class/backlight entry, not
   ryoku-hw-backlight's connected-panel pick -- unified (`83b083f1f`).
- [x] P1 all four fixed, tested, pushed to unstable-dev.
- [ ] P2 respond with the four fixes and ask them to confirm on the FA507NV
      once the next unstable lands; the board denylist is one data point, so a
      second FA507NV owner or a report that native is wrong elsewhere would
      widen it.

## Verification gate (all items)

- Python: throwaway HOME runs for 211; `shellcheck -x` on touched scripts;
  `go test` for the daemon (215); live nested-session probes where the fix
  is behavioural (207, 218).
- Each fix: one commit with a `Note:` trailer, pushed to unstable-dev, then
  the issue commented and closed pointing at the next release.
