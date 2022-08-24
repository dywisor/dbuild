#!/bin/sh
# Rewrite symlinks to $TARGET_ROOTFS
# so that they do no longer point to the build directory's path.
# (Rewrite link dst /tmp/tmp_4w466dfgsd/rootfs/usr/lib to /usr/lib, ...)
#

print_action "Rewrite symbolic links in target"
autodie "${DBUILD_BUILD_SCRIPTS:?}/fix-symlinks.py" "${TARGET_ROOTFS}"
