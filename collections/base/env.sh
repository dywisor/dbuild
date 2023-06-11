#!/bin/sh
# hook functions not available yet, check OFEAT_ directly

# merged-usr paths
if [ "${OFEAT_MERGED_USR:-0}" -eq 0 ]; then
    TARGET_FHS_BIN='/bin'
    TARGET_FHS_LIB='/lib'
    TARGET_FHS_LIB32='/lib32'
    TARGET_FHS_LIB64='/lib64'
    TARGET_FHS_LIBEXEC='/libexec'
    TARGET_FHS_SBIN='/sbin'

else
    TARGET_FHS_BIN='/usr/bin'
    TARGET_FHS_LIB='/usr/lib'
    TARGET_FHS_LIB32='/usr/lib32'
    TARGET_FHS_LIB64='/usr/lib64'
    TARGET_FHS_LIBEXEC='/usr/libexec'
    TARGET_FHS_SBIN='/usr/sbin'
fi
