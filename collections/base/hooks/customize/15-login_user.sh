#!/bin/sh
# Configure the login user

if feat_all "${OFEAT_LOGIN_USER:-0}"; then
    # build list of additional (ssh) groups for the login user
    groups=''
    autodie get_user_extra_groups \
        "${OFEAT_LOGIN_USER_SSH:-0}" \
        "${OFEAT_LOGIN_USER_SSH_SHELL:-0}" \
        "${OFEAT_LOGIN_USER_SSH_FORWARDING:-0}"

    # create login user group
    autodie target_chroot groupadd \
        -g "${OCONF_LOGIN_UID}" \
        "${OCONF_LOGIN_USER}"

    login_user_shell='/bin/bash'
    if [ ! -e "${TARGET_ROOTFS}/${login_user_shell#/}" ]; then
        login_user_shell='/bin/sh'
    fi

    # create login user
    autodie target_chroot useradd \
        -c 'login user' \
        -d "/home/${OCONF_LOGIN_USER}" \
        -g "${OCONF_LOGIN_UID}" \
        -G "${groups}" \
        -M \
        -p "${OCONF_LOGIN_USER_PASSWORD}" \
        -s "${login_user_shell}" \
        -u "${OCONF_LOGIN_UID}" \
        "${OCONF_LOGIN_USER}"

    # create home directory for the login user (ramdisk or simple directory)
    if feat_all "${OFEAT_LOGIN_USER_RAMDISK:-0}"; then
        autodie dodir_mode \
            "${TARGET_ROOTFS:?}/home/${OCONF_LOGIN_USER}" \
            '0500' \
            '0:0'

        {
cat << EOF >> "${TARGET_ROOTFS:?}/etc/fstab"
# login user home
home /home/${OCONF_LOGIN_USER} tmpfs rw,nosuid,nodev,noexec,size=${OCONF_LOGIN_USER_RAMDISK_SIZE:?}m,mode=0700,uid=${OCONF_LOGIN_UID},gid=${OCONF_LOGIN_UID} 0 0
EOF
        } || die "Failed to set up ramdisk home for login user"

    else
        autodie dodir_mode \
            "${TARGET_ROOTFS:?}/home/${OCONF_LOGIN_USER}" \
            '0700' \
            "${OCONF_LOGIN_UID}:${OCONF_LOGIN_UID}"
    fi

    # SSH authorized keys
    if feat_all "${OFEAT_SSHD_CONFIG:-0}" "${OFEAT_LOGIN_USER_SSH:-0}"; then
        autodie dofile \
            "${TARGET_ROOTFS:?}/etc/ssh/authorized_keys/${OCONF_LOGIN_USER:?}" \
            0640 "0:${OCONF_LOGIN_UID}" \
            printf '%s\n' "${OCONF_LOGIN_SSH_KEY-}"
    fi
fi
