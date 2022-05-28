#!/bin/sh
# Cleanup just before finalizing the image

# remove temporary mmdebstrap dpkg.conf, apt.conf
autodie rm -- "${TARGET_ROOTFS:?}/etc/dpkg/dpkg.cfg.d/99mmdebstrap-local"
autodie rm -- "${TARGET_ROOTFS:?}/etc/apt/apt.conf.d/99mmdebstrap-local"
