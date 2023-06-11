#!/bin/sh
# Create a dummy appliance.info file
# (Proxmox PVE seems to quert this file -- TODO)

# FIXME: distro details
{
cat << EOF > "${TARGET_ROOTFS:?}/etc/appliance.info"
Name: debian-12-standard
Version: 12.0-1
Type: lxc
OS: debian-12
Section: system
Maintainer: Proxmox Support Team <support@proxmox.com>
Architecture: amd64
Installed-Size: 500
Infopage: https://pve.proxmox.com/wiki/Linux_Container#pct_supported_distributions
Description: Debian 12 Bookworm (standard)
 A small Debian Bookworm system including all standard packages.
EOF
} || die "Failed to write appliance.info"
