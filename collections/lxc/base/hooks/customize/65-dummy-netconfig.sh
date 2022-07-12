#!/bin/sh
# Create a dummy /etc/network/interfaces file

autodie dodir_mode "${TARGET_ROOTFS:?}/etc/network"
autodie touch "${TARGET_ROOTFS:?}/etc/network/interfaces"
