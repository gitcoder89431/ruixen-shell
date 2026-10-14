#!/usr/bin/env bash
# Real live report: the Settings page's own Update button runs
# update.sh/install.sh as a child of the CURRENTLY RUNNING quickshell
# (see ruixen.launcher/extensions/settings/services/PluginService.qml's updateRuixenShell()
# own comment) -- `omarchy restart shell` tearing that same quickshell
# process down killed this script's own process group as a side effect,
# silently skipping orphan-plugin removal, the repo-path write, and
# clear_lifecycle_journal every time it ran that way. Confirmed live:
# shell.json was correctly stripped of a removed plugin's id (that part
# runs before the restart), but the plugin's own deployed directory and
# the lifecycle journal both survived untouched until a second, manual,
# terminal-invoked run finished the job (a process tree that was never
# a quickshell descendant to begin with, so it was never at risk).
#
# install.sh now runs everything from "omarchy restart shell" onward
# inside `setsid bash -c '...'`, moving it into a brand new session
# before that command runs, immune to whatever reaps this script's
# original group. This test proves that actually happens at runtime
# (the restart step's own session differs from the rest of the script)
# rather than trusting the setsid call is wired correctly by inspection
# of the source alone.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

pass=0
fail_count=0
check() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   - %s\n' "$desc"
    pass=$((pass + 1))
  else
    printf 'FAIL - %s\n       got:  %s\n       want: %s\n' "$desc" "$got" "$want"
    fail_count=$((fail_count + 1))
  fi
}

home1="$(mktemp -d)"
trap 'rm -rf "$home1"' EXIT

outer_sid="$(ps -o sid= -p $$ | tr -d ' ')"
record_prefix="$home1/restart-session"

if ( HOME="$home1" PATH="$fake_bin:$PATH" FAKE_OMARCHY_RECORD_RESTART_SESSION="$record_prefix" "$repo_dir/install.sh" ) \
  >"$home1/install.out" 2>&1; then
  status=0
else
  status=$?
fi

check "install.sh exits 0" "$status" "0"
check "the restart step recorded its own pid/session id" \
  "$([[ -s "$record_prefix.pid" && -s "$record_prefix.sid" ]] && echo yes || echo no)" "yes"

restart_sid="$(cat "$record_prefix.sid" 2>/dev/null || echo "")"

check "the restart step ran in a DIFFERENT session than the rest of this script (proves setsid actually took effect, not just present in the source)" \
  "$([[ -n "$restart_sid" && "$restart_sid" != "$outer_sid" ]] && echo yes || echo no)" "yes"

# --- omarchy restart shell reporting "not ready in time" (direct report:
# "omarchy restart shell had to be manually pressed... I noticed sometimes
# on my update too") must not silently abort the rest of the tail --------
# omarchy-restart-shell (not ours to edit) can legitimately exit non-zero
# on nothing more than its own short readiness poll losing the race against
# install.sh's qmlcache wipe forcing a cold recompile -- by the time it
# returns at all, the old shell is already dead and a new one already
# dispatched, so bookkeeping below it (orphan cleanup, repo-path,
# clear_lifecycle_journal) must still run rather than being skipped by
# `set -e` reacting to that one command. The fake stub fails EVERY restart
# call while this flag is set (both the first attempt and the retry), so a
# passing install here proves the tail tolerates a restart that never
# confirms ready at all, not just a flaky-once case.
home2="$(mktemp -d)"
trap 'rm -rf "$home1" "$home2"' EXIT

if ( HOME="$home2" PATH="$fake_bin:$PATH" FAKE_OMARCHY_FAIL_RESTART=1 "$repo_dir/install.sh" ) \
  >"$home2/install.out" 2>&1; then
  status2=0
else
  status2=$?
fi

check "install.sh still exits 0 when omarchy restart shell never confirms ready" "$status2" "0"
check "repo-path is still written (not skipped by the restart step's own failure)" \
  "$([[ -s "$home2/.local/state/ruixen/repo-path" ]] && echo yes || echo no)" "yes"
check "the lifecycle journal is still cleared (not left stale, forcing --acknowledge-interrupted on the next run)" \
  "$([[ -e "$home2/.local/state/ruixen/lifecycle-journal.json" ]] && echo no || echo yes)" "yes"
check "a warning about the unconfirmed restart is printed, not swallowed silently" \
  "$(grep -Fc 'did not confirm the new shell was ready in time' "$home2/install.out")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
