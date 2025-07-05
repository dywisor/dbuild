#!/bin/sh

NFT_RULES_TMPFILE="${DBUILD_STAGING_TMP:?}/nftables.conf"

# nft_rules_add ( *argv )
#  -I <rule> : add input rule
#  -O <rule> : add output rule
nft_rules_add() {
    "${DBUILD_BUILD_SCRIPTS:?}/nft_rules_add.py" \
        --file "${NFT_RULES_TMPFILE}" \
        --inplace \
        "${@}"
}
