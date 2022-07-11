#!/bin/sh
# Create firstboot /etc/motd
#

print_action "Create firstboot /etc/motd"

if [ -e "${TARGET_ROOTFS}/etc/motd" ]; then
    autodie rm -f -- "${TARGET_ROOTFS}/etc/motd.dist"
    autodie mv -- "${TARGET_ROOTFS}/etc/motd" "${TARGET_ROOTFS}/etc/motd.dist"
fi

( set +f; cat -- "${TARGET_ROOTFS}/etc/firstboot-motd.d"/*.motd; ) > "${TARGET_ROOTFS}/etc/motd"
