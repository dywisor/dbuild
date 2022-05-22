#!/bin/sh
# dynamic package list for the 'base' collection
set -fu

# extra packages from config
if [ "${OFEAT_PKG_INSTALL:-0}" -eq 1 ]; then
    printf '%s\n' ${OCONF_PKG_INSTALL}  # noglob is set
fi

# ctrl user implies sudo
if [ "${OFEAT_CTRL_USER:-0}" -eq 1 ]; then
    printf '%s\n' sudo
fi

# ansible-controlled node implies python3, python3-apt, sudo
if [ "${OFEAT_ANSIBLE_CTRL:-0}" -eq 1 ]; then
    printf '%s\n' python3 python3-apt sudo
fi

# timezone needs tzdata
if [ -n "${OCONF_TIMEZONE-}" ]; then
    printf '%s\n' tzdata
fi

# SSH server
if [ "${OFEAT_SSHD_CONFIG:-0}" -eq 1 ]; then
    printf '%s\n' openssh-server
fi

# man pages
if [ "${OFEAT_MAN_PAGES:-0}" -eq 1 ]; then
    printf '%s\n' man-db manpages
fi

# cron daemon
if [ "${OFEAT_CRON:-0}" -eq 1 ]; then
    printf '%s\n' cron
fi

# rsyslog
if [ "${OFEAT_RSYSLOG:-0}" -eq 1 ]; then
    printf '%s\n' rsyslog logrotate
fi

exit 0
