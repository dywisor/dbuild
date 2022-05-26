#!/usr/bin/python3
# -*- coding: utf-8 -*-

import argparse
import collections
import os
import pathlib
import shlex
import subprocess
import sys
import tempfile


class RuntimeEnv(object):

    HOOK_PHASES = [
        'setup',
        'extract',
        'essential',
        'customize',
    ]

    def __init__(self):
        super().__init__()
        self.script_file_called = None
        self.script_file        = None
        self.project_root       = None
        self.project_share_dir  = None
        self.vmap               = None

        self.staging            = None
        self.config_file        = None
        self.tar_outfile        = None

        self.build_collections  = None
        self.mm_argv            = None
    # --- end of __init__ (...) ---

    def get_mm_cmdv(self, quiet=False):
        cmdv = ['mmdebstrap']

        if quiet:
            cmdv.append('--quiet')

        if self.mm_argv:
            cmdv.extend(self.mm_argv)

        cmdv.append(self.vmap['DBUILD_TARGET_CODENAME'])
        cmdv.append(str(self.tar_outfile))

        return cmdv
    # --- end of get_mm_cmdv (...) ---

# --- end of RuntimeEnv ---


class StagingEnv(object):

    CWD_TMPDIR = object()

    ENV_KEEP = {
        'TERM'      : 'linux',
        'HOME'      : None,
        'SHELL'     : '/bin/sh',
        'USER'      : None,
        'LOGNAME'   : None,
        'PATH'      : None,
        'TMPDIR'    : None,

        # PYTHONPATH?
        # PERL5LIB?
    }

    ENV_LANG = 'C.UTF-8'

    ENV_DEFAULTS = {
        'LANG'      : ENV_LANG,
        'LANGUAGE'  : ENV_LANG,
        'LC_ALL'    : ENV_LANG,
    }

    def __init__(self, staging_dir):
        super().__init__()
        self.root = staging_dir
        self.hook_dir = (self.root / 'hooks')

        self.tmpdir_root = (self.root / 'tmp')

        self.env  = self.build_env()
    # --- end of __init__ (...) ---

    def build_env(self):
        env = {}

        for varname, fallback in self.ENV_KEEP.items():
            try:
                env[varname] = os.environ[varname]
            except KeyError:
                if fallback is not None:
                    env[varname] = str(fallback)
        # -- end for

        env.update(self.ENV_DEFAULTS)

        return env
    # --- end of build_env (...) ---

    def get_tmpdir(self):
        return tempfile.TemporaryDirectory(dir=self.tmpdir_root)
    # --- end of get_tmpdir (...) ---

    def run_cmd(
        self, cmdv,
        stdin=subprocess.DEVNULL, check=True, cwd=None, env=None,
        **kwargs
    ):
        envp = dict(self.env)
        if env:
            envp.update(env)
        # --

        if cwd is self.CWD_TMPDIR:
            # run in tmpdir
            with self.get_tmpdir() as tmpdir:
                envp['TMPDIR'] = str(tmpdir)

                proc = subprocess.run(
                    cmdv,
                    stdin=stdin, cwd=str(tmpdir), env=envp,
                    check=check,
                    **kwargs
                )
            # -- end with

        else:
            if not cwd:
                cwd = self.root
            # --

            proc = subprocess.run(
                cmdv,
                stdin=stdin, cwd=str(cwd), env=envp,
                check=check,
                **kwargs
            )
        # --

        return proc
    # --- end of run_cmd (...) ---

# --- end of StagingEnv ---


class BuildCollectionInfo(object):

    def __init__(self, name, prio, root):
        super().__init__()
        self.name = name
        self.prio = prio
        self.root = root
        self.hooks_dir = (self.root / 'hooks')
        self.files_dir = (self.root / 'files')
        self.overlay_dir = (self.root / 'overlay')

        self.hook_env = {
            'HOOK_FILESDIR': self.files_dir,
        }
    # --- end of __init__ (...) ---

# --- end of BuildCollectionInfo ---


def main(prog, argv):
    cfg = RuntimeEnv()
    cfg.script_file_called  = pathlib.Path(os.path.abspath(__file__))
    cfg.script_file         = pathlib.Path(os.path.realpath(cfg.script_file_called))
    cfg.project_root        = cfg.script_file.parent.parent
    cfg.project_share_dir   = cfg.project_root / 'share'

    arg_parser              = get_arg_parser(prog)
    arg_config              = arg_parser.parse_args(argv)

    cfg.staging             = StagingEnv(cfg.script_file_called.parent)

    cfg.config_file         = (cfg.staging.root / 'config')
    cfg.vmap                = load_config(cfg.config_file)

    cfg.tar_outfile         = (cfg.staging.root / 'deb.tar.zst')


    if cfg.vmap.get('DBUILD_TMPDIR_ROOT'):
        cfg.staging.tmpdir_root = cfg.vmap['DBUILD_TMPDIR_ROOT']

    cfg.build_collections   = collections.OrderedDict((
        (
            name,
            BuildCollectionInfo(name, prio, (cfg.project_root / 'collections' / name))
        )
        for prio, name in enumerate(
            filter(
                None,
                cfg.vmap['DBUILD_TARGET_COLLECTIONS'].split()
            )
        )
    ))

    main_init_staging_dir(cfg)
    main_build_hooks(cfg)
    main_build_mmdebstrap_opts(cfg)

    mm_cmdv = cfg.get_mm_cmdv(quiet=arg_config.quiet)

    if arg_config.dry_run:
        sys.stdout.write('dry-run mode: scripts have been generated, exiting.\n')
        return True
    # --

    cfg.staging.run_cmd(mm_cmdv, cwd=StagingEnv.CWD_TMPDIR)
