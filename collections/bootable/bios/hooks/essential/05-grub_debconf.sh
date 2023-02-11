#!/bin/sh

print_action "Configure grub package debconf for BIOS targets"
autodie target_debconf << EOF
grub-pc grub2/update_nvram boolean false
grub-pc grub2/force_efi_extra_removable boolean true
EOF
