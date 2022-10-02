#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
#  Initializes a staging directory and runs build-image within it.
#

import argparse
import collections
import configparser
import datetime
import os
import pathlib
import shlex
import shutil
import subprocess
import sys
import tempfile


class RuntimeConfig(object):

    def __init__(self):
        super().__init__()
        self.script_file_called     = None
        self.script_file            = None
        self.project_root           = None
        self.project_scripts_dir    = None
        self.project_share_dir      = None
        self.project_bcol_root      = None

        self.images_root            = None

        self.profile_config_file    = None
        self.profile_config_name    = None
        self.profile_config         = None
        self.profile_bcol           = None
    # ---

# --- end of RuntimeConfig ---


class StagingEnv(object):

    def __init__(self, staging_dir):
        super().__init__()
        self.root = staging_dir
        self.images_root = (staging_dir / 'images')
    # --- end of __init__ (...) ---

    def run_cmd(
        self, cmdv,
        stdin=subprocess.DEVNULL, check=True,
        **kwargs
    ):
        if 'cwd' not in kwargs:
            kwargs['cwd'] = str(self.root)

        return subprocess.run(cmdv, stdin=stdin, check=check, **kwargs)
    # --- end of run_cmd (...) ---

# --- end of StagingEnv ---


def main(prog, argv):
    cfg = RuntimeConfig()
    cfg.script_file_called  = pathlib.Path(os.path.abspath(__file__))
    cfg.script_file         = pathlib.Path(os.path.realpath(cfg.script_file_called))
    cfg.project_root        = cfg.script_file.parent.parent
    cfg.project_scripts_dir = cfg.project_root / 'build-scripts'
    cfg.project_share_dir   = cfg.project_root / 'share'
    cfg.project_bcol_root   = cfg.project_root / 'collections'

    arg_parser              = get_arg_parser(prog)
    arg_config              = arg_parser.parse_args(argv)

    if arg_config.images_dir:
        cfg.images_root = pathlib.Path(os.path.abspath(arg_config.images_dir))
    else:
        cfg.images_root = cfg.project_root / 'obj'
    # --

    cfg.profile_config_file = pathlib.Path(os.path.abspath(arg_config.profile_config))
    cfg.profile_config_name = cfg.profile_config_file.name
    cfg.profile_config      = load_config(cfg.profile_config_file)

    try:
        want_bcol_names = [w for w in cfg.profile_config['DBUILD_TARGET_COLLECTIONS'].split() if w]
    except KeyError:
        sys.stderr.write('DBUILD_TARGET_COLLECTIONS not set in profile config, aborting.\n')
        return False
    # --

    if not want_bcol_names:
        sys.stderr.write('DBUILD_TARGET_COLLECTIONS is empty in profile config, aborting.\n')
        return False
    # --

    if arg_config.resolve_bcol_dep:
        cfg.profile_bcol = collections.OrderedDict(
            main_gen_expand_build_collections(cfg, want_bcol_names)
        )

    else:
        cfg.profile_bcol = collections.OrderedDict((
            (name, cfg.project_bcol_root / name)
            for name in want_bcol_names
        ))
    # --

    bcol_dir_missing = [
        (name, dirpath) for name, dirpath in cfg.profile_bcol.items()
        if not dirpath.is_dir()
    ]

    if bcol_dir_missing:
        sys.stderr.write('Missing dbuild collections:\n')
        sys.stderr.write(
            ''.join((
                f'  - {name}\n    {dirpath}\n'
                for name, dirpath in sorted(bcol_dir_missing, key=lambda xv: xv[0])
            ))
        )
        return False
    # --

    if arg_config.staging_dir:
        staging_env = StagingEnv(
            pathlib.Path(os.path.abspath(arg_config.staging_dir))
        )

        os.makedirs(staging_env.root, exist_ok=True)

        main_init_staging_dir(cfg, staging_env)
        main_run_build(cfg, staging_env, arg_config)

        main_run_publish(cfg, staging_env, arg_config)

    else:
        with tempfile.TemporaryDirectory() as tmpdir:
            staging_env = StagingEnv(pathlib.Path(os.path.abspath(tmpdir)))

            main_init_staging_dir(cfg, staging_env)

            main_run_build(cfg, staging_env, arg_config)

            main_run_publish(cfg, staging_env, arg_config)
        # -- end with
    # -- end if
