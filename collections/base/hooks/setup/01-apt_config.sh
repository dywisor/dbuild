#!/bin/sh
# Generate temporary mmdebstrap apt.conf
# (build-time proxy config, ...)

hook_gen_apt_config() {
    printf '%s\n' '# build-time apt configuration'

    if [ -n "${DBUILD_APT_PROXY}" ]; then
cat << EOF
Acquire::http::Pipeline-Depth 0;
Acquire::http::Proxy "${DBUILD_APT_PROXY}";
Acquire::https::Proxy "${DBUILD_APT_PROXY}";
EOF
    fi
}

{
    hook_gen_apt_config | \
        target_write_to_file "/etc/apt/apt.conf.d/99mmdebstrap-local" 0644
} || die
