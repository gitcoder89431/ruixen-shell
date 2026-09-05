#!/usr/bin/env bash
# Covers a direct follow-up after #36 ("can you make sure we just
# disable people from dragging icons into the workspace group blowing
# it up again"): #36 fixed workspacesPill's own filter to a strict
# single-id match, but the bar's own drag-to-reorder feature could
# still let someone DROP an arbitrary widget there (or onto any other
# exact-match pill -- applauncher, pinnedapps, tray, the curated system
# four, weather/clock) with no warning. Since none of those pills are a
# catch-all, the dropped widget would just stop rendering anywhere on
# the bar at all, silently -- the exact same failure mode #36 fixed for
# a stale shell.json, just reachable live through drag-and-drop too.
#
# Fix: moduleDropAtScene's own candidate search now excludes any slot
# whose moduleName is in protectedModuleIds UNLESS the thing being
# dragged is ALSO protected (so Ruixen's own structural ids can still
# freely reorder among each other, e.g. the System pill's own four
# items) -- only a genuinely foreign/arbitrary id gets steered away.
#
# Can't drive a real Quickshell instance here (no compositor in CI), so
# this is a static invariant check against the actual QML source, same
# style as tests/bar-right-side-groups.sh's own pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
bar_qml="$repo_dir/ruixen.bar/Bar.qml"

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

check "protectedModuleIds exists, exactly once" \
  "$(grep -c 'readonly property var protectedModuleIds:' "$bar_qml" || true)" "1"

check "protectedModuleIds includes ruixen.workspaces (the #36 report's own pill)" \
  "$(grep -A6 'readonly property var protectedModuleIds:' "$bar_qml" | grep -c '"ruixen.workspaces"' || true)" "1"

check "protectedModuleIds folds in curatedRightIds (the System pill's own fixed four)" \
  "$(grep -c 'root.curatedRightIds.concat(root.centerSpecialIds)' "$bar_qml" || true)" "1"

check "moduleDropAtScene computes whether the dragged source is itself protected" \
  "$(grep -c 'var sourceIsProtected = sourceSlot && root.protectedModuleIds.indexOf(sourceSlot.moduleName)' "$bar_qml" || true)" "1"

check "moduleDropAtScene's candidate loop skips protected slots for a non-protected drag source" \
  "$(grep -Fc 'if (!sourceIsProtected && root.protectedModuleIds.indexOf(slot.moduleName) !== -1) continue' "$bar_qml" || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
