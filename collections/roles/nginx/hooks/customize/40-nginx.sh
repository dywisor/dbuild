#!/bin/sh
# nginx setup

# NOTE: except for the default site
#       and $nginx_vhost_name (derived from OCONF_NGINX_CONFIG_ROLE),
#       no other vhost sites are touched here

nginx_confdir='/etc/nginx'
target_nginx_confdir="${TARGET_ROOTFS:?}${nginx_confdir}"

# nginx_copy_site_config ( name )
nginx_copy_site_config() {
    local name

    name="${1:?}"
    autodie install -m 0644 -o 0 -g 0 \
        "${HOOK_FILESDIR:?}/sites-available/${name}" \
        "${target_nginx_confdir:?}/sites-available/${name}"
}


__nginx_gen_site_config() {
    sed -r "${@}" < "${HOOK_FILESDIR:?}/sites-available/${name:?}.in"
}

# nginx_gen_site_config ( name, *sed_args )
nginx_gen_site_config() {
    local name

    name="${1:?}"
    shift

    write_to_file "${target_nginx_confdir}/sites-available/${name}" 0644 '0:0' \
        __nginx_gen_site_config "${@}"
}

# common directories
print_action "Create directories for nginx"
autodie dodir_mode "${TARGET_ROOTFS:?}/var/www/empty" 0755
autodie dodir_mode "${target_nginx_confdir}/sites-available" 0755
autodie dodir_mode "${target_nginx_confdir}/sites-enabled" 0755
autodie dodir_mode "${target_nginx_confdir}/ssl" 0700
autodie dopath "${target_nginx_confdir}/ssl" 0700 '0:0'

# disable default site
if check_fs_lexists "${target_nginx_confdir}/sites-enabled/default"; then
    print_action "Disable vendor-default nginx site"
    autodie rm -- "${target_nginx_confdir}/sites-enabled/default"
fi

nginx_vhost_desc=''
nginx_vhost_name=''
nginx_vhost_enable=0

case "${OCONF_NGINX_CONFIG_ROLE?}" in
    ''|'none')
        # no configuration
    ;;

    'app')
        nginx_vhost_desc='application / reverse proxy'
        nginx_vhost_name='app'
        nginx_vhost_enable=1

        nginx_proxy_pass=''
        : "${OCONF_NGINX_APP_PROXY_PASS:?}"
        if printf '%s' "${OCONF_NGINX_APP_PROXY_PASS}" | grep -Eq -- '^[0-9]+$'; then
            # not checking whether OCONF_NGINX_APP_PROXY_PASS is a valid (tcp) port number
            nginx_proxy_pass="http://127.0.0.1:${OCONF_NGINX_APP_PROXY_PASS}"
        else
            nginx_proxy_pass="${OCONF_NGINX_APP_PROXY_PASS}"
        fi

        autodie nginx_gen_site_config "${nginx_vhost_name}" \
            -e "s=@@PROXY_PASS@@=${nginx_proxy_pass}=g"
    ;;

    'static')
        nginx_vhost_desc='static web server'
        nginx_vhost_name='static'
        nginx_vhost_enable=1

        autodie nginx_copy_site_config "${nginx_vhost_name}"

        # initialize static web root
        autodie dodir_mode "${TARGET_ROOTFS:?}/var/www/static" 0755
    ;;

    *)
        die "Unsupported nginx configuration role: ${OCONF_NGINX_CONFIG_ROLE}"
    ;;
esac


# enable vhost site?
if [ "${nginx_vhost_enable}" -eq 1 ]; then
    : "${nginx_vhost_name:?}"
    : "${nginx_vhost_desc:?}"
    print_action "Enable nginx site: ${nginx_vhost_desc}"
    rm -f -- "${target_nginx_confdir}/sites-enabled/${nginx_vhost_name}"
    autodie ln -s -- \
        "${nginx_confdir}/sites-available/${nginx_vhost_name}" \
        "${target_nginx_confdir}/sites-enabled/${nginx_vhost_name}"
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
