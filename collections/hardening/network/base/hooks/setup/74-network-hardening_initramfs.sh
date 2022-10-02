#!/bin/sh
# Request initramfs rebuild with early network hardening.
#

print_action "Request initramfs rebuild for network-hardening"
autodie dbuild_want_update_initramfs
