#!/usr/bin/env bash

# The live image and the target share a Fedora release.
fedora_os_release_version() {
  local os_release=${RYOKU_OS_RELEASE:-/etc/os-release}
  [[ -r $os_release ]] || return 0
  awk -F= '$1 == "VERSION_ID" { gsub(/"/, "", $2); print $2 }' "$os_release"
}

fedora_dnf() {
  run dnf5 -y --installroot=/mnt --releasever="$RYOKU_FEDORA_RELEASEVER" "$@"
}

fedora_chroot() {
  run chroot /mnt "$@"
}

fedora_resolve() {
  "$RYOKU_RESOLVER" --table "$RYOKU_REPO/fedora/packages/translations.tsv" "$@"
}

fedora_dedupe() {
  local -n list=$1
  mapfile -t list < <(printf '%s\n' "${list[@]}" | awk 'NF && !seen[$0]++')
}

FEDORA_RESOLV_MARK=/mnt/etc/.ryoku-resolv-link

# Driver scripts install through dnf inside the chroot, so the target borrows the
# live session's resolver until the bootloader step hands /etc/resolv.conf back.
fedora_target_dns() {
  if [[ -n ${RYOKU_DRYRUN:-} ]]; then
    printf 'DRYRUN: lend the live /etc/resolv.conf to /mnt until the bootloader step\n'
    return 0
  fi
  if [[ -L /mnt/etc/resolv.conf ]]; then
    readlink /mnt/etc/resolv.conf >"$FEDORA_RESOLV_MARK"
  elif [[ -e /mnt/etc/resolv.conf ]]; then
    cp -a /mnt/etc/resolv.conf "$FEDORA_RESOLV_MARK.file"
  fi
  rm -f /mnt/etc/resolv.conf
  cp -L /etc/resolv.conf /mnt/etc/resolv.conf
}

fedora_target_dns_restore() {
  if [[ -n ${RYOKU_DRYRUN:-} ]]; then
    printf 'DRYRUN: restore the target /etc/resolv.conf\n'
    return 0
  fi
  rm -f /mnt/etc/resolv.conf
  if [[ -f $FEDORA_RESOLV_MARK ]]; then
    ln -s "$(<"$FEDORA_RESOLV_MARK")" /mnt/etc/resolv.conf
    rm -f "$FEDORA_RESOLV_MARK"
  elif [[ -f $FEDORA_RESOLV_MARK.file ]]; then
    mv -f "$FEDORA_RESOLV_MARK.file" /mnt/etc/resolv.conf
  fi
}
