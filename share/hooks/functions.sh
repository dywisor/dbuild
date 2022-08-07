#!/bin/sh

print_err() {
    printf '%s\n' "${@}" 1>&2
}


print_info() {
    printf '%s\n' "${@}" 1>&2
}


print_action() {
    printf '\n*** %s ***\n' "${1}"
}

die() {
    printf '%s\n' "${1:+died: }${1:-died.}" 1>&2
    exit "${2:-255}"
}

autodie() {
    "${@}" || die "command '${*}' returned ${?}" "${?}"
}

__nostdout__() { "${@}" 1>/dev/null; }
__nostderr__() { "${@}" 2>/dev/null; }
__quietly__()  { "${@}" 1>/dev/null 2>&1; }

__have_cmd__() { __quietly__ command -V "${1}"; }

__retlatch__() {
    "${@}" && rc=0 || rc=${?}
    return ${rc}
}

# feat_all ( *args )
#
#  Returns true if all args are set to '1'
#  and at least one arg was given, otherwise false.
#
#  Empty args will be interpreted as '0'.
#
#  This can be used for feature checks:
#
#    if feat_all "${A:-0}" "${B:-0}"; then
#       ...
#    fi
#
feat_all() {
    [ ${#} -gt 0 ] || return 1

    while [ ${#} -gt 0 ]; do
        [ "${1:-0}" -eq 1 ] || return 1
        shift
    done

    return 0
}

# feat_not_all ( *args )
#   IS NEGATED feat_all()
#
feat_not_all() {
    ! feat_all "${@}"
}

# feat_any( *args )
#
#  Returns true if at least one arg is set to '1'.
#
feat_any() {
    while [ ${#} -gt 0 ]; do
        if [ "${1:-0}" -eq 1 ]; then
            return 0
        fi
        shift
    done

    return 1
}

check_fs_lexists() {
    [ -e "${1}" ] || [ -h "${1}" ]
}

# _dopath { dst, [mode], [owner] )
_dopath() {
    [ "${2:--}" = '-' ] || chmod    -- "${2}" "${1}" || return
    [ "${3:--}" = '-' ] || chown -h -- "${3}" "${1}" || return
}

dopath() {
    [ -n "${1-}" ] || return 2
    check_fs_lexists "${1}" || return

    _dopath "${@}"
}

# _dofile ( dst, [mode], [owner] )
_dofile() {
    : "${1:?}"

    # racy
    rm -f -- "${1}" || return
    ( umask 0177 && :> "${1}"; ) || return

    _dopath "${@}"
}

# dofile ( dst, [mode], [owner], [cmdv...] )
dofile() {
    local dst
    dst="${1:?}"

    _dofile "${dst}" "${2-}" "${3-}" || return

    if [ ${#} -gt 3 ]; then
        shift 3 || return
        "${@}" > "${dst}" || return
    fi
}

# @BADLY_NAMED dodir_mode ( dst, [mode], [owner] )
dodir_mode() {
    : "${1:?}"

    mkdir -p -m "${2:-0755}" -- "${1}" || return
    dopath "${@}"
}



# target_chroot ( *cmdv )
#
#   Runs a command in TARGET_ROOTFS
#
#   FIXME: qemu-user for foreign arch?
#
target_chroot() {
    chroot "${TARGET_ROOTFS}" "${@}"
}

# @stdin target_debconf_set_selections()
#
#   Runs debconf-set-selections in TARGET_ROOTFS,
#   expecting input via stdin.
#
target_debconf_set_selections() {
    target_chroot debconf-set-selections
}

# @ALIAS @stdin target_debconf()
#   IS target_debconf_set_selections()
#
target_debconf() {
    target_debconf_set_selections "${@}"
}


# @autodie @stdin write_to_file ( outfile, [mode], [owner], [cmdv...] )
write_to_file() {
    local outfile
    local mode
    local owner

    outfile="${1:?}"
    mode="${2-}"
    owner="${3-}"

    if [ $# -gt 3 ]; then
        shift 3 || return
    else
        set -- cat
    fi

    dofile "${outfile}" "${mode}" "${owner}" "${@}" || \
        die "Failed to write ${1:?}"
}

# @autodie @stdin target_write_to_file ( outfile_relpath, [mode], [owner], [cmdv...] )
target_write_to_file() {
    local outfile_relpath
    outfile_relpath="${1:?}"; shift

    write_to_file "${TARGET_ROOTFS:?}/${outfile_relpath#/}" "${@}"
}

# get_user_extra_groups (
#   flag_ssh_login, flag_ssh_shell, flag_ssh_forwarding,
#   **groups!
# )
get_user_extra_groups() {
    groups=""

    if feat_all "${OFEAT_SSHD_CONFIG:-0}" "${1:-0}"; then
        groups="${groups}${groups:+,}${OCONF_SSHD_GROUP_LOGIN:?}"

        if feat_all "${2:-0}"; then
            groups="${groups:?},${OCONF_SSHD_GROUP_SHELL:?}"
        fi

        if feat_all "${3:-0}"; then
            groups="${groups:?},${OCONF_SSHD_GROUP_FORWARDING:?}"
        fi
    fi
}
