#!/bin/sh

print_action "Configure GRUB/EFI"

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

target_boot="${TARGET_ROOTFS}/boot"
target_esp="${target_boot}/efi"
target_esp_efi="${target_esp}/EFI"
target_esp_boot="${target_esp_efi}/boot"
target_esp_debian="${target_esp_efi}/debian"

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

# write firstboot grub.cfg
autodie dodir_mode "${target_boot}/grub" 0755
autodie write_to_file "${target_boot}/grub/grub.cfg" 0644 << EOF
set default="0"
set timeout="5"

menuentry "Debian Initial Boot" {
    insmod part_gpt
    insmod ext2

    search --no-floppy --fs-uuid --set=root ${boot_fs_uuid}

    echo 'Loading Kernel ${target_boot_kver}'
    linux ${boot_fs_prefix}/vmlinuz-${target_boot_kver} root=UUID=${rootfs_uuid} ro firstboot=1

    echo 'Loading initial ramdisk ...'
    initrd ${boot_fs_prefix}/initrd.img-${target_boot_kver}
}
EOF


autodie dodir_mode "${target_esp}" 0700
autodie dodir_mode "${target_esp_efi}" 0755
autodie dodir_mode "${target_esp_boot}" 0755
autodie dodir_mode "${target_esp_debian}" 0755

# copy EFI bootloader to removable path
if feat_all "${OFEAT_UEFI_SECURE_BOOT:-0}"; then
    # signed bootloader
    print_action "Install GRUB/EFI to ESP (signed)"

    autodie install -m 0700 \
        "${TARGET_ROOTFS:?}/usr/lib/shim/shimx64.efi.signed" \
        "${target_esp_boot}/bootx64.efi"

    autodie install -m 0700 \
        "${TARGET_ROOTFS:?}/usr/lib/grub/x86_64-efi-signed/grubx64.efi.signed" \
        "${target_esp_boot}/grubx64.efi"

else
    # unsigned bootloader
    print_action "Install GRUB/EFI to ESP (unsigned)"

    autodie install -m 0700 \
        "${TARGET_ROOTFS:?}/usr/lib/grub/x86_64-efi/monolithic/grubx64.efi" \
        "${target_esp_boot}/bootx64.efi"
fi

# create stub grub.cfg that chainloads /boot/grub/grub.cfg
#  (must be present in <ESP>/EFI/debian/grub.cfg)
autodie write_to_file "${target_esp_debian}/grub.cfg" 0600 << EOF
search.fs_uuid ${boot_fs_uuid} root
set prefix=(\$root)'${boot_fs_prefix}/grub'
configfile \$prefix/grub.cfg
EOF
