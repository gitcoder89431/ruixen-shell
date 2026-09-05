#!/usr/bin/env bash
# Covers a direct request to rework the bar's right side, done in five
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
#   stayawake pill instead (stayawakeGroupIds) -- stayawake stays first
#   in that list since it's still the actual anchor id tray is adjacent
#   to.
#
# Pass 3: ruixen.pluginpins (the pin/unpin dropdown for every other
#   installed bar-widget) joined the curated group after quickactions,
#   before settingsbutton.
#
# Pass 4: stayawakeGroupPill (stayawake + agents) merged into curatedPill
#   per direct follow-up ("can we collapse this with the plugin pin one
#   cause there the same, i dont think anything shows up on this group
#   other than that").
#
# Pass 5 (direct follow-up, after Pass 4 read as "blowing up the icon
#   groups, this doesnt make any sense"): redrawn into four groups, left
#   to right -- "starting from the first left icon group, the
#   onepassword and open app pill group, next pill group is the
#   PLUGSINSPIN and the popup plugin widget pin icon. then the next
#   group is more actions and setting. then the last pill group is
#   weather and time":
#     1. trayPill -- tray merged with the generic catch-all (whatever
#        else is pinned with no dedicated pill: stayawake, agents,
#        system-update, power, or any third-party widget pinned via
#        ruixen.pluginpins). thirdPartyPill (the old catch-all) no
#        longer exists as a separate pill -- folded into trayPill.
#     2. pluginPinsPill -- ruixen.pluginpins alone, its own group (not
#        folded into curatedPill).
#     3. curatedPill -- quickactions + settingsbutton only now.
#     4. clockPill -- weather + clock, unchanged.
#   curatedRightIds narrowed to just the "more actions and setting"
#   pair; sideRightIds (every id with its own dedicated pill, used to
#   exclude from trayPill's catch-all) is curatedRightIds + pluginpins,
#   deliberately NOT including ruixen.tray anymore, so tray falls into
#   the same catch-all filter as everything else instead of needing its
#   own separate exact-id match.
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
curated_ids_line="$(grep -m1 'readonly property var curatedRightIds:' "$bar_qml")"
check "curatedRightIds is just quickactions + settingsbutton (more actions and setting)" \
  "$curated_ids_line" '  readonly property var curatedRightIds: ["ruixen.quickactions", "ruixen.settingsbutton"]'

side_right_line="$(grep -m1 'readonly property var sideRightIds:' "$bar_qml")"
check "sideRightIds is curatedRightIds + pluginpins, deliberately not tray" \
  "$side_right_line" '  readonly property var sideRightIds: curatedRightIds.concat(["ruixen.pluginpins"])'

# --- pill existence -----------------------------------------------------
for pill_id in curatedPill pluginPinsPill trayPill clockPill; do
  check "pill '$pill_id' exists, exactly once" \
    "$(grep -c "id: $pill_id\$" "$bar_qml" || true)" "1"
done

# The old togglesPill/rightPill/stayawakePill/stayawakeGroupPill/
# thirdPartyPill names must be fully retired from actual code (comments
# referencing the OLD names for historical context are fine and
# expected, so this only checks id: declarations, not prose).
for old_id in togglesPill rightPill stayawakePill stayawakeGroupPill thirdPartyPill; do
  check "no leftover 'id: $old_id' declaration" \
    "$(grep -c "id: $old_id\$" "$bar_qml" || true)" "0"
done

# --- anchor chain: tray -> pluginPins -> curated -> clock
#
# This exact order is what makes "third-party lands left of the coffee"
# true on screen and not just in shell.json's own array order.
check "curatedPill anchors off clockPill (rightmost of this cluster)" \
  "$(grep -A2 'id: curatedPill$' "$bar_qml" | grep -c 'anchors.right: clockPill.left' || true)" "1"
check "pluginPinsPill anchors off curatedPill (sits just left of more actions/setting)" \
  "$(grep -A2 'id: pluginPinsPill$' "$bar_qml" | grep -c 'anchors.right: curatedPill.left' || true)" "1"
check "trayPill anchors off pluginPinsPill (leftmost of this cluster)" \
  "$(grep -A2 'id: trayPill$' "$bar_qml" | grep -c 'anchors.right: pluginPinsPill.left' || true)" "1"

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
# oversight. trayPill stays the leftmost pill of this cluster through
# every reorg above, so rightDockedBg/rightShoulderWing's own x formulas
# (anchored to trayPill.x) are unaffected by any of them.
check "rightShoulderWing overlaps rightDockedBg by 1px, not flush against it" \
  "$(grep -m1 'x: rightDockedBg.x - size' "$bar_qml")" '          x: rightDockedBg.x - size + 1'

# --- each pill's own ModuleList filters on the right id list -----------
check "curatedContent filters on curatedRightIds" \
  "$(grep -A3 'id: curatedContent$' "$bar_qml" | grep -c 'root\.curatedRightIds\.indexOf' || true)" "1"
check "pluginPinsContent filters on the exact ruixen.pluginpins id" \
  "$(grep -A3 'id: pluginPinsContent$' "$bar_qml" | grep -c 'root\.entryId(e) === "ruixen.pluginpins"' || true)" "1"
check "trayContent is the catch-all (excludes sideRightIds), same as the old thirdPartyContent was" \
  "$(grep -A5 'id: trayContent$' "$bar_qml" | grep -c 'root\.sideRightIds\.indexOf.*=== -1' || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
