#!/usr/bin/python3
# -*- coding: utf-8 -*-

import argparse
import os
import re
import shlex
import subprocess
import sys

def expand_config(vmap):
    def expand_config_pwvars(vmap):
        pwvars = {k: v for k, v in vmap.items() if k[-9:].lower() == '_password'}

        for varname, orig_value in pwvars.items():
            value = '*'

            if not orig_value:
                value = '*'

            elif orig_value[0] == '$':
                value = orig_value

            else:
                proc = subprocess.run(
                    ['mkpasswd', '--stdin', '--method=yescrypt'],
                    input=orig_value.encode('utf-8'),
                    capture_output=True,
                    check=True
                )
                stdout_lines = proc.stdout.decode('utf-8').splitlines()
                value = (stdout_lines[0] or '*')
            # --

            vmap[varname] = value
        # --
    # ---

    expand_config_pwvars(vmap)
# --- end of expand_config (...) ---


def unalias_varname(alias_map, varname_orig):
    visited = set()
    varname_cur = varname_orig

    while varname_cur not in visited:
        visited.add(varname_cur)

        try:
            varname_next = alias_map[varname_cur]
        except KeyError:
            return varname_cur
        # --

        varname_cur = varname_next
    # -- end while

    raise ValueError(f'circular ref in alias map: start={varname_orig} break={varname_cur}', alias_map)
# --- end of unalias_varname (...) ---


def get_unalias_varname_func(alias_map):
    if alias_map:
        return (lambda v, *, _m=alias_map: unalias_varname(_m, v))
    else:
        return (lambda v: v)
# --- end of get_unalias_varname_func (...) ---


def merge_config_vars(vmap, new_vars, *, alias_map=None, varnames_merge_value=None):
    fn_unalias_varname = get_unalias_varname_func(alias_map)

    if varnames_merge_value is None:
        varnames_merge_value = set()
    # --

    for varname_orig, value in new_vars:
        varname = fn_unalias_varname(varname_orig)

        if varname in varnames_merge_value:
            old_value = vmap.get(varname, None)
            new_value = ' '.join((
                item for item in (old_value, value) if item
            ))

            vmap[varname] = new_value

        else:
            # replace any existing value
            vmap[varname] = value
        # --
    # -- end for
# --- end of merge_config_vars (...) ---


def main(prog, argv):
    arg_parser = main_get_arg_parser(prog)
    arg_config = arg_parser.parse_args(argv)

    config_parser = ConfigParser()

    alias_map = {}
    if arg_config.alias_map:
        alias_map.update(config_parser.gen_parse_alias_map(arg_config.alias_map))
    # --

    varnames_merge_value = set(
        map(get_unalias_varname_func(alias_map), arg_config.merge_vars)
    )

    vmap = {}
    for infile in arg_config.infiles:
        merge_config_vars(
            vmap, config_parser.gen_parse_vars(infile),
            alias_map=alias_map,
            varnames_merge_value=varnames_merge_value
        )
    # -- end for

    if arg_config.extra_vars:
        merge_config_vars(
            vmap, arg_config.extra_vars,
            alias_map=alias_map,
            varnames_merge_value=varnames_merge_value
        )
    # --

    expand_config(vmap)

    if arg_config.query:
        try:
            config_value = vmap[arg_config.query]
        except KeyError:
            sys.stderr.write('config var not defined: {}\n'.format(arg_config.query))
            return False

        else:
            sys.stdout.write(str(config_value) + '\n')
        # --

    else:
        output_config = '\n'.join((
            '{name}={value}'.format(name=name, value=shell_quote(value))
            for name, value in sorted(vmap.items(), key=lambda kv: kv[0])
        ))

        if arg_config.outfile:
            with open(arg_config.outfile, 'wt') as fh:
                fh.write(output_config + '\n')

        else:
            print(output_config)
        # --
# --- end of main (...) ---


def main_get_arg_parser(prog):
    def arg_vardef(arg):
        if not arg:
            raise argparse.ArgumentTypeError("expected non-empty argument")
        else:
            varname, vsep, value = arg.partition('=')

            if not varname or not vsep:
                raise argparse.ArgumentTypeError("expected VARNAME=[VALUE] argument")

            return (varname, value)
        # --
    # --- end of arg_vardef (...) ---

    parser = argparse.ArgumentParser(prog=os.path.basename(prog))

    parser.add_argument(
        '-o', '--outfile', metavar='<outfile>',
        help='output config file (default: stdout)'
    )

    parser.add_argument(
        '-A', '--alias-map', metavar='<file>',
        default=None,
        help='varname aliases map file'
    )

    parser.add_argument(
        '-Q', '--query', metavar='<varname>',
        default=None,
        help='query a single variable from the merged config and write it to stdout (and do not write outfile)'
    )

    parser.add_argument(
        '-m', '--merge-vars', metavar='<varname>',
        dest='merge_vars',
        default=[], action='append',
        help='variables that should be merged with existing values (instead of replacing them)'
    )

    parser.add_argument(
        '-e', '--extra-vars', metavar='<vardef>',
        dest='extra_vars',
        default=[], action='append',
        type=arg_vardef,
        help='additional variable(s)'
    )

    parser.add_argument(
        'infiles', nargs='+',
        help='input config files'
    )

    return parser
# --- end of main_get_arg_parser (...) ---


def shell_quote(s):
    """
    Encloses the input string in quotes,
    even if not strictly necessary for shell usage.
    """

    return ("'" + s.replace("'", "'\"'\"'") + "'")
# --- end of shell_quote (...) ---


class ConfigParser(object):

    RESTR_VARNAME = r'^[A-Za-z][A-Za-z0-9_]*$'

    def __init__(self):
        super().__init__()
        self.re_varname = re.compile(self.RESTR_VARNAME)
    # --- end of __init__ (...) ---

    def gen_parse(self, infile):
        re_varname = self.re_varname  # ref

        with open(infile, 'rt') as fh:
            lexer = shlex.shlex(fh, infile, posix=True, punctuation_chars=True)

            for tok in lexer:
                varname, vsep, value = tok.partition('=')

                if vsep and re_varname.match(varname):
                    yield (varname, value)

                else:
                    raise ValueError("Failed to match vardef", infile, tok)
    # --- end of gen_parse (...) ---

    def gen_parse_vars(self, infile):
        # format: varname=value
        yield from self.gen_parse(infile)
    # --- end of gen_parse_vars (...) ---

    def gen_parse_alias_map(self, infile):
        # format: old_varname=new_varname
        re_varname = self.re_varname  # ref

        for old_varname, new_varname in self.gen_parse(infile):
            if re_varname.match(new_varname):
                yield (old_varname, new_varname)
            else:
                raise ValueError("Failed to match alias mapping", infile, (old_varname, new_varname))
        # -- end for
    # --- end of gen_parse_alias_map (...) ---

# --- end of ConfigParser ---


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
