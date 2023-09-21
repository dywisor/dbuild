#!/bin/sh

rootfs_uuid=
read -r rootfs_uuid < "${DBUILD_STAGING_TMP:?}/uuid.rootfs" \
    && [ -n "${rootfs_uuid}" ] || die "Failed to read rootfs uuid"

if feat_all "${OFEAT_VM_SWAP:-0}"; then
    swap_uuid=
    read -r swap_uuid < "${DBUILD_STAGING_TMP:?}/uuid.swap" \
        && [ -n "${swap_uuid}" ] || die "Failed to read swap uuid"
fi

print_action "base fstab for UEFI VM images"

gen_fstab() {
cat << EOF
# fstab for UEFI VMs
UUID=${rootfs_uuid} / ext4 discard,relatime,user_xattr,errors=remount-ro 0 1
LABEL=ESP /boot/efi vfat umask=0077 0 2
EOF

    if feat_all "${OFEAT_VM_SWAP:-0}"; then
cat << EOF
UUID=${swap_uuid} none swap sw,nofail 0 0
EOF
    fi
}

autodie target_write_to_file /etc/fstab 0644 0:0 gen_fstab
