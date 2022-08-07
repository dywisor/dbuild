#!/bin/sh

autodie zstd -z \
    "${DBUILD_STAGING_TMP:?}/rootfs.img" \
    -o "${DBUILD_STAGING_IMG:?}/rootfs.img.zst"

if feat_all "${OFEAT_VM_SWAP:-0}"; then
    autodie zstd -z \
        "${DBUILD_STAGING_TMP:?}/swap.img" \
        -o "${DBUILD_STAGING_IMG:?}/swap.img.zst"
fi
