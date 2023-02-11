#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
#  Converts a dbuild tarball to a bootable disk image.
#
#  Note that this script needs root privileges (e.g. via sudo).
#

import abc
import argparse
import collections
import enum
import os
import pathlib
import shlex
import subprocess
import sys
import tempfile
import uuid

# import dataclasses
from dataclasses import dataclass
from typing import Optional

# optional dep: yaml  (using json as fallback)
import json
try:
    import yaml
except ModuleNotFoundError:
    HAVE_YAML = False
else:
    HAVE_YAML = True


class RuntimeEnvironment(object):

    CHROOT_ENV = {
        'TERM'          : 'linux',
        'USER'          : 'root',
        'LOGNAME'       : 'root',
        'SHELL'         : '/bin/sh',
        'LANG'          : 'en_US.utf8',
        'LC_COLLATE'    : 'C',
        'PATH'          : '/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin',
        'PWD'           : '/',
        'HOME'          : '/root',
    }

    def __init__(self):
        super().__init__()
        self.script_file_called     = None
        self.script_file            = None
        self.project_root           = None
        self.project_scripts_dir    = None
        self.project_share_dir      = None

        self.cmd_wrapper            = None
    # --- end of __init__ (...) ---

    def prepare_run_env(self, kwargs):
        extra_env = kwargs.pop('extra_env', None)

        if extra_env:
            base_env = kwargs.pop('env', None)
            if base_env is None:
                base_env = os.environ
            # --

            env = dict(base_env)
            env.update(extra_env)

            kwargs['env'] = env
        # --
    # --- end of prepare_run_env (...) ---

    def convert_env_to_cmdv(self, env, *, env_chdir=None):
        env_cmdv = ['env', '-i']

        if env_chdir:
            env_cmdv.extend(['-C', str(env_chdir)])
        # --

        env_cmdv.extend((
            f'{varname}={value}'
            for varname, value in sorted(env.items(), key=lambda kv: kv[0])
        ))

        return env_cmdv
    # --- end of convert_env_to_cmdv (...) ---

    def run(self, cmdv, **kwargs):
        self.prepare_run_env(kwargs)

        return self.cmd_wrapper.run(cmdv, **kwargs)
    # --- end of run (...) ---

    def run_as_admin(self, cmdv, **kwargs):
        self.prepare_run_env(kwargs)

        # when running through sudo, it's quite useless to specify env as parameter
        env = kwargs.pop('env', None)

        admin_cmdv = []

        if env:
            admin_cmdv.extend(self.convert_env_to_cmdv(env))
        # --

        admin_cmdv.extend(cmdv)

        return self.cmd_wrapper.run_as_admin(admin_cmdv, **kwargs)
    # --- end of run_as_admin (...) ---

    def run_as_admin_chroot(self, chroot_dir, cmdv, **kwargs):

        # chroot variant for prepare_run_env():
        #  - create a basic environment,
        #  - add extra_env if specified
        #  - raise an error if env= was specified
        base_env = kwargs.pop('env', None)
        if base_env:
            raise TypeError('run_as_admin_chroot() does not accept env=')
        # --

        env = dict(self.CHROOT_ENV)

        extra_env = kwargs.pop('extra_env', None)
        if extra_env:
            env.update(extra_env)

        # when running through sudo, it's quite useless to specify env as parameter
        chroot_cmdv = []

        if env:
            chroot_cmdv.extend(self.convert_env_to_cmdv(env, env_chdir=chroot_dir))
        # --

        chroot_cmdv.append('chroot')
        chroot_cmdv.append(str(chroot_dir))
        chroot_cmdv.extend(cmdv)

        return self.cmd_wrapper.run_as_admin(chroot_cmdv, **kwargs)
    # --- end of run_as_admin_chroot (...) ---

# --- end of RuntimeEnvironment ---


@enum.unique
class BootType(enum.IntEnum):
    (BIOS, UEFI, OTHER) = range(3)
# --- end of BootType ---


@enum.unique
class FilesystemType(enum.IntEnum):
    (
        EXT4,
        BTRFS,
        VFAT,
        SWAP,
    ) = range(4)
# --- end of FilesystemType ---


@dataclass
class VolumeConfig:
    enabled     : bool
    label       : str
    size        : str
    fstype      : FilesystemType
    fs_uuid     : str               # vfat has a reduced UUID
    volume_id   : Optional[str]     # for vfat
# --- end of VolumeConfig


@dataclass
class SimpleDiskConfig:
    root_vg_name    : str
    disk_size_root  : str
    boot_type       : BootType
    volumes         : dict[str, VolumeConfig]
# --- end of SimpleDiskConfig ---


@dataclass
class MountEntry:
    mnt_fsname      : str
    # mnt_dir (from mount root's perspective, e.g. '/boot')
    mnt_dir         : str
    mnt_type        : str
    mnt_opts        : str
