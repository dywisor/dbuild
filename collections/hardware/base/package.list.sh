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
