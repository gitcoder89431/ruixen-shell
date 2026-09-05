#!/usr/bin/env bash
# Covers a direct request: "the plugs in can rearrange within group or
# create one more group on the left side after the pin apps group" --
# a left-side twin of pluginPinsPill (right side), reachable via
# ruixen.pluginpins' own dropdown (left/right click on a row, see
# tests/pluginpins-model.sh), not drag-and-drop -- dragging turned out
# to have no way to populate an initially-empty group (ModuleList only
# registers a real drop-target slot for entries that already exist).
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

check "leftPluginPinsPill exists, exactly once" \
  "$(grep -c 'id: leftPluginPinsPill$' "$bar_qml" || true)" "1"

check "leftPluginPinsPill sits right after pinnedappsPill (anchors.left)" \
  "$(grep -A2 'id: leftPluginPinsPill$' "$bar_qml" | grep -c 'anchors.left: pinnedappsPill.right' || true)" "1"

check "settingsPill now anchors off leftPluginPinsPill, not pinnedappsPill directly" \
  "$(grep -A8 'id: settingsPill$' "$bar_qml" | grep -c 'anchors.left: leftPluginPinsPill.right' || true)" "1"

check "leftPluginPinsPill has no toggle icon of its own -- ruixen.pluginpins' dropdown stays the one control surface" \
  "$(grep -A20 'id: leftPluginPinsPill$' "$bar_qml" | grep -c 'ModuleSlot' || true)" "0"

check "leftPluginPinsContent excludes every left-side structural id (applauncher/workspaces/pinnedapps/settingsbutton)" \
  "$(grep -A8 'id: leftPluginPinsContent$' "$bar_qml" | grep -c 'ruixen\.applauncher.*ruixen\.workspaces\|entryId(e) !== "ruixen.applauncher"' || true)" "1"

check "leftPluginPinsPill uses the zero-collapse width pattern (same as pinnedappsPill), not a fixed width" \
  "$(grep -A6 'id: leftPluginPinsPill$' "$bar_qml" | grep -c 'width: leftPluginPinsContent\.width > 0 ? leftPluginPinsContent\.width + 8 \* 2 : 0' || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
