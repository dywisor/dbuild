#!/bin/sh
# Debian 12 shenanigans:
# *Somehow*, the systemd package ignores the id range configured 
# in sysusers.d when creating systemd-* users/groups.
#
# Breaking expectations with every release :/
#
# As a workaround, create systemd users/groups statically
# with a known uid/gid beforehand.
#

# create_sysuser ( name, uid, gid, gecos, home_dir, shell:="/usr/sbin/nologin" )
create_sysuser() {
    if target_chroot getent group "${1:?}" 2>/dev/null; then
        :
    else
        print_action "Debian 12 hacks: create group: ${1}"
        autodie target_chroot groupadd -r -g "${3:?}" "${1:?}"
    fi

    if [ "${2:--}" = '-' ]; then
        # group only
        :

    elif target_chroot getent passwd "${1:?}" 2>/dev/null; then
        :
    else
        print_action "Debian 12 hacks: create user: ${1}"
        autodie target_chroot useradd \
            -r \
            -u "${2:?}" \
            -g "${3:?}" \
            -c "${4:?}" \
            -d "${5:?}" \
            -s "${6:-/usr/sbin/nologin}" \
            -p '*' \
            "${1:?}"
    fi
}

create_sysuser systemd-journal  -   250
create_sysuser systemd-network  251 251 'systemd Network Management'    '/run/systemd'
create_sysuser systemd-resolve  252 252 'systemd Resolver'              '/run/systemd'
create_sysuser systemd-timesync 253 253 'systemd Time Synchronization'  '/'
create_sysuser systemd-coredump 254 254 'systemd Core Dumper'           '/'
