#!/bin/sh
# Remove or generate /etc/resolv.conf
#
# Note that hooks relying on DNS lookups
# may fail when run after this hook.
#

TARGET_RESOLV_CONF="${TARGET_ROOTFS:?}/etc/resolv.conf"

gen_resolv_conf() {
    (
        set -f
        set -- ${OCONF_RESOLV_CONF_NS-}

        if [ $# -eq 0 ]; then
            printf 'Error: OCONF_RESOLV_CONF_NS is empty (must list at least one nameserver)\n' 1>&2
            exit 255
        fi

        printf '# generated /etc/resolv.conf\n'
        if [ -n "${OCONF_RESOLV_CONF_SEARCH-}" ]; then
            printf 'search %s\n' "${OCONF_RESOLV_CONF_SEARCH}"
        fi
        printf 'nameserver %s\n' "${@}"
    )
}


if [ -e "${TARGET_RESOLV_CONF}" ]; then
    print_action "Remove build-time /etc/resolv.conf"
    autodie rm -- "${TARGET_RESOLV_CONF}"
fi


if feat_all "${OFEAT_RESOLV_CONF:-0}"; then
    print_action "Generate /etc/resolv.conf"

    autodie dofile \
        "${TARGET_RESOLV_CONF}" 0644 "0:0" \
        gen_resolv_conf
fi
