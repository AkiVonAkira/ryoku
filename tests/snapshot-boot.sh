#!/usr/bin/env bash
# hermetic test for Fedora's snapshot boot menu (fedora/system/boot).
#
# case 1: the payload, the spec, the units and the CLI agree on names and
#         paths, and the snapper plugin touches /.snapshots only after a
#         snapshot is created or deleted.
# case 2: the initramfs look hook stacks a RAM overlay on the snapshot and
#         masks systemd-remount-fs for that boot.
# case 3: ryoku-grub-menu renders the snippet into grub.cfg once, and purge
#         drops the menu and its kernel copies.
# shellcheck disable=SC2329 # stubs and predicates run indirectly
# shellcheck disable=SC2016 # single-quoted patterns are literal file text

set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd -P)"
bm="$repo/fedora/system/boot"
mod="$bm/dracut/90ryoku-snapshot"
payload="$repo/fedora/packages/rpm/payload/ryoku-desktop.sh"
spec="$repo/fedora/packages/rpm/ryoku-desktop.spec"
cli="$repo/ryoku/cli/internal/updater/bootmenu.go"
restore="$repo/ryoku/cli/internal/updater/bootmenu_restore.go"
manifest="$repo/system/services/manifest.tsv"

work=$(mktemp -d /tmp/ryoku-snapshot-boot.XXXXXX)
trap 'rm -rf "$work"' EXIT

fail=0
ok() { printf 'ok   %s\n' "$1"; }
bad() { printf 'FAIL %s\n' "$1"; fail=1; }
check() { if "${@:2}"; then ok "$1"; else bad "$1"; fi; }
line() { grep -qxF -- "$2" "$1"; }
has() { grep -qF -- "$2" "$1"; }
absent() { [ ! -e "$1" ]; }

# case 1
for dest in \
  usr/bin/ryoku-grub-menu \
  etc/grub.d/42_ryoku_snapshots \
  usr/libexec/snapper/plugins/50-ryoku-boot-menu; do
  check "ryoku-desktop ships /$dest" has "$payload" "\"\$pkgdir/$dest\""
done
for unit in ryoku-snapshot-menu.service ryoku-snapshot-menu.path ryoku-snapshot-restored.service; do
  check "ryoku-desktop ships $unit" has "$payload" "$unit"
  check "$unit exists" test -f "$bm/$unit"
done
check "ryoku-desktop ships the dracut module" has "$payload" '"$pkgdir/usr/lib/dracut/modules.d/90ryoku-snapshot/$mod"'
check "%posttrans renders the snippet" has "$spec" "/usr/bin/ryoku-grub-menu install"
check "%posttrans lists the snapshots on disk and watches for more" has "$spec" \
  "systemctl start --no-block ryoku-snapshot-menu.path ryoku-snapshot-menu.service"
check "%preun disables the menu trigger" has "$spec" \
  "systemctl disable --now ryoku-snapshot-menu.path ryoku-snapshot-restored.service"
check "%preun drops the menu" has "$spec" "/usr/bin/ryoku-grub-menu purge"
check "%postun drops it from grub.cfg" has "$spec" "grub2-mkconfig -o /boot/grub2/grub.cfg"
check "Fedora's boot-success timer is left alone" test -z "$(grep -n 'grub-boot-success' "$spec")"
for dep in grub2-tools grubby btrfs-progs snapper dracut; do
  check "ryoku-desktop requires $dep" grep -qE "^Requires: +$dep\$" "$spec"
done
check "the manifest enables the menu trigger at boot" grep -qP '^snapshot-menu\tsystem\tboot\tryoku-snapshot-menu\.path\t' "$manifest"
check "the manifest enables the restore follow-up at boot" grep -qP '^snapshot-restored\tsystem\tboot\tryoku-snapshot-restored\.service\t' "$manifest"
check "the menu unit runs the CLI sync" line "$bm/ryoku-snapshot-menu.service" "ExecStart=/usr/bin/ryoku boot-menu sync"
check "the trigger watches /.snapshots" line "$bm/ryoku-snapshot-menu.path" "PathChanged=/.snapshots"
check "the trigger starts the menu unit" line "$bm/ryoku-snapshot-menu.path" "Unit=ryoku-snapshot-menu.service"
check "the plugin touches /.snapshots" has "$bm/snapper/50-ryoku-boot-menu" '${RYOKU_SNAPSHOTS_DIR:-/.snapshots}'
check "the CLI rescans until /.snapshots holds still" grep -q 'modTime(snapshotsDir).Equal(before)' "$cli"
check "the restored unit runs the CLI follow-up" line "$bm/ryoku-snapshot-restored.service" "ExecStart=/usr/bin/ryoku boot-menu restored"
check "the restored unit waits for the restore's flag" line "$bm/ryoku-snapshot-restored.service" \
  "ConditionPathExists=/var/lib/ryoku/snapshot-restored"