# --- end of MountEntry ---


class CommandWrapper(object):

    def normalize_cmdv(self, cmdv):
        return [str(a) for a in cmdv]
    # --- end of normalize_cmdv (...) ---

    def _run(self, cmdv, **kwargs):
        print("CMD:", shlex.join(cmdv))
        return subprocess.run(cmdv, **kwargs)
    # --- end of _run (...) ---

    def run(self, cmdv, **kwargs):
        return self._run(
            self.normalize_cmdv(cmdv),
            **kwargs
        )
    # --- end of run (...) ---

    @abc.abstractmethod
    def run_as_admin(self, cmdv, **kwargs):
        raise NotImplementedError(self)
    # --- end of run_as_admin (...) ---

# --- end of CommandWrapper ---


class DefaultCommandWrapper(CommandWrapper):

    def run_as_admin(self, cmdv, **kwargs):
        return self.run(cmdv, **kwargs)

# --- end of DefaultCommandWrapper ---


class SudoCommandWrapper(CommandWrapper):

    def run_as_admin(self, cmdv, **kwargs):
        return self._run(
            (['sudo'] + self.normalize_cmdv(cmdv)),
            **kwargs
        )
    # --- end of run_as_admin (...) ---

# --- end of SudoCommandWrapper ---


class DJ(object):
    def __init__(self, env):
        super().__init__()
        self.env = env

        self.opened_loop_dev = collections.OrderedDict()
        self.opened_lvm_vg = collections.OrderedDict()
        self.opened_mount = collections.OrderedDict()
    # --- end of __init__ (...) ---

    def __enter__(self):
        return self

    def __exit__(self, exc_type, exc_value, exc_traceback):
        def revlist(d):
            return reversed(list(d))
        # ---

        cleanup_errors = []

        for mp in revlist(self.opened_mount):
            try:
                self.mount_close(mp)

            except:
                cleanup_errors.append(('mp', mp, sys.exc_info()))
        # -- end for mp

        for vg in revlist(self.opened_lvm_vg):
            try:
                self.lvm_vg_close(vg)

            except:
                cleanup_errors.append(('vg', vg, sys.exc_info()))
        # -- end for vg

        for loop_dev in revlist(self.opened_loop_dev):
            try:
                self.loop_dev_close(loop_dev)

            except:
                cleanup_errors.append(('loop_dev', loop_dev, sys.exc_info()))
        # -- end for loop_dev

        if cleanup_errors:
            raise OSError(cleanup_errors)
        # -- end if cleanup_errors
    # --- end of __exit__ (...) ---

    def loop_dev_open(self, filepath):
        proc = self.env.run_as_admin(
            ['losetup', '--show', '--find', filepath],
            check=True,
            stdout=subprocess.PIPE
        )

        loop_dev = proc.stdout.decode('utf-8').strip()

        self.opened_loop_dev[loop_dev] = filepath

        # scan partition table (non-fatal)
        self.env.run_as_admin(
            ['partx', '-a', loop_dev],
            check=False
        )

        return loop_dev
    # --- end of loop_dev_open (...) ---

    def loop_dev_close(self, loop_dev):
        # forget partition table (non-fatal)
        self.env.run_as_admin(
            ['partx', '-d', loop_dev],
            check=False
        )

        self.env.run_as_admin(
            ['losetup', '--detach', loop_dev],
            check=True
        )

        self.opened_loop_dev.pop(loop_dev, None)
    # --- end of loop_dev_close (...) ---

    def lvm_vg_open(self, vg_name):
        self.env.run_as_admin(
            ['vgchange', '-a', 'y', vg_name],
            check=True
        )

        self.opened_lvm_vg[vg_name] = True
    # --- end of lvm_vg_open (...) ---

    def lvm_vg_close(self, vg_name):
        self.env.run_as_admin(
            ['vgchange', '-a', 'n', vg_name],
            check=True
        )

        self.opened_lvm_vg.pop(vg_name, None)
    # --- end of lvm_vg_close (...) ---

    def mount_open(self, mnt_root, mnt_fsname, mnt_dir, mnt_type=None, mnt_opts=None):
        assert mnt_root

        if mnt_dir:
            mnt_dir = str(mnt_dir).lstrip('/')
        # --

        if mnt_dir:
            mnt_dir_abs = mnt_root / mnt_dir
            mnt_dir_root_pov = f'/{mnt_dir}'
        else:
            mnt_dir_abs = mnt_root
            mnt_dir_root_pov = '/'
        # --

        if not mnt_type:
            mnt_type = 'auto'
        # --

        if mnt_opts:
            if isinstance(mnt_opts, str):
                mnt_opts_str = mnt_opts

            elif hasattr(mnt_opts, '__iter__') or hasattr(mnt_opts, '__next__'):
                mnt_opts_str = ','.join((str(w).replace(',', '\\,') for w in mnt_opts))

            else:
                raise ValueError(mnt_opts)
        else:
            mnt_opts_str = 'defaults'
        # -- end if

        cmdv = [
            'mount',
            '-t', str(mnt_type),
            '-o', mnt_opts_str,
            mnt_fsname,
            mnt_dir_abs
        ]

        # create directory
        self.env.run_as_admin(['mkdir', '-p', mnt_dir_abs], check=True)

        # mount fs
        self.env.run_as_admin(cmdv, check=True)

        mnt_entry = MountEntry(mnt_fsname, mnt_dir_root_pov, mnt_type, mnt_opts_str)
        self.opened_mount[mnt_dir_abs] = mnt_entry
        return (mnt_dir_abs, mnt_entry)
    # --- end of mount_open (...) ---

    def mount_close(self, mnt_dir):
        self.env.run_as_admin(
            ['sync', '-f', os.path.join(mnt_dir, '.')],
            check=False
        )

        self.env.run_as_admin(
            ['umount', mnt_dir],
            check=True
        )

        self.opened_mount.pop(mnt_dir, None)
    # --- end of mount_close (...) ---

