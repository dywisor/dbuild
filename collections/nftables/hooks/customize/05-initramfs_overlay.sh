#!/bin/sh
# Include initramfs scripts for early config
# on targets that have their own kernel image / initramfs.
#
if feat_all "${OFEAT_KERNEL_IMAGE:-0}"; then
    print_action "Add initramfs scripts for nftables"
    autodie dbuild_import_overlay \
        "${HOOK_FILESDIR}/initramfs-overlay"
fi