# --- end of main (...) ---


def main_gen_expand_build_collections(cfg, wanted):
    def section_iter_list(d, k):
        try:
            v = d[k]

        except KeyError:
            return

        else:
            for item in v.split():
                if item:
                    yield item
    # --- end of section_iter_list (...) ---

    # resolve build collection dependencies while preserving
    # the order requested in the config as much as possible
    collections_done       = set()
    collections_todo_queue = []
    collections_todo_dep   = collections.OrderedDict()

    ## scan for additional dependencies
    collections_todo_scan = wanted

    while collections_todo_scan:
        collections_todo_scan_next = []

        for name in collections_todo_scan:
            if name not in collections_todo_dep:
                bcol_dir = cfg.project_bcol_root / name

                dep_set = set()

                bcol_meta_config_file = bcol_dir / 'meta'
                bcol_is_virtual = False

                # NOTE on missing collections: will raise an error in main() later on
                if bcol_meta_config_file.is_file():
                    bcol_meta_config_parser = configparser.ConfigParser()

                    # ConfigParser.read() does not throw an error on missing file(s),
                    # use open() + ConfigParser.read_file() instead
                    with open(bcol_meta_config_file, 'rt') as fh:
                        bcol_meta_config_parser.read_file(fh, source=bcol_meta_config_file)
                    # --

                    try:
                        bcol_meta_config = bcol_meta_config_parser['collection']

                    except KeyError:
                        sys.stderr.write(f'WARN: dbuild collection meta config has no [collection] section: {name}\n')
                        bcol_meta_config = None
                    # -- end try

                    if bcol_meta_config:
                        bcol_is_virtual = bcol_meta_config_parser.getboolean('collection', 'virtual', fallback=False)

                        # depends X: add dep on X, enqueue scanning of X
                        for item in section_iter_list(bcol_meta_config, 'depends'):
                            dep_set.add(item)
                            collections_todo_scan_next.append(item)
                        # --

                        # wants X: enqueue scanning of X
                        for item in section_iter_list(bcol_meta_config, 'wants'):
                            collections_todo_scan_next.append(item)
                        # --
                    # -- end if
                # -- end if have collection meta config file

                # virtual collections may pull in dependencies,
                # but are ignored otherwise
                # (This skips any collection dir related tasks
                # such as copying files from overlay and executing hooks.)
                if not bcol_is_virtual:
                    collections_todo_queue.append((name, bcol_dir))
                    collections_todo_dep[name] = dep_set
                # -- end if
            # -- end if dependencies already scanned?

            collections_todo_scan = collections_todo_scan_next
        # -- end for
    # -- end while scan for dependencies

    ## resolve dependencies
    while collections_todo_queue:
        resolved_any_dep = False
        collections_todo_queue_next = []

        for name, bcol_dir in collections_todo_queue:
            if name not in collections_done:
                dep = collections_todo_dep[name]

                if not dep:
                    # -> resolved (no pending dependencies)
                    collections_done.add(name)

                    del collections_todo_dep[name]

                    # remove name from all remaining dependencies
                    for other_dep_set in collections_todo_dep.values():
                        other_dep_set.discard(name)
                    # --

                    yield (name, bcol_dir)

                    resolved_any_dep = True

                else:
                    # -> not resolved (yet)
                    collections_todo_queue_next.append((name, bcol_dir))
                # -- end if
            # -- end if name not resolved yet (pre dep check)
        # -- end for

        if not resolved_any_dep:
            raise RuntimeError("Cannot resolve build collection dependencies", collections_todo_dep)
        # -- end if

        collections_todo_queue = collections_todo_queue_next
    # -- end while
# --- end of main_gen_expand_build_collections (...) ---


