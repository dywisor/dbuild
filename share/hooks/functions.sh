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

# int _dbuild_import_overlay__rsync ( args... )
#
#   default rsync options/excludes split out from dbuild_import_overlay(),
#   courtesy of merged-usr support.
_dbuild_import_overlay__rsync() {
    rsync -haxHAX \
        --exclude='__pycache__' \
        --exclude='*.py[co]' \
        --exclude='[._]*.s[a-v][a-z]' \
        --exclude='[._]*.sw[a-p]' \
        --exclude='[._]s[a-rt-v][a-z]' \
        --exclude='[._]ss[a-gi-z]' \
        --exclude='[._]sw[a-p]' \
        --exclude='Session.vim' \
        --exclude='.netrwhist' \
        --exclude='*~' \
        --exclude='.DS_Store' \
        --exclude='.AppleDouble' \
        --exclude='.LSOverride' \
        "${@}"
}


# int dbuild_import_overlay ( overlay_src, [overlay_dst_rel:="/"], [args...], **OFEAT_MERGED_USR )
#
#   Recursively copies files from an overlay directory
#   to the target rootfs (or a subdirectory thereof).
#
dbuild_import_overlay() {
    local overlay_src
    local overlay_dst
    local dirname

    overlay_src="${1:?}"
    case "${2-}" in
        ''|'/')
            overlay_dst="${TARGET_ROOTFS:?}"
        ;;
        *)
            overlay_dst="${TARGET_ROOTFS:?}/${2#/}"
        ;;
    esac

    if [ $# -gt 2 ]; then
        shift 2 || return
    else
        set --
    fi

    if ! feat_all "${OFEAT_MERGED_USR:-0}"; then
        # traditional no-merged-usr variant:
        #   copy without adjusting filesystem paths
        _dbuild_import_overlay__rsync \
            "${@}" \
            -- \
            "${overlay_src%/}/" \
            "${overlay_dst%/}/" || return

    else
        # merged-usr variant: relocate known directories,
        # resulting in *many* rsync invocations
        #
        # NOTE: excludes in %args may be broken for /usr paths!
        #
        _dbuild_import_overlay__rsync \
            --exclude='/bin' \
            --exclude='/lib' \
            --exclude='/lib32' \
            --exclude='/lib64' \
            --exclude='/libexec' \
            --exclude='/sbin' \
            \
            "${@}" \
            -- \
            "${overlay_src%/}/" \
            "${overlay_dst%/}/" || return

        for dirname in bin lib lib32 lib64 libexec sbin; do
            if \
                [ -d "${overlay_src}/${dirname}" ] && \
                [ ! -h "${overlay_src}/${dirname}" ]
            then
                dodir_mode "${overlay_dst%/}/usr/${dirname}" || return

                _dbuild_import_overlay__rsync \
                    "${overlay_src%/}/${dirname}/" \
                    "${overlay_dst%/}/usr/${dirname}/" || return
            fi
        done
    fi
}


# verify_file_checksum_generic ( checksum_cmd, checksum_file, target_file )
#
verify_file_checksum_generic() {
    local checksum_cmd
    local checksum_file
    local target_file

    local checksum_wanted
    local checksum_target

    checksum_cmd="${1:?}"
    checksum_file="${2:?}"
    target_file="${3:?}"

    # verify sha512sum (or other %checksum_cmd)
    # (a) ignore missing files listed in the checksum file
    # (b) downloaded file must be present in the checksum file

    checksum_wanted="$(
        awk \
            -v fname="${target_file##*/}" \
            '($2 == fname) { print $1; exit; }' \
            < "${checksum_file}"
    )"

    checksum_target="$( "${checksum_cmd}" "${target_file}" | awk '{ print $1; }' )"

    if [ -z "${checksum_target}" ]; then
        print_err "Cannot verify ${target_file##*/} - failed to get ${checksum_cmd}"
        return 1

    elif [ -z "${checksum_wanted}" ]; then
        print_err "Cannot verify ${target_file##*/} - no good ${checksum_cmd} known"
        return 2

    elif [ "${checksum_target}" != "${checksum_wanted}" ]; then
        print_err "Failed to verify ${target_file##*/} - ${checksum_cmd} differs, ${checksum_wanted} (expected) != ${checksum_target} (downloaded)"
        return 3

    else
        return 0
    fi
}


# verify_file_checksum ( target_file, [category] )
#
#   Verifies target_file against a known sha512 checksum
#   stored in HOOK_FILESDIR/sha512sums (or <category>.sha512sums).
#
verify_file_checksum() {
    local checksum_file

    if [ -n "${2-}" ]; then
        checksum_file="${HOOK_FILESDIR:?}/${2}.sha512sums"
    else
        checksum_file="${HOOK_FILESDIR:?}/sha512sums"
    fi

    verify_file_checksum_generic sha512sum "${checksum_file}" "${1:?}"
}
