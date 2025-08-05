#!/bin/sh
# Initialize system users/groups from the 'base' collection.
# This does not create the accounts (yet), it merely requests them,
# which will be picked by the sysusers-create hook later on.

print_action "sysusers: request system user/groups for base collection"


# ssh access groups
if feat_all "${OFEAT_SSHD_CONFIG:-0}"; then
    print_action "sysusers: ssh access groups"

    # username uid group gid password home shell groups comment
    autodie dbuild_sysusers_write << EOF
- - ${OCONF_SSHD_GROUP_LOGIN:?} ${OCONF_SSHD_GID_LOGIN:?}
- - ${OCONF_SSHD_GROUP_SHELL:?} ${OCONF_SSHD_GID_SHELL:?}
- - ${OCONF_SSHD_GROUP_FORWARDING:?} ${OCONF_SSHD_GID_FORWARDING:?}
EOF
fi


# login user
if feat_all "${OFEAT_LOGIN_USER:-0}"; then
    print_action "sysusers: login user"

    # build list of additional (ssh) groups for the login user
    groups=''
    autodie get_user_extra_groups \
        "${OFEAT_LOGIN_USER_SSH:-0}" \
        "${OFEAT_LOGIN_USER_SSH_SHELL:-0}" \
        "${OFEAT_LOGIN_USER_SSH_FORWARDING:-0}"

    login_user_shell='/bin/bash'
    if [ ! -e "${TARGET_ROOTFS}/${login_user_shell#/}" ]; then
        login_user_shell='/bin/sh'
    fi

    # username uid group gid password home shell groups comment
    autodie dbuild_sysusers_write << EOF
${OCONF_LOGIN_USER:?} ${OCONF_LOGIN_UID:?} ${OCONF_LOGIN_USER:?} ${OCONF_LOGIN_UID:?} ${OCONF_LOGIN_USER_PASSWORD:-*} /home/${OCONF_LOGIN_USER:?} ${login_user_shell:?} ${groups:--} login user
EOF
fi

# unpriv user
if feat_all "${OFEAT_UNPRIV_USER:-0}"; then
    print_action "sysusers: unpriv user"

    # username uid group gid password home shell groups comment
    autodie dbuild_sysusers_write << EOF
${OCONF_UNPRIV_USER:?} ${OCONF_UNPRIV_UID:?} ${OCONF_UNPRIV_USER:?} ${OCONF_UNPRIV_UID:?} * /home/${OCONF_UNPRIV_USER:?} - - unprivileged user
EOF
fi


# ctrl user
if feat_all "${OFEAT_CTRL_USER:-0}"; then
    print_action "sysusers: ctrl user"

    # build list of additional (ssh) groups for the ctrl user
    groups=''
    autodie get_user_extra_groups \
        "${OFEAT_CTRL_USER_SSH:-0}" \
        "${OFEAT_CTRL_USER_SSH_SHELL:-0}" \
        "${OFEAT_CTRL_USER_SSH_FORWARDING:-0}"

    ctrl_user_shell='/bin/sh'

    # username uid group gid password home shell groups comment
    autodie dbuild_sysusers_write << EOF
${OCONF_CTRL_USER:?} ${OCONF_CTRL_UID:?} ${OCONF_CTRL_USER:?} ${OCONF_CTRL_UID:?} * /home/${OCONF_CTRL_USER:?} ${ctrl_user_shell:?} ${groups:--} ctrl user
EOF
fi
