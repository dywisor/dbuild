#!/bin/sh
# Web proxy config
#
# Note that hooks relying on web connections
# may fail when run after this hook.
#

hook_gen_web_proxy_env() {
    local varname

    for varname in \
        'http_proxy' 'https_proxy' 'ftp_proxy' \
        'HTTP_PROXY' 'HTTPS_PROXY' 'FTP_PROXY'
    do
        printf '%s=%s\n' "${varname}" "${OCONF_WEB_PROXY:?}"
    done

    if [ -n "${OCONF_WEB_NO_PROXY-}" ]; then
        for varname in no_proxy NO_PROXY; do
            printf '%s=%s\n' "${varname}" "${OCONF_WEB_NO_PROXY:?}"
        done
    fi

    printf '%s=%s\n' 'http_proxy' "${OCONF_WEB_PROXY:?}"
    printf '%s=%s\n' 'http_proxy' "${OCONF_WEB_PROXY:?}"
}

hook_gen_web_proxy_env_local() {
    printf '# proxy\n'
    hook_gen_web_proxy_env
}

hook_gen_apt_proxy_env() {
    cat << EOF
Acquire::http::Pipeline-Depth 0;
Acquire::http::Proxy "${OCONF_WEB_PROXY_APT:?}";
Acquire::https::Proxy "${OCONF_WEB_PROXY_APT:?}";
EOF
}

# /etc/environment (snippet)
if feat_all "${OFEAT_WEB_PROXY:-0}"; then
    print_action "Generate proxy config for /etc/environment"
    dbuild_envd_push 20-proxy hook_gen_web_proxy_env
fi

# /etc/local-env.d/proxy.sh
if feat_all "${OFEAT_WEB_PROXY_LOCAL_ENV:-0}"; then
    print_action "Generate proxy config for /etc/local-env.d"
    autodie dodir_mode "${TARGET_ROOTFS:?}/etc/local-env.d"
    target_write_to_file \
        "/etc/local-env.d/proxy.sh" \
        "0644" "0:0" \
        hook_gen_web_proxy_env_local
fi

# /etc/apt/apt.conf.d/99proxy
if feat_all "${OFEAT_WEB_PROXY_APT:-0}"; then
    print_action "Generate proxy config for apt"
    autodie dodir_mode "${TARGET_ROOTFS:?}/etc/apt/apt.conf.d"
    target_write_to_file \
        "/etc/apt/apt.conf.d/99proxy" \
        "0644" "0:0" \
        hook_gen_apt_proxy_env
fi