check "the CLI writes the flag the unit waits for" grep -q 'restoredFlag = "/var/lib/ryoku/snapshot-restored"' "$restore"
check "the CLI restores from the snapshot the look hook mounted" grep -q 'previewLower = "/run/ryoku/preview/lower"' "$restore"
check "the look hook mounts it there" has "$mod/ryoku-snapshot-preview.sh" 'base="$run/ryoku/preview"'
check "the CLI builds images with the shipped module" grep -q 'snapshotDracutMod *= "ryoku-snapshot"' "$cli"
check "the CLI detects the menu by the tool the package ships" grep -q 'snapshotMenuTool *= "/usr/bin/ryoku-grub-menu"' "$cli"
check "the snippet sources the file the CLI writes" has "$bm/grub/42_ryoku_snapshots" 'source "${config_directory}/ryoku-snapshots.cfg"'
check "the grub.d snippet renders" sh -c "sh '$bm/grub/42_ryoku_snapshots' | grep -q '^if \\[ -f '"
check "the module is only built in on request" grep -q '^  return 255$' "$mod/module-setup.sh"
check "the module has no unattended restore" test ! -e "$mod/ryoku-snapshot-restore.sh"

plugin() { RYOKU_SNAPSHOTS_DIR="$work/snapshots" sh "$bm/snapper/50-ryoku-boot-menu" "$1" / btrfs 42; }
touched() { test "$(stat -c %Y "$work/snapshots")" != 0; }
mkdir "$work/snapshots" && touch -d @0 "$work/snapshots"
for event in create-snapshot-pre modify-snapshot-post create-config; do
  plugin "$event"
done
check "the plugin leaves /.snapshots alone before or besides a snapshot" test "$(stat -c %Y "$work/snapshots")" = 0
plugin create-snapshot-post
check "the plugin touches /.snapshots after a snapshot is created" touched
touch -d @0 "$work/snapshots"
plugin delete-snapshot-post
check "the plugin touches /.snapshots after a snapshot is deleted" touched
check "the plugin never starts a unit, which SELinux denies snapperd" \
  test -z "$(grep -n systemctl "$bm/snapper/50-ryoku-boot-menu")"

stubs="$work/bin"
mkdir -p "$stubs"

# case 2
# hook <script> <cmdline>: source a dracut hook with the dracut-lib helpers
# stubbed, the root device at /dev/null and /run at $work/run.
hook() {
  local script="$1" cmdline="$2"
  (
    set +eu
    export RYOKU_RUN="$work/run" NEWROOT="$work/sysroot"
    getarg() {
      local tok
      for tok in $cmdline; do
        case "$tok" in "$1"*) echo "${tok#"$1"}"; return 0 ;; esac
      done
      return 1
    }
    warn() { echo "warn: $*" >>"$work/hook.log"; }
    info() { echo "info: $*" >>"$work/hook.log"; }
    label_uuid_to_dev() { echo /dev/null; }
    mount() { echo "mount $*" >>"$work/mount.log"; [ -z "${MOUNT_FAILS:-}" ]; }
    umount() { :; }
    # shellcheck source=/dev/null
    . "$script"
  )
}

hook "$mod/ryoku-snapshot-preview.sh" "root=UUID=abc ro rootflags=subvol=.snapshots/42/snapshot rd.ryoku.preview=.snapshots/42/snapshot"
base="$work/run/ryoku/preview"
check "look mounts the snapshot read-only as the lower layer" \
  grep -qxF "mount -t btrfs -o ro,subvol=.snapshots/42/snapshot /dev/null $base/lower" "$work/mount.log"
check "look keeps its writes in RAM" grep -qxF "mount -t tmpfs -o mode=0755 ryoku-preview $base/rw" "$work/mount.log"
check "look stacks the overlay on the root" grep -qxF \
  "mount -t overlay ryoku-preview -o lowerdir=$base/lower,upperdir=$base/rw/upper,workdir=$base/rw/work $work/sysroot" \
  "$work/mount.log"
check "look masks systemd-remount-fs for this boot" \
  test "$(readlink "$work/run/systemd/system/systemd-remount-fs.service")" = /dev/null

rm -f "$work/mount.log"
hook "$mod/ryoku-snapshot-preview.sh" "root=UUID=abc ro rootflags=subvol=root"
check "no look argument, nothing is mounted" absent "$work/mount.log"
hook "$mod/ryoku-snapshot-preview.sh" "root=UUID=abc rd.ryoku.preview=../x"
check "look refuses a path outside the filesystem" absent "$work/mount.log"

# case 3
grub="$work/boot/grub2"
mkdir -p "$grub"
cat >"$stubs/mkconfig" <<EOF_STUB
#!/bin/sh
echo run >>"$work/mkconfig.log"
sh "$bm/grub/42_ryoku_snapshots" >"\$2"
EOF_STUB
chmod +x "$stubs/mkconfig"
menu() { RYOKU_GRUB_DIR="$grub" RYOKU_GRUB_MKCONFIG="$stubs/mkconfig" bash "$bm/grub/ryoku-grub-menu" "$@"; }
runs() { test "$(wc -l <"$work/mkconfig.log" 2>/dev/null || echo 0)" = "$1"; }

menu install
check "install rebuilds grub.cfg with the snapshot menu" has "$grub/grub.cfg" "ryoku-snapshots.cfg"
menu install
check "a second install does not rebuild" runs 1
: >"$grub/grub.cfg"
menu install
check "install rebuilds a grub.cfg that lost the snapshot menu" runs 2

mkdir -p "$work/boot/ryoku/snapshots/k" && : >"$grub/ryoku-snapshots.cfg"
menu purge
check "purge removes the menu and the kernel copies" \
  test ! -e "$grub/ryoku-snapshots.cfg" -a ! -e "$work/boot/ryoku"
check "purge leaves grub.cfg to %postun" test -f "$grub/grub.cfg"

rm -rf "$grub"
menu install
check "install does nothing without a GRUB directory" runs 2

exit "$fail"
