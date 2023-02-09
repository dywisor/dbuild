#!/bin/sh
print_action "Generate UUID for rootfs"
uuidgen > "${DBUILD_STAGING_TMP:?}/uuid.rootfs" || die
