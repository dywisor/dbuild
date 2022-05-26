#!/bin/sh

# /etc/hosts
target_write_to_file /etc/hosts 0644 << EOF
127.0.0.1   localhost

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOF

# remove /etc/hostname
autodie rm -- "${TARGET_ROOTFS:?}/etc/hostname"

# remove /etc/resolv.conf
autodie rm -- "${TARGET_ROOTFS:?}/etc/resolv.conf"


# remove /etc/machine-id (if present)
if [ -e "${TARGET_ROOTFS:?}/etc/machine-id" ]; then
    autodie rm -- "${TARGET_ROOTFS:?}/etc/machine-id"
fi

# remove SSH host keys
autodie find "${TARGET_ROOTFS:?}/etc/ssh" \
    -mindepth 1 -maxdepth 1 \
    -type f \
    \( -name 'ssh_host_*_key' -or -name 'ssh_host_*_key.pub' \) \
    -delete
