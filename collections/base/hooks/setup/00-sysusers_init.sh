#!/bin/sh
# Reset sysusers

print_action "Reset sysusers"
autodie dbuild_sysusers_reset
