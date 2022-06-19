#!/bin/sh
# Initialze manpage index

if feat_all "${OFEAT_MAN_PAGES:-0}"; then
    autodie target_chroot /usr/bin/mandb
fi
