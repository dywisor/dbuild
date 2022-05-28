#!/bin/sh

rootfs_uuid=
read -r rootfs_uuid < "${DBUILD_STAGING_TMP:?}/uuid.rootfs" \
    && [ -n "${rootfs_uuid}" ] || die "Failed to read rootfs uuid"

print_action "base fstab for KVM"

autodie target_write_to_file /etc/fstab 0644 << EOF
# fstab for KVM
UUID=${rootfs_uuid} / ext4 discard,relatime,user_xattr,errors=remount-ro 0 1
LABEL=ESP /boot/efi vfat umask=0077 0 1
EOF
