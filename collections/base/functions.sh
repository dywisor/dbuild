#!/bin/sh
## update-initramfs environment

DBUILD_STAGING_UPDATE_INITRAMFS_ENV="${DBUILD_STAGING_TMP:?}/update-initramfs.env"

dbuild_reset_update_initramfs_env() {
    if check_fs_lexists "${DBUILD_STAGING_UPDATE_INITRAMFS_ENV:?}"; then
        autodie rm -- "${DBUILD_STAGING_UPDATE_INITRAMFS_ENV}"
    fi

    printf 'WANT_UPDATE_INITRAMFS=\n' > "${DBUILD_STAGING_UPDATE_INITRAMFS_ENV:?}"
}

dbuild_want_update_initramfs() {
    printf 'WANT_UPDATE_INITRAMFS=1\n' >> "${DBUILD_STAGING_UPDATE_INITRAMFS_ENV:?}"
}

dbuild_update_initramfs_env() {
    while [ $# -gt 0 ]; do
        [ -z "${1}" ] || printf 'export %s\n' "${1}"
        shift
    done >> "${DBUILD_STAGING_UPDATE_INITRAMFS_ENV:?}"
}

dbuild_load_update_initramfs_env() {
    . "${DBUILD_STAGING_UPDATE_INITRAMFS_ENV}"
}
