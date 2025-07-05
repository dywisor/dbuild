#!/bin/sh
# Enable unattended upgrades

if feat_all "${OFEAT_UNATTENDED_UPGRADES:-0}"; then
    print_action "Enabling unattended upgrades"

    autodie target_debconf << EOF
unattended-upgrades unattended-upgrades/enable_auto_updates boolean true
EOF
fi
