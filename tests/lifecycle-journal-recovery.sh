#!/usr/bin/env bash
# Issue #32 (scoped down -- detect + explicit acknowledgment, not
# automatic recovery; see lib/lifecycle-journal.sh's own header comment
# for the full reasoning). Two layers:
#
#   1. Library-level checks against lib/lifecycle-journal.sh's own
#      functions directly, in isolation -- fast, precise, no need to
#      spin up a real install.sh for every case.
#   2. End-to-end checks against the REAL install.sh, same fixture
#      pattern tests/install-rollback.sh already uses (throwaway fake
#      $HOME, fixtures/fake-bin stubs) -- proving the actual wiring
#      works, not just the library it calls.
#
# A real kill -9 mid-run is not simulated here (timing a real SIGKILL
# at an exact phase boundary isn't reliably reproducible in a test, and
# isn't actually necessary): a crash's only observable effect on disk
# is "the journal file it last wrote is still there, unord." Planting
# that exact file by hand and asserting install.sh reacts correctly to
# finding it IS the faithful test -- it doesn't matter to install.sh's
# own detection logic whether the file was left by a real interruption
# or by this test writing it directly, since both look identical on
# disk.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'lifecycle-journal-recovery: jq is required (command "jq" not found)\n' >&2
  exit 1
}
# uninstall.sh's own end-to-end coverage below sources the REAL
# omarchy-shell-config (same reasoning as tests/uninstall-preserve-
# thirdparty.sh's own comment) -- skip that half gracefully on a
# machine that doesn't have it, same as that test does.
have_omarchy_shell_config=1
command -v omarchy-shell-config >/dev/null 2>&1 || have_omarchy_shell_config=0

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

homes=()
cleanup() { rm -rf "${homes[@]}"; }
trap cleanup EXIT

# --- Layer 1: library functions in isolation ---------------------------

lib_home="$(mktemp -d)"
homes+=("$lib_home")
lib_state_dir="$lib_home/.local/state/ruixen"
mkdir -p "$lib_state_dir"
journal="$lib_state_dir/lifecycle-journal.json"

# shellcheck source=lib/lifecycle-journal.sh
source "$repo_dir/lib/lifecycle-journal.sh"

# No journal yet -- nothing to report, proceeds.
if check_lifecycle_journal_or_refuse "$lib_state_dir" >/dev/null 2>&1; then
  check "no journal: check_lifecycle_journal_or_refuse returns 0" "0" "0"
else
  check "no journal: check_lifecycle_journal_or_refuse returns 0" "1" "0"
fi

write_lifecycle_journal "$lib_state_dir" install
check "write_lifecycle_journal: journal file exists" "$([[ -e "$journal" ]] && echo yes || echo no)" "yes"
check "write_lifecycle_journal: operation field is install" "$(jq -r '.operation' "$journal")" "install"
check "write_lifecycle_journal: phase field starts as 'started'" "$(jq -r '.phase' "$journal")" "started"
check "write_lifecycle_journal: pid field is this test's own PID" "$(jq -r '.pid' "$journal")" "$$"

update_lifecycle_journal_phase "$lib_state_dir" "4/7 applying shell layout"
check "update_lifecycle_journal_phase: phase field updated" "$(jq -r '.phase' "$journal")" "4/7 applying shell layout"
check "update_lifecycle_journal_phase: operation field untouched" "$(jq -r '.operation' "$journal")" "install"

# A real interruption left this behind -- refuse without the flag.
refuse_output="$(check_lifecycle_journal_or_refuse "$lib_state_dir" 2>&1 1>/dev/null || true)"
if check_lifecycle_journal_or_refuse "$lib_state_dir" >/dev/null 2>&1; then
  refuse_status=0
else
  refuse_status=$?
fi
check "stale journal, no flag: check_lifecycle_journal_or_refuse returns 1" "$refuse_status" "1"
check "stale journal, no flag: message names the interrupted operation" \
  "$(grep -c 'previous install run appears to have been interrupted' <<< "$refuse_output")" "1"
check "stale journal, no flag: message names the reached phase" \
  "$(grep -c '4/7 applying shell layout' <<< "$refuse_output")" "1"
