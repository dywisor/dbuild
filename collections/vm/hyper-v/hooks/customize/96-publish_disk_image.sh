#!/bin/sh

print_action "Publishing disk image as vhdx for Hyper-V"
autodie qemu-img convert -O vhdx \
    "${DBUILD_STAGING_TMP:?}/rootfs.img" \
    "${DBUILD_STAGING_IMG:?}/rootfs.vhdx"

if feat_all "${OFEAT_VM_SWAP:-0}"; then
    autodie qemu-img convert -O vhdx \
        "${DBUILD_STAGING_TMP:?}/swap.img" \
        "${DBUILD_STAGING_IMG:?}/swap.vhdx"
fi
