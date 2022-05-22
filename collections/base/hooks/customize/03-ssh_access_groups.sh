#!/bin/sh
# Create ssh access groups

if feat_all "${OFEAT_SSHD_CONFIG:-0}"; then
    # create ssh login group
    autodie target_chroot groupadd \
        -g "${OCONF_SSHD_GID_LOGIN:?}" \
        "${OCONF_SSHD_GROUP_LOGIN:?}"

    # create ssh shell group
    autodie target_chroot groupadd \
        -g "${OCONF_SSHD_GID_SHELL:?}" \
        "${OCONF_SSHD_GROUP_SHELL:?}"

    # create ssh forwarding group
    autodie target_chroot groupadd \
        -g "${OCONF_SSHD_GID_FORWARDING:?}" \
        "${OCONF_SSHD_GROUP_FORWARDING:?}"
fi
