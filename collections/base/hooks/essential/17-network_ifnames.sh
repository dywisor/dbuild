#!/bin/sh
# Configure locales


if feat_all "${OFEAT_IFNAMES:-0}"; then
    print_action "Allowing network interface renaming"

    autodie rm -f -- "${TARGET_ROOTFS}/etc/systemd/network/99-default.link"

else
    print_action "Disabling network interface renaming"

    autodie dodir_mode "${TARGET_ROOTFS}/etc/systemd/network"
    autodie dofile "${TARGET_ROOTFS}/etc/systemd/network/99-default.link" \
        0644 '0:0' \
        cat << EOF
[Match]
OriginalName = *

[Link]
NamePolicy =
EOF
fi
