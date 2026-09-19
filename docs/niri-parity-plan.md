# Niri parity & frame-budget plan

Tracks the Ambxst 1.3.6 / axctl comparison findings (2026-09-19). Each item
lists its phases and a status line; update the status as work lands.
Reference repo lives at /tmp/ambxst and /tmp/axctl.

## A1 - Gate the overview backdrop blur to the open overview  [done]

The backdrop surface blurred a full-screen wallpaper every frame while enabled
(`ryoku/shell/quickshell/shell/modules/wallpaper/OverviewBackdrop.qml`); niri
only reveals it during the overview. Ambxst fixed exactly this by driving the
blur from `OverviewOpenedOrClosed` (`/tmp/ambxst Wallpaper.qml:46-52`).

- [x] P1 seam: fold `OverviewOpenedOrClosed` in `ryoku/wm/niri/watch.go` into a
      typed `FrameOverview` (new kind in `ryoku/wm/state.go`); `watch_test.go`
      pins the fold and the narrowed-watch skip.
- [x] P2 daemon: cache `wmOverview` + publish `overviewOpen` on the wm topic
      (`ryoku/shell/ipc/wmclient.go`); `wmclient_test.go` pins the fold; all
      five vendored `state.go` copies re-synced.
- [x] P3 QML: `Wm.overviewOpen` in `ryoku/ui/Singletons/Wm.qml`; the backdrop
      keeps its `MultiEffect` mounted but drives `blur` from the live state so
      the pass eases in/out through niri's own animation (a `Loader` remount
      would pop a fresh render target at the worst instant). Surface stays
      mapped so the backdrop is ready the moment the overview lifts.
- [x] P4 prove: live niri 26.04 - `ryoku-wm-niri watch overview` against the
      real socket replayed `{"kind":"overview"}` on connect, then
      `{"kind":"overview","overviewOpen":true}` on ToggleOverview and cleared
      on close. qmllint clean on the touched shell + ui roots.

## A2 - Typed delta frames end-to-end (kill the whole-desktop rebind)

Every provider frame currently replaces one monolithic `_frame`
(`ryoku/ui/Singletons/Wm.qml:224-231`) and the daemon coalesces all state into
one publish (`wmclient.go:68-121`), so a title keystroke rebinds workspaces,
dock, focus feeds. axctl broadcasts typed events; consumers subscribe per kind.

- [ ] P1 daemon: publish per-kind frames (kind + only the fields that kind
      owns); keep the first `ready` frame full.
- [ ] P2 Wm.qml: split `_frame` into `_windows/_workspaces/_focus/_outputs/
      _keyboard` merged per kind; derived lists depend only on their inputs.
- [ ] P3 audit consumers: any component reading `Wm.*` inside a binding that
      re-evaluates on unrelated kinds gets fixed with the narrower property.
- [ ] P4 prove: `qs -p` harness or live session - count binding re-evaluations
      (console.log probe) before/after a focus change.

## A3 - End the subprocess-per-second polls

`sh -c` timers in the shell's event loop: wifi `nmcli` 1.2s, mic `wpctl` 0.6s,
nightlight `pgrep` 2s (`ryoku/shell/quickshell/shell/services/Toggles.qml:24-61`),
`StatsFeed` 1.5s incl. `nvidia-smi` (`StatsFeed.qml:142-176`), `Sysinfo` 1.5s.
Ambxst owns all of this in the Go daemon with push subscriptions.

- [ ] P1 wifi: the daemon already speaks NetworkManager
      (`ryoku/shell/ipc/network.go`) - expose radio state on a topic and make
      `Toggles.qml` subscribe instead of polling `nmcli`.
- [ ] P2 mic: daemon-side PipeWire watch (Wp/pactl event or a long-lived
      `wpctl events` process) publishing mute state; shell subscribes.
- [ ] P3 nightlight: publish the hyprsunset unit's active state from the
      daemon's systemd watch (or ride `Toggles` off a one-shot + toggle echo).
- [ ] P4 stats: FileViews on `/sys` (`gpu_busy_percent`, hwmon) where present;
      `nvidia-smi` only when sysfs lacks the value, and slower (>=5s) or
      daemon-owned; fans via sysfs FileView.
- [ ] P5 prove: `pidstat`/strace count of `sh` forks by ryoku-shell before/
      after during 60s idle.

## B1 - Super-alone opens the overview (niri)

niri binds on press only, so press-Super-to-open-overview needs a modifier
state machine. We already have both halves: `keypress.go:352-359` emits
standalone-modifier taps, and `ActionOverviewToggle` exists
(`ryoku/wm/niri/act.go:173`). axctl wrote `pkg/keymon` for exactly this.

- [ ] P1 wire: tap("Super") in the shell's `Keypresses` feed triggers
      `Wm.act(overviewToggle)` (capability-gated; Hyprland keeps its own).
- [ ] P2 UX: debounce so a Super+letter chord never fires the tap (verify the
      existing `used` flag covers chords); ignore repeat.
- [ ] P3 prove: live niri - tap Super, overview opens; hold Super and press a
      bind, overview does NOT open.

## B2 - Gaming mode reaches niri

The Hub performance/gaming page is Hyprland-parsed
(`ryoku/hub/quickshell/pages/PerformancePage.qml:33`); under niri it is dead
config (known decision memory). Ambxst normalizes every rendered compositor
config through a game-mode flag that strips animations/blur/borders on both
compositors (`/tmp/ambxst backend/pkg/svc/compositor/toml.go:61-78`).

- [ ] P1 provider: niri settings schema gains the perf knobs (animations
      enabled, blur disabled, borders) written through the existing KDL apply;
      validate with `niri check`.
- [ ] P2 Hub: gate the Performance page rows by capability so niri users get
      the real subset instead of dead toggles.
- [ ] P3 shell: a live "perf" flag (from the same store) unmounts shell-side
      blur/particle/animation surfaces while gaming mode is on.
- [ ] P4 prove: live niri - toggle gaming mode, diff `niri` config + observe
      animations off; shell blur surfaces gone.

## B3 - File chooser under niri (probe first)

User report: "file selection doesn't open in some areas". We route niri to
`xdg-desktop-portal-gnome` (`release/packages/ryoku-desktop-niri/PKGBUILD:31`)
and restart the portal stack at session start (`ryoku/niri/autostart.kdl:32`).
Ambxst ships no portal work - hypothesis, not measured cause.

- [ ] P1 probe: live niri - open the file picker from Firefox, Thunar,
      Chromium, Electron, kitty `nnn`; record which fail and what
      `xdg-desktop-portal` logs (per-app: portal routing, `GTK_USE_PORTAL`).
- [ ] P2 fix: likely per-interface routing (`choose` config: FileChooser ->
      gtk backend) shipped via the niri variant config + a doctor reconciler;
      or fix the gnome backend's session-type detection.
- [ ] P3 prove: every app from P1 opens a picker; screencast still routes to
      the gnome portal (recording must not regress).

## Verification gate (all items)

- `go test` per module; `bin/ryoku-dev-verify-wm-vendor` after any `ryoku/wm`
  change; shellcheck on touched scripts; live niri session probes via
  `ryoku-live-verify`/`verify-ryoku-niri-desktop-with-input-and-grim` skills.
- One commit per item with a `Note:` trailer; push to unstable-dev only after
  its prove phase is green.
