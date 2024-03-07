#!/bin/sh
## env.d (for generating /etc/environment)
DBUILD_STAGING_ENVD="${DBUILD_STAGING_TMP:?}/env.d"

# dbuild_envd_reset()
dbuild_envd_reset() {
    if check_fs_lexists "${DBUILD_STAGING_ENVD:?}"; then
        autodie rm -r -- "${DBUILD_STAGING_ENVD}"
    fi

    mkdir -- "${DBUILD_STAGING_ENVD:?}"
}

# @autodie dbuild_envd_push ( name, ... )
dbuild_envd_push() {
    local name

    name="${1:?}"; shift

    autodie write_to_file "${DBUILD_STAGING_ENVD:?}/${name}" '-' '-' "${@}"
}

# @stdout dbuild_envd_cat()
dbuild_envd_cat() {
    # bypass noglob temporarily
    case "$-" in
        *f*)
            set +f
            set -- "${DBUILD_STAGING_ENVD:?}/"*
            set -f
        ;;
        *)
            set -- "${DBUILD_STAGING_ENVD:?}/"*
        ;;
    esac

    # drop unmatched pattern from result list
    if [ $# -gt 0 ] && [ "${1}" = "${DBUILD_STAGING_ENVD:?}/*" ]; then
        shift
    fi

    if [ $# -gt 0 ]; then
        cat -- "${@}"
    fi
}


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
