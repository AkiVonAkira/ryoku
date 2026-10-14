#!/usr/bin/env bash
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=tests/install-dryrun-harness.sh
source "$here/install-dryrun-harness.sh"
repo=$INSTALL_DRYRUN_ROOT
backend=$(install_dryrun_backend_path fedora)
builder=$repo/fedora/iso/build.sh

fail() {
  printf 'fedora installer dry-run matrix: %s\n' "$*" >&2
  exit 1
}

mapfile -t sourced_shared < <(
  sed -n 's|^[[:space:]]*source "\$SHARED_LIB_DIR/\([A-Za-z0-9_-]*\)\.sh"$|\1|p' "$backend"
)
mapfile -t staged_shared < <(
  awk '
    /^[[:space:]]*for library in / {
      for (i = 4; i <= NF; i++) {
        gsub(/;/, "", $i)
        if ($i == "do") exit
        print $i
      }
      exit
    }
  ' "$builder"
)
((${#sourced_shared[@]})) || fail 'no shared backend imports found'
((${#staged_shared[@]})) || fail 'no staged shared backend libraries found'
declare -A staged_set=()
for library in "${staged_shared[@]}"; do staged_set[$library]=1; done
for library in "${sourced_shared[@]}"; do
  [[ -n ${staged_set[$library]:-} ]] || fail "shared backend library is not staged: $library"
done

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

run_case() {
  local name=$1 strategy=$2 compositor=$3 config=$4 encrypt=$5 esp_mode=${6:-dedicated} snapshots=${7:-1}
  local out=$tmp/$name.out
  local -a envs=(
    RYOKU_DISK_STRATEGY="$strategy"
    RYOKU_PROFILE=amd
    RYOKU_COMPOSITOR="$compositor"
    RYOKU_COMPOSITOR_CONFIG_DIR="$config"
    RYOKU_BROWSER=firefox
    RYOKU_LOGIN_SHELL=fish
    RYOKU_ESP_MODE="$esp_mode"
    RYOKU_SUBVOL_SNAPSHOTS="$snapshots"
    RYOKU_OS_RELEASE="$tmp/os-release"
  )
  [[ $encrypt == yes ]] && envs+=(RYOKU_ENCRYPT=1 RYOKU_LUKS_PASSPHRASE=secret)
  install_dryrun_run fedora "$out" "${envs[@]}" || fail "$name: dry run failed"

  mapfile -t stages < <(grep '^@@RYOKU_STEP ' "$out" | awk '{print $2}')
  [[ ${stages[*]} == 'partition filesystems mount pacstrap configure bootloader' ]] \
    || fail "$name: bad stages: ${stages[*]}"
  [[ $(grep -c '^@@RYOKU_DONE$' "$out") == 1 ]] || fail "$name: no completion sentinel"
  grep -q 'with Secure Boot allowed' "$out" || fail "$name: preflight refuses Secure Boot"
  grep -qE 'dnf5 -y --installroot=/mnt --releasever=44 --use-host-config .* install @core fedora-release shim-x64 grub2-efi-x64 grub2-tools ' "$out" \
    || fail "$name: base install plan"
  grep -qE 'dnf5 -y --installroot=/mnt --releasever=44 install .* ryoku-desktop ' "$out" \
    || fail "$name: desktop install plan"
  grep -qF 'baseurl=https://repo.ryoku.dev/stable/fedora/$releasever/x86_64' "$out" || fail "$name: Ryoku repository"
  grep -qF 'rpm --root /mnt --import /mnt/etc/pki/rpm-gpg/RPM-GPG-KEY-ryoku' "$out" || fail "$name: key import"
  grep -qF -- '--loader \EFI\fedora\shimx64.efi' "$out" || fail "$name: shim boot entry"
  grep -qF 'grub2-mkconfig -o /boot/grub2/grub.cfg' "$out" || fail "$name: GRUB config"
  grep -qF 'chroot /mnt setfiles -F' "$out" || fail "$name: target labelled before configure"
  grep -qF 'write /mnt/.autorelabel' "$out" || fail "$name: SELinux relabel"
  grep -qF 'systemctl set-default graphical.target' "$out" || fail "$name: graphical target"
  ! grep -qiE 'limine|xbps|pacman -S' "$out" || fail "$name: another edition's tooling leaked in"

  # The chosen provider's variant lands, no other provider's does, and a
  # provider with a lane of its own name in the table gets that lane's packages.
  grep -qE "install .* ryoku-desktop-$compositor( |$)" "$out" || fail "$name: $compositor variant"
  others=$(grep -oE 'ryoku-desktop-[a-z]+' "$out" | sort -u | grep -vx -- "ryoku-desktop-$compositor" || true)
  [[ -z $others ]] || fail "$name: another provider's variant installed: $others"
  if cut -f3 "$repo/fedora/packages/translations.tsv" | tr ',' '\n' | grep -qx -- "$compositor"; then
    grep -qE "install .* $compositor( |$)" "$out" || fail "$name: $compositor lane"
  fi
  if [[ $encrypt == yes ]]; then
    grep -qF 'rd.luks.uuid=luks-' "$out" || fail "$name: LUKS cmdline"
    grep -qF 'write /mnt/etc/dracut.conf.d/20-ryoku-crypt.conf' "$out" || fail "$name: dracut crypt"
  fi
  if [[ $snapshots == 1 ]]; then
    grep -qF 'btrfs subvolume create /mnt/@snapshots' "$out" || fail "$name: @snapshots"
    grep -qF $'/.snapshots\tbtrfs' "$out" || fail "$name: @snapshots fstab"
  else
    grep -qF 'write /mnt/etc/ryoku/snapshots-disabled' "$out" || fail "$name: snapshots opt-out"
  fi

  grep -qE '^  boot: [^ ]+ at /boot and /boot/efi$' "$out" || fail "$name: /boot and the ESP should share Ryoku's partition"
  if [[ $strategy == alongside ]]; then
    grep -qF 'GRUB_DISABLE_OS_PROBER=false' "$out" || fail "$name: os-prober"
  fi
}

printf 'VERSION_ID=44\n' >"$tmp/os-release"
run_case whole-niri whole niri niri no
run_case whole-hyprland-crypt whole hyprland hypr yes
run_case whole-no-snapshots whole niri niri no dedicated 0
run_case alongside-auto alongside niri niri no auto
run_case alongside-dedicated alongside hyprland hypr yes dedicated

shared_out=$tmp/shared-refused.out
if install_dryrun_run fedora "$shared_out" \
  RYOKU_DISK_STRATEGY=alongside RYOKU_PROFILE=amd RYOKU_COMPOSITOR=niri \
  RYOKU_COMPOSITOR_CONFIG_DIR=niri RYOKU_ESP_MODE=shared \
  RYOKU_OS_RELEASE="$tmp/os-release"; then
  fail 'a shared ESP was accepted'
fi
grep -qF 'with its own ESP only' "$shared_out" || fail 'shared ESP refusal did not explain itself'

bios_out=$tmp/bios-refused.out
if install_dryrun_run fedora "$bios_out" \
  RYOKU_DISK_STRATEGY=whole RYOKU_PROFILE=vm RYOKU_COMPOSITOR=niri \
  RYOKU_COMPOSITOR_CONFIG_DIR=niri RYOKU_FIRMWARE_MODE=bios \
  RYOKU_OS_RELEASE="$tmp/os-release"; then
  fail 'legacy BIOS was accepted'
fi
grep -qF 'UEFI only' "$bios_out" || fail 'legacy BIOS refusal did not explain itself'

printf 'fedora installer dry-run matrix: ok\n'
