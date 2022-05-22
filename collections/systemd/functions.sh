#!/bin/sh

target_is_systemd()     { return 0; }
target_is_sysvinit()    { return 1; }


# target_systemctl ( "enable"|"disable"|"mask", unit... )
if __have_cmd__ systemctl; then
    target_systemctl() {
        systemctl --root "${TARGET_ROOTFS:?}" "${@}"
    }

else
    target_systemctl() {
        die "systemctl actions need a host running systemd"
    }
fi


# target_set_svc ( "0"|"disable"|"1"|"enable"|"mask", *svc )
target_set_svc() {
    local action

    action="${1:?}"; shift

    case "${action}" in
        '0'|'disable')
            action='disable'
        ;;
        '1'|'enable')
            action='enable'
        ;;
        'mask')
            action='mask'
        ;;
        *)
            return 64
        ;;
    esac

    while [ $# -gt 0 ]; do
        print_info "${action} svc: ${1}"
        target_systemctl "${action}" "${1}"

        shift
    done
}


target_enable_svc()     { target_set_svc enable "${@}"; }
target_disable_svc()    { target_set_svc disable "${@}"; }
target_mask_svc()       { target_set_svc mask "${@}"; }
