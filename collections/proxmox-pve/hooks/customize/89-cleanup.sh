#!/bin/sh
# Proxmox: Cleanup just before finalizing the image

# remove Proxmox "install mode" flag file
print_action "Remove Proxmox install mode flag file"
autodie rm -- "${TARGET_ROOTFS:?}/proxmox_install_mode"

# remove possibly leftover files
# (mmdebstrap complains about stray files in /tmp otherwise)
print_action "Remove Proxmox install leftover files (if present)"
autodie rm -f -- "${TARGET_ROOTFS:?}/tmp/.ifupdown2-first-install"
