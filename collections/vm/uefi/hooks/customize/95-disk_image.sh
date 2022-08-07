#!/bin/sh

esp_partuuid=
read -r esp_partuuid < "${DBUILD_STAGING_TMP:?}/partuuid.esp" \
    && [ -n "${esp_partuuid}" ] || die "Failed to read esp partuuid"

if feat_all "${OFEAT_VM_SWAP:-0}"; then
    swap_partuuid=
    read -r swap_partuuid < "${DBUILD_STAGING_TMP:?}/partuuid.swap" \
        && [ -n "${swap_partuuid}" ] || die "Failed to read swap partuuid"

    swap_uuid=
    read -r swap_uuid < "${DBUILD_STAGING_TMP:?}/uuid.swap" \
        && [ -n "${swap_uuid}" ] || die "Failed to read swap uuid"
fi

rootfs_partuuid=
read -r rootfs_partuuid < "${DBUILD_STAGING_TMP:?}/partuuid.rootfs" \
    && [ -n "${rootfs_partuuid}" ] || die "Failed to read rootfs partuuid"

rootfs_uuid=
read -r rootfs_uuid < "${DBUILD_STAGING_TMP:?}/uuid.rootfs" \
    && [ -n "${rootfs_uuid}" ] || die "Failed to read rootfs uuid"

genimage_config="${DBUILD_STAGING_TMP:?}/genimage-efi.cfg"
genimage_config_template="${HOOK_FILESDIR:?}/genimage-efi.cfg.in"

autodie rm -f -- "${genimage_config}"
set -- \
    -e "s=@@ESP_PARTUUID@@=${esp_partuuid}=g" \
    -e "s=@@ESP_SIZE@@=${OCONF_VM_ESP_SIZE:?}=g" \
    -e "s=@@ROOTFS_PARTUUID@@=${rootfs_partuuid}=g" \
    -e "s=@@ROOTFS_UUID@@=${rootfs_uuid}=g" \
    -e "s=@@ROOTFS_SIZE@@=${OCONF_VM_ROOTFS_SIZE:?}=g"

if feat_all "${OFEAT_VM_SWAP:-0}"; then
    set -- "${@}" \
        -e "s=@@SWAP_PARTUUID@@=${swap_partuuid}=g"

    print_action "Creating swap space"
    (
        umask 0077 && \
        autodie truncate \
            --size="${OCONF_VM_SWAP_SIZE:?}" \
            "${DBUILD_STAGING_TMP:?}/swap.file"
    ) || exit
    autodie mkswap -L swap -U "${swap_uuid}" "${DBUILD_STAGING_TMP:?}/swap.file"

else
    set -- "${@}" \
        -e '/^## BEGIN OFEAT_VM_SWAP$/,/## END OFEAT_VM_SWAP$/d'
fi

{
    < "${genimage_config_template}" > "${genimage_config}" sed -r "${@}"
} || die "Failed to generate genimage config"


print_action "Building disk image"
autodie genimage \
    --rootpath      "${TARGET_ROOTFS:?}" \
    --inputpath     "${DBUILD_STAGING_TMP:?}" \
    --outputpath    "${DBUILD_STAGING_TMP:?}" \
    --config        "${genimage_config}"
