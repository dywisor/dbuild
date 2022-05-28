#!/bin/sh
# Configures the hostname

target_hostname="${OCONF_HOSTNAME:-staging}"

print_action "Configuring hostname: ${target_hostname}"

autodie target_write_to_file /etc/hostname 0644 << EOF
${target_hostname}
EOF
