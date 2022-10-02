Debian image builder using mmdebstrap

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

Building VM images (KVM/Hyper-V/VMware) takes considerably longer (about 2 minutes).


Host dependencies:

  - ``python3``
  - ``mmdebstrap``
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

Example usage:

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
