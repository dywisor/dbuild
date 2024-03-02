#!/bin/sh
if feat_all "${OFEAT_GEN_FS_UUID:-0}"; then
    print_action "Generate UUID for rootfs"
    uuidgen > "${DBUILD_STAGING_TMP:?}/uuid.rootfs" || die

    if feat_all "${OFEAT_SEPARATE_BOOT:-0}"; then
        print_action "Generate UUID for /boot"
        uuidgen > "${DBUILD_STAGING_TMP:?}/uuid.boot" || die
    fi
fi
