#!/bin/sh
# Generate temporary mmdebstrap dpkg.cfg
# (do not overwrite config files from overlay, ...)

hook_gen_dpkg_config() {
    printf '%s\n' '# build-time dpkg configuration'

cat << EOF
force-confold
EOF
}

print_action "dpkg build-time configuration"
{
    hook_gen_dpkg_config | \
        target_write_to_file "/etc/dpkg/dpkg.cfg.d/99mmdebstrap-local" 0644
} || die
