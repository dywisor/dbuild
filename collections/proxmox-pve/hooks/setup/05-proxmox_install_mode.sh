#!/bin/sh
# Create Proxmox "install mode" flag file
#
#  This fill suppresses some tasks usually performed
#  when installing Proxmox packages.
#
#  Known:
#    * ifupdown2: tries to reload the network configuration otherwise
#      (*might* fail due to ifupdown2 not being active,
#      or, worse, *might* succeed)
#
print_action "Create Proxmox install mode flag file"

autodie touch -- "${TARGET_ROOTFS:?}/proxmox_install_mode"
