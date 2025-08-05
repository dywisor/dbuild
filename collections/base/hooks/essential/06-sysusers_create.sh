#!/bin/sh
# Create system users/groups (early during 'essential')
print_action "Creating sysusers (early)"
dbuild_sysusers_print

autodie "${DBUILD_BUILD_SCRIPTS:?}/make_sysusers.py" \
    --root "${TARGET_ROOTFS:?}" \
    "${DBUILD_STAGING_SYSUSERS:?}"
