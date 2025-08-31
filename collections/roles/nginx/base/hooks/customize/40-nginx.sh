#!/bin/sh
# nginx setup

nginx_confdir='/etc/nginx'
target_nginx_confdir="${TARGET_ROOTFS:?}${nginx_confdir}"

# common directories
print_action "Create directories for nginx"
autodie dodir_mode "${TARGET_ROOTFS:?}/var/www/empty" 0755
autodie dodir_mode "${target_nginx_confdir}/ssl" 0700
autodie dopath "${target_nginx_confdir}/ssl" 0700 '0:0'

# disable default site
if check_fs_lexists "${target_nginx_confdir}/sites-enabled/default"; then
    print_action "Disable vendor-default nginx site"
    autodie rm -- "${target_nginx_confdir}/sites-enabled/default"
fi

# NOTE: factory dhparam.pem has been removed
# (prior to ever releasing this collection)
# DHE ciphers are disabled in the nginx TLS configuration.

# factory server certificate
# TODO/DECIDE: use a builhost-cached factory self-signed server certificate?
if \
    ! check_fs_lexists "${target_nginx_confdir}/ssl/server.key" && \
    ! check_fs_lexists "${target_nginx_confdir}/ssl/server.crt"
then
    # slightly racy, but ok
    # (hook scripts are run sequentially at build time,
    # using an exclusive temporary directory)

    # NOTE: BSI TR-02102-2 recommends brainpool over secp elliptic curve ciphers
    # (version 2025-1, chapter 3.6.2)
    # secp seems to be more common, though...
    # * brainpoolP384r1
    # * secp384r1

    print_action "Create factory self-signed server certificate for nginx"
    autodie openssl req -x509 -newkey ec \
        -pkeyopt ec_paramgen_curve:secp384r1 \
        -keyout "${target_nginx_confdir}/ssl/server.key" \
        -out "${target_nginx_confdir}/ssl/server.crt" \
        -sha256 \
        -nodes \
        -days "${OCONF_NGINX_TLS_CERT_LIFETIME:?}" \
        -subj "${OCONF_NGINX_TLS_CERT_SUBJECT:?}"
fi
