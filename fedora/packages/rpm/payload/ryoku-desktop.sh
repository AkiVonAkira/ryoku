# shellcheck shell=bash
startdir=${startdir:?stage-package.sh must set startdir}
srcdir=${srcdir:?stage-package.sh must set srcdir}
pkgdir=${pkgdir:?stage-package.sh must set pkgdir}
pkgver=${RYOKU_PKGVER:?stage-package.sh must set RYOKU_PKGVER}
_repo="$startdir/../../../.."
_payload="$_repo/release/packages/ryoku-desktop/payload.sh"

build() {
  RYOKU_SRC="$_repo" RYOKU_BUILD_DIR="$srcdir" RYOKU_PKGVER="$pkgver" \
    "$_payload" build
}

package() {
  RYOKU_SRC="$_repo" RYOKU_BUILD_DIR="$srcdir" RYOKU_PKGVER="$pkgver" \
    RYOKU_RELEASE="${RYOKU_RELEASE:-}" RYOKU_CHANNEL="${RYOKU_CHANNEL:-}" \
    RYOKU_NAME="${RYOKU_NAME:-}" RYOKU_COMMIT="${RYOKU_COMMIT:-}" \
    "$_payload" install "$pkgdir" systemd

  rm -rf "$pkgdir/etc/boot" \
    "$pkgdir/usr/lib/initcpio" \
    "$pkgdir/usr/share/libalpm" \
    "$pkgdir/usr/share/ryoku/boot"
  rm -f "$pkgdir/usr/bin/ryoku-boot-apply" \
    "$pkgdir/usr/bin/ryoku-windows-entry"

  install -Dm644 "$_repo/fedora/system/hardware/network/ryoku-wifi-regdom.service" \
    "$pkgdir/usr/lib/systemd/system/ryoku-wifi-regdom.service"

  # the snapshot boot menu (fedora/system/boot): the "Ryoku snapshots" GRUB
  # submenu, resynced after every snapshot by the snapper plugin and
  # ryoku-snapshot-menu.path; %posttrans renders the snippet into grub.cfg.
  local boot="$_repo/fedora/system/boot" unit mod
  install -Dm755 "$boot/grub/ryoku-grub-menu" "$pkgdir/usr/bin/ryoku-grub-menu"
  install -Dm755 "$boot/grub/42_ryoku_snapshots" "$pkgdir/etc/grub.d/42_ryoku_snapshots"
  install -Dm755 "$boot/snapper/50-ryoku-boot-menu" \
    "$pkgdir/usr/libexec/snapper/plugins/50-ryoku-boot-menu"
  for unit in ryoku-snapshot-menu.service ryoku-snapshot-menu.path ryoku-snapshot-restored.service; do
    install -Dm644 "$boot/$unit" "$pkgdir/usr/lib/systemd/system/$unit"
  done
  for mod in module-setup.sh ryoku-snapshot-preview.sh; do
    install -Dm755 "$boot/dracut/90ryoku-snapshot/$mod" \
      "$pkgdir/usr/lib/dracut/modules.d/90ryoku-snapshot/$mod"
  done
}
