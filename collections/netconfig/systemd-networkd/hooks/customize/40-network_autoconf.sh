#!/bin/sh
# Configure network interfaces automatically on boot

if ! {
    feat_all "${OFEAT_NETCONFIG:-0}" && \
    [ "${OCONF_NETCONFIG_PROVIDER:-}" = 'systemd-networkd' ]
}; then
    exit 0
fi

MATCH_INTERFACE_TYPE='ether'

# @stdout gen_networkd_link_rename ( **OFEAT_*, **OCONF_* )
gen_networkd_link_rename() {
    printf '[Match]\n'

    if [ -n "${OCONF_NETCONFIG_IFACE_BY_MAC-}" ]; then
        printf 'PermanentMACAddress = %s\n' "${OCONF_NETCONFIG_IFACE_BY_MAC}"
    elif [ -n "${OCONF_NETCONFIG_IFACE_BY_NAME-}" ]; then
        printf 'OriginalName = %s\n' "${OCONF_NETCONFIG_IFACE_BY_NAME}"
    else
        die "Cannot match interface..."
    fi

cat << EOF
Type = ${MATCH_INTERFACE_TYPE:?}

[Link]
NamePolicy =
Name = ${OCONF_NETCONFIG_IFACE_NAME:?}
EOF
}


# @stdout gen_networkd_network_address ( address )
gen_networkd_network_address() {
cat << EOF

[Address]
Address                 = ${1:?}
EOF
}


# @stdout gen_networkd_network_address ( destination, gateway )
gen_networkd_network_route() {
cat << EOF

[Route]
Destination             = ${1:?}
Gateway                 = ${2:?}
EOF
}

# @stdout gen_networkd_network ( **OFEAT_*, **OCONF_* )
gen_networkd_network() {
    local opt_dhcp4
    local opt_dhcp6
    local cfg_dhcp
    local cfg_ip6
    local cfg_ip6_slaac

    opt_dhcp4=0
    opt_dhcp6=0
    cfg_dhcp='no'
    cfg_ip6='no'
    cfg_ip6_slaac='no'

    if feat_all "${OFEAT_NETCONFIG_IP4:-0}"; then
        if feat_all "${OFEAT_NETCONFIG_IP4_DHCP:-0}"; then
            opt_dhcp4=1
        fi
    fi

    if feat_all "${OFEAT_NETCONFIG_IP6:-0}"; then
        cfg_ip6='yes'

        if feat_all "${OFEAT_NETCONFIG_IP6_DHCP:-0}"; then
            opt_dhcp6=1
        fi

        if feat_all "${OFEAT_NETCONFIG_IP6_SLAAC:-0}"; then
            cfg_ip6_slaac='yes'
        fi
    fi

    case "${opt_dhcp4}${opt_dhcp6}" in
        00) cfg_dhcp='no' ;;
        01) cfg_dhcp='ipv6' ;;
        10) cfg_dhcp='ipv4' ;;
        11) cfg_dhcp='yes' ;;
        *) die "dhcp config error" ;;
    esac

    if [ -n "${OCONF_NETCONFIG_IFACE_NAME-}" ]; then
        # match by (renamed) interface name
        printf '[Match]\n'
        printf 'Name = %s\n' "${OCONF_NETCONFIG_IFACE_NAME}"

    else
        # match by MAC address or (original/not-renamed-here) interface name
        printf '[Match]\n'

        if [ -n "${OCONF_NETCONFIG_IFACE_BY_MAC-}" ]; then
            printf 'PermanentMACAddress = %s\n' "${OCONF_NETCONFIG_IFACE_BY_MAC}"
        elif [ -n "${OCONF_NETCONFIG_IFACE_BY_NAME-}" ]; then
            printf 'Name = %s\n' "${OCONF_NETCONFIG_IFACE_BY_NAME}"
        else
            printf 'Name = *\n'
        fi

        printf 'Type = %s\n' "${MATCH_INTERFACE_TYPE:?}"
    fi

    printf '\n'
    printf '[Link]\n'
    printf 'RequiredForOnline       = %s\n' "routable"
    printf '\n'
    printf '[Network]\n'
    printf 'Description             = %s\n' "default network"
    printf 'DHCP                    = %s\n' "${cfg_dhcp}"
    printf 'LinkLocalAddressing     = %s\n' "${cfg_ip6}"
    printf 'IPv6AcceptRA            = %s\n' "${cfg_ip6_slaac}"
    printf 'IPv6PrivacyExtensions   = %s\n' "yes"

    if [ "${opt_dhcp4}" -eq 1 ]; then
        printf '\n'
        printf '[DHCPv4]\n'
        printf 'SendHostname            = no\n'
    fi

    if [ "${opt_dhcp6}" -eq 1 ]; then
        printf '\n'
        printf '[DHCPv6]\n'
        printf 'SendHostname            = no\n'
    fi

    if feat_all "${OFEAT_NETCONFIG_IP4:-0}" "${OFEAT_NETCONFIG_IP4_STATIC:-0}"; then
        gen_networkd_network_address "${OCONF_NETCONFIG_IP4_STATIC:?}"

        if [ -n "${OCONF_NETCONFIG_IP4_STATIC_GW-}" ]; then
            gen_networkd_network_route '0.0.0.0/0' "${OCONF_NETCONFIG_IP4_STATIC_GW:?}"
        fi
    fi

    if feat_all "${OFEAT_NETCONFIG_IP6:-0}" "${OFEAT_NETCONFIG_IP6_STATIC:-0}"; then
        gen_networkd_network_address "${OCONF_NETCONFIG_IP6_STATIC:?}"

        if [ -n "${OCONF_NETCONFIG_IP6_STATIC_GW-}" ]; then
            gen_networkd_network_route '::/0' "${OCONF_NETCONFIG_IP6_STATIC_GW:?}"
        fi
    fi
}


autodie dodir_mode "${TARGET_ROOTFS}/etc/systemd/network"

conf_index='10'
case "${OCONF_NETCONFIG_IFACE_BY_NAME-}" in
    ''|*'*'*)
        conf_name='eth'
    ;;
    *)
        conf_name="${OCONF_NETCONFIG_IFACE_BY_NAME:?}"
    ;;
esac

# create .link file if necessary
if [ -n "${OCONF_NETCONFIG_IFACE_NAME-}" ]; then
    # FIXME: not checking for valid OCONF_NETCONFIG_IFACE_NAME (but should be done elsewhere)
    conf_name="${OCONF_NETCONFIG_IFACE_NAME:?}"

    if [ -n "${OCONF_NETCONFIG_IFACE_BY_MAC-}" ] || [ -n "${OCONF_NETCONFIG_IFACE_BY_NAME-}" ]; then
        autodie dofile \
            "${TARGET_ROOTFS}/etc/systemd/network/${conf_index:?}-${conf_name:?}.link" \
            0644 "0:0" \
            gen_networkd_link_rename

        print_action "Request initramfs rebuild due to systemd-networkd link file changes"
        autodie dbuild_want_update_initramfs
    fi
fi

# create .network file
autodie dofile \
    "${TARGET_ROOTFS}/etc/systemd/network/${conf_index:?}-${conf_name:?}.network" \
    0644 "0:0" \
    gen_networkd_network
