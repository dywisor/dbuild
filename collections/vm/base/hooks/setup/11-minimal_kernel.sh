#!/bin/sh
# Generate dpkg.cfg

hook_gen_dpkg_cfg_minimal_kernel() {
        cat << 'EOF'
# reduce size of installed kernel images by removing
# kernel modules not needed for virtual machines

#> kernel/drivers/
path-exclude=/lib/modules/*-amd64/kernel/drivers/android*
path-exclude=/lib/modules/*-amd64/kernel/drivers/atm*
path-exclude=/lib/modules/*-amd64/kernel/drivers/bluetooth*
path-exclude=/lib/modules/*-amd64/kernel/drivers/comedi*
path-exclude=/lib/modules/*-amd64/kernel/drivers/firewire*
path-exclude=/lib/modules/*-amd64/kernel/drivers/gpu/drm/amd*
path-exclude=/lib/modules/*-amd64/kernel/drivers/gpu/drm/gma500*
path-exclude=/lib/modules/*-amd64/kernel/drivers/gpu/drm/i915*
path-exclude=/lib/modules/*-amd64/kernel/drivers/gpu/drm/nouveau*
path-exclude=/lib/modules/*-amd64/kernel/drivers/gpu/drm/radeon*
path-exclude=/lib/modules/*-amd64/kernel/drivers/iio*
path-exclude=/lib/modules/*-amd64/kernel/drivers/infiniband*
path-exclude=/lib/modules/*-amd64/kernel/drivers/isdn*
path-exclude=/lib/modules/*-amd64/kernel/drivers/media*
path-exclude=/lib/modules/*-amd64/kernel/drivers/net/can*
path-exclude=/lib/modules/*-amd64/kernel/drivers/net/ethernet*
# include both e1000 and e1000e
path-include=/lib/modules/*-amd64/kernel/drivers/net/ethernet/intel/e1000*
path-exclude=/lib/modules/*-amd64/kernel/drivers/net/usb*
path-exclude=/lib/modules/*-amd64/kernel/drivers/net/wireless*
path-exclude=/lib/modules/*-amd64/kernel/drivers/pcmcia*
path-exclude=/lib/modules/*-amd64/kernel/drivers/staging*
path-exclude=/lib/modules/*-amd64/kernel/drivers/target*
path-exclude=/lib/modules/*-amd64/kernel/drivers/usb/gadget*
path-exclude=/lib/modules/*-amd64/kernel/drivers/usb/serial*
#path-exclude=/lib/modules/*-amd64/kernel/drivers/

#> kernel/fs/
path-exclude=/lib/modules/*-amd64/kernel/fs/affs*
path-exclude=/lib/modules/*-amd64/kernel/fs/afs*
path-exclude=/lib/modules/*-amd64/kernel/fs/ceph*
path-exclude=/lib/modules/*-amd64/kernel/fs/coda*
path-exclude=/lib/modules/*-amd64/kernel/fs/gfs2*
path-exclude=/lib/modules/*-amd64/kernel/fs/jfs*
path-exclude=/lib/modules/*-amd64/kernel/fs/ksmbd*
path-exclude=/lib/modules/*-amd64/kernel/fs/nilfs2*
path-exclude=/lib/modules/*-amd64/kernel/fs/ocfs2*
path-exclude=/lib/modules/*-amd64/kernel/fs/orangefs*
path-exclude=/lib/modules/*-amd64/kernel/fs/reiserfs*
path-exclude=/lib/modules/*-amd64/kernel/fs/ubifs*

#> kernel/lib/
path-exclude=/lib/modules/*-amd64/kernel/lib/test_bpf.ko

#> kernel/sound/
path-exclude=/lib/modules/*-amd64/kernel/sound*

#> kernel/net/
path-exclude=/lib/modules/*-amd64/kernel/net/bluetooth*
path-exclude=/lib/modules/*-amd64/kernel/net/mac80211*
path-exclude=/lib/modules/*-amd64/kernel/net/wireless*
EOF
}

if feat_all "${OFEAT_ROOTFS_MINIMAL_KERNEL:-0}"; then
    print_action "dpkg minimal-install configuration: linux-image-amd64-vm"

    {
        hook_gen_dpkg_cfg_minimal_kernel | \
            target_write_to_file "/etc/dpkg/dpkg.cfg.d/linux-image-amd64-vm" 0644
    } || die
fi
