#!/usr/bin/python3
# -*- coding: utf-8 -*-

import argparse
import os
import ipaddress
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

    def expand_config_net_sinkhole(vmap):
        vmap_bool = lambda k, *, _vmap=vmap: (_vmap.get(k) == '1')

        def build_routes(vmap, ip_version, config_routes_map):
            if ip_version == 4:
                network_cls = ipaddress.IPv4Network
            elif ip_version == 6:
                network_cls = ipaddress.IPv6Network
            else:
                raise NotImplementedError(ip_version)

            accumulated_routes = set()
            for varname_suffix, var_routes in config_routes_map.items():
                varname = f"OFEAT_NET_SINKHOLE_ROUTES_IP{ip_version}_{varname_suffix}"
                if vmap_bool(varname):
                    accumulated_routes.update((network_cls(o) for o in var_routes))

            var_routes = vmap.get(f"OCONF_NET_SINKHOLE_ROUTES_IP{ip_version}_CUSTOM")
            if var_routes:
                accumulated_routes.update((
                    network_cls(o) for o in var_routes.strip().split() if o
                ))

            return ipaddress.collapse_addresses(accumulated_routes)
        # --- end of build_routes (...) ---

        def build_routes_str(*args, **kwargs):
            return ' '.join(map(str, build_routes(*args, **kwargs)))

        if vmap_bool('OFEAT_NET_SINKHOLE'):
            vmap['OCONF_NET_SINKHOLE_ROUTES_IP4'] = build_routes_str(
                vmap,
                4,
                {
                    'DOC'       : ['192.0.2.0/24', '198.51.100.0/24', '203.0.113.0/24'],
                    'CGNAT'     : ['100.64.0.0/10'],
                    'DSLITE'    : ['192.0.0.0/24'],
                    'BENCHMARK' : ['198.18.0.0/15'],
                    'RFC1918'   : ['10.0.0.0/8', '172.16.0.0/12', '192.168.0.0/16'],
                }
            )

            vmap['OCONF_NET_SINKHOLE_ROUTES_IP6'] = build_routes_str(
                vmap,
                6,
                {
                    'DOC'       : ['2001:db8::/32'],
                    'ULA'       : ['fc00::/7'],
                    'TEREDO'    : ['2001:0000::/32'],
                    'BENCHMARK' : ['2001:2::/48'],
                    '6TO4'      : ['2002::/16'],
                }
            )

        else:
            vmap.pop('OFEAT_NET_SINKHOLE_ROUTES_IP4', None)
            vmap.pop('OFEAT_NET_SINKHOLE_ROUTES_IP6', None)
    # ---

    expand_config_pwvars(vmap)
    expand_config_net_sinkhole(vmap)
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


def merge_config_vars(vmap, new_vars, *, alias_map=None, varnames_merge_value=None, source=None):
    fn_unalias_varname = get_unalias_varname_func(alias_map)

    if varnames_merge_value is None:
        varnames_merge_value = set()
    # --

    for is_declaration, varname_orig, value in new_vars:
        varname = fn_unalias_varname(varname_orig)

        if is_declaration is not None:
            if not is_declaration and varname not in vmap:
                raise RuntimeError(f'variable {varname_orig} gets set in {source}, but has not been declared yet')

            elif is_declaration and varname in vmap:
                raise RuntimeError(f'variable {varname_orig} gets declared in {source}, but has already been declared previously')
            # --
        # --

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

    varnames_merge_value = set()

    if arg_config.merge_vars_file:
        varnames_merge_value.update(
            map(
                get_unalias_varname_func(alias_map),
                config_parser.gen_parse_merge_vars(arg_config.merge_vars_file)
            )
        )
    # --

    if arg_config.merge_vars:
        varnames_merge_value.update(
            map(get_unalias_varname_func(alias_map), arg_config.merge_vars)
        )
    # --

    vmap = {}
    for infile in arg_config.infiles:
        merge_config_vars(
            vmap, config_parser.gen_parse_vars(infile),
            alias_map=alias_map,
            varnames_merge_value=varnames_merge_value,
            source=infile,
        )
    # -- end for

    if arg_config.extra_vars:
        merge_config_vars(
            vmap, arg_config.extra_vars,
            alias_map=alias_map,
            varnames_merge_value=varnames_merge_value,
            source='cmdline',
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

            return (False, varname, value)
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
        '-M', '--merge-vars-file', metavar='<file>',
        dest='merge_vars_file',
        default=None,
        help='file containing variables that should be merged with existing files (instead of replace them)'
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
                varname_tok, vsep, value = tok.partition('=')

                if not varname_tok:
                    varname = varname_tok
                    is_declaration = False

                elif varname_tok[-1] == '*':
                    varname = varname_tok[:-1]
                    is_declaration = True

                elif varname_tok[-1] == '?':
                    varname = varname_tok[:-1]
                    is_declaration = None

                else:
                    varname = varname_tok
                    is_declaration = False
                # --

                if vsep and re_varname.match(varname):
                    yield (is_declaration, varname, value)

                else:
                    raise ValueError("Failed to match vardef", infile, tok)
    # --- end of gen_parse (...) ---

    def gen_parse_vars(self, infile):
        # format: varname[*|?]=value
        yield from self.gen_parse(infile)
    # --- end of gen_parse_vars (...) ---

    def gen_parse_alias_map(self, infile):
        # format: old_varname=new_varname
        re_varname = self.re_varname  # ref

        for is_declaration, old_varname, new_varname in self.gen_parse(infile):
            if is_declaration is not False:
                raise ValueError("alias mapping does not support declaration syntax")
            # --

            if re_varname.match(new_varname):
                yield (old_varname, new_varname)
            else:
                raise ValueError("Failed to match alias mapping", infile, (old_varname, new_varname))
        # -- end for
    # --- end of gen_parse_alias_map (...) ---

    def gen_parse_merge_vars(self, infile):
        # format: varname
        re_varname = self.re_varname  # ref

        with open(infile, 'rt') as fh:
            for line in filter(None, (l.rstrip() for l in fh)):
                if line[0] == '#':
                    # comment
                    pass

                elif re_varname.match(line):
                    yield line

                else:
                    raise ValueError("invalid merge_vars file", infile, line)
            # -- end for
        # -- end with
    # --- end of gen_parse_merge_vars (...) ---

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
