#!/usr/bin/env bash
# Removes the one-time "what did this machine look like before Ruixen"
# baseline recorded under $1 (the ruixen state dir) -- called by
# uninstall.sh once every earlier restoration step it depends on has
# already succeeded, so the NEXT install/uninstall cycle captures a
# fresh baseline instead of silently reusing this one.
#
# Direct review finding ("Reset pristine install snapshots after a
# successful full uninstall", #13): install.sh's own snapshot writes
# are guarded by `[[ -e ... ]] ||` -- write ONCE, never overwritten
# (see build-shell-json.sh's install.sh caller and apply-looknfeel.sh's
# own comments for why: re-recording on every reinstall/update would
# throw away the real original and replace it with Ruixen's own prior
# state). That guard is correct within a single install lifecycle, but
# it also means a SECOND, later install->uninstall cycle on the same
# machine silently reuses the FIRST cycle's baseline forever unless
# something resets it in between -- uninstall.sh is that "in between".
#
# This script does none of the actual restoring itself (that's already
# done by the time uninstall.sh reaches this point) and is deliberately
# narrow: only the two pre-install baseline records, never anything
# else under $1 (launcher favorites, animation profile, the repo-path
# marker, plugin install backups) -- those are normal Ruixen state or
# user preferences, not rollback metadata, and this issue's own
# non-goal is not wiping them just to solve the staleness bug.
#
# $2 (optional, default "both") -- "bar", "looknfeel", or "both". Added
# for "[P2] Make full uninstall best-effort and report partial cleanup
# failures" (#19): uninstall.sh's bar restore and looknfeel restore are
# now independently recoverable steps that can each fail on their own,
# so each piece of baseline metadata may only be safe to consume if ITS
# OWN restoration actually succeeded -- not "delete both, or neither."
set -Eeuo pipefail

state_dir="$1"
what="${2:-both}"

case "$what" in
  both)
    rm -f "$state_dir/shell.json.pre-ruixen"
    rm -rf "$state_dir/looknfeel-pristine"
    ;;
  bar)
    rm -f "$state_dir/shell.json.pre-ruixen"
    ;;
  looknfeel)
    rm -rf "$state_dir/looknfeel-pristine"
    ;;
  *)
    printf 'reset-pristine-baseline: unknown selector: %s (expected bar, looknfeel, or both)\n' "$what" >&2
    exit 1
    ;;
esac
