# Fedora edition

The Fedora edition installs Ryoku on mutable Fedora 44 or 45 Workstation, KDE
Plasma, Server, and spin systems, `x86_64`, with systemd and either Hyprland or
niri. Atomic and other rpm-ostree systems are refused. Use the same public
installer as the other existing-system editions:

```sh
curl -fsSL https://raw.githubusercontent.com/ryoku-dev/ryoku/main/ryoku-shell-installer/install.sh | bash
```

Before sudo or any system change, the installer requires repository metadata
for the selected channel and running Fedora release. If Ryoku does not publish
that release, it stops and prints the supported list from
`https://repo.ryoku.dev/stable/fedora/releases`. The installer uses dnf5 or
dnf, verifies and imports Ryoku's release key, writes the signed RPM repository,
and configures SDDM. It replaces GDM when present; KDE keeps its existing SDDM
greeter configuration by default.

Ryoku's repository carries the Fedora-compatible Arch desktop set, including a
Ryoku-built Quickshell 0.3 or newer, GPU Screen Recorder, GlazePKG, the Hyprland
plugins, skwd-paper, Ryotunes, fonts, cursors, controller support, and optional
apps. Package-restricted COPR repositories provide only the Hyprland stack,
starship, lazygit, and yazi packages Fedora 44 and 45 lack. The package
translation maps the desktop's power-profile dependency to `ppd-service`, so
Fedora's tuned-ppd and power-profiles-daemon providers both work and the
installer does not replace one with the other.

Release jobs prepare SRPMs from the shared tree, rebuild and sign the binary
RPMs and `repomd.xml`, install-test both desktops on Fedora 44 and 45, then
publish the tested repositories. They also publish the supported release list
at `stable/fedora/releases`. For Fedora release `<N>`, the public layout below
`https://repo.ryoku.dev/` is:

```text
stable/fedora/releases
stable/fedora/<N>/x86_64
stable/fedora/<N>/releases/<tag>/x86_64
stable/fedora/<N>/releases/index.json
stable/fedora/<N>/channels/testing/x86_64
stable/fedora/<N>/channels/testing/builds/<build>/x86_64
stable/fedora/<N>/channels/testing/index.json
```

The build name replaces `+` with `_` in the frozen directory. Public repository
directories contain signed binary RPMs, `repodata/`, the detached armored
`repomd.xml` signature, and `release.json`; SRPMs are not published.

Specs under `packages/rpm/` either stage the Ryoku tree or build upstream
projects. Upstream URL sources have checksum manifests under `sources/`; locked
Go and Cargo dependencies are vendored for offline rebuilds; verified
`fetch/` hooks supply sources that need custom preparation. A matching trusted
upstream RPM may be reused from the published repository after signature and
dependency checks. Ryoku-tree RPMs always rebuild.

`ryoku update`, `ryoku track`, and `ryoku rollback` use DNF. Update and doctor
say when Ryoku has not published the running Fedora release and leave the
installed Ryoku set in place. Frozen release and testing targets are retained
for package rollback, and the boot guard can downgrade the Ryoku set after a
failed update.

Fedora has no Ryoku ISO, snapshots, or snapshot boot menu because it keeps
GRUB. NVIDIA stays on nouveau. Wayfire is unavailable because Fedora ships
0.10.1 and Ryoku requires 0.11. AUR-only extras such as Zen Browser, LocalSend,
Voxtype, Looking Glass, and SteamCMD are not shipped in the Fedora lane.
