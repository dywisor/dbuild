#!/bin/sh
# Request initramfs rebuild with early nftables rules.
#

print_action "Request initramfs rebuild for nftables"
autodie dbuild_want_update_initramfs
