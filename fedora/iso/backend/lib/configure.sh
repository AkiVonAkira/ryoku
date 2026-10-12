#!/usr/bin/env bash

fedora_configure() {
  fedora_relabel_target
  fedora_cfg_locale
  ryoku_cfg_keymap
  fedora_cfg_timezone
  ryoku_cfg_hostname
  ryoku_cfg_user
  fedora_cfg_selinux
}

# Package scripts create files (such as /etc/.pwd.lock) before the target has a
# policy, so they stay unlabeled and the live system's enforcing SELinux denies
# chpasswd and friends. Label the target with its own contexts first.
fedora_relabel_target() {
  log 'SELinux: labelling the installed packages'
  fedora_chroot setfiles -F -e /proc -e /sys -e /dev -e /run -e /boot \
    /etc/selinux/targeted/contexts/files/file_contexts /
}

fedora_cfg_locale() {
  log 'locale: %s' "$RYOKU_LOCALE"
  write_file /mnt/etc/locale.conf <<EOF
LANG=$RYOKU_LOCALE
EOF
}

fedora_cfg_timezone() {
  local timezone
  ryoku_resolve_timezone "$RYOKU_TIMEZONE"
  timezone=$RYOKU_RESOLVED_TIMEZONE
  log 'timezone: %s' "$timezone"
  run ln -sf "/usr/share/zoneinfo/$timezone" /mnt/etc/localtime
  fedora_chroot hwclock --systohc || true
}

# Files written from the live session carry no SELinux labels; the first boot
# relabels the target and reboots once.
fedora_cfg_selinux() {
  log 'SELinux: relabelling the target on first boot'
  write_file /mnt/.autorelabel </dev/null
}

fedora_services() {
  local unit
  local -a units=()
  for unit in sddm NetworkManager bluetooth power-profiles-daemon; do
    if [[ -n ${RYOKU_DRYRUN:-} || -f /mnt/usr/lib/systemd/system/$unit.service ]]; then
      units+=("$unit.service")
    fi
  done
  log 'enabling %s' "${units[*]}"
  fedora_chroot systemctl enable "${units[@]}"
  fedora_chroot systemctl set-default graphical.target
}
