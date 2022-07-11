#!/bin/sh
# Install nftables.conf in rootfs and for initramfs

print_action "Install nftables.conf"

if \
    [ ! -h "${TARGET_ROOTFS:?}/etc/nftables.conf.initramfs" ] && \
    [ -e "${TARGET_ROOTFS:?}/etc/nftables.conf.initramfs" ]
then
    print_info "Adjusting permissions for /etc/nftables.conf.initramfs"
    autodie chmod -- 0600 "${TARGET_ROOTFS:?}/etc/nftables.conf.initramfs"
fi

if [ -s "${TARGET_ROOTFS:?}/etc/nftables.conf.dist" ]; then
    autodie rm -f -- "${TARGET_ROOTFS:?}/etc/nftables.conf"

    autodie mv -f -- \
        "${TARGET_ROOTFS:?}/etc/nftables.conf.dist" \
        "${TARGET_ROOTFS:?}/etc/nftables.conf"

    autodie dofile "${TARGET_ROOTFS:?}/etc/nftables.conf" 0600 "0:0"

elif [ -s "${TARGET_ROOTFS:?}/etc/nftables.conf.initramfs" ]; then
    # fallback: use initramfs nftables.conf as default nftables.conf for the rootfs

    autodie rm -f -- "${TARGET_ROOTFS:?}/etc/nftables.conf"

    autodie cp -aL -- \
        "${TARGET_ROOTFS:?}/etc/nftables.conf.initramfs" \
        "${TARGET_ROOTFS:?}/etc/nftables.conf"
fi
