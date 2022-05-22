#!/bin/sh
# Configure tmpfs size limits in /etc/fstab

# NOTE: assuming 'clean' fstab, i.e. no previous entry for /dev/shm, /tmp, ...
{
cat << EOF >> "${TARGET_ROOTFS:?}/etc/fstab"
tmpfs /dev/shm  tmpfs   defaults,rw,nosuid,nodev,size=120m 0 0
tmpfs /tmp      tmpfs   defaults,rw,mode=1777,nosuid,nodev,size=120m 0 0
tmpfs /var/tmp  tmpfs   defaults,rw,nosuid,nodev,size=120m 0 0
tmpfs /run      tmpfs   defaults,rw,nosuid,nodev,noexec,relatime,mode=0755,size=100m 0 0
EOF
} || die "Failed to configure tmpfs mounts in /etc/fstab"
