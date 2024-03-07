#!/bin/sh
# Reset env.d (snippets for generating /etc/environment)

print_action "Reset env.d"
autodie dbuild_envd_reset
