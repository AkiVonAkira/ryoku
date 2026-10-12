#!/usr/bin/env bash

fedora_bootloader() {
  if [[ -n ${RYOKU_DRYRUN:-} || -d /mnt/usr/share/plymouth/themes/ryoku ]]; then
    fedora_chroot plymouth-set-default-theme ryoku || true
  fi
  log 'building the initramfs images'
  fedora_chroot dracut --force --regenerate-all
  fedora_grub_config
  fedora_efi_entry
}

# The ESP stub hands over to the grub.cfg on the /boot partition, as Fedora lays it out.
fedora_grub_config() {
  local boot_uuid
  boot_uuid=$(dev_uuid "$ESP_DEV") || die 'GRUB: could not read boot UUID from %s' "$ESP_DEV"
  if [[ -z ${RYOKU_DRYRUN:-} && ! -f /mnt/boot/efi/EFI/fedora/shimx64.efi ]]; then
    die 'shim is missing from the ESP: /boot/efi/EFI/fedora/shimx64.efi'
  fi
  log 'writing the GRUB configuration'
  printf 'search --no-floppy --fs-uuid --set=dev %s\nset prefix=($dev)/grub2\nexport $prefix\nconfigfile $prefix/grub.cfg\n' \
    "$boot_uuid" | write_file /mnt/boot/efi/EFI/fedora/grub.cfg
  fedora_chroot grub2-mkconfig -o /boot/grub2/grub.cfg
}

fedora_efi_entry() {
  local partnum
  partnum=$(part_num "$ESP_DEV")
  run efibootmgr --create --disk "$RYOKU_DISK" --part "$partnum" --label Ryoku \
    --loader '\EFI\fedora\shimx64.efi' --unicode || \
    log 'warning: firmware rejected the Ryoku NVRAM entry; EFI/BOOT/BOOTX64.EFI (shim) remains bootable'
}