check "stale journal, no flag: journal is left in place (not silently cleared)" "$([[ -e "$journal" ]] && echo yes || echo no)" "yes"

# --acknowledge-interrupted clears it and proceeds.
if check_lifecycle_journal_or_refuse "$lib_state_dir" --acknowledge-interrupted >/dev/null 2>&1; then
  check "stale journal, with flag: check_lifecycle_journal_or_refuse returns 0" "0" "0"
else
  check "stale journal, with flag: check_lifecycle_journal_or_refuse returns 0" "1" "0"
fi
check "stale journal, with flag: journal is cleared" "$([[ -e "$journal" ]] && echo yes || echo no)" "no"

clear_lifecycle_journal "$lib_state_dir"
check "clear_lifecycle_journal: safe to call with no journal present" "$([[ -e "$journal" ]] && echo yes || echo no)" "no"

# A corrupted journal refuses rather than guessing.
printf 'not valid json at all' > "$journal"
if check_lifecycle_journal_or_refuse "$lib_state_dir" >/dev/null 2>&1; then
  corrupt_status=0
else
  corrupt_status=$?
fi
check "corrupted journal: check_lifecycle_journal_or_refuse returns 1" "$corrupt_status" "1"
corrupt_output="$(check_lifecycle_journal_or_refuse "$lib_state_dir" 2>&1 1>/dev/null || true)"
check "corrupted journal: message says it isn't a readable journal" \
  "$(grep -c 'not a readable journal' <<< "$corrupt_output")" "1"
rm -f "$journal"

# --- Layer 2: real install.sh end-to-end --------------------------------

# A previous run's own journal, exactly as write_lifecycle_journal +
# update_lifecycle_journal_phase would have left it behind, planted in
# a throwaway fake $HOME with no other Ruixen state -- this is what a
# fresh machine's very first install.sh run looks like if THAT run got
# interrupted before ever finishing.
e2e_home="$(mktemp -d)"
homes+=("$e2e_home")
e2e_state_dir="$e2e_home/.local/state/ruixen"
mkdir -p "$e2e_state_dir"
jq -n '{schema_version: 1, operation: "install", pid: 999999, started_at: "2020-01-01T00:00:00Z", phase: "5/7 matching Hyprland window look to the frame/bar"}' \
  > "$e2e_state_dir/lifecycle-journal.json"

if ( HOME="$e2e_home" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) >"$e2e_home/install.out" 2>&1; then
  e2e_refuse_status=0
else
  e2e_refuse_status=$?
fi
check "e2e stale journal, no flag: install.sh exits non-zero" "$e2e_refuse_status" "1"
check "e2e stale journal, no flag: install.sh's own message reached the terminal" \
  "$(grep -c 'previous install run appears to have been interrupted' "$e2e_home/install.out")" "1"
check "e2e stale journal, no flag: no plugin was deployed" \
  "$([[ -d "$e2e_home/.config/omarchy/plugins/ruixen.bar" ]] && echo yes || echo no)" "no"
check "e2e stale journal, no flag: shell.json was never written" \
  "$([[ -e "$e2e_home/.config/omarchy/shell.json" ]] && echo yes || echo no)" "no"

