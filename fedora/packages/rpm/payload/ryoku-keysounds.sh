# shellcheck shell=bash
: "${startdir:?}" "${srcdir:?}" "${pkgdir:?}"
source "$startdir/hyprland-plugin.sh"
_repo="$startdir/../../../.."

build() {
  cp -a "$_repo/ryoku/hyprland/plugins/keysounds" "$srcdir/keysounds"
  make -C "$srcdir/keysounds" all \
    MECHVIBES="$_repo/.rpm-ryoku-keysounds/mechvibes" \
    IMPORTER="$_repo/ryoku/hyprland/scripts/ryoku-keysounds-import"
}

package() {
  install -Dm755 "$srcdir/keysounds/keysounds.so" \
    "$pkgdir/usr/lib/hyprland/plugins/keysounds.so"
  install_plugin_abi keysounds
  install -d "$pkgdir/usr/share/ryoku/keysounds"
  cp -a "$srcdir/keysounds/sounds/." "$pkgdir/usr/share/ryoku/keysounds/"
  install -Dm644 "$_repo/.rpm-ryoku-keysounds/mechvibes/LICENSE" \
    "$pkgdir/usr/share/licenses/ryoku-keysounds/LICENSE.mechvibes"
  install -Dm644 -t "$pkgdir/usr/share/ryoku/hypr-plugins/keysounds" \
    "$_repo/ryoku/hyprland/plugins/keysounds/main.cpp" \
    "$_repo/ryoku/hyprland/plugins/keysounds/Makefile" \
    "$_repo/ryoku/hyprland/plugins/keysounds/hyprpm.toml" \
    "$_repo/ryoku/hyprland/plugins/keysounds/profiles.txt" \
    "$_repo/ryoku/hyprland/plugins/keysounds/README.md"
}