# --- end of class DJ ---

def parse_disk_config(disk_config_data):
    def dict_chain_get(d, key_path, fallback):
        node = d
        for key in key_path:
            if node is None:
                return fallback

            try:
                node = node[key]
            except KeyError:
                return fallback
        # -- end for

        return (fallback if node is None else node)
    # --- end of dict_chain_get (...) ---

    def mkobj_bool(arg, fallback):
        if arg is None:
            return fallback
        else:
            return bool(arg)
    # --- end of mkobj_bool (...) ---

    def mkobj_boot_type(arg):
        norm_arg = arg.lower()

        if norm_arg == 'bios':
            return BootType.BIOS

        elif norm_arg == 'uefi':
            return BootType.UEFI

        else:
            raise ValueError('unsupported/invalid boot type', arg)
    # --- end of mkobj_boot_type (...) ---

    def mkobj_fstype(arg):
        norm_arg = arg.lower()

        if norm_arg == 'btrfs':
            return FilesystemType.BTRFS

        elif norm_arg == 'ext4':
            return FilesystemType.EXT4

        elif norm_arg == 'swap':
            return FilesystemType.SWAP

        elif norm_arg == 'vfat':
            return FilesystemType.VFAT

        else:
            raise ValueError('unsupported/invalid fstype', arg)
    # --- end of mkobj_fstype (...) ---

    def mkobj_default_uuid(fstype):
        fs_uuid = str(uuid.uuid4())

        if fstype == FilesystemType.VFAT:
            # FAT volume ID is a 32bit hex number
            # 3aad3da3-3971-47a6-b4e7-7910290fcfc7 -> {uuid: 3971-47A6, volume id: 397147A6}
            fs_uuid_parts = [w.upper() for w in fs_uuid.split('-', 3)[1:3]]

            return '-'.join(fs_uuid_parts)

        else:
            return fs_uuid
    # --- end of mkobj_default_uuid (...) ---

    def mkobj_volume_id(fstype, fs_uuid):
        if fstype == FilesystemType.VFAT:
            return ''.join((w.upper() for w in fs_uuid.split('-')))

        else:
            return None
    # --- end of mkobj_volume_id (...) ---

    def mkobj_volume(arg_volume):
        name = arg_volume['name']

        if not name:
            raise ValueError('missing name for volume', arg_volume)

        if not arg_volume.get('size'):
            raise ValueError('missing size for volume', arg_volume)

        arg_fstype = arg_volume.get('fstype')
        if not arg_fstype:
            raise ValueError('missing fstype for volume', arg_volume)

        fstype      = mkobj_fstype(arg_fstype)
        fs_uuid     = arg_volume.get('fs_uuid') or mkobj_default_uuid(fstype)
        volume_id   = mkobj_volume_id(fstype, fs_uuid)

        volume = VolumeConfig(
            enabled     = mkobj_bool(arg_volume.get('enabled'), True),
            label       = (arg_volume.get('label') or name),
            size        = arg_volume['size'],
            fstype      = fstype,
            fs_uuid     = fs_uuid,
            volume_id   = volume_id,
        )

        return (name, volume)
    # --- end of mkobj_volume (...) ---

    def mkobj_volumes(arg_volumes):
        volumes = dict((mkobj_volume(arg_volume) for arg_volume in arg_volumes))

        return volumes
    # --- end of mkobj_volumes (...) ---

    disk_config = SimpleDiskConfig(
        root_vg_name   = dict_chain_get(disk_config_data, ['root_vg_name'], 'vg0'),
        disk_size_root = dict_chain_get(disk_config_data, ['disk_size_root'], '10G'),
        boot_type      = mkobj_boot_type(dict_chain_get(disk_config_data, ['boot_type'], 'bios')),
        volumes        = mkobj_volumes(dict_chain_get(disk_config_data, ['volumes'], None)),
    )

    # sanity checks:
    #
    # (1) for any boot type:
    #     - must have an active 'root' volume
    #     - must have an active 'boot' volume
    #       (technically optional, but required here)
    #
    # (2) for UEFI:
    #     - must have an active 'ESP' volume
    #

    missing_volumes = []

    for volume_name in ['root', 'boot']:
        if (
            (volume_name not in disk_config.volumes)
            or (not disk_config.volumes[volume_name].enabled)
        ):
            missing_volumes.append(volume_name)
    # --

    if disk_config.boot_type == BootType.UEFI:
        for volume_name in ['esp']:
            if (
                (volume_name not in disk_config.volumes)
                or (not disk_config.volumes[volume_name].enabled)
            ):
                missing_volumes.append(volume_name)
        # --
    # --

    if missing_volumes:
        raise ValueError('missing volumes in disk config', missing_volumes)
    # --

    return disk_config
