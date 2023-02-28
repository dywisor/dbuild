#!/bin/sh

rootfs_uuid=
read -r rootfs_uuid < "${DBUILD_STAGING_TMP:?}/uuid.rootfs" \
    && [ -n "${rootfs_uuid}" ] || die "Failed to read rootfs uuid"

boot_uuid=
read -r boot_uuid < "${DBUILD_STAGING_TMP:?}/uuid.boot" \
    && [ -n "${boot_uuid}" ] || die "Failed to read boot uuid"

diskimage_config="${DBUILD_STAGING_TMP:?}/diskimage-efi.cfg"
diskimage_config_template="${HOOK_FILESDIR:?}/tar-to-disk.yml.in"

esp_enabled=0

case "${OCONF_HW_BOOT_TYPE:?}" in
    'uefi')
        esp_enabled=1
    ;;
esac

autodie rm -f -- "${diskimage_config}"
set -- \
    -e "s=@@ROOT_DISK_VG_NAME@@=${OCONF_HW_ROOT_VG_NAME:?}=g" \
    -e "s=@@ROOT_DISK_SIZE@@=${OCONF_HW_ROOT_DISK_SIZE:?}=g" \
    -e "s=@@BOOT_TYPE@@=${OCONF_HW_BOOT_TYPE:?}=g" \
    \
    -e "s=@@BOOT_SIZE@@=${OCONF_HW_BOOT_SIZE:?}=g" \
    -e "s=@@BOOT_UUID@@=${boot_uuid:?}=g" \
    \
    -e "s=@@ESP_SIZE@@=${OCONF_HW_ESP_SIZE:?}=g" \
    -e "s=@@ESP_ENABLED@@=${esp_enabled:?}=g" \
    \
    -e "s=@@ROOTFS_SIZE@@=${OCONF_HW_ROOTFS_SIZE:?}=g" \
    -e "s=@@ROOTFS_FSTYPE@@=${OCONF_ROOTFS_TYPE:?}=g" \
    -e "s=@@ROOTFS_UUID@@=${rootfs_uuid:?}=g" \
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
