#!/bin/sh
# Enable/disable various services for systemd targets

print_action "Enable/disable various services for systemd targets"

if feat_all "${OFEAT_NETCONFIG_DHCP:-0}"; then
    # enable systemd-networkd (but do not disable otherwise)
    autodie target_enable_svc systemd-networkd
fi

# dbus is statically enabled
## autodie target_enable_svc \
##     dbus
