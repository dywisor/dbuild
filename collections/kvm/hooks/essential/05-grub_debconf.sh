#!/bin/sh

print_action "Configure grub package debconf for KVM"
autodie target_debconf << EOF
grub-efi-amd64 grub2/update_nvram boolean false
grub-efi-amd64 grub2/foce_efi_extra_removable boolean true
EOF
