#!/bin/sh
# Configure the unpriv user

if feat_all "${OFEAT_UNPRIV_USER:-0}"; then
    # unpriv user already created by sysusers, get uid/gid
    autodie target_getpwnam_id "${OCONF_UNPRIV_USER:?}"
    unpriv_user_uid="${pw_uid:?}"
    unpriv_user_gid="${pw_gid:?}"
    # TODO/LATER: pw_dir ?
    unpriv_user_home="/home/${OCONF_UNPRIV_USER:?}"

    # create home directory for the unpriv user
    autodie dodir_mode \
        "${TARGET_ROOTFS:?}${unpriv_user_home:?}" \
        '0700' \
        "${unpriv_user_uid}:${unpriv_user_gid}"
fi