# Same fake $HOME, now with --acknowledge-interrupted: proceeds and
# actually completes a real install.
if ( HOME="$e2e_home" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" --acknowledge-interrupted ) >"$e2e_home/install2.out" 2>&1; then
  e2e_ack_status=0
else
  e2e_ack_status=$?
fi
check "e2e stale journal, with flag: install.sh exits 0" "$e2e_ack_status" "0"
check "e2e stale journal, with flag: a real plugin was actually deployed" \
  "$([[ -d "$e2e_home/.config/omarchy/plugins/ruixen.bar" ]] && echo yes || echo no)" "yes"
check "e2e stale journal, with flag: journal is gone after a successful run" \
  "$([[ -e "$e2e_state_dir/lifecycle-journal.json" ]] && echo yes || echo no)" "no"

# A normal, uninterrupted successful run never leaves a journal behind
# at all -- fresh $HOME, no pre-planted anything.
clean_home="$(mktemp -d)"
homes+=("$clean_home")
( HOME="$clean_home" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) >"$clean_home/install.out" 2>&1
check "clean successful install: no journal left behind" \
  "$([[ -e "$clean_home/.local/state/ruixen/lifecycle-journal.json" ]] && echo yes || echo no)" "no"

# A run that fails and rolls back the ordinary way (ERR trap catches
# it, ERR trap is what a real kill -9 skips) also leaves no journal --
# only a genuine interruption should.
rollback_home="$(mktemp -d)"
homes+=("$rollback_home")
( HOME="$rollback_home" PATH="$fake_bin:$PATH" FAKE_OMARCHY_FAIL_RESTART=1 "$repo_dir/install.sh" ) >"$rollback_home/install.out" 2>&1 || true
check "ordinary rollback (not a crash): no journal left behind" \
  "$([[ -e "$rollback_home/.local/state/ruixen/lifecycle-journal.json" ]] && echo yes || echo no)" "no"

# --- Layer 2b: real uninstall.sh end-to-end -----------------------------

if [[ "$have_omarchy_shell_config" -eq 1 ]]; then
  u_home="$(mktemp -d)"
  homes+=("$u_home")
  # A real working install first -- uninstall.sh has real Ruixen state
  # to act on, same as tests/uninstall-preserve-thirdparty.sh's own setup.
  ( HOME="$u_home" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) >"$u_home/install.out" 2>&1

  u_state_dir="$u_home/.local/state/ruixen"
  jq -n '{schema_version: 1, operation: "uninstall", pid: 999999, started_at: "2020-01-01T00:00:00Z", phase: "2/4 removing Ruixen Shell plugins"}' \
    > "$u_state_dir/lifecycle-journal.json"

  if ( HOME="$u_home" PATH="$fake_bin:$PATH" "$repo_dir/uninstall.sh" ) >"$u_home/uninstall.out" 2>&1; then
    u_refuse_status=0
  else
    u_refuse_status=$?
  fi
  check "uninstall e2e stale journal, no flag: uninstall.sh exits non-zero" "$u_refuse_status" "1"
  check "uninstall e2e stale journal, no flag: message reached the terminal" \
    "$(grep -c 'previous uninstall run appears to have been interrupted' "$u_home/uninstall.out")" "1"
  check "uninstall e2e stale journal, no flag: plugin was NOT removed" \
    "$([[ -d "$u_home/.config/omarchy/plugins/ruixen.bar" ]] && echo yes || echo no)" "yes"

  if ( HOME="$u_home" PATH="$fake_bin:$PATH" "$repo_dir/uninstall.sh" --acknowledge-interrupted ) >"$u_home/uninstall2.out" 2>&1; then
    u_ack_status=0
  else
    u_ack_status=$?
  fi
  check "uninstall e2e stale journal, with flag: uninstall.sh exits 0" "$u_ack_status" "0"
  check "uninstall e2e stale journal, with flag: plugin was actually removed" \
    "$([[ -d "$u_home/.config/omarchy/plugins/ruixen.bar" ]] && echo yes || echo no)" "no"
  check "uninstall e2e stale journal, with flag: journal is gone after a successful run" \
    "$([[ -e "$u_state_dir/lifecycle-journal.json" ]] && echo yes || echo no)" "no"

  # A normal, uninterrupted uninstall never leaves a journal behind.
  clean_u_home="$(mktemp -d)"
  homes+=("$clean_u_home")
  ( HOME="$clean_u_home" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) >"$clean_u_home/install.out" 2>&1
  ( HOME="$clean_u_home" PATH="$fake_bin:$PATH" "$repo_dir/uninstall.sh" ) >"$clean_u_home/uninstall.out" 2>&1
  check "clean successful uninstall: no journal left behind" \
    "$([[ -e "$clean_u_home/.local/state/ruixen/lifecycle-journal.json" ]] && echo yes || echo no)" "no"
else
  printf 'SKIP - uninstall.sh end-to-end checks (omarchy-shell-config not on PATH, not a real Omarchy machine)\n'
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
