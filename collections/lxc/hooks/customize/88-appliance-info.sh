#!/bin/sh
# Create a dummy appliance.info file
# (Proxmox PVE seems to quert this file -- TODO)

# FIXME: distro details
{
cat << EOF > "${TARGET_ROOTFS:?}/etc/appliance.info"
Name: debian-11-standard
Version: 11.3-1
Type: lxc
OS: debian-11
Section: system
Maintainer: Proxmox Support Team <support@proxmox.com>
Architecture: amd64
Installed-Size: 500
Infopage: https://pve.proxmox.com/wiki/Linux_Container#pct_supported_distributions
Description: Debian 11 Bullseye (standard)
 A small Debian Bullseye system including all standard packages.
EOF
} || die "Failed to write appliance.info"
