#!/bin/sh

print_action "Configure GRUB/BIOS"

# *** STUB, no action ***

# get rootfs and boot UUID
rootfs_uuid=
boot_fs_uuid=
boot_fs_prefix=

if feat_all "${OFEAT_GEN_FS_UUID:-0}"; then
    # read rootfs and boot UUID

    read -r rootfs_uuid < "${DBUILD_STAGING_TMP:?}/uuid.rootfs" \
        && [ -n "${rootfs_uuid}" ] || die "Failed to read rootfs uuid"

    if feat_all "${OFEAT_SEPARATE_BOOT:-0}"; then
        read -r boot_fs_uuid < "${DBUILD_STAGING_TMP:?}/uuid.boot" && \
        [ -n "${boot_fs_uuid}" ] || die "Failed to read boot uuid"
    fi

else
    rootfs_uuid='@@ROOT_FS_UUID@@'
    boot_fs_uuid='@@BOOT_FS_UUID@@'
fi

if feat_all "${OFEAT_SEPARATE_BOOT:-0}"; then
    # booting from separate /boot
    boot_fs_prefix=
else
    # /boot on rootfs
    boot_fs_prefix=/boot
    boot_fs_uuid="${rootfs_uuid:?}"
fi


# directory paths
target_boot="${TARGET_ROOTFS}/boot"

# /boot must already exist (see grub_config hook)
#autodie dodir_mode "${target_boot}" 0755

# /boot/grub/grub.cfg must already exist (see grub_config hook)
