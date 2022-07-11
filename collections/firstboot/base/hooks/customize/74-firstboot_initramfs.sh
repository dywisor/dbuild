#!/bin/sh
# Regenerate initramfs with firstboot mode support enabled.
#

print_action "Regenerate initramfs with firstboot mode support"
autodie target_chroot env INITRAMFS_FIRSTBOOT=YES update-initramfs -u -k all
