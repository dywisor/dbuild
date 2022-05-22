#!/bin/sh
# Configure the ctrl user

if feat_all "${OFEAT_CTRL_USER:-0}"; then
    # build list of additional (ssh) groups for the ctrl user
    groups=''
    autodie get_user_extra_groups \
        "${OFEAT_CTRL_USER_SSH:-0}" \
        "${OFEAT_CTRL_USER_SSH_SHELL:-0}" \
        "${OFEAT_CTRL_USER_SSH_FORWARDING:-0}"

    # create ctrl group
    autodie target_chroot groupadd \
        -g "${OCONF_CTRL_UID}" \
        "${OCONF_CTRL_USER}"

    # create ctrl user
    autodie target_chroot useradd \
        -c 'login user' \
        -d "/home/${OCONF_CTRL_USER}" \
        -g "${OCONF_CTRL_UID}" \
        -G "${groups}" \
        -M \
        -p '*' \
        -s '/bin/sh' \
        -u "${OCONF_CTRL_UID}" \
        "${OCONF_CTRL_USER}"

    # create home directory for the ctrl user (ramdisk or simple directory)
    if feat_all "${OFEAT_CTRL_USER_RAMDISK:-0}"; then
        autodie dodir_mode \
            "${TARGET_ROOTFS:?}/home/${OCONF_CTRL_USER}" \
            '0500' \
            '0:0'

        # ctrl home mount needs exec
        # and cross-directory for all users (mode=0711)
        {
cat << EOF >> "${TARGET_ROOTFS:?}/etc/fstab"
# ctrl user home
home /home/${OCONF_CTRL_USER} tmpfs rw,nosuid,nodev,exec,size=${OCONF_CTRL_USER_RAMDISK_SIZE:?}m,mode=0711,uid=${OCONF_CTRL_UID},gid=${OCONF_CTRL_UID} 0 0
EOF
        } || die "Failed to set up ramdisk home for ctrl user"

    else
        autodie dodir_mode \
            "${TARGET_ROOTFS:?}/home/${OCONF_CTRL_USER}" \
            '0711' \
            "${OCONF_CTRL_UID}:${OCONF_CTRL_UID}"
    fi

    # SSH authorized keys
    if feat_all "${OFEAT_SSHD_CONFIG:-0}" "${OFEAT_CTRL_USER_SSH:-0}"; then
        autodie dofile \
            "${TARGET_ROOTFS:?}/etc/ssh/authorized_keys/${OCONF_CTRL_USER:?}" \
            0640 "0:${OCONF_CTRL_UID}" \
            printf '%s\n' "${OCONF_CTRL_SSH_KEY-}"
    fi

    # sudoers config
    autodie dodir_mode "${TARGET_ROOTFS:?}/etc/sudoers.d" '0755' '0:0'
    (
umask 0077 && \
cat << EOF > "${TARGET_ROOTFS:?}/etc/sudoers.d/ctrl"
Defaults:${OCONF_CTRL_USER} targetpw
Defaults:${OCONF_CTRL_USER} passwd_tries=0
Defaults:${OCONF_CTRL_USER} env_reset
Defaults:${OCONF_CTRL_USER} !setenv
Defaults:${OCONF_CTRL_USER} !env_keep
Defaults:${OCONF_CTRL_USER} secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

${OCONF_CTRL_USER} ALL = (ALL) EXEC: NOMAIL: NOPASSWD: ALL
EOF
    ) || die "Failed to write sudoers config for ctrl user"
fi
