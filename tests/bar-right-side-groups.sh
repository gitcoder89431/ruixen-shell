#!/usr/bin/env bash
# Covers a direct request to rework the bar's right side, done in two
# passes:
#
# Pass 1: ruixen.stayawake ("the coffee cup") stays alone in its own
#   pill -- it's the anchor a newly-enabled third-party widget lands to
#   the LEFT of by default. Omarchy's own bar-widget placement
#   (PluginRegistry.qml's defaultBarWidgetSection/barTarget, what
#   `omarchy plugin enable <id>` runs with no explicit --section)
#   inserts a widget with no placement right after the section's own
#   anchor id -- hardcoded to ruixen.tray for "right" -- so as long as
#   stayawake stays the very next shell.json layout entry after tray, a
#   newly-enabled widget's default insertion point lands BETWEEN them.
#   For that to be true on SCREEN too, not just in the config, the
#   catch-all pill for unrecognized ids (thirdPartyPill, was rightPill)
#   had to move from its old position next to clockPill to sit between
#   trayPill and the coffee's own pill instead.
#   omarchy.system-update, omarchy.agents, ruixen.quickactions,
#   omarchy.power, and ruixen.settingsbutton merged into one curated
#   group ("Update when available, AI, more options, setting"),
#   replacing the old togglesPill/rightPill split.
#
# Pass 2 (direct follow-up: "move the AI so it goes where the coffee
#   group is too, so we have power more actions and settings"):
#   omarchy.agents moved out of the curated group and into the
#   stayawake pill instead (stayawakeGroupIds, renamed from
#   stayawakePillIds since it's no longer just stayawake alone) --
#   stayawake stays first in that list since it's still the actual
#   anchor id tray is adjacent to. system-update stays in the curated
#   group per direct confirmation ("stays in the right group") even
#   though it wasn't in the follow-up's own restated order; the
#   remaining curatedRightIds order is system-update, power,
#   quickactions, settingsbutton.
#
# Pass 3: ruixen.pluginpins (the pin/unpin dropdown for every other
#   installed bar-widget) joined the curated group after quickactions,
#   before settingsbutton -- a core ruixen utility, not a random
#   third-party thing, so it doesn't belong in thirdPartyPill's own
#   generic catch-all.
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
stayawake_ids_line="$(grep -m1 'readonly property var stayawakeGroupIds:' "$bar_qml")"
check "stayawakeGroupIds is stayawake then AI, in that order (stayawake stays the real anchor)" \
  "$stayawake_ids_line" '  readonly property var stayawakeGroupIds: ["ruixen.stayawake", "omarchy.agents"]'

curated_ids_line="$(grep -m1 'readonly property var curatedRightIds:' "$bar_qml")"
check "curatedRightIds is update, power, more-actions, plugin-pins, settings in that exact order" \
  "$curated_ids_line" '  readonly property var curatedRightIds: ["omarchy.system-update", "omarchy.power", "ruixen.quickactions", "ruixen.pluginpins", "ruixen.settingsbutton"]'

side_right_line="$(grep -m1 'readonly property var sideRightIds:' "$bar_qml")"
check "sideRightIds is built from stayawakeGroupIds + curatedRightIds + tray, not a separate hand-picked list" \
  "$side_right_line" '  readonly property var sideRightIds: stayawakeGroupIds.concat(curatedRightIds).concat(["ruixen.tray"])'

# --- pill existence -----------------------------------------------------
for pill_id in curatedPill stayawakeGroupPill thirdPartyPill trayPill clockPill; do
  check "pill '$pill_id' exists, exactly once" \
    "$(grep -c "id: $pill_id\$" "$bar_qml" || true)" "1"
done

# The old togglesPill/rightPill/stayawakePill names must be fully
# retired from actual code (comments referencing the OLD names for
# historical context are fine and expected, so this only checks id:
# declarations, not prose).
for old_id in togglesPill rightPill stayawakePill; do
  check "no leftover 'id: $old_id' declaration" \
    "$(grep -c "id: $old_id\$" "$bar_qml" || true)" "0"
