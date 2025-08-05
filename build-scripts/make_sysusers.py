#!/usr/bin/python3
# -*- coding: utf-8 -*-

from __future__ import annotations

from collections.abc import Hashable, Iterable, Iterator
from typing import Any, Optional

import argparse
import collections
import collections.abc
import os
import pathlib
import sys
import time

from dataclasses import dataclass, field


class Globals:
    DEFAULT_HOME = "/"
    DEFAULT_SHELL = "/usr/sbin/nologin"
    SYSTEM_USER_ID_RANGE = (100, 399)
    REGULAR_USER_ID_RANGE = (1000, 1999)


class DuplicateKeyError(KeyError):
    pass


class OrderedSet(collections.abc.MutableSet):
    def __init__(self, data: Optional[Iterable[Hashable]] = None):
        super().__init__()
        self.data = collections.OrderedDict()
        if data:
            self.update(data)

    def __contains__(self, item: Hashable) -> bool:
        return item in self.data

    def __iter__(self) -> Iterator[Hashable]:
        return iter(self.data)

    def __len__(self) -> int:
        return len(self.data)

    def add(self, item: Hashable) -> None:
        self.data[item] = True

    def discard(self, item: Hashable) -> None:
        self.data.pop(item, None)


@dataclass
class SysusersEntry:
    username: Optional[str]
    uid: Optional[int]
    group: str
    gid: int
    password: Optional[str]
    home: Optional[str]
    shell: Optional[str]
    groups: Optional[list[str]]
    comment: Optional[str]


@dataclass
class AbstractEntry:
    raw: Optional[str]
    changed: bool = field(init=False, default=False)

    def get_name(self) -> str:
        raise NotImplementedError(self)

    def get_id(self) -> None | int:
        raise NotImplementedError(self)

    def get_fields(self) -> list[Any]:
        raise NotImplementedError(self)

    def __str__(self) -> str:
        if self.changed or not self.raw:
            return ":".join(map(str, self.get_fields()))
        else:
            return self.raw


@dataclass
class UserEntry(AbstractEntry):
    pw_name: str
    pw_passwd: str
    pw_uid: int
    pw_gid: int
    pw_gecos: str
    pw_dir: str
    pw_shell: str

    def get_name(self) -> str:
        return self.pw_name

    def get_id(self) -> int:
        return self.pw_uid

    def get_fields(self) -> list[Any]:
        return [
            self.pw_name,
            self.pw_passwd,
            self.pw_uid,
            self.pw_gid,
            self.pw_gecos,
            self.pw_dir,
            self.pw_shell,
        ]


@dataclass
class GroupEntry(AbstractEntry):
    gr_name: str
    gr_passwd: str
    gr_gid: int
    gr_mem: OrderedSet[str]

    def get_name(self) -> str:
        return self.gr_name

    def get_id(self) -> int:
        return self.gr_gid

    def get_fields(self) -> list[Any]:
        return [
            self.gr_name,
            self.gr_passwd,
            self.gr_gid,
            ",".join(self.gr_mem),
        ]


class SimpleEntryDB(collections.abc.Mapping):

    def __init__(self):
        super().__init__()
        self.data = collections.OrderedDict()

    def add(self, key: Hashable, value: Any) -> None:
        if key in self.data:
            raise DuplicateKeyError(key)
        else:
            self.data[key] = value

    def add_or_replace(self, key: Hashable, value: Any) -> None:
        self.data[key] = value

    def __getitem__(self, key: Hashable) -> Any:
        return self.data[key]

    def __iter__(self) -> Iterator[Hashable]:
        return iter(self.data)

    def __len__(self) -> int:
        return len(self.data)

    def __contains__(self, key: Hashable) -> bool:
        return key in self.data

    def iter_entries(self) -> Iterator[Any]:
        yield from self.data.values()


class EntryDB:

    def __init__(self):
        super().__init__()
        self.by_name = collections.OrderedDict()
        self.by_id = {}

    def add(self, entry: AbstractEntry) -> None:
        name = entry.get_name()
        entry_id = entry.get_id()

        if name in self.by_name:
            raise DuplicateKeyError(name)

        if entry_id is not None and entry_id in self.by_id:
            raise DuplicateKeyError(entry_id)

        self.by_name[name] = entry

        if entry_id is not None:
            self.by_id[entry_id] = entry

    def get_by_name(self, name: str) -> AbstractEntry:
        return self.by_name[name]

    def get_by_id(self, entry_id: int) -> AbstractEntry:
        return self.by_id[entry_id]

    def iter_entries(self) -> Iterator[AbstractEntry]:
        yield from self.by_name.values()


