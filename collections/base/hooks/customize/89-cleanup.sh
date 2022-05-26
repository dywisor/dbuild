#!/bin/sh
# Cleanup just before finalizing the image

# remove temporary mmdebstrap apt.conf
autodie rm -- "${TARGET_ROOTFS:?}/etc/apt/apt.conf.d/99mmdebstrap-local"