# --- end of main (...) ---


def main_init_staging_dir(cfg):
    #> create directories (may already exist)
    for dirpath in [
        cfg.staging.tmpdir_root,
    ]:
        os.makedirs(dirpath, exist_ok=True)
    # --
# --- end of main_init_staging_dir (...) ---


def main_build_hooks(cfg):
    hooks_share_dir = cfg.project_share_dir / 'hooks'

    # hook_base_script
    hook_base_list = [
        (hooks_share_dir / 'header.sh'),
        cfg.config_file,
        (hooks_share_dir / 'functions.sh'),
    ]

    hook_base_script_blocks = []

    for hook_file in hook_base_list:
        with open(hook_file, 'rt') as infh:
            hook_base_script_blocks.append(infh.read())
        # -- end with
    # -- end for

    hook_base_script = '\n'.join(hook_base_script_blocks)

    hook_files_map = {
        hook_phase: []
        for hook_phase in cfg.HOOK_PHASES
    }

    # walk through collections
    for bcol in cfg.build_collections.values():
        if os.path.isdir(bcol.hooks_dir):
            for hook_phase in cfg.HOOK_PHASES:
                hook_list = hook_files_map[hook_phase]

                try:
                    with os.scandir(bcol.hooks_dir / hook_phase) as it:
                        for entry in it:
                            entry_fp = pathlib.Path(entry.path)
                            if entry_fp.suffix == '.sh' and entry.is_file():
                                hook_list.append((bcol, entry_fp.stem, entry_fp))
                            # --
                        # -- end for
                    # -- end with

                except FileNotFoundError:
                    pass
                # -- end try
            # -- end for
        # -- end if
    # -- end for

    os.makedirs(cfg.staging.hook_dir, exist_ok=True)

    # write hook scripts
    for hook_phase, hook_list in sorted(hook_files_map.items(), key=lambda kv: kv[0]):
        hook_script = cfg.staging.hook_dir / f'{hook_phase}.sh'

        with open(hook_script, 'wt') as outfh:
            #> base script
            outfh.write(hook_base_script)

            #> additional environment read from <collection>/env.sh
            outfh.write('\n### additional runtime environment vars\n')
            for bcol in cfg.build_collections.values():
                env_file = bcol.root / 'env.sh'

                if env_file.is_file():
                    outfh.write(f'## {bcol.name}\n')

                    for line in gen_passthrough_script(env_file):
                        outfh.write(line)

                    outfh.write('\n')
                # --
            # --

            #> additional shell functions read from <collection>/functions.sh
            outfh.write('\n### additional runtime environment functions\n')
            for bcol in cfg.build_collections.values():
                env_file = bcol.root / 'functions.sh'

                if env_file.is_file():
                    outfh.write(f'## {bcol.name}\n')

                    for line in gen_passthrough_script(env_file):
                        outfh.write(line)

                    outfh.write('\n')
                # --
            # --

            #> add code for copying files from <collection>/overlay/<phase>
            outfh.write('\n### rootfs overlay(s)\n')

            for bcol in cfg.build_collections.values():
                rootfs_overlay = bcol.overlay_dir / hook_phase
                if rootfs_overlay.is_dir():
                    outfh.write(f'## {bcol.name}\n')
                    outfh.write(
                        (
                            'rsync -haxHAX \\\n'
                            '    -- \\\n'
                            '    {src}/ \\\n'
                            '    "${{TARGET_ROOTFS:?}}/" || exit\n'
                        ).format(
                            src=shlex.quote(str(rootfs_overlay))
                        )
                    )
                # --

                rootfs_overlay_permtab = bcol.overlay_dir / f'{hook_phase}.permtab'
                if rootfs_overlay_permtab.is_file():
                    for line in gen_permtab_script(rootfs_overlay_permtab):
                        outfh.write(line + '\n')
                # --
            # -- end for

            #> add hooks
            outfh.write('\n### hooks\n')

            for bcol, hook_name, hook_file in sorted(
                hook_list, key=lambda xv: (xv[1], xv[0].prio)
            ):
                bcol_hook_env = dict(bcol.hook_env)

                # start subshell
                # (do not leak variables across hooks)
                outfh.write(f'## {bcol.name} // {hook_name}\n')
                outfh.write('(\n')
                outfh.write(
                    '\n'.join((
                        '{name}={value}'.format(
                            name=name,
                            value=shlex.quote(str(value))
                        )
                        for name, value in sorted(
                            bcol_hook_env.items(),
                            key=lambda kv: kv[0]
                        )
                    )) + '\n'
                )

                for line in gen_passthrough_script(hook_file):
                    outfh.write(line)
                # --

                # end subshell
                outfh.write('\n')
                outfh.write('\n) || exit\n')
                outfh.write(f'## end {bcol.name} // {hook_name}\n')
            # -- end for
        # -- end with

        os.chmod(hook_script, 0o755)
    # -- end for
