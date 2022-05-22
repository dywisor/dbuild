#!/bin/sh
# Configure the root user

# set password for root user
autodie target_chroot usermod \
    -p "${OCONF_INSTALL_ROOT_PASSWORD:?}" \
    root
