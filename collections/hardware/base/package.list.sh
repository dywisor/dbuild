#!/bin/sh
# dynamic package list for the 'hardware/base' collection
set -fu

# mdadm?
if \
    [ "${OFEAT_HW_BOOT_RAID1:-0}" -eq 1 ] || \
    [ "${OFEAT_HW_ROOT_VG_RAID1:-0}" -eq 1 ]
then
    printf '%s\n' \
        mdadm
fi

# LUKS?
if [ "${OFEAT_HW_ROOT_VG_LUKS:-0}" -eq 1 ]; then
    printf '%s\n' \
        cryptsetup \
        cryptsetup-initramfs
fi

# (LVM is always enabled)

# separate boot needs e2fsprogs
if [ "${OFEAT_SEPARATE_BOOT:-0}" -eq 1 ]; then
    printf '%s\n' e2fsprogs
fi

# btrfs-progs / e2fsprogs depending on rootfs
case "${OCONF_ROOTFS_TYPE-}" in
    'ext4')
        printf '%s\n' e2fsprogs
    ;;
    'btrfs')
        printf '%s\n' btrfs-progs
    ;;
esac
