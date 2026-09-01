#!/usr/bin/env bash
# Sourced (not executed) by install.sh and update.sh -- the shared
# lock-acquisition helper for "[P1] Hold the lifecycle lock while
# update.sh changes the source checkout" (#21).
#
# #16 gave install.sh/uninstall.sh their own independent flock on
# ~/.local/state/ruixen/install.lock, correctly serializing DESTINATION
# mutations (plugins, shell.json, looknfeel). But update.sh's own
# `git pull --ff-only` rewrites the SOURCE checkout before ever calling
# install.sh, entirely outside that lock -- a manual install.sh running
# concurrently could read a torn mix of pre-pull and post-pull files
# from the same checkout mid-pull, or (in the other order) update.sh's
# pull could land while install.sh is already mid-`cp -r` from that
# same tree.
#
# Naively adding update.sh's own flock around just the pull, separate
# from install.sh's, would NOT fix this -- update.sh would release its
# lock before calling install.sh, leaving the exact same gap between
# "pull finishes" and "install.sh re-acquires its own lock" that #16's
# design already had. What's needed is ONE lock held continuously from
# before the pull through to the end of install.sh's own run -- but
# update.sh calling install.sh as a child process while STILL holding
# that same lock would deadlock install.sh's own independent flock -n
# attempt (confirmed empirically: a child process's flock -n on the
# same file as a lock its parent already holds correctly detects
# contention and fails, even though it's a child of the SAME process
# tree -- flock locks are per OPEN FILE DESCRIPTION, not per process or
# inode, and install.sh always opens its own fresh file descriptor
# rather than inheriting the parent's).
#
# The fix: acquire_lifecycle_lock is idempotent within one already-
# locked run. update.sh calls it once (acquiring for real, then
# exporting RUIXEN_LIFECYCLE_LOCK_HELD=1 so any child process -- like
# the install.sh it's about to call -- inherits that signal via the
# environment, the same way any other exported shell variable would).
# install.sh calls the SAME function; seeing the flag already set, it
# trusts its caller and skips acquiring a second, genuinely separate
# lock on the same file (which would otherwise self-contend against the
# one its parent already holds). A manual, standalone install.sh run
# has no such flag in its environment, so it acquires the lock fresh,
# exactly as before #21.
#
# Usage: acquire_lifecycle_lock "$state_dir" || fail "..."
# ($state_dir is the caller's own $HOME/.local/state/ruixen -- passed
# in rather than hardcoded so this stays a pure function of its input,
# matching this repo's other lib/*.sh scripts.)
acquire_lifecycle_lock() {
  local state_dir="$1" lock_file

  if [[ "${RUIXEN_LIFECYCLE_LOCK_HELD:-0}" == "1" ]]; then
    return 0
  fi

  lock_file="$state_dir/install.lock"
  exec {RUIXEN_LIFECYCLE_LOCK_FD}>"$lock_file"
  if ! flock -n "$RUIXEN_LIFECYCLE_LOCK_FD"; then
    printf 'another Ruixen install/update/uninstall appears to be running (lock: %s) -- wait for it to finish and try again\n' "$lock_file" >&2
    return 1
  fi

  # Exported (not just set) so a child process this script itself
  # spawns -- update.sh calling install.sh -- inherits it too, without
  # needing to know or pass along the actual file descriptor number.
  export RUIXEN_LIFECYCLE_LOCK_HELD=1
  return 0
}
