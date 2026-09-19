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

- [x] P1 wifi: the daemon already speaks NetworkManager
      (`ryoku/shell/ipc/network.go`) - `Toggles.qml` reads `Network.wifiRadio`
      and toggles through `network.wifiSetEnabled`; no nmcli probe.
- [x] P2 mic: Quickshell's Pipewire service is the live source the shell
      already owns (`Audio.source.audio.muted`); `Toggles.qml` binds it
      directly, so no daemon watch and no wpctl probe were needed.
- [x] P3 nightlight: the daemon publishes `nightlight` {on, temperature} from
      an inotify watch on the state dir plus a /proc comm scan (`nightlight.go`);
      `Toggles.qml` and the Hub's comfort page read the `Nightlight` view, and
      the intents ride `nightlight.toggle` / `nightlight.set`.
- [x] P4 stats: `Sysinfo.qml` reads /proc and hwmon through FileViews (the
      CPU-sensor zone resolves once at load); `StatsFeed.qml` resolves its
      sensor paths once at load, reads AMD busy/temp/power and the fan tacho
      through FileViews, and keeps nvidia-smi only on a 5s tick gated to the
      card being runtime-awake, with df at 30s.
- [x] P5 prove: the awake-gated pollers are gone from the QML sources
      (`Toggles.qml` has no Process at all; Sysinfo forks nothing per tick);
      the nightlight push path is covered end to end by
      `nightlight_watch_test.go` (toggle -> frame, temp change -> frame,
      toggle off -> frame) with a fake hyprsunset and a PATH-shimmed script.

## B1 - Super-alone opens the overview (niri)

niri binds on press only, so press-Super-to-open-overview needs a modifier
state machine. We already have both halves: `keypress.go:352-359` emits
standalone-modifier taps, and `ActionOverviewToggle` exists
(`ryoku/wm/niri/act.go:173`). axctl wrote `pkg/keymon` for exactly this.

- [x] P1 wire: `shell.qml` binds a standalone Super tap from the `Keypresses`
      feed to `toggleSurface("overview")`; the daemon keeps the reader alive
      for taps even with the visualiser off (`keypress.taps` claim, tap-only
      frames), and the claim is gated on `Wm.caps.nativeOverview` so Hyprland
      keeps its own binding and no reader runs there for taps.
- [x] P2 UX: the composer's existing `used` flag already suppresses a tap once
      any chord key is pressed (verified live: Super+R opened nothing); the
      shell consumer also drops `repeat` and non-tap states.
- [x] P3 prove: live niri - tapped Super, the overview opened (watch stream
      `overviewOpen:true` + screenshot); tapped again it closed; Super+R left
      it closed.

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
