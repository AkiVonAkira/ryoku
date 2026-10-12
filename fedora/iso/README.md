# Ryoku Fedora ISO (experimental)

The Fedora image boots straight into the same graphical installer as the Arch
and Void images. Before setup starts, it shows a short `Ryoku on Fedora` note.
The image is a minimal Fedora 44 live system with no desktop of its own. It is
built locally only: no workflow publishes it, the release ledgers carry no
Fedora images, and it has not been boot-tested yet.

`build.sh` stages the shared installer, builds its static TUI, stages the
Fedora backend (`backend/`) with the shared backend libraries, and runs kiwi-ng
in the official `fedora:44` container against the `kiwi/` image description.
The container installs the latest kiwi from Fedora's `updates` repository and
prints its version to the build log. Build from a Ryoku checkout:

```sh
RYOKU_FEDORA_ISO_WORK=/tmp/ryoku-fedora-iso \
RYOKU_FEDORA_ISO_OUT="$PWD/fedora/iso/out" \
RYOKU_FEDORA_ISO_WORKTREE=1 \
  fedora/iso/build.sh
```

| Variable | Default | Meaning |
|---|---|---|
| `RYOKU_FEDORA_ISO_CHANNEL` | `testing` | Ryoku channel the image and the installed system use (`stable` or `testing`). Testing until `stable/fedora/44` is published. |
| `RYOKU_FEDORA_ISO_RYOKU_REPO` | the channel's repository | Override the Ryoku RPM repository used for the image. |
| `RYOKU_FEDORA_ISO_WORKTREE` | `0` | `1` bakes tracked and untracked, non-ignored working-tree files into the payload. |
| `RYOKU_FEDORA_ISO_WORK`, `_OUT`, `_STAGE` | under `fedora/iso/` | Work, output and staging directories. |
| `RYOKU_FEDORA_ISO_IMAGE` | `registry.fedoraproject.org/fedora:44` | Build container image. |
| `RYOKU_CONTAINER_ENGINE` | `docker` | Set to `podman` to use Podman. The build runs privileged. |

`--stage-only` stops after preparing the image description. The result is
`out/ryoku-fedora-<version>-x86_64.iso` plus `out/SHA256SUMS`.

## Install contract

- **Online only.** The image carries no package repository. The backend checks
  DNS, the Ryoku repository and the Fedora metalink before touching the disk,
  then installs with `dnf5 --installroot`: `@core`, the kernel, shim and GRUB,
  then the same `desktop`-lane package plan the shell installer uses
  (`system/packages/resolve` with `fedora/packages/translations.tsv`).
- **UEFI only, Secure Boot on.** The live image and the installed system boot
  through Fedora's signed shim and GRUB, so Secure Boot can stay enabled.
  The ISO also starts on legacy BIOS, like Fedora's own live media, but the
  installer refuses to install there.
- **Disk.** Btrfs with the shared subvolume layout, including `@snapshots`
  mounted at `/.snapshots`. Optional LUKS2. Alongside another OS, Ryoku always
  creates its own ESP, because Fedora's shim and GRUB packages own `EFI/BOOT`
  and `EFI/fedora` on whatever ESP is mounted; `RYOKU_ESP_MODE=shared` is
  refused. GRUB's os-prober lists the other system.
- **Desktop.** Hyprland or niri. NVIDIA stays on nouveau, as on the converted
  Fedora edition. The first boot relabels SELinux and reboots once.

## Remaining limits

- No CI build or publishing, and no release-ledger images.
- No offline package repository.
- Snapshots: `@snapshots` exists, but snapper, the snapshot boot menu and
  rollback are not wired.
- The ASUS backlight fix writes a Limine setting only, so GRUB installs do not
  get it.
- The default browser is not set on Fedora installs.
