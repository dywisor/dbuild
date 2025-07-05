#!/bin/sh
# Install nftables.conf in rootfs and for initramfs

print_action "Install nftables.conf.initramfs"
autodie install -m 0600 -o 0 -g 0 -- \
    "${HOOK_FILESDIR:?}/nftables.conf.initramfs" \
    "${TARGET_ROOTFS:?}/etc/nftables.conf.initramfs"

print_action "Install nftables.conf"
autodie install -m 0600 -o 0 -g 0 -- \
    "${NFT_RULES_TMPFILE:?}" \
    "${TARGET_ROOTFS:?}/etc/nftables.conf"