@dataclass
class UsersGroupsDB:
    passwd: EntryDB
    group: EntryDB
    shadow: Optional[SimpleEntryDB]
    gshadow: Optional[SimpleEntryDB]


class UidGidGenerator:
    # NOTE: manages id_min/id_max exclusively,
    # cannot cooperate with UidGidGenerator instances sharing the same id range
    def __init__(self, users_groups_db: UsersGroupsDB, id_min: int, id_max: int):
        super().__init__()
        self.users_groups_db = users_groups_db
        self.id_min = id_min  # unused
        self.id_max = id_max
        self._id_next = id_min
        self._name_id_cache = {}

    def get(self, name: str) -> int:
        name_id_cache = self._name_id_cache  # ref/modified

        try:
            return name_id_cache[name]
        except KeyError:
            pass

        passwd_id = self.users_groups_db.passwd.by_name.get(name, None)
        group_id = self.users_groups_db.group.by_name.get(name, None)

        if passwd_id is not None:
            if group_id is None or passwd_id == group_id:
                name_id_cache[name] = passwd_id
                return passwd_id

        elif group_id is not None:  # and passwd_is None, already checked
            name_id_cache[name] = group_id
            return group_id

        passwd_id_db = self.users_groups_db.passwd.by_id  # ref
        group_id_db = self.users_groups_db.group.by_id  # ref

        id_max = self.id_max  # ref

        id_next = self._id_next

        while id_next <= id_max and (id_next in passwd_id_db or id_next in group_id_db):
            id_next += 1

        if id_next > id_max:
            raise RuntimeError("uid/gid generator exhausted", id_next, id_max)

        else:
            name_id_cache[name] = id_next
            self._id_next = id_next + 1
            return id_next


def get_argument_parser(prog: str) -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog=prog)

    parser.add_argument(
        "-R",
        "--root",
        metavar="<target_rootfs>",
        dest="target_rootfs",
        required=True,
        type=pathlib.Path,
        help="target rootfs directory",
    )

    parser.add_argument(
        "-O",
        "--outdir",
        metavar="<outdir>",
        dest="outdir",
        default=None,
        type=pathlib.Path,
        help="specify alternate output directory for files",
    )

    parser.add_argument("sysusers_file", type=pathlib.Path, help="make-sysusers file")

    return parser


def main(prog: str, argv: list[str]) -> None | int | bool:
    arg_parser = get_argument_parser(prog)
    arg_config = arg_parser.parse_args(argv)

    target_rootfs = arg_config.target_rootfs

    outdir = arg_config.outdir
    if not outdir:
        outdir = target_rootfs / "etc"
    target_users_groups_db = load_users_groups_db(target_rootfs)

    merge_sysusers(
        target_users_groups_db, iparse_sysusers_file(arg_config.sysusers_file)
    )

    write_outfile(outdir / "passwd", target_users_groups_db.passwd.iter_entries())
    write_outfile(outdir / "group", target_users_groups_db.group.iter_entries())

    if target_users_groups_db.shadow is not None:
        write_outfile(outdir / "shadow", target_users_groups_db.shadow.iter_entries())

    if target_users_groups_db.gshadow is not None:
        write_outfile(outdir / "gshadow", target_users_groups_db.gshadow.iter_entries())


def write_outfile(filepath: pathlib.Path, entries: Iterable[Any]) -> None:
    with open(filepath, "wt") as fh:
        fh.write("\n".join(map(str, entries)) + "\n")


def load_users_groups_db(rootfs: pathlib.Path) -> UsersGroupsDB:
    passwd_db = load_passwd_file(rootfs / "etc" / "passwd")
    group_db = load_group_file(rootfs / "etc" / "group")
    try:
        shadow_db = load_shadow_file(rootfs / "etc" / "shadow")
    except FileNotFoundError:
        shadow_db = None
    try:
        gshadow_db = load_gshadow_file(rootfs / "etc" / "gshadow")
    except FileNotFoundError:
        gshadow_db = None

    return UsersGroupsDB(
        passwd=passwd_db,
        group=group_db,
        shadow=shadow_db,
        gshadow=gshadow_db,
    )


