#!/usr/bin/env bash
# Sourced (not executed) by uninstall.sh -- the error-aggregation
# primitives for "[P2] Make full uninstall best-effort and report
# partial cleanup failures" (#19), factored out on their own so they
# can be tested (tests/uninstall-failure-aggregation.sh) without
# needing to fake the omarchy CLI at all: the thing actually worth unit
# testing here is "does the array grow and the exit code flip
# correctly," not any particular uninstall step.
#
# Usage in uninstall.sh: source this file once near the top, then wrap
# every INDEPENDENTLY RECOVERABLE step in an `if`/`||` that calls
# record_failure on failure instead of letting it bubble up and abort
# the whole script -- genuinely fatal preconditions (missing omarchy/jq)
# still use uninstall.sh's own separate fail()/exit 1, unrelated to this.
failures=()

record_failure() {
  failures+=("$1")
  printf 'ruixen-shell uninstall: WARNING: %s\n' "$1" >&2
}

# Prints the final summary if anything failed and returns 1 (so the
# caller can `print_failure_summary || exit 1`); prints nothing and
# returns 0 if the run was fully clean. Never exits itself -- kept a
# plain function so a test can call it and inspect the return code
# without spawning a subshell.
print_failure_summary() {
  [[ "${#failures[@]}" -eq 0 ]] && return 0
  printf '\nRuixen Shell uninstall finished with %d unresolved issue(s):\n' "${#failures[@]}" >&2
  local f
  for f in "${failures[@]}"; do
    printf '  - %s\n' "$f" >&2
  done
  printf '\nEverything else above completed. Re-run uninstall.sh to retry the failed step(s), or resolve the rest by hand.\n' >&2
  return 1
}
