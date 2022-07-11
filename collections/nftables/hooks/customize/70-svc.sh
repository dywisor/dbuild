#!/bin/sh
# Enable nftables service

print_action "Enable nftables service"

autodie target_enable_svc nftables
