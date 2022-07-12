#!/bin/sh
# Cleanup just before finalizing the image

# remove temporary mmdebstrap dpkg.conf, apt.conf
print_action "Clean up temporary configuration files"
autodie rm -- "${TARGET_ROOTFS:?}/etc/dpkg/dpkg.cfg.d/99mmdebstrap-local"
autodie rm -- "${TARGET_ROOTFS:?}/etc/apt/apt.conf.d/99mmdebstrap-local"

# remove cached apt files
#  (only useful when creating images from TARGET_ROOTFS directly)
print_action "Remove cached apt files"
autodie target_chroot apt-get clean
autodie find \
    "${TARGET_ROOTFS:?}/var/cache/apt" \
    "${TARGET_ROOTFS:?}/var/lib/apt/lists" \
    "${TARGET_ROOTFS:?}/var/lib/apt/lists/partial" \
    -mindepth 1 -maxdepth 1 -type f \
    -name '*.bin' -delete
