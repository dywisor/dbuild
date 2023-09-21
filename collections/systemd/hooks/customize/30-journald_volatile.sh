#!/bin/sh
# Lets systemd-journald write to volatile storage only
# if another syslog daemon has been installed.
#

gen_journald_volatile() {
cat << EOF
[Journal]
Storage=volatile
EOF
}


if feat_all "${OFEAT_RSYSLOG:-0}"; then
    print_action "Configure volatile storage for systemd-journald"

    autodie dodir_mode "${TARGET_ROOTFS}/etc/systemd/journald.conf.d"

    autodie dofile \
        "${TARGET_ROOTFS}/etc/systemd/journald.conf.d/volatile.conf" \
        0644 "0:0" \
        gen_journald_volatile
fi
