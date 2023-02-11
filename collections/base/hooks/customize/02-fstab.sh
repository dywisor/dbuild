#!/bin/sh
# Configure tmpfs size limits in /etc/fstab

if ! feat_all "${OFEAT_TMPFS_MOUNTS:-0}"; then
    exit 0
fi

print_action "Configure various tmpfs mounts in /etc/fstab"

# NOTE: assuming 'clean' fstab, i.e. no previous entry for /dev/shm, /tmp, ...
# (entries for other mountpoints such as '/' may have already been added)
{
cat << EOF >> "${TARGET_ROOTFS:?}/etc/fstab"
tmpfs /dev/shm  tmpfs   defaults,rw,nosuid,nodev,size=${OCONF_TMPFS_DEV_SHM_SIZE:?} 0 0
tmpfs /tmp      tmpfs   defaults,rw,mode=1777,nosuid,nodev,size=${OCONF_TMPFS_TMP_SIZE:?} 0 0
tmpfs /var/tmp  tmpfs   defaults,rw,nosuid,nodev,size=${OCONF_TMPFS_VAR_TMP_SIZE:?} 0 0
tmpfs /run      tmpfs   defaults,rw,nosuid,nodev,noexec,relatime,mode=0755,size=${OCONF_TMPFS_RUN_SIZE:?} 0 0
EOF
} || die "Failed to configure tmpfs mounts in /etc/fstab"
