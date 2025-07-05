#!/bin/sh
# Configure/enable unattended upgrades

# unattended-upgrades config gen
gen_ua_config() {
    set --

    if feat_all "${OFEAT_UNATTENDED_UPGRADES_REBOOT:-0}"; then
        set -- "${@}" -e 's=@@REBOOT@@=true=g'
    else
        set -- "${@}" -e 's=@@REBOOT@@=false=g'
    fi

    if feat_all "${OFEAT_UNATTENDED_UPGRADES_REBOOT_WITH_USERS:-0}"; then
        set -- "${@}" -e 's=@@REBOOT_WITH_USERS@@=true=g'
    else
        set -- "${@}" -e 's=@@REBOOT_WITH_USERS@@=false=g'
    fi

    set -- "${@}" -e "s=@@REBOOT_TIME@@=${OCONF_UNATTENDED_UPGRADES_REBOOT_TIME?}=g"

    sed -r "${@}" < "${HOOK_FILESDIR:?}/51unattended-upgrades-local.in"
}


autodie dodir_mode "${TARGET_ROOTFS:?}/etc/apt/apt.conf.d"

# unattended upgrades config (local overrides in 51* rather than the distribution-default 50* file)
autodie target_write_to_file \
    "/etc/apt/apt.conf.d/51unattended-upgrades-local" \
    "0644" \
    "0:0" \
    gen_ua_config


# enable?
if feat_all "${OFEAT_UNATTENDED_UPGRADES:-0}"; then
    print_action "Enabling unattended upgrades (via apt.conf.d/20auto-upgrades)"
    autodie install -m 0644 -o 0 -g 0 \
        "${HOOK_FILESDIR:?}/20auto-upgrades" \
        "${TARGET_ROOTFS:?}/etc/apt/apt.conf.d/20auto-upgrades"
fi
