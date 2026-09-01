#!/usr/bin/env bash
# Covers "[P2] Make full uninstall best-effort and report partial
# cleanup failures" (#19)'s own acceptance criterion ("Add tests around
# the error-aggregation logic without needing to fully emulate Omarchy
# where possible"): sources lib/uninstall-failures.sh directly and
# exercises record_failure/print_failure_summary in isolation -- the
# actual uninstall.sh sequence (bar restore, plugin removal, looknfeel
# restore, restart) is real omarchy-CLI-dependent shell that isn't
# faked anywhere else in this test suite either (see
# tests/uninstall-bar-restore.sh's own comment for the same reasoning),
# so this file is scoped to the one thing that's both new here and
# genuinely testable without that: does the array actually accumulate,
# and does the exit-code contract hold.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"

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

# Each case sources into a fresh subshell so `failures=()` never leaks
# between cases -- record_failure/print_failure_summary are meant to be
# sourced exactly once per real uninstall.sh run, this just re-sources
# per case to get that same "fresh array" starting point cheaply.

# --- Case 1: a clean run (nothing ever failed) --------------------
out1="$(
  set -Eeuo pipefail
  # shellcheck source=lib/uninstall-failures.sh
  source "$repo_dir/lib/uninstall-failures.sh"
  if print_failure_summary; then echo "SUMMARY_EXIT_0"; else echo "SUMMARY_EXIT_1"; fi
)"
check "clean run: print_failure_summary reports success" "$out1" "SUMMARY_EXIT_0"

# --- Case 2: one recorded failure ----------------------------------
out2="$(
  set -Eeuo pipefail
  # shellcheck source=lib/uninstall-failures.sh
  source "$repo_dir/lib/uninstall-failures.sh"
  record_failure "removing plugin ruixen.notch failed" >/dev/null 2>&1
  if print_failure_summary 2>&1; then echo "SUMMARY_EXIT_0"; else echo "SUMMARY_EXIT_1"; fi
)"
check "one failure: print_failure_summary reports failure (exit 1)" \
  "$(grep -c 'SUMMARY_EXIT_1' <<<"$out2")" "1"
check "one failure: summary names exactly the recorded failure" \
  "$(grep -c 'removing plugin ruixen.notch failed' <<<"$out2")" "1"
check "one failure: summary states the count" \
  "$(grep -c '1 unresolved issue' <<<"$out2")" "1"

# --- Case 3: multiple independent failures accumulate, none lost ---
out3="$(
  set -Eeuo pipefail
  # shellcheck source=lib/uninstall-failures.sh
  source "$repo_dir/lib/uninstall-failures.sh"
  record_failure "removing plugin ruixen.notch failed" >/dev/null 2>&1
  record_failure "restoring looknfeel.lua failed" >/dev/null 2>&1
  record_failure "restarting the Omarchy shell failed" >/dev/null 2>&1
  print_failure_summary 2>&1 || true
  printf 'COUNT=%d\n' "${#failures[@]}"
)"
check "three failures: none of the three messages are lost" \
  "$(grep -Ec 'ruixen.notch failed|looknfeel.lua failed|Omarchy shell failed' <<<"$out3")" "3"
check "three failures: the array itself has exactly three entries" \
  "$(grep -o 'COUNT=[0-9]*' <<<"$out3")" "COUNT=3"
check "three failures: summary states the count" \
  "$(grep -c '3 unresolved issue' <<<"$out3")" "1"

# --- Case 4: record_failure also prints a live WARNING as it happens,
# not just at the very end -- so someone watching output during a long
# uninstall sees a failure immediately, not only in the final summary -
out4="$(
  set -Eeuo pipefail
  # shellcheck source=lib/uninstall-failures.sh
  source "$repo_dir/lib/uninstall-failures.sh"
  record_failure "deleting backup foo.bak.123 failed" 2>&1
)"
check "record_failure prints a WARNING immediately, not deferred" \
  "$(grep -c 'WARNING: deleting backup foo.bak.123 failed' <<<"$out4")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