def main_init_staging_dir(cfg, staging_env):
    #> create script links in staging dir
    for script_name in ['build-image.py']:
        real_script = cfg.project_scripts_dir / script_name
        script_link = staging_env.root / script_name

        try:
            os.unlink(script_link)
        except FileNotFoundError:
            pass

        os.symlink(real_script, script_link)
    # --

    #> create merged configuration file
    config_files = []

    for bcol_name, bcol_dir in cfg.profile_bcol.items():
        bcol_config = bcol_dir / 'config'
        if bcol_config.is_file():
            config_files.append(bcol_config)
        # --
    # --

    config_files.append(cfg.profile_config_file)

    merge_config_cmdv = [
        str(cfg.project_scripts_dir / 'merge-config.py'),
        '-o', str(staging_env.root / 'config'),
    ]

    for varname, value in [
        ('DBUILD_PROFILE_NAME', cfg.profile_config_name),
        (
            'DBUILD_TARGET_COLLECTIONS',
            ' '.join((name for name in cfg.profile_bcol))
        ),
    ]:
        merge_config_cmdv.extend(['-e', f'{varname}={value}'])
    # --

    merge_config_cmdv.extend(map(str, config_files))

    staging_env.run_cmd(merge_config_cmdv)
# --- end of main_init_staging_dir (...) ---


def main_run_build(cfg, staging_env, arg_config):
    cmdv = [
        str(staging_env.root / 'build-image.py'),
    ]

    if arg_config.dry_run:
        cmdv.append('-n')
    # --

    staging_env.run_cmd(cmdv)
# --- end of main_run_build (...) ---


def main_run_publish(cfg, staging_env, arg_config):
    if arg_config.dry_run:
        # nothing to be seen in dry run mode
        return
    # --

    timestamp  = datetime.datetime.now().strftime("%Y-%m-%d_%s")
    images_dir = cfg.images_root / cfg.profile_config_name

    with os.scandir(staging_env.images_root) as dir_it:
        for entry in dir_it:
            if not entry.name.startswith('.') and entry.is_file():
                src_file = pathlib.Path(entry.path)
                suffixes = ''.join(src_file.suffixes)
                name     = src_file.name[:-len(suffixes)]

                dst_fname = f'{cfg.profile_config_name}_{name}_{timestamp}{suffixes}'
                dst_lname = f'{cfg.profile_config_name}_{name}{suffixes}'

                dst_file  = images_dir / dst_fname
                dst_link  = images_dir / dst_lname

                sys.stdout.write(f'Publishing image: {dst_file}\n')
                os.makedirs(images_dir, exist_ok=True)
                shutil.move(src_file, dst_file)

                try:
                    os.unlink(dst_link)
                except FileNotFoundError:
                    pass

                dst_link.symlink_to(dst_file.name)
            # -- end if
        # -- end for
    # -- end with
# --- end of main_run_publish (...) ---


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


def get_arg_parser(prog):
    parser = argparse.ArgumentParser(prog=os.path.basename(prog))

    parser.add_argument(
        'profile_config',
        help='path to the profile configuration file'
    )

    parser.add_argument(
        '-q', '--quiet',
        dest='quiet',
        default=False, action='store_true',
        help='suppress informational output'
    )

    parser.add_argument(
        '--resolve-bcol-dep',
        dest='resolve_bcol_dep',
        default=True, action='store_true',
        help='resolve build collection dependencies (enabled by default)'
    )

    parser.add_argument(
        '--no-resolve-bcol-dep',
        dest='resolve_bcol_dep',
        default=argparse.SUPPRESS, action='store_false',
        help='do not resolve build collection dependencies'
    )

    parser.add_argument(
        '-S', '--staging', metavar='<staging_dir>',
        dest='staging_dir',
        help='use <staging_dir> as staging dir instead of a temporary directory'
    )

    parser.add_argument(
        '-D', '--images', metavar='<images_dir>',
        dest='images_dir',
        help='publish generated image below <images_dir>/<profile_name>/'
    )

    parser.add_argument(
        '-n', '--dry-run',
        dest='dry_run',
        default=False, action='store_true',
        help='prepare files, but do not run mmdebstrap'
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
