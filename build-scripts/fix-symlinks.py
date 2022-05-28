#!/usr/bin/python3
# -*- coding: utf-8 -*-
#
# Ugly script that rewrites symlinks so that they do no longer point
# to the build-time path of the temporary TARGET_ROOTFS.
#

import argparse
import itertools
import os
import pathlib
import sys


def main(prog, argv):
    arg_parser = main_get_arg_parser(prog)
    arg_config = arg_parser.parse_args(argv)

    links_to_fix = {}

    link_root_src = (
        (arg_config.link_root_src or arg_config.target_rootfs)
    )
    link_root_src_prefix = link_root_src.rstrip('/') + '/'
    link_root_src_prefixlen = len(link_root_src_prefix)

    link_root_dst = arg_config.link_root_dest
    link_root_dst_prefix = link_root_dst.rstrip('/') + '/'

    for link_path in walk_target_rootfs_symlinks(arg_config.target_rootfs):
        link_target = str(link_path.readlink())

        if link_target == link_root_src:
            link_target_new = link_root_dst
            links_to_fix[link_path] = (link_target, link_root_dst)

        elif link_target.startswith(link_root_src_prefix):
            link_target_rel_to_root = link_target[link_root_src_prefixlen:]

            if link_target_rel_to_root:
                link_target_new = link_root_dst_prefix + link_target_rel_to_root
            else:
                link_target_new = link_root_dst
            # --

            links_to_fix[link_path] = (link_target, link_target_new)
        # -- end if
    # -- end for

    if arg_config.dry_run:
        for fpath, (link_target_old, link_target_new) in sorted(
            links_to_fix.items(), key=lambda kv: kv[0]
        ):
            print(f"{fpath}: {link_target_old} => {link_target_new}")
        # -- end for

    else:
        for fpath, (link_target_old, link_target_new) in sorted(
            links_to_fix.items(), key=lambda kv: kv[0]
        ):
            print(f"{fpath}: {link_target_old} => {link_target_new}")

            os.unlink(fpath)
            os.symlink(link_target_new, fpath)
        # -- end for
    # -- end if
# --- end of main (...) ---


def main_get_arg_parser(prog):
    parser = argparse.ArgumentParser(prog=os.path.basename(prog))

    parser.add_argument(
        '--from',
        dest='link_root_src',
    )

    parser.add_argument(
        '--to',
        dest='link_root_dest',
        default='/',
    )

    parser.add_argument(
        '-n', '--dry-run',
        dest='dry_run',
        default=False, action='store_true',
        help='just show what would be done'
    )

    parser.add_argument(
        'target_rootfs',
        help='target rootfs directory'
    )

    return parser
# --- end of main_get_arg_parser (...) ---


def walk_target_rootfs_symlinks(root):
    for (dirpath, dirnames, filenames) in os.walk(root, followlinks=False):
        for filename in itertools.chain(filenames, dirnames):
            fpath = pathlib.Path(dirpath, filename)
            if fpath.is_symlink():
                yield fpath
            # -- end if
        # -- end for
    # -- end for
# --- end of walk_target_rootfs_symlinks (...) ---


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
