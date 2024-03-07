#!/bin/sh
# Generate /etc/environment from env.d snippets

print_action "Generate /etc/environment"

# also use existing environment file from target rootfs
if [ -r "${TARGET_ROOTFS:?}/etc/environment" ]; then
    dbuild_envd_push 00-default < "${TARGET_ROOTFS:?}/etc/environment"
fi

target_write_to_file /etc/environment "0644" "0:0" dbuild_envd_cat
