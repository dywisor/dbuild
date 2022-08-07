#!/bin/sh
print_action "Generate PARTUUID for ESP"
uuidgen > "${DBUILD_STAGING_TMP:?}/partuuid.esp" || die

if feat_all "${OFEAT_VM_SWAP:-0}"; then
    print_action "Generate PARTUUID for swap"
    uuidgen > "${DBUILD_STAGING_TMP:?}/partuuid.swap" || die

    print_action "Generate UUID for swap"
    uuidgen > "${DBUILD_STAGING_TMP:?}/uuid.swap" || die
fi

print_action "Generate PARTUUID for rootfs"
uuidgen > "${DBUILD_STAGING_TMP:?}/partuuid.rootfs" || die

print_action "Generate UUID for rootfs"
uuidgen > "${DBUILD_STAGING_TMP:?}/uuid.rootfs" || die
