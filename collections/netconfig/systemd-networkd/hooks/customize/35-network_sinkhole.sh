#!/bin/sh
# Configure network sinkhole

if ! {
    feat_all "${OFEAT_NET_SINKHOLE:-0}" && \
    [ "${OCONF_NETCONFIG_PROVIDER:-}" = 'systemd-networkd' ]
}; then
    exit 0
fi

gen_networkd_sinkhole_netdev() {
cat << EOF
[NetDev]
Description = sinkhole interface
Name        = ${OCONF_NET_SINKHOLE_NAME:?}
Kind        = dummy
EOF
}

gen_sinkhole_route() {
    while [ $# -gt 0 ];do
        {
cat << EOF

[Route]
Destination = ${1:?}
Type        = ${OCONF_NET_SINKHOLE_ROUTE_TYPE:?}
EOF
        }
        shift
    done
}

gen_networkd_sinkhole_network() {
cat << EOF
[Match]
Name = ${OCONF_NET_SINKHOLE_NAME:?}

[Link]
RequiredForOnline       = no

[Network]
Description             = sinkhole interface
ConfigureWithoutCarrier = yes
IgnoreCarrierLoss       = yes
DHCP                    = no
LinkLocalAddressing     = no
IPv6AcceptRA            = no
EOF

    # Sinkhole routes
    # * IPv4: list accumulated by merge-config.py
    if [ -n "${OCONF_NET_SINKHOLE_ROUTES_IP4-}" ]; then
        # set -o noglob is enabled globally
        gen_sinkhole_route ${OCONF_NET_SINKHOLE_ROUTES_IP4-}
    fi

    # * IPv6: list accumulated by merge-config.py
    if [ -n "${OCONF_NET_SINKHOLE_ROUTES_IP6-}" ]; then
        # set -o noglob is enabled globally
        gen_sinkhole_route ${OCONF_NET_SINKHOLE_ROUTES_IP6-}
    fi
}

print_action "Configure network sinkhole interface"

autodie dodir_mode "${TARGET_ROOTFS}/etc/systemd/network"
conf_index='01'
conf_name="${OCONF_NET_SINKHOLE_NAME:?}"

# create .netdev file
autodie dofile \
    "${TARGET_ROOTFS}/etc/systemd/network/${conf_index:?}-${conf_name:?}.netdev" \
    0644 "0:0" \
    gen_networkd_sinkhole_netdev

# create .network file
autodie dofile \
    "${TARGET_ROOTFS}/etc/systemd/network/${conf_index:?}-${conf_name:?}.network" \
    0644 "0:0" \
    gen_networkd_sinkhole_network
