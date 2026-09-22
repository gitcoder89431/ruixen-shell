#!/usr/bin/env bash
# Covers issue #72: ruixen.launcher's first open after >30s idle felt
# noticeably janky compared to an immediate second open, even after
# issues #46/#50's own earlier fixes (defer refresh() one frame, then
# throttle it to 30s).
#
# Live-instrumented profiling (timestamped console.log at every stage,
# a real `omarchy restart shell` + `omarchy-shell shell toggle`, not
# guessed) found two real causes, both in the refresh chain that runs
# once the 30s throttle window has actually expired:
#
# 1. menuFile.onLoaded and userMenuFile.onLoaded each called
#    rebuildEntries() independently. Since defaultSettled/userSettled
#    are usually already true by a second refresh, BOTH calls passed
#    the settled gate and redid the full rebuild -- measured live at
#    ~123ms of blocking, synchronous JS EACH (merging entries, then
#    generating the 150+-condition guard script text), so ~240ms of
#    main-thread work spread across two redundant passes per open.
#
# 2. refresh() was deferred only one frame (Qt.callLater) past
#    root.opened, but the actual expensive work only starts once each
#    FileView's own async reload lands -- real file I/O, not bounded
#    by "one frame." That expensive synchronous work was landing mid-
#    animation regardless, however long after that one frame the file
#    read happened to finish.
#
# The fix: rebuildEntries() now schedules the real work via
# Qt.callLater(doRebuildEntries), which coalesces multiple calls
# arriving before the deferred slot runs into exactly one execution.
# open() now defers the whole refresh() call via a real 160ms Timer
# (140ms animation + margin) instead of one frame, so by the time the
# expensive chain can possibly start, the opening animation has
# already finished rendering.
#
# Verified live: with both fixes, a stale (>30s) reopen showed exactly
# ONE doRebuildEntries/guardProc.exec() pass (not two), starting ~223ms
# after open -- fully clear of the 140ms animation. Focus still lands
# on the search field within ~1-3ms of open either way, and direct
# extension payloads (`{"extension":"settings"}`) still work.
#
# Static QML checks only, same reasoning the cava test files already
# document -- the actual timing improvement needs a live profiling run
# to see (this session's own root-cause investigation did exactly
# that, documented in the fix commit), not something a CI fixture can
# measure cheaply.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
launcher_qml="$repo_dir/ruixen.launcher/Launcher.qml"
provider_qml="$repo_dir/ruixen.launcher/OmarchyActionsProvider.qml"

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

# --- Launcher.qml: refresh deferred past the full animation, not one frame

check "refreshDeferTimer exists" \
  "$(grep -c 'id: refreshDeferTimer' "$launcher_qml")" "1"
check "refreshDeferTimer's interval clears the 140ms opening animation with margin" \
  "$(grep -A2 'id: refreshDeferTimer' "$launcher_qml" | grep -c 'interval: 160')" "1"
check "refreshDeferTimer calls provider refresh() on trigger" \
  "$(grep -A3 'id: refreshDeferTimer' "$launcher_qml" | grep -c 'onTriggered: omarchyActionsProvider.refresh()')" "1"
check "open() restarts the defer timer, not a bare one-frame Qt.callLater for refresh" \
  "$(grep -c 'refreshDeferTimer.restart()' "$launcher_qml")" "1"
check "no leftover direct Qt.callLater(...omarchyActionsProvider.refresh) in open()" \
  "$(grep -c 'Qt.callLater(function() { omarchyActionsProvider.refresh' "$launcher_qml" || true)" "0"
check "focus-input still dispatches via Qt.callLater, unaffected by the refresh defer" \
  "$(grep -c 'Qt.callLater(function() { searchHeader.focusInput() })' "$launcher_qml")" "1"

# --- OmarchyActionsProvider.qml: the two onLoaded-triggered rebuilds coalesce

check "rebuildEntries() schedules via Qt.callLater instead of running inline" \
  "$(grep -A1 'function rebuildEntries() {' "$provider_qml" | grep -c 'Qt.callLater(root.doRebuildEntries)')" "1"
check "doRebuildEntries() exists and owns the actual settled-gate/guard-script body" \
  "$(grep -c 'function doRebuildEntries() {' "$provider_qml")" "1"
check "the settled gate lives in doRebuildEntries(), not the thin rebuildEntries() wrapper" \
  "$(grep -A2 'function doRebuildEntries() {' "$provider_qml" | grep -c 'if (!root.defaultSettled || !root.userSettled) return')" "1"
check "menuFile.onLoaded still calls rebuildEntries() (now the coalescing wrapper)" \
  "$(grep -c 'root.rebuildEntries()' "$provider_qml")" "3"

# --- no leftover debug instrumentation from this investigation ----------

check "no leftover PROFILE-72 debug logging in Launcher.qml" \
  "$(grep -c 'PROFILE-72' "$launcher_qml" || true)" "0"
check "no leftover PROFILE-72 debug logging in OmarchyActionsProvider.qml" \
  "$(grep -c 'PROFILE-72' "$provider_qml" || true)" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
