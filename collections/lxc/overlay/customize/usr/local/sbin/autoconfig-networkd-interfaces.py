#!/usr/bin/python3
# -*- coding: utf-8 -*-

import hashlib
import os
import re
import sys

AUTOCONFIG_FILE_COMMENT = '# autoconfig-network'


class NetworkConfig(object):
    def __init__(self, name):
        super().__init__()
        self.name = name
        self.ip   = {}
        self.gw   = {}
    # --- end of __init__ (...) ---

    def __repr__(self):
        return f'{self.__class__}(name={self.name}, ip={self.ip!r}, gw={self.gw!r})'
    # --- end of __repr__ (...) ---

# --- end of NetworkConfig ---


def main(prog, argv):
    autoconfig_file_comment = AUTOCONFIG_FILE_COMMENT  # ref

    num_args = len(argv)

    ifcfg_file = (argv[0] if (num_args) else '/etc/network/interfaces')
    outdir     = (argv[1] if (num_args > 1) else '/etc/systemd/network')
    checksum_file = os.path.join(outdir, '.autoconfig-network.state')

    try:
        with open(ifcfg_file, 'rt') as fh:
            ifcfg_input_data = fh.read()

    except FileNotFoundError:
        sys.stdout.write(f'Input config file missing (exit ok): {ifcfg_file}\n')
        return True
    # --

    input_checksum = get_text_checksum(ifcfg_input_data)

    try:
        with open(checksum_file, 'rt') as fh:
            last_outdir_checksum = fh.readline().rstrip()
        # --
    except FileNotFoundError:
        last_outdir_checksum = None
    # --

    if (
        (last_outdir_checksum is not None)
        and (input_checksum == last_outdir_checksum)
    ):
        sys.stdout.write('Config is up-to-date according to checksum check, exiting.\n')
        return True
    # --

    ifcfg_map = read_network_interfaces_config(ifcfg_input_data)


    # drop outdated files
    files_to_del = []
    with os.scandir(outdir) as dir_it:
        for entry in dir_it:
            if entry.name[-8:] == '.network' and entry.is_file():
                with open(entry.path, 'rt') as fh:
                    first_line = fh.readline().rstrip()
                # --

                if first_line == autoconfig_file_comment:
                    files_to_del.append(entry.path)
                # -- end if delete file?
            # -- end if could be a candidate for deletion?
        # -- end for
    # -- end with

    if files_to_del:
        for fpath in files_to_del:
            sys.stdout.write(f'Deleting: {fpath}\n')
            os.unlink(fpath)
        # -- end for
    # -- end if

    # create directory if necessary
    os.makedirs(outdir, exist_ok=True)

    # write new config files
    for outfile_name, outfile_text in gen_networkd_config(ifcfg_map):
        outfile = os.path.join(outdir, outfile_name)
        with open(outfile, 'wt') as outfh:
            sys.stdout.write(f'Writing: {outfile}\n')
            outfh.write(outfile_text + '\n')
    # --

    # write checksum
    with open(checksum_file, 'wt') as fh:
        fh.write(input_checksum + '\n')
    # --
# --- end of main (...) ---


def get_text_checksum(text):
    hash_alg = hashlib.new('blake2b')
    hash_alg.update(text.encode('utf-8'))
    return hash_alg.hexdigest()
# --- end of get_text_checksum (...) ---


def gen_networkd_config(ifcfg_map):
    def gen_network_config(ifcfg, *, autoconfig_file_comment=AUTOCONFIG_FILE_COMMENT):
        yield autoconfig_file_comment
        yield '[Match]'
        yield f'Name = {ifcfg.name}'
        yield ''
        yield '[Network]'

        for fam in [4, 6]:
            try:
                ip = ifcfg.ip[fam]
            except KeyError:
                pass
            else:
                yield f'Address = {ip}'

                try:
                    gw = ifcfg.gw[fam]
                except KeyError:
                    pass
                else:
                    yield f'Gateway = {gw}'
                # -- end try gw
            # -- end try ip
        # -- end for fam
    # ---

    idx = 10
    for iface_name, ifcfg in sorted(ifcfg_map.items(), key=lambda kv: kv[0]):
        outfile_name = f'{idx:02d}-{iface_name}.network'
        yield (outfile_name, '\n'.join(gen_network_config(ifcfg)))

        if idx <= 90:
            idx += 1
    # -- end for
# --- end of gen_networkd_config (...) ---


def read_network_interfaces_config(ifcfg_input_data):
    re_iface_def = re.compile(
        '^iface\s+(?P<name>\S+)\s+(?P<fam>inet6?)\s+static\s*$'
    )
    re_iface_opt = re.compile(
        '^\s+(?P<key>\S+)\s+(?P<val>\S+(?:\s+\S+)*)$'
    )

    ifcfg_map = {}

    current_ifcfg = None
    current_iface_name = None
    current_iface_fam = None

    for line in gen_read_file_data(ifcfg_input_data):
        match_iface_def = re_iface_def.match(line)

        if match_iface_def is not None:
            current_iface_name = match_iface_def.group('name')
            current_iface_fam  = (
                4 if (match_iface_def.group('fam') == 'inet') else 6
            )

            try:
                current_ifcfg = ifcfg_map[current_iface_name]
            except KeyError:
                current_ifcfg = NetworkConfig(current_iface_name)
                ifcfg_map[current_iface_name] = current_ifcfg
            # --

        elif current_ifcfg is not None:
            match_iface_opt = re_iface_opt.match(line)

            if match_iface_opt is not None:
                key = match_iface_opt.group('key')
                val = match_iface_opt.group('val')

                if key == 'address':
                    current_ifcfg.ip[current_iface_fam] = val

                elif key == 'gateway':
                    current_ifcfg.gw[current_iface_fam] = val

                # -- else don't care here

        else:
            # any other line resets the context
            current_ifcfg = None
            current_iface_name = None
            current_iface_fam = None
        # --
    # --

    return ifcfg_map
# --- end of read_network_interfaces_config (...) ---


def gen_read_file_data(file_data):
    for line in file_data.splitlines():
        sline = line.rstrip()

        if sline and sline[0] != '#':
            yield sline
# --- end of gen_read_file (...) ---


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
