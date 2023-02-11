#!/bin/sh
# Set the rootfs type for the firstboot initramfs config

if [ -z "${OCONF_ROOTFS_TYPE-}" ]; then
    exit 0
fi

print_action "Configure FSTYPE for initramfs firstboot"

{
    printf '\nFSTYPE=%s\n' "${OCONF_ROOTFS_TYPE}" \
        >> "${TARGET_ROOTFS}/etc/initramfs-tools/conf.d/90-firstboot-base"
} || die "Failed to set initramfs rootfs type"
