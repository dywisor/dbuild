#!/bin/sh

print_action "Converting disk images to VMDK for ESXi"
autodie qemu-img convert -O vmdk \
    "${DBUILD_STAGING_TMP:?}/rootfs.img" \
    "${DBUILD_STAGING_TMP:?}/rootfs.vmdk"

if feat_all "${OFEAT_VM_SWAP:-0}"; then
    autodie qemu-img convert -O vmdk \
        "${DBUILD_STAGING_TMP:?}/swap.img" \
        "${DBUILD_STAGING_TMP:?}/swap.vmdk"
fi

print_action "Generating VM configuration (.vmx) for ESXi"

vmx_config="${DBUILD_STAGING_TMP:?}/${DBUILD_PROFILE_NAME:?}.vmx"
vmx_config_template="${HOOK_FILESDIR:?}/esxi.vmx.in"

set -- \
    -e "s=@@VM_NAME@@=${DBUILD_PROFILE_NAME:?}=g" \
    -e "s=@@VM_HW_VERSION@@=${OCONF_VM_ESXI_HW_VERSION:?}=g" \
    -e "s=@@VM_OS_TYPE@@=${OCONF_VM_ESXI_OS_TYPE:?}=g"

if ! feat_all "${OFEAT_VM_SWAP:-0}"; then
    # remove swap drive config
    set -- "${@}" \
        -e '/^## BEGIN OFEAT_VM_SWAP$/,/## END OFEAT_VM_SWAP$/d'
fi

{
    < "${vmx_config_template}" > "${vmx_config}" sed -r "${@}"
} || die "Failed to generate VM config"

print_action "Creating VM image (.ova) for ESXi"
(
    cd "${DBUILD_STAGING_TMP:?}" || exit
    # ovftool tries to writes its log to /tmp/vmware-root/... for whatever reason
    # See "ovftool --help debug" for a full list of extra options.
    autodie ovftool \
        --X:logFile=/dev/null \
        --X:logToConsole=true \
        --X:logLevel=info \
        --X:noPrompting=true \
        "${vmx_config}" \
        "${DBUILD_STAGING_IMG:?}/vm.ova"
) || die "Failed to create VM image"
