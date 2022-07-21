#!/bin/sh

print_action "Publishing disk image as vhdx for Hyper-V"
autodie qemu-img convert -O vhdx \
    "${DBUILD_STAGING_TMP:?}/disk.img" \
    "${DBUILD_STAGING_IMG:?}/disk.vhdx"
