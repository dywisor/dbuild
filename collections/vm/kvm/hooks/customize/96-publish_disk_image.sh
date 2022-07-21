#!/bin/sh

autodie zstd -z \
    "${DBUILD_STAGING_TMP:?}/disk.img" \
    -o "${DBUILD_STAGING_IMG:?}/disk.img.zst"
