#!/bin/sh
# Enable/disable various services for systemd targets

print_action "Enable/disable various services for systemd targets"

# dbus is statically enabled
## autodie target_enable_svc \
##     dbus
