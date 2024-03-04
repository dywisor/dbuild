#!/bin/sh
# Enable/disable various services for systemd targets

print_action "Enable/disable various services for systemd targets"

if feat_all "${OFEAT_NTP_CONF:-0}"; then
    autodie target_mask_svc systemd-timesyncd.service
fi

# dbus is statically enabled
## autodie target_enable_svc \
##     dbus
