#!/bin/sh
# dynamic package list for the 'lxc' collection
set -fu

# using systemd-networkd if available, else ifupdown2
if [ "${DBUILD_TARGET_INIT_SYSTEM-}" = 'systemd' ]; then
    # config generator needs Python 3
    printf '%s\n' python3

else
    # non-systemd: use ifupdown2
    printf '%s\n' ifupdown2
fi


exit 0
