#!/bin/sh
# Configure locales

locale='en_US.UTF-8'

print_action "Configuring locale: ${locale}"

autodie target_debconf << EOF
    locales locales/locales_to_be_generated multiselect ${locale} UTF-8
    locales locales/default_environment_locale  select  ${locale}
EOF

autodie dodir_mode "${TARGET_ROOTFS:?}/etc/default" 0755 0:0
autodie target_write_to_file etc/default/locale 0644 0:0 << EOF
#  File generated by update-locale
LANG="${locale}"
LC_COLLATE="${locale}"
EOF