def merge_sysusers(
    users_groups_db: UsersGroupsDB, sysuser_entries: Iterable[SysusersEntry]
) -> None:
    default_home = Globals.DEFAULT_HOME  # ref
    default_shell = Globals.DEFAULT_SHELL  # ref

    if users_groups_db.shadow is not None:
        shadow_password_age = int(time.time() / 86400.0)
    else:
        shadow_password_age = None

    system_id_generator = UidGidGenerator(
        users_groups_db=users_groups_db,
        id_min=Globals.SYSTEM_USER_ID_RANGE[0],
        id_max=Globals.SYSTEM_USER_ID_RANGE[1],
    )

    regular_id_generator = UidGidGenerator(
        users_groups_db=users_groups_db,
        id_min=Globals.REGULAR_USER_ID_RANGE[0],
        id_max=Globals.REGULAR_USER_ID_RANGE[1],
    )

    def resolve_id(
        name: str,
        value: int,
        *,
        _system_id_generator=system_id_generator,
        _regular_id_generator=regular_id_generator,
    ) -> int:
        if value > 0:
            return value
        elif value == -1:
            return _system_id_generator.get(name)
        elif value == -2:
            return _regular_id_generator.get(name)
        else:
            raise ValueError(name, value)

    def update_or_add_group(
        users_groups_db: UsersGroupsDB, name: str, gid: int
    ) -> GroupEntry:
        try:
            group_db_entry = users_groups_db.group.by_name[name]

        except KeyError:
            # add new group
            gid = resolve_id(name, gid)

            group_db_entry = GroupEntry(
                raw=None,
                gr_name=name,
                gr_passwd="x",
                gr_gid=gid,
                gr_mem=OrderedSet(),
            )
            group_db_entry.changed = True

            users_groups_db.group.add(group_db_entry)

        else:
            # update existing group
            if gid > 0 and gid != group_db_entry.gr_gid:
                group_db_entry.gr_gid = gid
                group_db_entry.changed = True

        return group_db_entry

    # --- end of update_or_add_group (...) ---

    # group_name => set<user_name>
    group_members_map = {}

    for sysuser_entry in sysuser_entries:
        # add/update group
        group_db_entry = update_or_add_group(
            users_groups_db, sysuser_entry.group, sysuser_entry.gid
        )

        # add gshadow entry if loaded and entry missing
        if users_groups_db.gshadow is not None:
            users_groups_db.gshadow.add_or_replace(
                sysuser_entry.group, f"{sysuser_entry.group}:*::"
            )
        # -- end if users_groups_db.gshadow

        if sysuser_entry.username:
            # add/update user
            try:
                user_db_entry = users_groups_db.passwd.by_name[sysuser_entry.username]

            except KeyError:
                # add new user
                uid = resolve_id(sysuser_entry.username, sysuser_entry.uid)

                user_db_entry = UserEntry(
                    raw=None,
                    pw_name=sysuser_entry.username,
                    pw_passwd="x",
                    pw_uid=uid,
                    pw_gid=group_db_entry.gr_gid,
                    pw_gecos=(sysuser_entry.comment or ""),
                    pw_dir=(sysuser_entry.home or default_home),
                    pw_shell=(sysuser_entry.shell or default_shell),
                )
                user_db_entry.changed = True

                users_groups_db.passwd.add(user_db_entry)

            else:
                # update existing user
                if sysuser_entry.uid > 0 and sysuser_entry.uid != user_db_entry.pw_uid:
                    user_db_entry.pw_uid = sysuser_entry.uid
                    user_db_entry.changed = True

                if group_db_entry.gr_gid != user_db_entry.pw_gid:
                    user_db_entry.pw_gid = group_db_entry.gr_gid
                    user_db_entry.changed = True

                if (
                    sysuser_entry.comment
                    and sysuser_entry.comment != user_db_entry.pw_gecos
                ):
                    user_db_entry.pw_gecos = sysuser_entry.comment
                    user_db_entry.changed = True

                if sysuser_entry.home and sysuser_entry.home != user_db_entry.pw_dir:
                    user_db_entry.pw_dir = sysuser_entry.home
                    user_db_entry.changed = True

                if (
                    sysuser_entry.shell
                    and sysuser_entry.shell != user_db_entry.pw_shell
                ):
                    user_db_entry.pw_shell = sysuser_entry.shell
                    user_db_entry.changed = True

            # user group membership will be resolved later
            if sysuser_entry.groups:
                for member_group_name in sysuser_entry.groups:
                    try:
                        group_members_node = group_members_map[member_group_name]
                    except KeyError:
                        group_members_node = set()
                        group_members_map[member_group_name] = group_members_node

                    group_members_node.add(sysuser_entry.username)
            # --

            # add shadow entry if loaded and entry missing
            if users_groups_db.shadow is not None:
                if user_db_entry.pw_passwd != "x":
                    user_db_entry.pw_passwd = "x"
                    user_db_entry.changed = True

                users_groups_db.shadow.add_or_replace(
                    sysuser_entry.username,
                    f"{sysuser_entry.username}:{sysuser_entry.password}:{shadow_password_age}::::::",
                )
            # -- end if users_groups_db.shadow
        # -- end if sysuser_entry.username
    # -- end for sysuser_entry in sysuser_entries

    for group_name, usernames in group_members_map.items():
        # add/update group
        group_db_entry = update_or_add_group(users_groups_db, group_name, -1)

        # update group members
        for username in usernames:
            if username not in group_db_entry.gr_mem:
                group_db_entry.gr_mem.add(username)
                group_db_entry.changed = True


