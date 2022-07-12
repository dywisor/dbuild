#!/bin/sh

esp_partuuid=
read -r esp_partuuid < "${DBUILD_STAGING_TMP:?}/partuuid.esp" \
    && [ -n "${esp_partuuid}" ] || die "Failed to read esp partuuid"

swap_partuuid=
read -r swap_partuuid < "${DBUILD_STAGING_TMP:?}/partuuid.swap" \
    && [ -n "${swap_partuuid}" ] || die "Failed to read swap partuuid"

swap_uuid=
read -r swap_uuid < "${DBUILD_STAGING_TMP:?}/uuid.swap" \
    && [ -n "${swap_uuid}" ] || die "Failed to read swap uuid"

rootfs_partuuid=
read -r rootfs_partuuid < "${DBUILD_STAGING_TMP:?}/partuuid.rootfs" \
    && [ -n "${rootfs_partuuid}" ] || die "Failed to read rootfs partuuid"

rootfs_uuid=
read -r rootfs_uuid < "${DBUILD_STAGING_TMP:?}/uuid.rootfs" \
    && [ -n "${rootfs_uuid}" ] || die "Failed to read rootfs uuid"

genimage_config="${DBUILD_STAGING_TMP:?}/genimage-efi.cfg"
genimage_config_template="${HOOK_FILESDIR:?}/genimage-efi.cfg.in"

autodie rm -f -- "${genimage_config}"
{
< "${genimage_config_template}" > "${genimage_config}" sed -r \
    -e "s=@@ESP_PARTUUID@@=${esp_partuuid}=g" \
    -e "s=@@SWAP_PARTUUID@@=${swap_partuuid}=g" \
    -e "s=@@ROOTFS_PARTUUID@@=${rootfs_partuuid}=g" \
    -e "s=@@ROOTFS_UUID@@=${rootfs_uuid}=g"
} || die "Failed to generate genimage config"


print_action "Creating swap space"
( umask 0077 && autodie truncate --size=536870912 "${DBUILD_STAGING_TMP:?}/swap.img"; ) || exit
autodie mkswap -L swap -U "${swap_uuid}" "${DBUILD_STAGING_TMP:?}/swap.img"

print_action "Building disk image"
autodie genimage \
    --rootpath      "${TARGET_ROOTFS:?}" \
    --inputpath     "${DBUILD_STAGING_TMP:?}" \
    --outputpath    "${DBUILD_STAGING_TMP:?}" \
    --config        "${genimage_config}"

autodie zstd -z \
    "${DBUILD_STAGING_TMP:?}/disk.img" \
    -o "${DBUILD_STAGING_IMG:?}/disk.img.zst"

find "${DBUILD_STAGING_IMG}"
ls -lh "${TARGET_ROOTFS:?}/sbin/init"
