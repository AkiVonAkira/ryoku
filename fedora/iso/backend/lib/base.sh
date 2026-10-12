#!/usr/bin/env bash

# rpm chmods files under /boot, which vfat refuses unless quiet.
FEDORA_VFAT_OPTS=fmask=0133,dmask=0022,shortname=winnt,quiet

# Fedora's shim and GRUB packages install to /boot/efi, so Ryoku's own ESP is
# mounted there as well as at /boot.
fedora_boot_mounts() {
  log 'boot: %s at /boot and /boot/efi' "$ESP_DEV"
  run umount /mnt/boot
  run mount -o "$FEDORA_VFAT_OPTS" "$ESP_DEV" /mnt/boot
  run mkdir -p /mnt/boot/efi
  run mount -o "$FEDORA_VFAT_OPTS" "$ESP_DEV" /mnt/boot/efi
}

fedora_write_fstab() {
  local boot_uuid
  boot_uuid=$(dev_uuid "$ESP_DEV") || die 'fstab: could not read boot UUID from %s' "$ESP_DEV"
  log "writing UUID-based /etc/fstab"
  run mkdir -p /mnt/etc
  {
    ryoku_fstab_subvolumes
    printf 'UUID=%s\t/boot\tvfat\t%s\t0 2\n' "$boot_uuid" "$FEDORA_VFAT_OPTS"
    printf 'UUID=%s\t/boot/efi\tvfat\t%s\t0 2\n' "$boot_uuid" "$FEDORA_VFAT_OPTS"
  } | write_file /mnt/etc/fstab
}

# Written before the kernel lands, so kernel-install and dracut see the target's
# cmdline and crypttab instead of the live session's.
fedora_boot_config() {
  local cmdline os_prober=true
  cmdline="$(ryoku_dracut_cmdline) rhgb quiet"
  [[ $RYOKU_DISK_STRATEGY == alongside ]] && os_prober=false
  log 'kernel cmdline: %s' "$cmdline"
  run mkdir -p /mnt/etc/kernel /mnt/etc/default
  write_file /mnt/etc/kernel/cmdline <<<"$cmdline"
  write_file /mnt/etc/default/grub <<EOF
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR="Ryoku"
GRUB_DEFAULT=saved
GRUB_DISABLE_SUBMENU=true
GRUB_TERMINAL_OUTPUT="console"
GRUB_CMDLINE_LINUX="$cmdline"
GRUB_DISABLE_RECOVERY="true"
GRUB_DISABLE_OS_PROBER=$os_prober
GRUB_ENABLE_BLSCFG=true
EOF
  ryoku_dracut_crypttab
}

fedora_base_install() {
  local -a packages=(@core fedora-release shim-x64 grub2-efi-x64 grub2-tools)
  local language=${RYOKU_LOCALE%%[_.@]*}
  # C and POSIX live in glibc itself; there is no langpack for them.
  [[ $language == C || $language == POSIX ]] || packages+=("glibc-langpack-$language")
  [[ $RYOKU_DISK_STRATEGY == alongside ]] && packages+=(os-prober)
  local -a args=(--lane system) drop_args=()
  local plan
  mapfile -t drop_args < <(ryoku_resolver_drop_args)
  args+=("${drop_args[@]}")
  plan=$(fedora_resolve "${args[@]}") || die 'could not resolve the Fedora system package plan'
  mapfile -t -O "${#packages[@]}" packages <<<"$plan"
  fedora_dedupe packages

  log 'installing the Fedora %s base system (%d packages)' "$RYOKU_FEDORA_RELEASEVER" "${#packages[@]}"
  fedora_dnf --use-host-config --setopt=cachedir="/mnt$RYOKU_PACKAGE_CACHE_DIR" \
    install "${packages[@]}"
}
