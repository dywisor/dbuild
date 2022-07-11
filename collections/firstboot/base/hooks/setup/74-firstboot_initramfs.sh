#!/bin/sh
# Request initramfs rebuild with firstboot mode support enabled.
#

print_action "Request initramfs rebuild with firstboot mode support"
autodie dbuild_want_update_initramfs
autodie dbuild_update_initramfs_env INITRAMFS_FIRSTBOOT=YES
