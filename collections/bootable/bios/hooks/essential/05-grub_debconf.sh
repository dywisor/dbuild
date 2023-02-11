#!/bin/sh

print_action "Configure grub package debconf for BIOS targets"
autodie target_debconf << EOF
grub-pc grub2/update_nvram boolean false
grub-pc grub2/force_efi_extra_removable boolean true
EOF

if feat_all "${OFEAT_BOOT_CMDLINE:-0}"; then
    autodie target_debconf << EOF
grub-pc grub2/linux_cmdline string ${OCONF_BOOT_CMDLINE-}
EOF
fi
