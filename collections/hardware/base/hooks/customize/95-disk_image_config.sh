#!/bin/sh

diskimage_config="${DBUILD_STAGING_TMP:?}/diskimage-efi.cfg"
diskimage_config_template="${HOOK_FILESDIR:?}/tar-to-disk.yml.in"

esp_enabled=0

case "${OCONF_BOOT_TYPE:?}" in
    'uefi')
        esp_enabled=1
    ;;
esac

autodie rm -f -- "${diskimage_config}"
set -- \
    -e "s=@@ROOT_DISK_VG_NAME@@=${OCONF_HW_ROOT_VG_NAME:?}=g" \
    -e "s=@@ROOT_DISK_SIZE@@=${OCONF_HW_ROOT_DISK_SIZE:?}=g" \
    -e "s=@@BOOT_TYPE@@=${OCONF_BOOT_TYPE:?}=g" \
    \
    -e "s=@@BOOT_RAID_ENABLED@@=${OFEAT_HW_BOOT_RAID1:?}=g" \
    -e "s=@@ROOT_RAID_ENABLED@@=${OFEAT_HW_ROOT_VG_RAID1:?}=g" \
    -e "s=@@ROOT_LUKS_ENABLED@@=${OFEAT_HW_ROOT_VG_LUKS:?}=g" \
    -e "s=@@ROOT_LUKS_PASSPHRASE@@=${OCONF_HW_ROOT_VG_LUKS_PASSPHRASE:?}=g" \
    \
    -e "s=@@BOOT_SIZE@@=${OCONF_HW_BOOT_SIZE:?}=g" \
    \
    -e "s=@@ESP_SIZE@@=${OCONF_HW_ESP_SIZE:?}=g" \
    -e "s=@@ESP_ENABLED@@=${esp_enabled:?}=g" \
    \
    -e "s=@@ROOTFS_SIZE@@=${OCONF_HW_ROOTFS_SIZE:?}=g" \
    -e "s=@@ROOTFS_FSTYPE@@=${OCONF_ROOTFS_TYPE:?}=g" \
    -e "s=@@ROOTFS_COMPRESSION@@=${OCONF_HW_ROOTFS_COMPRESSION?}=g" \
    \
    -e "s=@@SWAP_SIZE@@=${OCONF_HW_SWAP_SIZE:?}=g" \
    -e "s=@@SWAP_ENABLED@@=${OFEAT_HW_SWAP:?}=g" \
    \
    -e "s=@@LOG_SIZE@@=${OCONF_HW_LOG_LV_SIZE:?}=g" \
    -e "s=@@LOG_ENABLED@@=${OFEAT_HW_LOG_LV:?}=g" \
    \
    -e "s=@@APT_CACHE_SIZE@@=${OCONF_HW_APT_CACHE_LV_SIZE:?}=g" \
    -e "s=@@APT_CACHE_ENABLED@@=${OFEAT_HW_APT_CACHE_LV:?}=g"


{
    < "${diskimage_config_template}" > "${diskimage_config}" sed -r "${@}"
} || die "Failed to generate diskimage config"

# publish disk image config (STUB)
autodie cp -- \
    "${diskimage_config}" \
    "${DBUILD_STAGING_IMG:?}/diskimage.yml"