# --- end of main_build_hooks (...) ---


def main_build_mmdebstrap_opts(cfg):
    # build mmdebstrap opts
    cfg.mm_argv = [
        '--mode=fakechroot',
        '--format=tar',

        '--variant={}'.format(cfg.vmap['DBUILD_TARGET_VARIANT']),
        '--components={}'.format(cfg.vmap['DBUILD_TARGET_COMPONENTS']),
        '--architectures={}'.format(cfg.vmap['DBUILD_TARGET_ARCH']),

        '--hook-directory={}'.format(cfg.staging.hook_dir),
    ]

    for bcol in cfg.build_collections.values():
        pkg_list = set()

        # static package list
        try:
            pkg_list_file = bcol.root / 'package.list'
            pkg_list.update(gen_read_list_file(pkg_list_file))

        except FileNotFoundError:
            pass
        # --

        # dynamic package list
        pkg_list_script = bcol.root / 'package.list.sh'
        if os.path.isfile(pkg_list_script):  # racy, but OK
            proc = cfg.staging.run_cmd(
                [pkg_list_script],
                env=cfg.vmap,   # export whole config as env vars
                capture_output=True
            )

            pkg_list.update((
                pkg
                for l in proc.stdout.decode('ascii').splitlines()
                for pkg in l.split()
                if pkg
            ))
        # -- end if

        if pkg_list:
            cfg.mm_argv.append('--include={}'.format(' '.join(sorted(pkg_list))))
        # -- end try
    # -- end for
# --- end of main_build_mmdebstrap_opts (...) ---


def get_arg_parser(prog):
    parser = argparse.ArgumentParser(prog=os.path.basename(prog))

    parser.add_argument(
        '-q', '--quiet',
        dest='quiet',
        default=False, action='store_true',
        help='suppress informational output'
    )

    parser.add_argument(
        '-n', '--dry-run',
        dest='dry_run',
        default=False, action='store_true',
        help='prepare files, but do not run mmdebstrap'
    )

    return parser
# --- end of get_arg_parser (...) ---


def load_config(filepath):
    return dict(gen_load_config(filepath))
# --- end of load_config (...) ---


def gen_load_config(filepath):
    with open(filepath, 'rt') as fh:
        lexer = shlex.shlex(fh, filepath, posix=True, punctuation_chars=True)

        for tok in lexer:
            varname, vsep, value = tok.partition('=')

            # no validation here.
            yield (varname, value)
        # --
    # --
# --- end of gen_load_config (...) ---


def gen_read_file(filepath):
    with open(filepath, 'rt') as fh:
        for line in fh:
            sline = line.strip()
            if sline and sline[0] != '#':
                yield sline
# --- end of gen_read_file (...) ---


def gen_read_list_file(filepath):
    return (
        item
        for line in gen_read_file(filepath)
        for item in line.split()
        if item
    )
# --- end of gen_read_list_file (...) ---


def gen_permtab_script(filepath):
    for line in gen_read_file(filepath):
        fields = line.split(None, 3)

        if not fields:
            pass

        elif len(fields) != 4:
            raise ValueError(f'error in permtab file: {filepath}: {line}')

        else:
            (ftype, mode, owner, fpath_rel) = fields
            fpath = '"${{TARGET_ROOTFS:?}}"/{0}'.format(shlex.quote(fpath_rel))

            if ftype == 'f':
                # 'f': file, must exist
                yield f"test -f {fpath} || {{ printf 'Error, missing file: %s\\n' {fpath} 1>&2; exit 2; }}"

            elif ftype == 'd':
                # 'd': dir, must exist
                yield f"test -d {fpath} || {{ printf 'Error, missing directory: %s\\n' {fpath} 1>&2; exit 2; }}"

            elif ftype == 'D':
                # 'D': dir, will be created if necessary
                yield f'mkdir -p -- {fpath} || exit 2'

            else:
                raise ValueError(f'unknown ftype in permtab file: {filepath}: {line}')
            # --

            if mode and mode != '-':
                yield 'chmod -- {mode} {fpath} || exit 2'.format(
                    mode=shlex.quote(mode),
                    fpath=fpath
                )
            # --

            if owner and owner != '-':
                yield 'chown -h -- {owner} {fpath} || exit 2'.format(
                    owner=shlex.quote(owner),
                    fpath=fpath
                )
            # --
        # --
    # --
# --- end of gen_permtab_script (...) ---

def gen_passthrough_script(filepath):
    with open(filepath, 'rt') as fh:
        for idx, line in enumerate(fh):
            if not idx and line[:2] == '#!':
                pass
            else:
                yield line
        # --
# --- end of gen_passthrough_script (...) ---


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