done

# --- anchor chain: tray -> thirdParty -> stayawakeGroup -> curated -> clock
#
# This exact order is what makes "third-party lands left of the coffee"
# true on screen and not just in shell.json's own array order -- see
# thirdPartyPill's own comment for why its position (not just its id
# filter) had to move.
check "curatedPill anchors off clockPill (rightmost of this cluster)" \
  "$(grep -A2 'id: curatedPill$' "$bar_qml" | grep -c 'anchors.right: clockPill.left' || true)" "1"
check "stayawakeGroupPill anchors off curatedPill (sits just left of the curated group)" \
  "$(grep -A2 'id: stayawakeGroupPill$' "$bar_qml" | grep -c 'anchors.right: curatedPill.left' || true)" "1"
check "thirdPartyPill anchors off stayawakeGroupPill (sits just left of the coffee)" \
  "$(grep -A2 'id: thirdPartyPill$' "$bar_qml" | grep -c 'anchors.right: stayawakeGroupPill.left' || true)" "1"

# Direct live report: with a flat width/margin reserved even while
# empty (opacity 0), thirdPartyPill still pushed tray's own icons a
# real ~28px from the coffee/AI group whenever there was no actual
# third-party widget to show -- the common case on most systems, not
# an edge case, unlike trayPill's own "no apps in the tray" empty
# state. Both the padding and the margin have to actually collapse to
# zero, not just fade opacity, or the same gap resurfaces.
third_party_width_line="$(grep -m1 'width: thirdPartyContent.width' "$bar_qml")"
check "thirdPartyPill's own width collapses to 0 when empty, not a flat 8*2 padding" \
  "$third_party_width_line" '          width: thirdPartyContent.width > 0 ? thirdPartyContent.width + 8 * 2 : 0'
third_party_margin_line="$(grep -m1 'anchors.rightMargin: thirdPartyContent.width' "$bar_qml")"
check "thirdPartyPill's own rightMargin collapses to 0 when empty, not a flat 6px" \
  "$third_party_margin_line" '          anchors.rightMargin: thirdPartyContent.width > 0 ? 6 : 0'
check "trayPill anchors off thirdPartyPill (leftmost of this cluster)" \
  "$(grep -A2 'id: trayPill$' "$bar_qml" | grep -c 'anchors.right: thirdPartyPill.left' || true)" "1"

# --- docked-mode rendering: rightShoulderWing/rightDockedBg seam -------
#
# Direct live report: a thin vertical seam visible in docked mode right
# where the curved shoulder wing meets the flat merged pill background
# -- two independently-antialiased shapes meeting at the exact same X
# coordinate can each erode their own edge by a sub-pixel amount,
# letting the wallpaper show through as a hairline. Only rightShoulderWing
# was confirmed broken and fixed (a 1px deliberate overlap into
# rightDockedBg's own territory) -- leftShoulderWing was checked live and
# looked clean, so it's deliberately left untouched here, not an
# oversight.
check "rightShoulderWing overlaps rightDockedBg by 1px, not flush against it" \
  "$(grep -m1 'x: rightDockedBg.x - size' "$bar_qml")" '          x: rightDockedBg.x - size + 1'

# --- each pill's own ModuleList filters on the right id list -----------
check "curatedContent filters on curatedRightIds" \
  "$(grep -A3 'id: curatedContent$' "$bar_qml" | grep -c 'root\.curatedRightIds\.indexOf' || true)" "1"
check "stayawakeGroupContent filters on stayawakeGroupIds" \
  "$(grep -A3 'id: stayawakeGroupContent$' "$bar_qml" | grep -c 'root\.stayawakeGroupIds\.indexOf' || true)" "1"
check "thirdPartyContent is the catch-all (excludes sideRightIds), same as the old rightContent was" \
  "$(grep -A3 'id: thirdPartyContent$' "$bar_qml" | grep -c 'root\.sideRightIds\.indexOf.*=== -1' || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
