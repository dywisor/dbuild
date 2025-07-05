#!/usr/bin/python3
# -*- coding: utf-8 -*-

from __future__ import annotations

from collections.abc import Iterator

import argparse
import os
import sys
import re


def get_argument_parser(prog: str) -> argparse.ArgumentParser:
    def argtype_port_list(arg):
        if not arg:
            return []
        else:
            # only port numbers allowed
            return [int(w) for w in arg.split()]

    parser = argparse.ArgumentParser(prog=prog)

    parser.add_argument(
        "-f",
        "--file",
        metavar="<file>",
        dest="nft_config_file",
        required=True,
        help="nft config file",
    )

    parser.add_argument(
        "-I",
        "--input-rule",
        metavar="<rule>",
        dest="nft_input_rules",
        default=[],
        action="append",
        help="nft input rules to inject",
    )

    parser.add_argument(
        "--input-tcp",
        metavar="<port>",
        dest="nft_input_tcp",
        default=[],
        action="extend",
        type=argtype_port_list,
        help="nft input tcp ports to allow (space-separated)",
    )

    parser.add_argument(
        "--input-udp",
        metavar="<port>",
        dest="nft_input_udp",
        default=[],
        action="extend",
        type=argtype_port_list,
        help="nft input udp ports to allow (space-separated)",
    )

    parser.add_argument(
        "-O",
        "--output-rule",
        metavar="<rule>",
        dest="nft_output_rules",
        default=[],
        action="append",
        help="nft input rules to inject",
    )

    parser.add_argument(
        "--output-tcp",
        metavar="<port>",
        dest="nft_output_tcp",
        default=[],
        action="extend",
        type=argtype_port_list,
        help="nft output tcp ports to allow (space-separated)",
    )

    parser.add_argument(
        "--output-udp",
        metavar="<port>",
        dest="nft_output_udp",
        default=[],
        action="extend",
        type=argtype_port_list,
        help="nft output udp ports to allow (space-separated)",
    )

    outfile_mut_grp = parser.add_mutually_exclusive_group()

    outfile_mut_grp.add_argument(
        "-i",
        "--inplace",
        dest="outfile_inplace",
        default=False,
        action="store_true",
        help="edit nft config file in-place",
    )

    outfile_mut_grp.add_argument(
        "-o",
        "--outfile",
        metavar="<outfile>",
        dest="outfile",
        default=None,
        help="output file (default: <stdout>)",
    )

    return parser


def main(prog: str, argv: list[str]) -> None | int | bool:
    def gen_ports_rule(proto: str, ports: list[int]) -> str:
        ports_dedup = sorted(set(ports))

        if len(ports_dedup) == 1:
            ports_strlist = ports_dedup[0]
        else:
            ports_strlist = "{{ {plist} }}".format(
                plist=", ".join(map(str, ports_dedup))
            )

        return f"{proto} dport {ports_strlist} accept;"

    arg_parser = get_argument_parser(prog)
    arg_config = arg_parser.parse_args(argv)

    nft_config_file = arg_config.nft_config_file

    # collect input rules
    nft_input_rules = []

    if ports := arg_config.nft_input_tcp:
        nft_input_rules.append(gen_ports_rule("tcp", ports))

    if ports := arg_config.nft_input_udp:
        nft_input_rules.append(gen_ports_rule("udp", ports))

    nft_input_rules.extend(arg_config.nft_input_rules)

    # collect output rules
    nft_output_rules = []

    if ports := arg_config.nft_output_tcp:
        nft_output_rules.append(gen_ports_rule("tcp", ports))

    if ports := arg_config.nft_output_udp:
        nft_output_rules.append(gen_ports_rule("udp", ports))

    nft_output_rules.extend(arg_config.nft_output_rules)

    if arg_config.outfile_inplace:
        # consume input file
        nft_config = list(
            gen_edit_nft_config_file(
                nft_config_file,
                nft_input_rules,
                nft_output_rules,
            )
        )

        with open(nft_config_file, "wt") as fh:
            fh.writelines(nft_config)

    else:
        nft_config_gen = gen_edit_nft_config_file(
            nft_config_file,
            nft_input_rules,
            nft_output_rules,
        )

        outfile = arg_config.outfile

        if (not outfile) or (outfile == "-"):
            sys.stdout.writelines(nft_config_gen)

        else:
            with open(outfile, "wt") as fh:
                fh.writelines(nft_config_gen)


def gen_edit_nft_config_file(
    nft_config_file: str, input_rules: list[str], output_rules: list[str]
) -> Iterator[str]:
    # used to track whether rules have been inserted
    chain_rules_to_add: dict[str, list[str]] = {}

    if input_rules:
        chain_rules_to_add["input_local"] = input_rules

    if output_rules:
        chain_rules_to_add["output_local"] = output_rules

    chains_seen: set[str] = set()

    re_chain = re.compile("^(?P<indent>\s+)chain\s+(?P<name>\S+)\s+\{")
    re_match_chain = re_chain.match  # ref

    rule_indent = 4 * " "

    with open(nft_config_file, "rt") as fh:
        for line in fh:
            yield line  # pass-through all input lines

            sline = line.rstrip()

            if m := re_match_chain(sline):
                chain_name = m.group("name")

                if chain_name in chains_seen:
                    raise ValueError(f"redefinition of chain {chain_name}")

                else:
                    chains_seen.add(chain_name)

                    try:
                        rules_to_add = chain_rules_to_add.pop(chain_name)

                    except KeyError:
                        pass

                    else:
                        indent = m.group("indent") + rule_indent
                        for rule in rules_to_add:
                            yield f"{indent}{rule}\n"

    if chain_rules_to_add:
        raise RuntimeError(
            "could not add rules for chains: {}".format(sorted(chain_rules_to_add))
        )


if __name__ == "__main__":
    try:
        exit_code = main(sys.argv[0], sys.argv[1:])

    except KeyboardInterrupt:
        exit_code = 130

    except BrokenPipeError:
        exit_code = 11
        for fh in [sys.stdout, sys.stderr]:
            try:
                fh.close()
            except IOError:
                pass

    else:
        if (exit_code is True) or (exit_code is None):
            exit_code = getattr(os, "EX_OK", 0)

        elif exit_code is False:
            exit_code = getattr(os, "EX_OK", 0) ^ 1

    sys.exit(exit_code)
