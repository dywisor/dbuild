#!/bin/sh
print_action "Generate PARTUUID for ESP"
uuidgen > "${DBUILD_STAGING_TMP:?}/partuuid.esp" || die

print_action "Generate PARTUUID for swap"
uuidgen > "${DBUILD_STAGING_TMP:?}/partuuid.swap" || die

print_action "Generate UUID for swap"
uuidgen > "${DBUILD_STAGING_TMP:?}/uuid.swap" || die

print_action "Generate PARTUUID for rootfs"
uuidgen > "${DBUILD_STAGING_TMP:?}/partuuid.rootfs" || die

print_action "Generate UUID for rootfs"
uuidgen > "${DBUILD_STAGING_TMP:?}/uuid.rootfs" || die
