#!/bin/sh
# dynamic package list for the 'vm/uefi' collection
set -fu

# signed bootloader?
if [ "${OFEAT_UEFI_SECURE_BOOT:-0}" -eq 1 ]; then
    printf '%s\n' \
        grub-efi-amd64-signed \
        shim-helpers-amd64-signed \
        shim-signed shim-unsigned
fi
