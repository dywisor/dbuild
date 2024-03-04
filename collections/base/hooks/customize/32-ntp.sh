#!/bin/sh
# Configure chrony NTP daemon.

if ! feat_all "${OFEAT_NTP_CONF:-0}"; then
    exit 0
fi

print_action "Configure chrony NTP daemon"

gen_chrony_sources() {
    local s

    for s in ${OCONF_NTP_POOL-}; do
        printf 'pool %s iburst\n' "${s}"
    done

    for s in ${OCONF_NTP_SERVER-}; do
        printf 'server %s iburst\n' "${s}"
    done
}

chrony_confdir="/etc/chrony"
target_chrony_confdir="${TARGET_ROOTFS:?}${chrony_confdir}"

if [ -n "${OCONF_NTP_SERVER-}" ] || [ -n "${OCONF_NTP_POOL-}" ]; then
    print_action "chrony: Using configured NTP servers"

    # disable default ntp servers, use configured ones
    if ! grep -q -E -- \
        "^sourcedir\\s+${chrony_confdir}/sources[.]d\\s*\$" \
        "${target_chrony_confdir}/chrony.conf"
    then
        # could add it here, though...
        die "chrony lost its sourcedir config..."
    fi

    autodie dofile \
        "${target_chrony_confdir}/sources.d/10-default.sources" \
        0644 "0:0" \
        gen_chrony_sources

    autodie sed -r \
        -e 's=^((peer|pool|server)\s+)=#\1=' \
        -e 's=^(sourcedir\s+/run/chrony-dhcp)=#\1=' \
        -i "${target_chrony_confdir}/chrony.conf"
fi
