#!/bin/sh
# Debian 12 shenanigans:
# *Somehow*, the systemd package ignores the id range configured 
# in sysusers.d when creating systemd-* users/groups.
#
# Breaking expectations with every release :/
#
# As a workaround, create systemd users/groups statically
# with a known uid/gid beforehand.
#
# This is still a thing with Debian 13, so keep that hack around.
# Unfortunately, "passwd" and "libc-bin" are no longer part
# of the essential package selection during mmdebstrap.
# Possible options to deal with that:
# * run apt install in target chroot here
#   - not a great idea,
#     would need to deal with proxy settings and whatnot
# * configure user/groups statically by writing to passwd/group/[g]shadow directly,
#   bypassing getent/useradd/groupadd tools
#   - not the best idea, but will probably work reliably
# * use useradd/groupadd from the build system with the --root (native)
#   or --prefix (cross-compile) option
#   - no getent available
#   - still might be worth a shot - only "--root" supported for now


print_action "Debian systemd hacks: request systemd user/groups"
# username uid group gid password home shell groups comment
autodie dbuild_sysusers_write << 'EOF'
messagebus          -1  messagebus          -1  * /nonexistent - - System Message Bus
-                   -   systemd-journal     -1
systemd-network     -1  systemd-network     -1  * /run/systemd - - systemd Network Management
systemd-resolve     -1  systemd-resolve     -1  * /run/systemd - - systemd Resolver
systemd-timesync    -1  systemd-timesync    -1  * - - - systemd Time Synchronization
systemd-coredump    -1  systemd-coredump    -1  * - - - systemd Core Dumper
EOF
