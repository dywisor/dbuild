#!/bin/sh
# Reset update-initramfs env

print_action "Reset update-initramfs env"
autodie dbuild_reset_update_initramfs_env
