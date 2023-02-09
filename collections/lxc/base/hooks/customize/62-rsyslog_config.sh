#!/bin/sh
# Disable rsyslogd kernel logging for containers

if feat_all "${OFEAT_RSYSLOG:-}"; then
    autodie sed -r \
        -e '/^module\(load=\"imklog\"\)/{s,^,#,}' \
        -i "${TARGET_ROOTFS:?}/etc/rsyslog.conf"
fi
