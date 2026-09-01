#!/usr/bin/env bash
# Reads a pristine shell.json snapshot (install.sh's own
# shell.json.pre-ruixen, #1) from the file path in $1 and prints its
# `bar` object on stdout, exit 0, ONLY if it's usable as a genuine
# pre-Ruixen bar to restore -- present, and not already ruixen.bar.
# Otherwise prints nothing and exits 1, telling the caller
# (uninstall.sh) to fall back to Omarchy's own stock default instead.
#
# Pure read, no side effects -- kept separate so this decision has a
# real, isolated test (tests/uninstall-bar-restore.sh) without needing
# to fake an entire $HOME plus the real `omarchy` CLI the rest of
# uninstall.sh depends on for the actual restore.
set -Eeuo pipefail

snapshot="$1"

[[ -s "$snapshot" ]] || exit 1
jq -ce 'select(.bar.id and .bar.id != "ruixen.bar") | .bar' "$snapshot" 2>/dev/null