def iparse_sysusers_file(filepath: pathlib.Path) -> Iterator[SysusersEntry]:
    def normalize_field_value(value: str, /) -> Optional[str]:
        if not value or value == "-":
            return None
        else:
            return value

    def parse_uid_gid_value(value: str, /) -> int:
        id_value = int(value, 10)

        if id_value == 0 or id_value < -2:
            raise ValueError("invalid uid/gid")

        return id_value

    # https://buildroot.org/downloads/manual/manual.html#makeuser-syntax
    # https://buildroot.org/downloads/manual/makeusers-syntax.txt
    #
    # The syntax for adding a user is a space-separated list of fields, one
    # user per line; the fields are:
    #
    # |=================================================================
    # |username |uid |group |gid |password |home |shell |groups |comment
    # |=================================================================
    #
    # Where:
    #
    # - +username+ is the desired user name (aka login name) for the user.
    #   It can not be +root+, and must be unique. If set to +-+, then just a
    #   group will be created.
    # - +uid+ is the desired UID for the user. It must be unique, and not
    #   +0+. If set to +-1+ or +-2+, then a unique UID will be computed by
    #   Buildroot, with +-1+ denoting a system UID from [100...999] and +-2+
    #   denoting a user UID from [1000...1999].
    # - +group+ is the desired name for the user's main group. It can not
    #   be +root+. If the group does not exist, it will be created.
    # - +gid+ is the desired GID for the user's main group. It must be unique,
    #   and not +0+. If set to +-1+ or +-2+, and the group does not already
    #   exist, then a unique GID will be computed by Buildroot, with +-1+
    #   denoting a system GID from [100...999] and +-2+ denoting a user GID
    #   from [1000...1999].
    # - +password+ is the crypt(3)-encoded password. If prefixed with +!+,
    #   then login is disabled. If prefixed with +=+, then it is interpreted
    #   as clear-text, and will be crypt-encoded (using MD5). If prefixed with
    #   +!=+, then the password will be crypt-encoded (using MD5) and login
    #   will be disabled. If set to +*+, then login is not allowed. If set to
    #   +-+, then no password value will be set.
    # - +home+ is the desired home directory for the user. If set to '-', no
    #   home directory will be created, and the user's home will be +/+.
    #   Explicitly setting +home+ to +/+ is not allowed.
    # - +shell+ is the desired shell for the user. If set to +-+, then
    #   +/bin/false+ is set as the user's shell.
    # - +groups+ is the comma-separated list of additional groups the user
    #   should be part of. If set to +-+, then the user will be a member of
    #   no additional group. Missing groups will be created with an arbitrary
    #   +gid+.
    # - +comment+ (aka https://en.wikipedia.org/wiki/Gecos_field[GECOS]
    #   field) is an almost-free-form text.

    with open(filepath, "rt") as fh:
        for lino_m, line in enumerate(fh):
            lino = lino_m + 1
            sline = line.rstrip()

            if sline and sline[0] != "#":
                has_username = None

                fields = sline.split(None, 8)
                nfields = len(fields)
                if nfields < 9:
                    fields.extend(("-" for _ in range(9 - nfields)))

                entry_vars = {}

                # 0: +username+
                arg = normalize_field_value(fields[0])
                if arg and arg == "root":
                    raise ValueError(f"invalid sysuser username at line {lino}: {arg}")

                entry_vars["username"] = arg
                has_username = bool(arg)

                # 1: +uid+
                arg = normalize_field_value(fields[1])
                if has_username:
                    if not arg:
                        raise ValueError(f"invalid sysuser uid at line {lino}: {arg}")

                    try:
                        value = parse_uid_gid_value(arg)
                    except ValueError:
                        raise ValueError(f"invalid sysuser uid at line {lino}: {arg}")

                    entry_vars["uid"] = value

                else:
                    if arg:
                        raise ValueError(
                            f"sysuser has no username, uid must not be set at line {lino}"
                        )

                    entry_vars["uid"] = None

                # 2: +group+
                arg = normalize_field_value(fields[2])
                if arg and arg == "root":
                    raise ValueError(
                        f"invalid sysuser group name at line {lino}: {arg}"
                    )

                entry_vars["group"] = arg

                # 3: +gid+
                arg = normalize_field_value(fields[3])
                if not arg:
                    raise ValueError(f"invalid sysuser gid at line {lino}: <empty>")
                    # entry_vars["gid"] = arg

                else:
                    try:
                        value = parse_uid_gid_value(arg)
                    except ValueError:
                        raise ValueError(f"invalid sysuser gid at line {lino}: {arg}")

                    entry_vars["gid"] = value

                # 4: +password+ (PARTIALLY IMPLEMENTED)
                arg = normalize_field_value(fields[4])

                if has_username:
                    if not arg:
                        raise NotImplementedError(
                            f"sysuser empty password not implemented at line {lino}"
                        )

                    elif arg in {"*", "!"}:
                        # always accepted
                        entry_vars["password"] = arg

                    elif arg.startswith("=") or arg.startswith("!="):
                        raise NotImplementedError(
                            f"sysuser cleartext password not implemented at line {lino}"
                        )

                    else:
                        # pw hash
                        entry_vars["password"] = arg

                else:
                    # group-only: unset or "*" required
                    if not arg or arg in {"*", "!"}:
                        entry_vars["password"] = arg

                    else:
                        raise ValueError(
                            f"sysuser has no username, password must be empty or * at line {lino}"
                        )

                # 5: +home+
                arg = normalize_field_value(fields[5])

                if has_username:
                    if arg and arg == "/":
                        raise ValueError(f"invalid sysuser home at line {lino}: {arg}")

                    entry_vars["home"] = arg

                else:
                    if arg:
                        raise ValueError(
                            f"sysuser has no username, home must not be set at line {lino}"
                        )

                    entry_vars["home"] = None

                # 6: +shell+
                arg = normalize_field_value(fields[6])

                if has_username:
                    entry_vars["shell"] = arg

                else:
                    if arg:
                        raise ValueError(
                            f"sysuser has no username, home must not be set at line {lino}"
                        )

                    entry_vars["shell"] = None

                # 7: +groups+
                arg = normalize_field_value(fields[7])

                if has_username:
                    if not arg:
                        entry_vars["groups"] = []
                    else:
                        entry_vars["groups"] = arg.split(",")

                else:
                    if arg:
                        raise ValueError(
                            f"sysuser has no username, groups must not be set at line {lino}"
                        )

                    entry_vars["groups"] = None

                # 8: +comment+
                arg = fields[8]  # no normalization

                if has_username:
                    entry_vars["comment"] = arg

                else:
                    if arg and arg != "-":
                        raise ValueError(
                            f"sysuser has no username, comment must not be set at line {lino}"
                        )

                    entry_vars["comment"] = None

                yield SysusersEntry(**entry_vars)


