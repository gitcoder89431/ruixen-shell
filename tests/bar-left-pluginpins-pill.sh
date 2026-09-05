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
  "$(grep -A18 'id: leftPluginPinsPill$' "$bar_qml" | grep -c 'anchors.left: pinnedappsPill.right' || true)" "1"

check "settingsPill now anchors off leftPluginPinsPill, not pinnedappsPill directly" \
  "$(grep -A8 'id: settingsPill$' "$bar_qml" | grep -c 'anchors.left: leftPluginPinsPill.right' || true)" "1"

check "leftPluginPinsPill has no toggle icon of its own -- ruixen.pluginpins' dropdown stays the one control surface" \
  "$(grep -A62 'id: leftPluginPinsPill$' "$bar_qml" | grep -c 'ModuleSlot' || true)" "0"

check "leftPluginPinsContent excludes every left-side structural id (applauncher/workspaces/pinnedapps/settingsbutton)" \
  "$(grep -A10 'id: leftPluginPinsContent$' "$bar_qml" | grep -c 'ruixen\.applauncher.*ruixen\.workspaces\|entryId(e) !== "ruixen.applauncher"' || true)" "1"

check "leftPluginPinsContent stays vertically centered inside its own scroll viewport" \
  "$(grep -A2 'id: leftPluginPinsContent$' "$bar_qml" | grep -c 'anchors.verticalCenter: parent.verticalCenter' || true)" "1"

check "leftPluginPinsPill's own width is built from cappedContentWidth, still zero-collapses when empty" \
  "$(grep -A20 'id: leftPluginPinsPill$' "$bar_qml" | grep -c 'width: cappedContentWidth > 0 ? cappedContentWidth + 8 \* 2 : 0' || true)" "1"

# --- scroll cap: direct request ("limit 4 to show and then the 5th one
# requires a scroll... scroll it to spin a carousel of plugins") --------
check "leftPluginPinsPill caps visible pins at 4 before scrolling is needed" \
  "$(grep -A10 'id: leftPluginPinsPill$' "$bar_qml" | grep -c 'readonly property int visibleCap: 4' || true)" "1"
check "leftPluginPinsPill's cap is computed from real average icon width, not a hardcoded pixel guess" \
  "$(grep -A15 'id: leftPluginPinsPill$' "$bar_qml" | grep -c 'leftPluginPinsContent\.width / pinCount' || true)" "1"
check "leftPluginPinsViewport (the scrollable Flickable) exists, exactly once" \
  "$(grep -c 'id: leftPluginPinsViewport$' "$bar_qml" || true)" "1"
check "leftPluginPinsViewport is not interactive (drag-to-reorder must not fight with Flickable panning)" \
  "$(grep -A15 'id: leftPluginPinsViewport$' "$bar_qml" | grep -c 'interactive: false' || true)" "1"
check "leftPluginPinsViewport scrolls via WheelHandler, accepting either horizontal or vertical delta" \
  "$(grep -A35 'id: leftPluginPinsViewport$' "$bar_qml" | grep -c 'event\.angleDelta\.x !== 0 ? event\.angleDelta\.x : event\.angleDelta\.y' || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
