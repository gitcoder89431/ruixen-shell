#!/usr/bin/env bash
# Covers a direct request to rework the bar's right side. Went through
# many corrections before landing on the final shape -- condensed
# history, oldest first:
#
# 1. ruixen.stayawake ("the coffee cup") anchors a small group of its
#    own -- it's the boundary a newly-enabled third-party widget lands
#    to the LEFT of by default (Omarchy's own bar-widget placement,
#    PluginRegistry.qml's defaultBarWidgetSection/barTarget, hardcodes
#    ruixen.tray as the "right" section's anchor; a widget with no
#    placement inserts right after it in shell.json's own array).
#    omarchy.system-update/power/omarchy.agents/ruixen.quickactions/
#    ruixen.settingsbutton merged into one curated group; the catch-all
#    for unrecognized ids moved from next to clockPill to between
#    trayPill and stayawake's own pill, so the anchor role held true on
#    SCREEN, not just in the config.
# 2. ruixen.pluginpins (new: the pin/unpin dropdown for every other
#    installed bar-widget) joined the curated group.
# 3. stayawake's own separate pill merged into the curated group
#    ("can we collapse this with the plugin pin one... i dont think
#    anything shows up on this group other than that") -- read back as
#    "blowing up the icon groups, this doesnt make any sense".
# 4. Redrawn into four *named* groups per an explicit spec ("starting
#    from the first left icon group, the onepassword and open app pill
#    group, next pill group is the PLUGSINSPIN..., then more actions
#    and setting, then weather and time") -- but system-update/power
#    and then stayawake/agents each went through a wrong-group
#    correction before landing on the final answer below.
# 5. Final correction ("the plugs in toggle inside the pill it
#    toggles... microphone network cofee ai [are] toggleable from the
#    plugins pin so they stay pinnable or not in the plugin group" /
#    "system is POWER UPDATE MORE ACTIONS AND SETTING"): the toggle
#    icon lives together with whatever it toggles, and the "system"
#    group is an exact, fixed four that's never a catch-all.
#
# Final shape, left to right:
#   1. trayPill -- ruixen.tray ONLY. Literal open apps (1Password,
#      etc.), nothing else.
#   2. pluginPinsPill -- ruixen.pluginpins itself PLUS everything pinned
#      through it (stayawake, agents, microphone, network, any
#      third-party widget). This is the catch-all now: every id in
#      "right" that's neither tray nor the fixed system four.
#   3. curatedPill ("SYSTEM") -- an exact, fixed four: system-update,
#      power, quickactions, settingsbutton. Never grows to catch
#      anything else.
#   4. clockPill -- weather + clock, unchanged throughout every pass
#      above.
#
# curatedRightIds is that exact fixed four. There's no third named
# list (no more "sideRightIds") -- pill 2's own filter is just "not
# tray, not curatedRightIds", so a newly-pinned third-party widget
# lands there automatically with no id list to maintain.
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
check "curatedRightIds is the exact, fixed SYSTEM four: system-update, power, quickactions, settingsbutton" \
  "$curated_ids_line" '  readonly property var curatedRightIds: ["omarchy.system-update", "omarchy.power", "ruixen.quickactions", "ruixen.settingsbutton"]'

check "there is no separate sideRightIds list anymore (pill 2's own filter is inline: not tray, not curatedRightIds)" \
  "$(grep -c 'sideRightIds' "$bar_qml" || true)" "0"

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
check "pluginPinsPill anchors off curatedPill (sits just left of SYSTEM)" \
  "$(grep -A15 'id: pluginPinsPill$' "$bar_qml" | grep -c 'anchors.right: curatedPill.left' || true)" "1"
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
check "curatedContent filters on the exact curatedRightIds membership" \
  "$(grep -A3 'id: curatedContent$' "$bar_qml" | grep -c 'root\.curatedRightIds\.indexOf' || true)" "1"
check "trayContent is tray ONLY (exact id match, not a catch-all)" \
  "$(grep -A5 'id: trayContent$' "$bar_qml" | grep -c 'root\.entryId(e) === "ruixen.tray"' || true)" "1"
