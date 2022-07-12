#!/bin/sh
# systemd config for LXC containers

if ! target_is_systemd; then
    exit 0
fi

print_action "systemd configuration for LXC"

# The default 10% runtime dir rule doesn't really work for LXC containers.
# At least in Proxmox PVE, the host announces the whole amount of memory,
# but the container can only use its allocated size.
# However, 10% of "whole memory" usually amounts to a very large number
# (depending on the host).
#
autodie dodir_mode "${TARGET_ROOTFS:?}/etc/systemd/logind.conf.d"
target_write_to_file /etc/systemd/logind.conf.d/rundir-size.conf 0644 << EOF
[Login]
RuntimeDirectorySize = 100M
EOF


# Let journald log to tmpfs only
#
#   Use rsyslog for persistent storage (locally or via network).
#
autodie dodir_mode "${TARGET_ROOTFS:?}/etc/systemd/journald.conf.d"
target_write_to_file /etc/systemd/journald.conf.d/volatile.conf 0644 << EOF
[Journal]
Storage             = volatile
Compress            = yes
Seal                = no

RuntimeMaxUse       = 10M
RuntimeKeepFree     = 60M
RuntimeMaxFileSize  = 1M
RuntimeMaxFiles     = 10

# no point in reading kmsg in (unpriv) LXC containers
ReadKMsg            = no
EOF