# --- end of parse_disk_config (...) ---


def load_disk_config(filepath):
    with open(filepath, 'rt') as fh:
        disk_config_text = fh.read()

    if disk_config_text:
        if HAVE_YAML:
            disk_config_data = yaml.safe_load(disk_config_text)
        else:
            disk_config_data = json.loads(disk_config_text)
    else:
        disk_config_data = {}

    if not isinstance(disk_config_data, dict):
        raise ValueError('config data format error (must be a dict)')

    return parse_disk_config(disk_config_data)
# --- end of load_disk_config (...) ---


def get_default_disk_config_data(boot_type):
    disk_config_data = {
        'root_vg_name'      : 'vg0',
        'disk_size_root'    : '10G',
        'boot_type'         : boot_type.name,
        'volumes'           : [
            {
                'name'      : 'boot',
                'size'      : '1G',
                'fstype'    : 'ext4',
            },

            {
                'name'      : 'root',
                'size'      : '4G',
                'fstype'    : 'btrfs',
            },

            {
                'name'      : 'swap',
                'enabled'   : False,
                'size'      : '1G',
                'fstype'    : 'swap',
            },

            {
                'name'      : 'log',
                'size'      : '1G',
                'fstype'    : 'ext4',
            },
        ],
    }

    if boot_type == BootType.UEFI:
        disk_config_data['volumes'].append(
            {
                'name'      : 'esp',
                'size'      : '100M',
                'fstype'    : 'vfat',
            }
        )
    # --

    return disk_config_data
# --- end of get_default_disk_config_data (...) ---


def main(prog, argv):
    env = RuntimeEnvironment()
    env.script_file_called  = pathlib.Path(os.path.abspath(__file__))
    env.script_file         = pathlib.Path(os.path.realpath(env.script_file_called))
    env.project_root        = env.script_file.parent.parent
    env.project_scripts_dir = env.project_root / 'build-scripts'
    env.project_share_dir   = env.project_root / 'share'

    arg_parser              = get_arg_parser(prog)
    arg_config              = arg_parser.parse_args(argv)

    if os.getuid() == 0:
        env.cmd_wrapper = DefaultCommandWrapper()
    else:
        env.cmd_wrapper = SudoCommandWrapper()
    # --

    outdir = pathlib.Path(arg_config.outdir or os.getcwd()).absolute()

    if not arg_config.mount_root:
        # FIXME: argtype check
        raise ValueError("mount root must not be empty")
    # --

    mount_root = pathlib.Path(arg_config.mount_root)

    if arg_config.disk_config:
        disk_config = load_disk_config(arg_config.disk_config)

    else:
        # attr should be set
        disk_config = get_default_disk_config_data(arg_config.default_disk_config)
    # --

    return main_create_disk_image(
        arg_config  = arg_config,
        env         = env,
        disk_config = disk_config,
        mount_root  = mount_root,
        outdir      = outdir,
        rootfs_tarball_filepath = pathlib.Path(arg_config.infile).absolute(),
    )
# --- end of main (...) ---


