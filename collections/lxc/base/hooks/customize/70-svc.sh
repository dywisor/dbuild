#!/bin/sh
# Enable/disable various services for LXC containers

print_action "Enable/disable various services for LXC containers"


if target_is_systemd; then
    autodie target_enable_svc \
        autoconfig-networkd-interfaces.service \
        systemd-networkd.service

    # enable console
    autodie target_enable_svc \
        console-getty.service

    # broken on LXC
    autodie target_mask_svc \
        sys-kernel-config.mount \
        sys-kernel-debug.mount \
        systemd-journald-audit.socket

    # not needed
    autodie target_disable_svc \
        getty@tty1.service \
        fstrim.timer

    autodie target_mask_svc \
        systemd-resolved.service \
        systemd-modules-load.service \
        modprobe@.service \
        networking

else
    autodie target_enable_svc \
        networking
fi
