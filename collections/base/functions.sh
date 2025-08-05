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


## sysusers (for updating passwd/group/shadow/gshadow in target)
DBUILD_STAGING_SYSUSERS="${DBUILD_STAGING_TMP:?}/sysusers"

# dbuild_sysusers_reset()
dbuild_sysusers_reset() {
    if check_fs_lexists "${DBUILD_STAGING_SYSUSERS:?}"; then
        autodie rm -- "${DBUILD_STAGING_SYSUSERS}"
    fi

    touch -- "${DBUILD_STAGING_SYSUSERS:?}"
}

# @autodie @stdin dbuild_sysusers_write()
dbuild_sysusers_write() {
    # https://buildroot.org/downloads/manual/manual.html#makeuser-syntax
    # https://buildroot.org/downloads/manual/makeusers-syntax.txt
    #
    # The syntax for adding a user is a space-separated list of fields, one
    # user per line; the fields are:
    #
    # |=================================================================
    # |username |uid |group |gid |password |home |shell |groups |comment
    # |=================================================================
    #
    cat >> "${DBUILD_STAGING_SYSUSERS:?}" || die "Failed to add sysuser entries to tmpfile"
}

# @stdout dbuild_sysusers_print()
dbuild_sysusers_print() {
    < "${DBUILD_STAGING_SYSUSERS:?}" awk '
($5 != "") && ($5 != "*") { $5 = "_REDACTED_"; }
{ print; }
'
}


# @autodie dbuild_sysusers_add_system_user ( name, uid:=-1, gid:=<uid>, gecos:="", home_dir:="-", shell:="/usr/sbin/nologin" )
dbuild_sysusers_add_system_user() {
    local name
    local uid
    local gid

    [ $# -ge 1 ] && [ $# -lt 7 ] || return 64

    name="${1:?}"
    uid="${2:--1}"
    gid="${3:-${uid}}"

    dbuild_sysusers_write << EOF
${name} ${uid} ${name} ${gid} * ${5:--} ${6:-/usr/sbin/nologin} - ${4:-}
EOF
}


# @autodie dbuild_sysusers_add_system_group ( name, gid:=-1 )
dbuild_sysusers_add_system_group() {
    local name
    local gid

    [ $# -ge 1 ] && [ $# -lt 3 ] || return 64

    name="${1:?}"
    gid="${2:?}"

    dbuild_sysusers_write << EOF
- - ${name} ${gid} * - - -
EOF
}