def main_create_disk_image(arg_config, env, disk_config, mount_root, outdir, rootfs_tarball_filepath):
    def mkfs_ext4(volume_config, blk_dev, error_behavior='continue'):
        env.run_as_admin(
            [
                'mkfs.ext4',
                '-e', error_behavior,
                '-E', 'lazy_itable_init=0,lazy_journal_init=0,discard',
                '-L', volume_config.label,
                '-U', volume_config.fs_uuid,
                blk_dev
            ],
            check=True
        )
    # --- end of mkfs_ext4 (...) ---

    def mkfs_btrfs(volume_config, blk_dev):
        env.run_as_admin(
            [
                'mkfs.btrfs',
                '-L', volume_config.label,
                '-U', volume_config.fs_uuid,
                blk_dev
            ],
            check=True
        )
    # --- end of mkfs_btrfs (...) ---

    def mkfs_vfat(volume_config, blk_dev):
        env.run_as_admin(
            [
                'mkfs.vfat',
                '-F', '32',
                '-n', volume_config.label,
                '-i', volume_config.volume_id,
                blk_dev
            ],
            check=True
        )
    # --- end of mkfs_vfat (...) ---

    def init_fs(
        dj, fstab_entries, volume_config, blk_dev, mnt_dir,
        mnt_opts_base=None,
        mnt_opts_ext4=None,
        mnt_opts_btrfs=None,
        mnt_opts_vfat=None,
    ):
        is_rootfs = (mnt_dir is None)

        fstype_str = None

        if mnt_opts_base:
            mnt_opts = list(mnt_opts_base)
        else:
            mnt_opts =  ['defaults', 'rw', 'relatime']
        # --

        if volume_config.fstype == FilesystemType.EXT4:
            fstype_str = 'ext4'

            mkfs_ext4(
                volume_config,
                blk_dev,
                error_behavior=('remount-ro' if is_rootfs else 'continue')
            )

            if mnt_opts_ext4:
                mnt_opts.extend(mnt_opts_ext4)
            # --

            if is_rootfs:
                mnt_opts.append('errors=remount-ro')
            # --


        elif volume_config.fstype == FilesystemType.BTRFS:
            fstype_str = 'btrfs'

            if mnt_dir is False:
                # low-prio FIXME: fixable using a temporary directory
                raise NotImplementedError('cannot create subvol on no-mount filesystem')
            # --

            btrfs_subvol = ('@rootfs' if is_rootfs else '@')

            if mnt_opts_btrfs:
                mnt_opts.extend(mnt_opts_btrfs)
            # --

            mkfs_btrfs(volume_config, blk_dev)

            # mount temporarily and create subvol
            (mp, mnt_entry) = dj.mount_open(
                mnt_root    = mount_root,
                mnt_fsname  = blk_dev,
                mnt_dir     = mnt_dir,
                mnt_type    = fstype_str,
                mnt_opts    = mnt_opts,
            )

            env.run_as_admin(
                ['btrfs', 'subvolume', 'create', os.path.join(mp, btrfs_subvol)],
                check=True
            )

            dj.mount_close(mp)

            # finally, append subvol to mount options
            mnt_opts.append(f'subvol={btrfs_subvol}')

        elif volume_config.fstype == FilesystemType.SWAP:
            fstype_str = None

            env.run_as_admin(
                [
                    'mkswap',
                    '-L', volume_config.label,
                    '-U', volume_config.fs_uuid,
                    blk_dev
                ],
                check=True
            )

            fstab_entries.append(
                (
                    volume_config,
                    (blk_dev, 'none', 'swap', 'sw,nofail')
                )
            )

            # mnt_dir request ignored
            return

        elif volume_config.fstype == FilesystemType.VFAT:
            fstype_str = 'vfat'

            mkfs_vfat(volume_config, blk_dev)

            if mnt_opts_vfat:
                mnt_opts.extend(mnt_opts_vfat)
            # --

        else:
            raise NotImplementedError('fstype', volume_config)
        # --

        if mnt_dir is not False:
            assert fstype_str

            (mp, mnt_entry) = dj.mount_open(
                mnt_root    = mount_root,
                mnt_fsname  = blk_dev,
                mnt_dir     = mnt_dir,
                mnt_type    = fstype_str,
                mnt_opts    = mnt_opts,
            )
            fstab_entries.append((volume_config, mnt_entry))
        # --
    # --- end of init_fs (...) ---

    def write_text_file(outfile, text, mode='0644', owner='0', group='0'):
        outfile = pathlib.Path(outfile)

        if isinstance(text, list):
            text = '\n'.join(text) + '\n'
        # --

        # write to temporary file as user first, than install to dst
        temp_outfile = None

        try:
            with tempfile.NamedTemporaryFile(mode='wt', delete=False) as temp_outfile:
                temp_outfile.write(text)
            # --

            # drop existing dst file
            # FIXME: may or may not exist
            env.run_as_admin(['rm', '-f', '--', outfile], check=True)

            # copy new file to dst
            env.run_as_admin(
                [
                    'install',
                    '-m', mode,
                    '-o', owner,
                    '-g', group,
                    '--',
                    temp_outfile.name,
                    outfile,
                ],
                check=True
            )

        finally:
            if temp_outfile:
                # already closed due to with-context above, remove it then
                pathlib.Path(temp_outfile.name).unlink(missing_ok=True)
            # --
        # --
    # --- end of write_text_file (...) ---

    fstab_entries = []

    os.makedirs(outdir, exist_ok=True)

    env.run_as_admin(['mkdir', '-p', mount_root], check=True)

    with DJ(env) as dj:
        disk_layouts = collections.OrderedDict()

        disk_img_root   = outdir / 'root.img'
        root_part_esp   = None
        root_part_boot  = None
        root_part_swap  = None
        root_part_vg    = None

        # create sparse file
        #  (using truncate command instead of built-in fh.truncate()
        #  as that allows to specify a human-readable size argument)
        disk_img_root.unlink(missing_ok=True)
        env.run(['truncate', '-s', disk_config.disk_size_root, disk_img_root], check=True)

        # NOTE: not checking 'enabled' flag for mandatory volumes,
        #       this should have already been catched by parse_disk_config()

        if disk_config.boot_type == BootType.BIOS:  # BIOS/MBR
            disk_layout = []
            part_no = 1

            # boot partition
            disk_layout.append(
                'size={boot_size}, type=linux, bootable'.format(
                    boot_size=disk_config.volumes['boot'].size
                )
            )
            root_part_boot = part_no
            part_no += 1

            # swap partition (optional)
            if 'swap' in disk_config.volumes and disk_config.volumes['swap'].enabled:
                disk_layout.append(
                    'size={swap_size}, type=swap'.format(
                        swap_size=disk_config.volumes['swap'].size
                    )
                )
                root_part_swap = part_no
                part_no += 1
            # --

            # pv for LVM, taking up the remaining disk space
            disk_layout.append('type=lvm')
            root_part_vg = part_no
            part_no += 1

            disk_layouts[disk_img_root] = disk_layout

        elif disk_config.boot_type == BootType.UEFI:    # UEFI
            disk_layout = []
            part_no = 1

            # initialize as gpt
            disk_layout.append('label: gpt')

            # ESP
            disk_layout.append(
                'size={esp_size}, type=uefi, name=ESP'.format(
                    esp_size=disk_config.volumes['esp'].size
                )
            )
            root_part_esp = part_no
            part_no += 1

            # boot partition
            disk_layout.append(
                'size={boot_size}, type=linux, name=BOOT'.format(
                    boot_size=disk_config.volumes['boot'].size
                )
            )
            root_part_boot = part_no
            part_no += 1

            # swap partition (optional)
            if 'swap' in disk_config.volumes and disk_config.volumes['swap'].enabled:
                disk_layout.append(
                    'size={swap_size}, type=swap, name=SWAP'.format(
                        swap_size=disk_config.volumes['swap'].size
                    )
                )
                root_part_swap = part_no
                part_no += 1
            # --

            # pv for LVM, taking up the remaining disk space
            disk_layout.append('type=lvm, name=SYS')
            root_part_vg = part_no
            part_no += 1

            disk_layouts[disk_img_root] = disk_layout

        else:
            raise NotImplementedError("boot type", disk_config.boot_type)
        # -- end if

        for disk_img, disk_layout in disk_layouts.items():
            # FIXME hardcoded path
            env.run(
                ['/usr/sbin/sfdisk', disk_img],
                input=("\n".join(disk_layout) + "\n").encode('ascii'),
                check=True
            )
        # -- end for

        #> open disk image(s) as loop device
        loop_dev_root = dj.loop_dev_open(disk_img_root)

        #> create VG on root disk
        root_pv = f'{loop_dev_root}p{root_part_vg}'
        root_vg = f'/dev/mapper/{disk_config.root_vg_name}'

        env.run_as_admin(['pvcreate', root_pv], check=True)
        env.run_as_admin(
            ['vgcreate', disk_config.root_vg_name, root_pv],
            check=True
        )
        dj.lvm_vg_open(disk_config.root_vg_name)

        #> initialize filesystems (create LV ifneedbe, mkfs, mount)
        ##> initialize rootfs LV
        volume_config = disk_config.volumes['root']
        blk_dev = f'{root_vg}-root'

        env.run_as_admin(
            ['lvcreate', '-L', volume_config.size, '-n', 'root', disk_config.root_vg_name],
            check=True
        )

        init_fs(
            dj, fstab_entries, volume_config, blk_dev, None,
            mnt_opts_ext4=['user_xattr'],
        )

        ##> initialize boot partition/fs/mount
        if root_part_boot is None:
            raise AssertionError("boot partition requested but not allocated")
        # --

        volume_config = disk_config.volumes['boot']
        blk_dev = f'{loop_dev_root}p{root_part_boot}'

        init_fs(
            dj, fstab_entries, volume_config, blk_dev, 'boot',
            mnt_opts_base=['defaults', 'rw', 'noatime', 'nodev', 'nosuid']
        )

        ##> initialize EFI System Partition (ESP)
        if disk_config.boot_type == BootType.UEFI:
            if root_part_esp is None:
                raise AssertionError("esp partition requested but not allocated")
            # --

            volume_config = disk_config.volumes.get('esp')
            blk_dev = f'{loop_dev_root}p{root_part_esp}'

            init_fs(
                dj, fstab_entries, volume_config, blk_dev, 'boot/efi',
                mnt_opts_vfat=['umask=0077']
            )
        # -- end if EFI System Partition (ESP)

        ##> initialize swap space (but do not use it here)
        volume_config = disk_config.volumes.get('swap', None)
        if volume_config and volume_config.enabled:
            blk_dev = f'{loop_dev_root}p{root_part_swap}'

            if root_part_swap is None:
                raise AssertionError("swap partition requested but not allocated")
            # --

            init_fs(dj, fstab_entries, volume_config, blk_dev, False)
        # -- end if

        ##> initialize log LV (optional)
        volume_config = disk_config.volumes.get('log', None)
        if volume_config and volume_config.enabled:
            blk_dev = f'{root_vg}-log'

            env.run_as_admin(
                ['lvcreate', '-L', volume_config.size, '-n', 'log', disk_config.root_vg_name],
                check=True
            )

            init_fs(
                dj, fstab_entries, volume_config, blk_dev, 'var/log',
                mnt_opts_base=['defaults', 'rw', 'noatime', 'nodev', 'noexec', 'nosuid']
            )
        # -- end if

        #> unpack rootfs tarball to mounted fs tree
        env.run_as_admin(
            [
                'tar', '-xap',
                '-f', rootfs_tarball_filepath,
                '-C', mount_root,
                './'
            ],
            check=True
        )

        #> chroot mounts
        ##> proc
        dj.mount_open(
            mnt_root    = mount_root,
            mnt_fsname  = 'proc',
            mnt_dir     = 'proc',
            mnt_type    = 'proc',
            mnt_opts    = 'rw,nosuid,nodev,noexec,relatime'
        )

        ##> sys
        dj.mount_open(
            mnt_root    = mount_root,
            mnt_fsname  = 'sys',
            mnt_dir     = 'sys',
            mnt_type    = 'sysfs',
            mnt_opts    = 'rw,nosuid,nodev,noexec,relatime'
        )

        ##> dev
        dj.mount_open(
            mnt_root    = mount_root,
            mnt_fsname  = '/dev',
            mnt_dir     = 'dev',
            mnt_type    = 'none',
            mnt_opts    = 'bind'
        )

        ##> dev/pts
        dj.mount_open(
            mnt_root    = mount_root,
            mnt_fsname  = 'devpts',
            mnt_dir     = 'dev/pts',
            mnt_type    = 'devpts',
            mnt_opts    = 'rw,nosuid,noexec,relatime,gid=5,mode=620,ptmxmode=000,newinstance'
        )

        ##> dev/shm
        dj.mount_open(
            mnt_root    = mount_root,
            mnt_fsname  = 'shm',
            mnt_dir     = 'dev/shm',
            mnt_type    = 'tmpfs',
            mnt_opts    = 'rw,mode=1777,nosuid,nodev'
        )

        ##> var/tmp
        dj.mount_open(
            mnt_root    = mount_root,
            mnt_fsname  = 'vtmp',
            mnt_dir     = 'var/tmp',
            mnt_type    = 'tmpfs',
            mnt_opts    = 'rw,mode=1777'
        )

        ##> tmp
        dj.mount_open(
            mnt_root    = mount_root,
            mnt_fsname  = 'tmp',
            mnt_dir     = 'tmp',
            mnt_type    = 'tmpfs',
            mnt_opts    = 'rw,mode=1777'
        )

        ##> run
        dj.mount_open(
            mnt_root    = mount_root,
            mnt_fsname  = 'tmpfs',
            mnt_dir     = 'run',
            mnt_type    = 'tmpfs',
            mnt_opts    = 'rw,mode=0755,nosuid,nodev,noexec',
        )

        ##> run/lock
        dj.mount_open(
            mnt_root    = mount_root,
            mnt_fsname  = 'tmpfs',
            mnt_dir     = 'run/lock',
            mnt_type    = 'tmpfs',
            mnt_opts    = 'rw,mode=1777,nosuid,nodev,noexec',
        )

        #> rewrite fstab
        fstab_lines = [
            '# /etc/fstab: static file system information.'
        ]

        fstab_lines = [
            'UUID={fs_uuid} {mnt_dir} {mnt_type} {mnt_opts} 0 {mnt_passno}'.format(
                fs_uuid=volume_config.fs_uuid,
                mnt_dir=mnt_ent.mnt_dir,
                mnt_type=mnt_ent.mnt_type,
                mnt_opts=mnt_ent.mnt_opts,
                # enable fsck for select filesystems only
                # then use passno 1 for rootfs and 2 for everything else
                mnt_passno=(
                    0 if mnt_ent.mnt_type not in {'ext4'}
                    else (1 if mnt_ent.mnt_dir == '/' else 2)
                )
            )
            for volume_config, mnt_ent in fstab_entries
        ]

        # append existing fstab entries
        try:
            is_first = True
            with open((mount_root / 'etc/fstab'), 'rt') as fh:
                for line in fh:
                    sline = line.rstrip()

                    if is_first:
                        if not sline or sline[0] == '#':
                            pass

                        else:
                            fstab_lines.append('')
                            fstab_lines.append(sline)
                            is_first = False

                    else:
                        fstab_lines.append(sline)
                    # --
                # -- end for
            # -- end with

        except FileNotFoundError:
            pass
        # --

        write_text_file((mount_root / 'etc/fstab'), fstab_lines)

        #> update initramfs
        #  required because /etc/fstab has been modified
        print("update initramfs")
        env.run_as_admin_chroot(
            mount_root,
            ['update-initramfs', '-u', '-k', 'all'],
            extra_env={'INITRAMFS_FIRSTBOOT': 'y'},
            check=True
        )

        #> install bootloader
        if disk_config.boot_type == BootType.BIOS:
            print("install grub (BIOS)")
            env.run_as_admin_chroot(
                mount_root,
                [
                    'grub-install',
                    '--no-nvram',
                    '--skip-fs-probe',
                    '--target=i386-pc',
                    '--boot-directory=/boot',
                    loop_dev_root,
                ],
                check=True
            )

        elif disk_config.boot_type == BootType.UEFI:
            # nothing to do here
            pass

        else:
            raise NotImplementedError("install bootloader for boot type", disk_config.boot_type)
        # --

        #> optionally execute a chrooted shell
        if arg_config.exec_chroot:
            print("spawning chroot shell")
            env.run_as_admin_chroot(mount_root, ["/bin/bash", "-i"])
        # -- end if exec chroot?
    # -- end with