def load_passwd_file(filepath: pathlib.Path) -> EntryDB:
    entry_db = EntryDB()

    for line, fields in iparse_entry_file(filepath):
        if len(fields) != 7:
            raise ValueError(line)

        entry_db.add(
            UserEntry(
                raw=line,
                pw_name=fields[0],
                pw_passwd=fields[1],
                pw_uid=int(fields[2]),
                pw_gid=int(fields[3]),
                pw_gecos=fields[4],
                pw_dir=fields[5],
                pw_shell=fields[6],
            )
        )

    return entry_db


def load_group_file(filepath: pathlib.Path) -> EntryDB:
    entry_db = EntryDB()

    for line, fields in iparse_entry_file(filepath):
        if len(fields) != 4:
            raise ValueError(line)

        entry_db.add(
            GroupEntry(
                raw=line,
                gr_name=fields[0],
                gr_passwd=fields[1],
                gr_gid=int(fields[2]),
                gr_mem=fields[3],
            )
        )

    return entry_db


def load_shadow_file(filepath: pathlib.Path) -> EntryDB:
    entry_db = SimpleEntryDB()

    for line, fields in iparse_entry_file(filepath):
        if len(fields) != 9:
            raise ValueError(line)

        entry_db.add(fields[0], line)

    return entry_db


def load_gshadow_file(filepath: pathlib.Path) -> EntryDB:
    entry_db = SimpleEntryDB()

    for line, fields in iparse_entry_file(filepath):
        if len(fields) != 4:
            raise ValueError(line)

        entry_db.add(fields[0], line)

    return entry_db


def iparse_entry_file(filepath: pathlib.Path) -> Iterator[list[str]]:
    with open(filepath, "rt") as fh:
        for line in fh:
            sline = line.rstrip()
            fields = sline.split(":")
            yield (sline, fields)


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
