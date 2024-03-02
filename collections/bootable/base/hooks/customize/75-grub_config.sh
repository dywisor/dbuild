#!/bin/sh

print_action "Configure GRUB/generic"

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

# initialize additional grub config vars
grub_insmod_list=

#> grub insmod: partitioning scheme
case "${OCONF_BOOT_TYPE-}" in
    'uefi')
        grub_insmod_list="${grub_insmod_list} part_gpt"
    ;;
    *)
        grub_insmod_list="${grub_insmod_list} part_msdos"
    ;;
esac

#> grub insmod: lvm
if feat_all "${OFEAT_GRUB_INSMOD_LVM:-0}"; then
    grub_insmod_list="${grub_insmod_list} lvm"
fi

#> grub insmod: mdadm raid1
if feat_all "${OFEAT_GRUB_INSMOD_MDADM_RAID1:-0}"; then
    grub_insmod_list="${grub_insmod_list} mdraid1x"
fi

#> grub insmod: fstype for loading files from /boot
# NOTE/FIXME: boot fstype is hardcoded to ext4 (-> insmod ext2)
grub_insmod_list="${grub_insmod_list} ext2"

#> grub boot param: rootflags
grub_rootflags=

case "${OCONF_ROOTFS_TYPE-}" in
    'btrfs')
        # btrfs uses the hard-coded "@rootfs" subvolume
        grub_rootflags='subvol=@rootfs'

        # also insmod btrfs when /boot is on the rootfs
        if [ "${rootfs_uuid}" = "${boot_fs_uuid}" ]; then
            grub_insmod_list="${grub_insmod_list} btrfs"
        fi
    ;;
esac

#> grub boot param: additional parameters
grub_boot_params=
if feat_all "${OFEAT_BOOT_CMDLINE:-0}"; then
    grub_boot_params="${OCONF_BOOT_CMDLINE-}"
fi


# directory paths
target_boot="${TARGET_ROOTFS}/boot"

# create /boot in target (should already exist)
autodie dodir_mode "${target_boot}" 0755

# get most recent installed kernel version
# FIXME: amd64-specific
target_boot_kver="$(
     find "${target_boot}" -mindepth 1 -maxdepth 1 \
         -type f -name 'vmlinuz-*-amd64' \
         | sed -r -e 's=^.*/==' -e 's=^vmlinuz-==' \
         | sort -V \
         | tail -n 1
)"
[ -n "${target_boot_kver}" ] || die "Failed to get installed kernel version"

# code snippet for generating grub.cfg (using script-global vars)
gen_grub_cfg() {
    local iter

cat << EOF
set default="0"
set timeout="5"

menuentry "Debian Initial Boot" {
EOF

    for iter in ${grub_insmod_list}; do
cat << EOF
    insmod ${iter}
EOF
    done

cat << EOF

    search --no-floppy --fs-uuid --set=root ${boot_fs_uuid}

    echo 'Loading Kernel ${target_boot_kver}'
    linux ${boot_fs_prefix}/vmlinuz-${target_boot_kver} root=UUID=${rootfs_uuid} ${grub_rootflags:+rootflags=${grub_rootflags}} ro ${grub_boot_params} firstboot=1

    echo 'Loading initial ramdisk ...'
    initrd ${boot_fs_prefix}/initrd.img-${target_boot_kver}
}
EOF
}

# write firstboot grub.cfg
autodie dodir_mode "${target_boot}/grub" 0755
autodie write_to_file "${target_boot}/grub/grub.cfg" 0644 0:0 gen_grub_cfg