# --- end of main_create_disk_image (...) ---


def get_arg_parser(prog):
    parser = argparse.ArgumentParser(prog=os.path.basename(prog))

    parser.add_argument(
        'infile',
        help='rootfs tarball'
    )

    parser.add_argument(
        '-O', '--outdir', metavar='<dir>',
        dest='outdir', default=None,
        help='output directory (default: <cwd>)'
    )

    parser.add_argument(
        '-M', '--mount-root', metavar='<dir>',
        dest='mount_root', default='/mnt/dbuild',
        help='temporary mount root (default: %(default)s)'
    )

    parser.add_argument(
        '-q', '--quiet',
        dest='quiet',
        default=False, action='store_true',
        help='suppress informational output'
    )

    parser.add_argument(
        '-x', '--exec-chroot',
        dest='exec_chroot',
        default=False, action='store_true',
        help='execute a chrooted shell after creating disks/volumes and unpacking the rootfs'
    )

    config_grp = parser.add_argument_group(title='input config')
    config_mut_grp = config_grp.add_mutually_exclusive_group(required=True)

    config_mut_grp.add_argument(
        '-C', '--disk-config', metavar='<file>',
        dest='disk_config', default=None,
        help='disk config file (json/yaml)'
    )

    config_mut_grp.add_argument(
        '--bios',
        dest='default_disk_config',
        default=argparse.SUPPRESS,
        action='store_const', const=BootType.BIOS,
        help='use default BIOS-boot disk config'
    )

    config_mut_grp.add_argument(
        '--uefi',
        dest='default_disk_config',
        default=argparse.SUPPRESS,
        action='store_const', const=BootType.UEFI,
        help='use default UEFI-boot disk config'
    )

    return parser
# --- end of get_arg_parser (...) ---


def run_main():
    os_ex_ok = getattr(os, 'EX_OK', 0)

    try:
        exit_code = main(sys.argv[0], sys.argv[1:])

    except BrokenPipeError:
        for fh in [sys.stdout, sys.stderr]:
            try:
                fh.close()
            except:
                pass

        exit_code = os_ex_ok ^ 11

    except KeyboardInterrupt:
        exit_code = os_ex_ok ^ 130

    else:
        if (exit_code is None) or (exit_code is True):
            exit_code = os_ex_ok

        elif exit_code is False:
            exit_code = os_ex_ok ^ 1
    # --

    sys.exit(exit_code)
# --- end of run_main (...) ---


if __name__ == '__main__':
    run_main()
