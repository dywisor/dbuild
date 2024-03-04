#!/bin/sh
# Enable/disable various services for systemd-networkd targets

print_action "Enable/disable various services for systemd-networkd targets"

if feat_all "${OFEAT_NETCONFIG:-0}" && [ "${OCONF_NETCONFIG_PROVIDER:-}" = 'systemd-networkd' ]; then
    # enable systemd-networkd (but do not disable otherwise)
    autodie target_enable_svc systemd-networkd
fi
