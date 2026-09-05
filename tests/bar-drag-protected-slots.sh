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

check "moduleDropAtScene also computes whether the source is one of curatedRightIds specifically" \
  "$(grep -Fc 'var sourceIsCurated = sourceSlot && root.curatedRightIds.indexOf(sourceSlot.moduleName) !== -1' "$bar_qml" || true)" "1"

# Direct correction: curatedRightIds (the "settings and more options
# and power" group) is NOT allowed the same "any protected slot"
# latitude as the rest of protectedModuleIds -- it may only reorder
# among its own four, never pop out via drag onto another protected
# slot (ruixen.settingsbutton's own left-side settingsPill fallback
# included). "no i dont want the settings and more options and power
# etc to have that option, keep that pill rearrange within its group
# only".
check "a curated source's candidate loop only accepts other curatedRightIds slots" \
  "$(grep -Fc 'if (root.curatedRightIds.indexOf(slot.moduleName) === -1) continue' "$bar_qml" || true)" "1"

check "a non-curated, non-protected drag source still skips every protected slot (the plain foreign-widget case)" \
  "$(grep -Fc '} else if (!sourceIsProtected && root.protectedModuleIds.indexOf(slot.moduleName) !== -1) {' "$bar_qml" || true)" "1"

# Direct follow-up: solo pills (workspace, app launcher, pinned apps,
# tray, the pluginpins toggle itself) cannot be dragged AT ALL, in
# either direction -- protectedModuleIds alone only stopped a FOREIGN
# id from landing there; a protected source (ruixen.tray, say) could
# still be dropped onto another solo pill's own slot and vanish the
# same way.
check "immovableModuleIds exists, exactly once" \
  "$(grep -c 'readonly property var immovableModuleIds:' "$bar_qml" || true)" "1"

# ruixen.settingsbutton is deliberately NOT in immovableModuleIds --
# unlike the solo pills, it still needs to reorder freely among the
# other three curatedRightIds items. It is kept from popping out to
# its own left-side settingsPill fallback by the SEPARATE
# sourceIsCurated scoping above instead (direct correction: an earlier
# pass treated that pop-out as a keeper feature; "no i dont want the
# settings and more options and power etc to have that option, keep
# that pill rearrange within its group only").
check "immovableModuleIds does NOT include ruixen.settingsbutton (it still reorders within curatedPill)" \
  "$(grep -A6 'readonly property var immovableModuleIds:' "$bar_qml" | grep -c '"ruixen.settingsbutton"' || true)" "0"

check "canReorder is false for an immovable id, so its drag never even starts" \
  "$(grep -Fc 'root.immovableModuleIds.indexOf(slot.moduleName) === -1' "$bar_qml" || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
