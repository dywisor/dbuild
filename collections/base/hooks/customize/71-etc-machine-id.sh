#!/bin/sh
# Remove or create an empty /etc/machine-id
#

TARGET_ETC_MACHINE_ID="${TARGET_ROOTFS:?}/etc/machine-id"


if [ -e "${TARGET_ETC_MACHINE_ID}" ]; then
    print_action "Remove build-time /etc/machine-id"
    autodie rm -- "${TARGET_ETC_MACHINE_ID}"
fi


if feat_all "${OFEAT_ETC_MACHINE_ID:-0}"; then
    print_action "Create empty /etc/machine-id"
    autodie dofile "${TARGET_ETC_MACHINE_ID}" 0444 "0:0"
fi