check "pluginPinsContent is the catch-all now: not tray, not in curatedRightIds" \
  "$(grep -A5 'id: pluginPinsContent$' "$bar_qml" | grep -c 'curatedRightIds\.indexOf(id) === -1' || true)" "1"
check "pluginPinsContent also excludes ruixen.pluginpins itself (rendered separately, see pluginPinsToggle)" \
  "$(grep -A5 'id: pluginPinsContent$' "$bar_qml" | grep -c 'id !== "ruixen.pluginpins"' || true)" "1"

# --- pluginpins toggle icon: fixed at this pill's own right edge -------
#
# Direct request: "can you make it right of the pill group, so its like
# thing that stays fix at the first right position of the pill group".
# A ModuleList's own render order otherwise just follows shell.json's
# array order, which drifts every time something is pinned/unpinned
# through ruixen.pluginpins itself -- pulling the toggle out into its
# own ModuleSlot, anchored directly to this pill's own right edge, is
# what makes its position a real structural guarantee instead of a
# data-order coincidence.
check "pluginPinsToggle (the toggle icon's own slot) exists, exactly once" \
  "$(grep -c 'id: pluginPinsToggle$' "$bar_qml" || true)" "1"
check "pluginPinsToggle anchors to this pill's own right edge" \
  "$(grep -A2 'id: pluginPinsToggle$' "$bar_qml" | grep -c 'anchors.right: parent.right' || true)" "1"
check "pluginPinsToggle reserves its own 8px right margin (not flush against the pill's own edge)" \
  "$(grep -A12 'id: pluginPinsToggle$' "$bar_qml" | grep -c 'anchors.rightMargin: 8' || true)" "1"

# Direct live report after the toggle was first pulled into its own
# slot: "it doesnt shrink or expand anymore" and "the pill is lop
# sided now" -- both traced to the exact same stale-.implicitWidth bug
# curatedContent/trayContent already learned from (a ModuleList's own
# .implicitWidth, inherited from Loader, doesn't reliably update for a
# late-filled entries value; .width does -- see stayawakeGroupPill's
# own old comment, git history, for the original instance of this).
# The pill's own width formula now reads cappedContentWidth (see the
# scroll-cap checks below), which is itself built from
# pluginPinsContent.width, so the same fix still applies one level in.
check "pluginPinsPill's own width reads cappedContentWidth (built from .width, never .implicitWidth)" \
  "$(grep -c 'width: cappedContentWidth + pluginPinsToggle\.implicitWidth' "$bar_qml" || true)" "1"

# --- scroll cap: direct request ("limit 4 to show and then the 5th one
# requires a scroll... scroll it to spin a carousel of plugins") --------
check "pluginPinsPill caps visible pins at 4 before scrolling is needed" \
  "$(grep -A10 'id: pluginPinsPill$' "$bar_qml" | grep -c 'readonly property int visibleCap: 4' || true)" "1"
check "pluginPinsPill's cap is computed from real average icon width, not a hardcoded pixel guess" \
  "$(grep -A15 'id: pluginPinsPill$' "$bar_qml" | grep -c 'pluginPinsContent\.width / pinCount' || true)" "1"
check "pluginPinsViewport (the scrollable Flickable) exists, exactly once" \
  "$(grep -c 'id: pluginPinsViewport$' "$bar_qml" || true)" "1"
check "pluginPinsViewport is not interactive (drag-to-reorder must not fight with Flickable panning)" \
  "$(grep -A15 'id: pluginPinsViewport$' "$bar_qml" | grep -c 'interactive: false' || true)" "1"
check "pluginPinsViewport scrolls via WheelHandler, accepting either horizontal or vertical delta" \
  "$(grep -A35 'id: pluginPinsViewport$' "$bar_qml" | grep -c 'event\.angleDelta\.x !== 0 ? event\.angleDelta\.x : event\.angleDelta\.y' || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
