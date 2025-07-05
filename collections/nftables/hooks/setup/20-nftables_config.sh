#!/bin/sh
# Create staging nftables.conf using the initramfs default ruleset,
# which can be extended by other hooks via nft_rules_add()

print_action "Initialize nftables.conf for target"
autodie install -m 0600 -o 0 -g 0 -- \
    "${HOOK_FILESDIR:?}/nftables.conf.initramfs" \
    "${NFT_RULES_TMPFILE:?}"
