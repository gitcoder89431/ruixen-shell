#!/usr/bin/env bash
# Sourced (not executed) by install.sh and uninstall.sh -- issue #32,
# scoped down from its own original full-auto-recovery design.
#
# The lifecycle lock (lib/acquire-lifecycle-lock.sh) already serializes
# concurrent runs, and install.sh's own rollback_all (an ERR trap) already
# unwinds an ordinary failure cleanly. Neither covers a hard interruption
# that skips trap handling entirely -- kill -9, power loss, a crashed
# terminal. install.sh already has real, separate mitigations for parts
# of this (every deployed plugin is fully re-copied from source on each
# run, so a half-copied plugin self-heals; shell.json and looknfeel
# assets are written to a temp file and renamed into place, so neither
# can ever be left half-written) -- what was still missing was any way
# to tell WHETHER a given run had actually reached one of those safe
# points or was interrupted somewhere in between, so a user had no way
# to know whether "just run it again" was actually safe advice for
# their specific situation, only that it usually is.
#
# This is deliberately NOT automatic recovery. The issue's own original
# design asked for the next lifecycle command to "detect and safely
# recover an unfinished operation before doing new work" fully on its
# own -- automatic recovery logic is exactly the kind of code where a
# bug in the SAFETY NET becomes the thing that breaks a working install,
# and its own acceptance criteria call for testing real kill -9 timing
# at several exact phase boundaries, which can't be fully rehearsed
# against a live daily-driver machine with confidence. Detect, explain
# plainly what's known, and require an explicit human acknowledgment
# before proceeding gets the real protection (nothing silently mutates
# more state on top of an unconfirmed situation) without writing
# speculative auto-repair logic for scenarios this couldn't fully test.
#
# Usage:
#   write_lifecycle_journal "$state_dir" "<operation>"
#   update_lifecycle_journal_phase "$state_dir" "<phase description>"
#   clear_lifecycle_journal "$state_dir"
#   check_lifecycle_journal_or_refuse "$state_dir" "$@"

# Single JSON file, not the issue's own original per-run directory-with-
# a-token design -- this only ever needs to answer "was the LAST run
# left unfinished," never track multiple in-flight runs at once (the
# lifecycle lock already guarantees there is at most one), so there is
# nothing a directory of per-target backup/snapshot bookkeeping would
# add here that install.sh's own EXISTING rollback backups don't already
# cover.
_lifecycle_journal_path() {
  printf '%s/lifecycle-journal.json' "$1"
}

write_lifecycle_journal() {
  local state_dir="$1" operation="$2" journal
  journal="$(_lifecycle_journal_path "$state_dir")"
  jq -n \
    --argjson schema_version 1 \
    --arg operation "$operation" \
    --arg pid "$$" \
    --arg started_at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    --arg phase "started" \
    '{schema_version: $schema_version, operation: $operation, pid: ($pid | tonumber), started_at: $started_at, phase: $phase}' \
    > "$journal"
}

update_lifecycle_journal_phase() {
  local state_dir="$1" phase="$2" journal tmp
  journal="$(_lifecycle_journal_path "$state_dir")"
  # Best-effort -- a failure updating the journal's own phase marker
  # should never be what makes an otherwise-fine install/uninstall run
  # fail. Worst case, a later crash's own journal just names an earlier
  # phase than the run actually reached; check_lifecycle_journal_or_refuse
  # is written to treat that as "somewhere at or past this phase," not
  # as gospel down to the exact step.
  [[ -e "$journal" ]] || return 0
  tmp="$(mktemp "${journal}.XXXXXX")" || return 0
  if jq --arg phase "$phase" '.phase = $phase' "$journal" > "$tmp" 2>/dev/null; then
    mv "$tmp" "$journal"
  else
    rm -f "$tmp"
  fi
}

clear_lifecycle_journal() {
  local state_dir="$1"
  rm -f "$(_lifecycle_journal_path "$state_dir")"
}

# Returns 0 (proceed) if there is nothing to report, or if the caller
# passed --acknowledge-interrupted (any previous journal is cleared
# either way before returning, so a stale journal never lingers past
# this check). Prints a clear explanation and returns 1 (refuse) if a
# previous run's own journal is still there and wasn't acknowledged.
#
# Deliberately does NOT try to guess whether the previous run's PID is
# still alive -- this is only ever called while the lifecycle lock is
# already held, and that lock is what actually guarantees no genuinely
# concurrent run exists; a journal surviving to be seen here already
# means whatever wrote it exited without cleaning up, alive or not.
check_lifecycle_journal_or_refuse() {
  local state_dir="$1"; shift
  local journal arg acknowledge=0
  journal="$(_lifecycle_journal_path "$state_dir")"

  for arg in "$@"; do
    [[ "$arg" == "--acknowledge-interrupted" ]] && acknowledge=1
  done

  if [[ ! -e "$journal" ]]; then
    return 0
  fi

  if [[ "$acknowledge" == "1" ]]; then
    clear_lifecycle_journal "$state_dir"
    return 0
  fi

  # Refuses to guess at a journal it can't actually parse, same "refuse
  # unsafe recovery instead of guessing" requirement the issue itself
  # calls for -- a corrupted journal gets the same hard stop as a valid
  # one reporting a real interruption, not a silent skip.
  local operation started_at phase
  if ! operation="$(jq -r '.operation // empty' "$journal" 2>/dev/null)" || [[ -z "$operation" ]]; then
    printf '\nrefusing to proceed: %s exists but is not a readable journal -- inspect it by hand (or delete it once you are sure nothing is genuinely mid-run) before trying again\n' "$journal" >&2
    return 1
  fi
  started_at="$(jq -r '.started_at // "unknown time"' "$journal" 2>/dev/null || echo "unknown time")"
  phase="$(jq -r '.phase // "an unknown phase"' "$journal" 2>/dev/null || echo "an unknown phase")"

  printf '\nrefusing to proceed: a previous %s run appears to have been interrupted before finishing.\n' "$operation" >&2
  printf '  started: %s\n' "$started_at" >&2
  printf '  reached: %s\n' "$phase" >&2
  printf '\nThis usually just means a crash, a closed terminal, or a kill -9 caught it\n' >&2
  printf 'mid-run -- not that anything is broken. Every plugin this repo deploys is\n' >&2
  printf 'fully re-copied from source on each run, and shell.json/looknfeel writes are\n' >&2
  printf 'atomic (temp file + rename), so re-running is very likely safe on its own.\n' >&2
  printf '\nIf you want to check first: ./ruixen-doctor.sh (read-only) reports plugin\n' >&2
  printf 'drift and runtime health; ./ruixen-repair.sh --dry-run shows what it would fix.\n' >&2
  printf '\nOnce you are ready, re-run this command with --acknowledge-interrupted to\n' >&2
  printf 'continue.\n' >&2
  return 1
}
