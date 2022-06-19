#!/bin/sh
# Enable/disable various services for base image

print_action "Enable/disable various services for base image"

#> SSH server
# ssh is enabled by default when installing openssh-server
# ^ FIXME?
if ! feat_all "${OFEAT_SSHD_CONFIG:-0}"; then
    print_action "Disabling SSH server"
    autodie target_disable_svc ssh

fi

# always block ssh.socket for systemd hosts
#   OFEAT_SSHD_CONFIG=0: should not socket-activate ssh then
#   OFEAT_SSHD_CONFIG=1: blocks the regular ssh daemon in favor of per-client sessions
if target_is_systemd; then
    autodie target_mask_svc ssh.socket
fi

#> cron
autodie target_set_svc "${OFEAT_CRON:-0}" cron

#> rsyslog
autodie target_set_svc "${OFEAT_RSYSLOG:-0}" rsyslog
