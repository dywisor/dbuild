#!/bin/sh
# Configure the unpriv user

if feat_all "${OFEAT_UNPRIV_USER:-0}"; then
    # create unpriv user group
    autodie target_chroot groupadd \
        -g "${OCONF_UNPRIV_UID}" \
        "${OCONF_UNPRIV_USER}"

    # create unpriv user
    autodie target_chroot useradd \
        -c 'unprivileged user' \
        -d "/home/${OCONF_UNPRIV_USER}" \
        -g "${OCONF_UNPRIV_UID}" \
        -M \
        -p '*' \
        -s '/usr/sbin/nologin' \
        -u "${OCONF_UNPRIV_UID}" \
        "${OCONF_UNPRIV_USER}"

    # create home directory for the unpriv user
    autodie dodir_mode \
        "${TARGET_ROOTFS:?}/home/${OCONF_UNPRIV_USER}" \
        '0700' \
        "${OCONF_UNPRIV_UID}:${OCONF_UNPRIV_UID}"
fi
