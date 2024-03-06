#!/bin/sh
# Enable/disable various services for systemd-networkd targets

print_action "Enable/disable various services for systemd-networkd targets"

if [ "${OCONF_NETCONFIG_PROVIDER:-}" = 'systemd-networkd' ]; then
    if feat_any "${OFEAT_NETCONFIG:-0}" "${OFEAT_NET_SINKHOLE:-0}"; then
        # enable systemd-networkd (but do not disable otherwise)
        autodie target_enable_svc systemd-networkd
    fi
fi
