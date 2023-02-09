#!/bin/sh

print_action "Configure grub package debconf for UEFI targets"
autodie target_debconf << EOF
grub-efi-amd64 grub2/update_nvram boolean false
grub-efi-amd64 grub2/force_efi_extra_removable boolean true
EOF
