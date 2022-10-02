#!/bin/sh
# Regenerate initramfs if requested

(
    WANT_UPDATE_INITRAMFS=

    dbuild_load_update_initramfs_env || \
        die "Failed to load update-initramfs environment file"

    if feat_all "${WANT_UPDATE_INITRAMFS:-0}"; then
        if feat_all "${OFEAT_KERNEL_IMAGE:-0}"; then
            print_action "Regenerate initramfs"
            autodie target_chroot update-initramfs -u -k all

        else
            print_info "Not updating initramfs, no kernel image configured."
        fi

    else
        print_info "Not updating initramfs, not requested."
    fi
) || exit
