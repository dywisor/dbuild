#!/bin/sh
# Set the timezone

if [ -z "${OCONF_TIMEZONE-}" ]; then
    exit 0
fi

print_action "Setting timezone to ${OCONF_TIMEZONE}"

case "${OCONF_TIMEZONE}" in
    ?*/?*)
        autodie target_debconf << EOF
tzdata tzdata/Areas                         select ${OCONF_TIMEZONE%/*}
tzdata tzdata/Zones/${OCONF_TIMEZONE%/*}    select ${OCONF_TIMEZONE##*/}
EOF
    ;;

    *)
        print_error "Cannot set timezone: ${OCONF_TIMEZONE} (not supported)"
        exit 2
    ;;
esac
