#!/bin/sh

print_action "Configure GRUB/BIOS"

# STUB, no action

# read boot or rootfs UUID
boot_fs_uuid=
boot_fs_prefix=

read -r rootfs_uuid < "${DBUILD_STAGING_TMP:?}/uuid.rootfs" \
    && [ -n "${rootfs_uuid}" ] || die "Failed to read rootfs uuid"

if {
    [ -r "${DBUILD_STAGING_TMP:?}/uuid.boot" ] && \
    read -r boot_fs_uuid < "${DBUILD_STAGING_TMP:?}/uuid.boot" && \
    [ -n "${boot_fs_uuid}" ]
}; then
    # booting from separate /boot
    boot_fs_prefix=

else
    boot_fs_uuid="${rootfs_uuid}"
    boot_fs_prefix=/boot
fi


# directory paths
target_boot="${TARGET_ROOTFS}/boot"

# /boot must already exist (see grub_config hook)
#autodie dodir_mode "${target_boot}" 0755

# /boot/grub/grub.cfg must already exist (see grub_config hook)
