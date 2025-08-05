#!/bin/sh
# Configure the login user

if feat_all "${OFEAT_LOGIN_USER:-0}"; then
    # login user already created by sysusers, get uid/gid
    autodie target_getpwnam_id "${OCONF_LOGIN_USER:?}"
    login_user_uid="${pw_uid:?}"
    login_user_gid="${pw_gid:?}"
    # TODO/LATER: pw_dir ?
    login_user_home="/home/${OCONF_LOGIN_USER:?}"

    # create home directory for the login user (ramdisk or simple directory)
    if feat_all "${OFEAT_LOGIN_USER_RAMDISK:-0}"; then
        autodie dodir_mode \
            "${TARGET_ROOTFS:?}${login_user_home:?}" \
            '0500' \
            '0:0'

        {
cat << EOF >> "${TARGET_ROOTFS:?}/etc/fstab"
# login user home
home ${login_user_home:?} tmpfs rw,nosuid,nodev,noexec,size=${OCONF_LOGIN_USER_RAMDISK_SIZE:?}m,mode=0700,uid=${login_user_uid},gid=${login_user_gid} 0 0
EOF
        } || die "Failed to set up ramdisk home for login user"

    else
        autodie dodir_mode \
            "${TARGET_ROOTFS:?}${login_user_home:?}" \
            '0700' \
            "${login_user_uid}:${login_user_gid}"
    fi

    # SSH authorized keys
    if feat_all "${OFEAT_SSHD_CONFIG:-0}" "${OFEAT_LOGIN_USER_SSH:-0}"; then
        autodie dofile \
            "${TARGET_ROOTFS:?}/etc/ssh/authorized_keys/${OCONF_LOGIN_USER:?}" \
            0640 "0:${login_user_gid}" \
            printf '%s\n' "${OCONF_LOGIN_SSH_KEY-}"
    fi
fi
