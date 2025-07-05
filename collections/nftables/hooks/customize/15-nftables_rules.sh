#!/bin/sh
# Add simple tcp/udp rules to the nftables.conf input/output chain if configured

set --

if feat_all "${OFEAT_NFTABLES_ALLOW_INPUT:-0}"; then
    if [ -n "${OCONF_NFTABLES_ALLOW_INPUT_TCP-}" ]; then
        set -- "${@}" '--input-tcp' "${OCONF_NFTABLES_ALLOW_INPUT_TCP}"
    fi

    if [ -n "${OCONF_NFTABLES_ALLOW_INPUT_UDP-}" ]; then
        set -- "${@}" '--input-udp' "${OCONF_NFTABLES_ALLOW_INPUT_UDP}"
    fi
fi

if feat_all "${OFEAT_NFTABLES_ALLOW_OUTPUT:-0}"; then
    if [ -n "${OCONF_NFTABLES_ALLOW_OUTPUT_TCP-}" ]; then
        set -- "${@}" '--output-tcp' "${OCONF_NFTABLES_ALLOW_OUTPUT_TCP}"
    fi

    if [ -n "${OCONF_NFTABLES_ALLOW_OUTPUT_UDP-}" ]; then
        set -- "${@}" '--output-udp' "${OCONF_NFTABLES_ALLOW_OUTPUT_UDP}"
    fi
fi

if [ $# -gt 0 ]; then
    print_action "Add simple tcp/udp rules to nftables.conf input/output chain"
    autodie nft_rules_add "${@}"
fi
