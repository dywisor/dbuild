#!/bin/sh
# Configure third-party repo: Proxmox PVE
# Sets up apt sources and imports the signing key.

print_action "Configure apt repo - Proxmox PVE"

hook_gen_sources_proxmox_pve() {
cat << EOF
deb http://download.proxmox.com/debian/pve ${DBUILD_TARGET_CODENAME:?} pve-no-subscription
EOF
}


apt_config_root="/etc/apt"
apt_sources="${apt_config_root}/sources.list.d"
apt_trusted="${apt_config_root}/trusted.gpg.d"
apt_trusted_file="${apt_trusted}/proxmox-release-${DBUILD_TARGET_CODENAME:?}.gpg"

target_apt_trusted_file="${TARGET_ROOTFS:?}/${apt_trusted_file#/}"


autodie dodir_mode "${TARGET_ROOTFS:?}/${apt_sources#/}" 0755
autodie dodir_mode "${TARGET_ROOTFS:?}/${apt_trusted#/}" 0755

{
    hook_gen_sources_proxmox_pve | \
        write_to_file "${TARGET_ROOTFS:?}/${apt_sources#/}/pve-install-repo.list" 0644
} || die


# try to copy keyring from host, fall back to download
if \
    cp -vL -- "${apt_trusted_file}" "${target_apt_trusted_file}" 2>/dev/null && \
    verify_file_checksum "${target_apt_trusted_file}"
then
    autodie dopath "${target_apt_trusted_file}" 0644
    print_info "Copied keyring from host: ${target_apt_trusted_file##*/}"

else
    print_info "Could not copy keyring from host, downloading instead: ${target_apt_trusted_file##*/}"

    autodie curl -Ls -o "${target_apt_trusted_file}" \
        "https://enterprise.proxmox.com/debian/proxmox-release-${DBUILD_TARGET_CODENAME:?}.gpg"
    autodie dopath "${target_apt_trusted_file}" 0644
    autodie verify_file_checksum "${target_apt_trusted_file}"
fi
