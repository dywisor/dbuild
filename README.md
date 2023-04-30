Debian image builder using mmdebstrap
========================================================================

Introduction
------------------------------------------------------------------------

Prepares a new Debian image so that it can deployed on another host.
The main purpose is building images for Proxmox PVE containers (LXC),
but the approach should be quite generic and suitable for other purposes as well.

Currently, the following output image formats are supported:

  - LXC: rootfs tarball

  - KVM: disk image, UEFI boot
    (VM must be created manually, then attach disk(s) to it)

  - Hyper-V: disk image, UEFI boot
    (VM must be created manually, then attach disk(s) to it)

  - VMware ESXi/vSphere: OVA VM image, UEFI boot

  - Hardware (amd64): disk image, BIOS or UEFI boot

  - LVM-based, optionally with RAID1 and LUKS

      - rootfs: btrfs optionally w/ ``snapper`` initialized or ext4

      - RAID1: single-disk mdadm raid1 for /boot and/or root PV,
        redundancy must be added after deploying using ``mdadm --grow``

      - LUKS: intermediate passphrase,
        a proper key must be set after deploying

    - **not fully integrated** (yet?) -- must execute two distinct build scripts

Depending on the configuration profile, the image will be customized.
Features include:

  - Strict SSH server configuration
    (restrict users, public-key auth only)

  - Configure a dedicated user account for automated configuration
    using e.g. Ansible

  - Minimal package selection

Using the example config profile *deb11-amd64-lxc*,
building the image takes roughly 30 seconds
(with optimizations such as using tmpfs workdirs and a caching proxy).
The image size is about 100M compressed (zstd).
Once deployed, the container boots in half a second.

Building VM images (KVM/Hyper-V/VMware) or Hardware images takes considerably longer (about 2 minutes).


Host Dependencies
------------------------------------------------------------------------

- ``python3``
- ``mmdebstrap``
- GNU ``tar``
- ``rsync``
- ``systemctl`` (for systemd targets)
- ``qemu-user`` (for cross-arch targets)
- *optional*: genimage (for building disk images)

  See [pengutronix/genimage](https://github.com/pengutronix/genimage)
  and [dywisor/genimage-debian](https://github.com/dywisor/genimage-debian/tree/debian/stable/debian) for building a ``.deb``
- *optional*: ``qemu-img`` from ``qemu-utils``
  (for creating Hyper-V / VMware disk images)
- *optional*: VMware ``ovftool`` (for creating VMware OVA images)
- *optional*: web proxy for caching ``.deb`` downloads, e.g. ``apt-cacher-ng`` or ``squid``
- *optional*: for building Hardware images
  - ``sudo``
  - various ``coreutils`` tools
    - ``chroot``
    - ``install``
    - ``mkdir``
    - ``sync``
    - ``truncate``
  - various ``util-linux`` and related split-package tools
    - ``losetup``
    - ``mount``
    - ``mountpoint``
    - ``partx``
    - ``mkswap``
    - ``sfdisk``
    - ``umount``
  - ``lvm2``
  - ``e2fsprogs``
  - *optional*: ``btrfs-progs`` (for btrfs volumes)
  - *optional*: ``dosfstools`` (for UEFI boot)
  - *optional*: ``mdadm``: (for RAID1)
  - *optional*: ``cryptsetup`` (for LUKS)


Example Usage
------------------------------------------------------------------------

```
./mkimage ./profiles/examples/deb11-amd64-lxc
```

This will create an output image file at
``obj/deb11-amd64-lxc/deb11-amd64-lxc_rootfs_<DATE>_<TIMESTAMP>.tar.zst``.
Additionally, a symlink ``obj/deb11-amd64-lxc/deb11-amd64-lxc_rootfs.tar.zst``
pointing to that file will be created.

The container image can then be imported in Proxmox PVE, for instance
(adjust cmdline options as necessary):

```
pct create 9999 \
    /tmp/deb11-amd64-lxc_rootfs.tar.zst \
    --hostname    testing-deb11-amd64-lxc \
    --memory      1024 \
    --net0        "name=eth0,bridge=vmbr0,firewall=0,gw=198.51.100.1,ip=198.51.100.200/24,tag=10,type=veth" \
    --storage     "local" \
    --rootfs      "local:2" \
    --unprivileged 1 \
    --ostype      "debian" \
    --password    "install" \
    --features    "nesting=1" \
    --start        1
```

Note that the example config results in a container image
with an incomplete SSH *authorized_keys* configuration:
Only public key authentication is allowed, but no valid keys are configured.
Thus, only the ``root`` user may login locally (but not via SSH).
You should create your own configuration profile in ``profiles/`` instead
and specify the proper SSH keys there.

Review the ``profiles/examples/`` for starting configs
and see ``collections/base/config`` for a list of possible config options.

Customizations and package selections are organized in a modular fashion,
as so-called *collections*. You can add your own below ``collections/local/``,
which will be ignored by git.


Building Hardware Images
------------------------------------------------------------------------

Building hardware images is split into two stages:

#. Create a tarball containing the rootfs

#. Initialize a disk image with the configured storage layers
   and then unpack the rootfs tarball into it

The first stage is handled by ``mkimage``,
``convert-tar-to-disk`` takes care of stage 2.

The ``convert-tar-to-disk`` script requires root privileges
acquired via ``sudo(8)`` for setting up the disk image
and its various storage layers, as well as chrooting
into the target rootfs for final customizations.
You might want to consider running the build process
in a dedicated container or virtual machine.

The rootfs tarball and a configuration file
defining the desired disk/storage layout must be given as input.
The configuration file is usually created during stage 1,
see ``collections/hardware/base/files/tar-to-disk.yml.in`` for a template file
which contains the most common options.
For all possible configuration options,
have a look at the script itself (``class SimpleDiskConfig`` and its components).

This output disk image will be a single file
that can be written to a drive from which the target will boot.
It contains the following volumes:

- EFI system partition -- UEFI boot only

- separate /boot partition, ext4-formatted,
  *optionally* on top of RAID1

- *optional*: swap partition

- LVM volume group containing all remaining volumes,
  *optionally* on top of LUKS and/or RAID1

  - rootfs, btrfs-formatted by default

    - *optional*: initialize snapper -- btrfs-based rootfs only

  - *optional*: ``/var/log``, ext4-formatted by default

  - *optional*: ``/var/cache/apt``, ext4-formatted by default

LUKS-based encryption will use a passphrase set in the configuration file.
This should be understood as an **intermediate passphrase
that must be changed** after deploying the disk image
to the target using ``cryptsetup luksChangeKey``.

RAID1 will provide no redundancy, initially.
This has to be added after deploying the disk image
to the target using ``mdadm --grow``.


To create the disk image file, create the rootfs tarball first:

```
./mkimage ./profiles/<PROFILE>
```

Then, run ``convert-tar-to-disk``:

```
./build-scripts/convert-tar-to-disk.py -C <config> -O <output_dir> <rootfs_tarball>
```
