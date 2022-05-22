#!/bin/sh
# Configure locales

locale='en_US.UTF-8'

print_action "Configuring locale: ${locale}"

autodie target_debconf << EOF
    locales locales/locales_to_be_generated multiselect ${locale} UTF-8
    locales locales/default_environment_locale  select  ${locale}
EOF
