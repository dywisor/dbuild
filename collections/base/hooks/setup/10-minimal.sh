#!/bin/sh
# Generate dpkg.cfg

hook_gen_dpkg_cfg_minimal() {
    printf '%s\n' '# dpkg minimal configuration'

    if feat_all "${OFEAT_ROOTFS_MINIMAL_USR_SHARE:-0}"; then
        cat << EOF
path-exclude=/usr/share/man/*
path-include=/usr/share/man/man[1-9]/*
path-exclude=/usr/share/locale/*
path-include=/usr/share/locale/locale.alias
path-exclude=/usr/share/doc/*
path-include=/usr/share/doc/*/copyright
path-include=/usr/share/doc/*/changelog.Debian.*
path-exclude=/usr/share/{doc,info,man,omf,help,gnome/help}/*
EOF
    fi
}

if feat_all "${OFEAT_ROOTFS_MINIMAL:-0}"; then
    print_action "dpkg minimal-install configuration"

    {
        hook_gen_dpkg_cfg_minimal | \
            target_write_to_file "/etc/dpkg/dpkg.cfg.d/99minimal" 0644
    } || die
fi
