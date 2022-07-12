#!/bin/sh
# Configure network interfaces automatically on boot

gen_autoconf_iface() {
    < "${HOOK_FILESDIR:?}/default-network/by-name.network.in" \
        sed -r -e "s#@@IFNAME@@#${OCONF_NETCONFIG_DHCP_IFACE:?}#g"
}


if feat_all "${OFEAT_NETCONFIG_DHCP:-0}"; then

    if feat_all "${OFEAT_IFNAMES:-1}"; then
        print_action "Configure all network interfaces automatically on boot"

        autodie dodir_mode "${TARGET_ROOTFS}/etc/systemd/network"
        autodie install -m 0644 -- \
            "${HOOK_FILESDIR:?}/default-network/by-type.network" \
            "${TARGET_ROOTFS}/etc/systemd/network/98-autoconf.network"

    elif [ -n "${OCONF_NETCONFIG_DHCP_IFACE-}" ]; then
        print_action "Configure network interface ${OCONF_NETCONFIG_DHCP_IFACE} automatically on boot"

        autodie dodir_mode "${TARGET_ROOTFS}/etc/systemd/network"
        autodie dofile \
            "${TARGET_ROOTFS}/etc/systemd/network/98-autoconf.network" \
            0644 "0:0" \
            gen_autoconf_iface

    else
        die "OFEAT_NETCONFIG_DHCP=1, OFEAT_IFNAMES=0: requires non-empty OCONF_NETCONFIG_DHCP_IFACE"
    fi
fi
