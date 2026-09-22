#!/usr/bin/env bash
# Covers issue #69: ruixen.cava/CavaFeed.qml used to treat "cava is not
# installed" the same as a transient cava/PipeWire crash -- every exit
# (missing binary or a real crash alike) scheduled another 1.2s retry,
# so a machine with persisted enabled:true and cava later removed (PATH
# change, package uninstall) would retry forever.
#
# The fix: the spawn wrapper exits 42 specifically when `command -v
# cava` fails (not the previous plain exit 0), and onExited only latches
# cavaAvailable=false and stops for THAT exact code -- any other exit
# still gets the existing paced backoff/retry, since that's a real cava
# process that started and then stopped for some other reason.
# cavaAvailable resets to true whenever `enabled` flips on, so toggling
# the feature off and back on (or a full shell restart) is what notices
# a package got installed -- no polling loop.
#
# Static QML checks only, same "no live harness needed for pure wiring"
# reasoning tests/media-status-relay.sh's own header already documents --
# live end-to-end verification (faking a missing binary, watching for
# zero retries over 15+ seconds, then confirming a real `pkill -x cava`
# still respawns normally) was done manually against the actual running
# shell this session, not repeated here since it needs a live quickshell
# process and real cava, not something a CI fixture can synthesize
# cheaply.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
feed_qml="$repo_dir/ruixen.cava/CavaFeed.qml"

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

check "CavaFeed.qml exists" "$([[ -f "$feed_qml" ]] && echo yes || echo no)" "yes"

# --- the missing-dependency sentinel --------------------------------

check "the spawn wrapper exits 42 (not a plain 0) when cava isn't on PATH" \
  "$(grep -c 'command -v cava >/dev/null 2>&1 || exit 42' "$feed_qml")" "1"
check "no leftover plain 'exit 0' missing-cava guard from before the fix" \
  "$(grep -c 'command -v cava >/dev/null 2>&1 || exit 0' "$feed_qml" || true)" "0"

# --- cavaAvailable exists and gates the process -----------------------

check "cavaAvailable property exists" \
  "$(grep -c 'property bool cavaAvailable' "$feed_qml")" "1"
check "cavaProc's own running binding includes cavaAvailable" \
  "$(grep -c 'running: root.enabled && root.cavaAvailable && !cavaProc.backoff' "$feed_qml")" "1"

# --- onExited distinguishes the two cases -----------------------------

check "onExited takes the real exitCode, not a bare no-arg handler" \
  "$(grep -c 'onExited: (exitCode) =>' "$feed_qml")" "1"
check "onExited checks for exit code 42 specifically" \
  "$(grep -c 'if (exitCode === 42)' "$feed_qml")" "1"

# The missing-dependency branch: exactly the 3 lines between the 42
# check and its own closing brace, so a future edit that sneaks a
# restartTimer.restart() into that branch (reintroducing the retry
# loop) fails this line-count check instead of passing silently.
missing_branch="$(awk '/if \(exitCode === 42\)/{flag=1} flag{print; if (/^      \}$/) exit}' "$feed_qml")"
check "the missing-dependency branch is exactly latch + return, nothing else (4 lines)" \
  "$(printf '%s\n' "$missing_branch" | wc -l | tr -d ' ')" "4"
check "the missing-dependency branch does not schedule a retry" \
  "$(printf '%s\n' "$missing_branch" | grep -c 'restartTimer\|backoff' || true)" "0"

check "a real (non-42) exit still schedules the existing paced retry" \
  "$(grep -A2 'if (root.enabled) {' "$feed_qml" | grep -c 'cavaProc.backoff = true')" "1"
check "a real (non-42) exit still restarts the backoff timer" \
  "$(grep -c 'restartTimer.restart()' "$feed_qml")" "1"

# --- recovery path: re-enabling is a fresh, honest check ---------------

check "onEnabledChanged resets cavaAvailable to true when turning on" \
  "$(grep -A10 'onEnabledChanged: {' "$feed_qml" | grep -c 'cavaAvailable = true')" "1"

# --- onBandsChanged's restored binding also respects cavaAvailable -----
# (a real bug caught while building this: the Qt.binding() re-install in
# onBandsChanged had its own separate copy of the running expression,
# and it still needs cavaAvailable in it too, not just the original).

check "onBandsChanged's Qt.binding() restore also includes cavaAvailable" \
  "$(grep -c 'Qt.binding(function() { return root.enabled && root.cavaAvailable && !cavaProc.backoff })' "$feed_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
