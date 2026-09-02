#!/usr/bin/env bash
# Covers a direct request to rework the bar's right side:
#
# - ruixen.stayawake ("the coffee cup") stays alone in its own pill,
#   deliberately -- it's the anchor a newly-enabled third-party widget
#   lands to the LEFT of by default. Omarchy's own bar-widget placement
#   (PluginRegistry.qml's defaultBarWidgetSection/barTarget, what
#   `omarchy plugin enable <id>` runs with no explicit --section)
#   inserts a widget with no placement right after the section's own
#   anchor id -- hardcoded to ruixen.tray for "right" -- so as long as
#   stayawake stays the very next shell.json layout entry after tray,
#   a newly-enabled widget's default insertion point lands BETWEEN
#   them. For that to be true on SCREEN too, not just in the config,
#   the catch-all pill for unrecognized ids (thirdPartyPill, was
#   rightPill) had to move from its old position next to clockPill to
#   sit between trayPill and stayawakePill instead.
# - omarchy.system-update, omarchy.agents, ruixen.quickactions,
#   omarchy.power, and ruixen.settingsbutton merged into one curated
#   group ("Update when available, AI, more options, setting"),
#   replacing the old togglesPill/rightPill split.
#
# Can't drive a real Quickshell instance here (no compositor in CI), so
# this is a static invariant check against the actual QML source instead
# -- same style as tests/lint-shell.sh's own pattern-based guards.
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

# --- id-membership lists ---------------------------------------------
stayawake_ids_line="$(grep -m1 'readonly property var stayawakePillIds:' "$bar_qml")"
check "stayawakePillIds is exactly ruixen.stayawake, alone" \
  "$stayawake_ids_line" '  readonly property var stayawakePillIds: ["ruixen.stayawake"]'

curated_ids_line="$(grep -m1 'readonly property var curatedRightIds:' "$bar_qml")"
check "curatedRightIds is update, AI, more-actions, power, settings in that exact order" \
  "$curated_ids_line" '  readonly property var curatedRightIds: ["omarchy.system-update", "omarchy.agents", "ruixen.quickactions", "omarchy.power", "ruixen.settingsbutton"]'

side_right_line="$(grep -m1 'readonly property var sideRightIds:' "$bar_qml")"
check "sideRightIds is built from stayawakePillIds + curatedRightIds + tray, not a separate hand-picked list" \
  "$side_right_line" '  readonly property var sideRightIds: stayawakePillIds.concat(curatedRightIds).concat(["ruixen.tray"])'

# --- pill existence -----------------------------------------------------
for pill_id in curatedPill stayawakePill thirdPartyPill trayPill clockPill; do
  check "pill '$pill_id' exists, exactly once" \
    "$(grep -c "id: $pill_id\$" "$bar_qml" || true)" "1"
done

# The old togglesPill/rightPill names must be fully retired from actual
# code (comments referencing the OLD names for historical context are
# fine and expected, so this only checks id: declarations, not prose).
check "no leftover 'id: togglesPill' declaration" \
  "$(grep -c 'id: togglesPill$' "$bar_qml" || true)" "0"
check "no leftover 'id: rightPill' declaration" \
  "$(grep -c 'id: rightPill$' "$bar_qml" || true)" "0"

# --- anchor chain: tray -> thirdParty -> stayawake -> curated -> clock --
#
# This exact order is what makes "third-party lands left of the coffee"
# true on screen and not just in shell.json's own array order -- see
# thirdPartyPill's own comment for why its position (not just its id
# filter) had to move.
check "curatedPill anchors off clockPill (rightmost of this cluster)" \
  "$(grep -A2 'id: curatedPill$' "$bar_qml" | grep -c 'anchors.right: clockPill.left' || true)" "1"
check "stayawakePill anchors off curatedPill (sits just left of the curated group)" \
  "$(grep -A2 'id: stayawakePill$' "$bar_qml" | grep -c 'anchors.right: curatedPill.left' || true)" "1"
check "thirdPartyPill anchors off stayawakePill (sits just left of the coffee)" \
  "$(grep -A2 'id: thirdPartyPill$' "$bar_qml" | grep -c 'anchors.right: stayawakePill.left' || true)" "1"
check "trayPill anchors off thirdPartyPill (leftmost of this cluster)" \
  "$(grep -A2 'id: trayPill$' "$bar_qml" | grep -c 'anchors.right: thirdPartyPill.left' || true)" "1"

# --- each pill's own ModuleList filters on the right id list -----------
check "curatedContent filters on curatedRightIds" \
  "$(grep -A3 'id: curatedContent$' "$bar_qml" | grep -c 'root\.curatedRightIds\.indexOf' || true)" "1"
check "stayawakeContent filters on stayawakePillIds" \
  "$(grep -A3 'id: stayawakeContent$' "$bar_qml" | grep -c 'root\.stayawakePillIds\.indexOf' || true)" "1"
check "thirdPartyContent is the catch-all (excludes sideRightIds), same as the old rightContent was" \
  "$(grep -A3 'id: thirdPartyContent$' "$bar_qml" | grep -c 'root\.sideRightIds\.indexOf.*=== -1' || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
