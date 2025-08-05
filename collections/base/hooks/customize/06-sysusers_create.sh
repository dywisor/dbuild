#!/bin/sh
# Create system users/groups (late during 'customize', this may update password hashes again)
print_action "Creating sysusers (late)"
dbuild_sysusers_print

autodie "${DBUILD_BUILD_SCRIPTS:?}/make_sysusers.py" \
    --root "${TARGET_ROOTFS:?}" \
    "${DBUILD_STAGING_SYSUSERS:?}"
