#!/bin/sh
set -eu

mkdir -p /data/files
exec /usr/local/bin/dropdir /data/files "$@"
