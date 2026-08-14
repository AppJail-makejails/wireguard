#!/bin/sh

LOCKFILE="${TMPDIR:-/tmp}/.wg-xcaler.lock"

exec lockf -ks "${LOCKFILE}" /scripts/run.sh "$@"
