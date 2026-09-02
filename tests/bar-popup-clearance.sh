#!/usr/bin/env bash
# Covers a direct live report: in floating mode, opening weather's own
# popup (and, confirmed separately, stock Omarchy's clock calendar popup)
# visibly cut through the Notch's collapsed body.
#
# Both panels are built on qs.Ui's KeyboardPanel (centerOnBar: true), which
# is NOT ours to edit -- it's under /usr/share/omarchy, pacman-owned. Its
# cardOrigin math opens the popup at `anchorWindow.height + gap`, where
# anchorWindow is ruixen.bar's own BarPanel window and gap is
# Style.gapsOut (5 on the machine this was tuned against, from the real
# Hyprland gaps_out config). That calculation has zero awareness of
# ruixen.notch.
#
# First attempt (see git history) reused shoulderWingSize (docked's own
# existing +24, tuned for an unrelated reason -- room for the frame-hem
# corner wing graphic below the pill row) as the popup-clearing height in
# both modes. That cleared the Notch but overshot: popups opened
# noticeably lower than ruixen.quickactions' own "More Actions" popup (a
# DIFFERENT popup component, PopupCard, anchored off its own icon rather
# than this window's height, and already sitting right at the reserved
# zone's own edge). Direct follow-up report: "can it go a bit higher...
# the border matches the top of our hyprland window" pointing at that
# popup as the reference.
#
# Fixed by deriving the minimum height from the Notch's own real collapsed
# geometry instead (notchCollapsedBottomEdge, sourced from ruixen.notch's
# own NotchGeometry.qml service, not a second hardcoded number) --
# max(barSize, notchCollapsedBottomEdge) in floating mode. Docked keeps
# its own higher floor (barSize + shoulderWingSize) regardless of the
# Notch's numbers: leftFrameHemWing/rightFrameHemWing (the frame-hem
# corner wing graphics, docked only) occupy this window's own
# [barSize, barSize + shoulderWingSize] band, and sizing the window any
# shorter when docked would clip their bottom edge against the window's
# own Wayland surface bounds.
#
# Purely a window-height change -- does NOT touch
# margins.top/frameInset/topInset, so it doesn't move any pill's own
# on-screen position (the docked/floating split top margin from before
# #29 was reverted is untouched by this file).
#
# A follow-up attempt (see git history) tried pushing this shared value
# further down toward true screen-center, matching ruixen.settings' own
# dead-center dialog look. Reverted: the same shared `anchorWindow.height`
# every popup reads doesn't scale to every popup's own, wildly different
# content height -- a target tuned for weather's own ~228px popup pushed
# omarchy.agents' own popup (up to 640px, a scrollable dashboard) toward
# the bottom of the screen instead, via KeyboardPanel's own on-screen
# clamp. Confirmed live ("the ai agent popup... showing up at the bottom
# now"). Back to visibleBarHeight only (clears the Notch, no reach for
# center) -- this file's own checks guard THAT reverted state, not the
# center attempt.
#
# Can't drive a real Quickshell instance here (no compositor in CI), so
# this is a static invariant check against the actual QML source instead
# -- same style as tests/lint-shell.sh's own pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
bar_qml="$repo_dir/ruixen.bar/Bar.qml"
notch_geometry_qml="$repo_dir/ruixen.notch/NotchGeometry.qml"

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

bar_size="$(grep -oP 'readonly property int barSize:\s*\K[0-9]+' "$bar_qml")"
shoulder_wing_size="$(grep -oP 'readonly property int shoulderWingSize:\s*\K[0-9]+' "$bar_qml")"
notch_top_margin="$(grep -oP 'readonly property int collapsedTopMargin:\s*\K[0-9]+' "$notch_geometry_qml")"
notch_collapsed_height="$(grep -oP 'readonly property int collapsedHeight:\s*\K[0-9]+' "$notch_geometry_qml")"

check "barSize is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$bar_size" | wc -l | tr -d ' ')" "0"
check "shoulderWingSize is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$shoulder_wing_size" | wc -l | tr -d ' ')" "0"
check "NotchGeometry's collapsedTopMargin is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$notch_top_margin" | wc -l | tr -d ' ')" "0"
check "NotchGeometry's collapsedHeight is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$notch_collapsed_height" | wc -l | tr -d ' ')" "0"

# ruixen.bar's own fallback constant (used only if the notch service is
# unavailable) has to track NotchGeometry's real numbers, or a future
# change to either file silently drifts the fallback out of sync with the
# thing it's supposed to approximate.
notch_bottom_edge_fallback="$(grep -oP 'notchGeometryService && notchGeometryService\.collapsedBottomEdge \? notchGeometryService\.collapsedBottomEdge : \K[0-9]+' "$bar_qml")"
check "ruixen.bar's own notchCollapsedBottomEdge fallback matches NotchGeometry's real collapsedTopMargin + collapsedHeight" \
  "$notch_bottom_edge_fallback" "$((notch_top_margin + notch_collapsed_height))"

# Docked still needs the taller floor (barSize + shoulderWingSize) no
# matter what the Notch's own numbers are, so the frame-hem wing graphics
# never get clipped -- this must stay a real per-mode branch, unlike
# margins.top/exclusiveZone (which are deliberately NOT branched, see
# Bar.qml's own notchClearance comment for that separate history).
visible_bar_height_line="$(grep -m1 'readonly property int visibleBarHeight:' "$bar_qml")"
check "visibleBarHeight still branches on root.docked (docked keeps its own wing-graphic floor)" \
  "$(printf '%s' "$visible_bar_height_line" | grep -c 'root\.docked ?' || true)" "1"
check "visibleBarHeight derives from notchCollapsedBottomEdge in both branches, not a flat reused constant" \
  "$(printf '%s' "$visible_bar_height_line" | grep -o 'root\.notchCollapsedBottomEdge' | wc -l | tr -d ' ')" "2"
check "visibleBarHeight's docked branch still floors at barSize + shoulderWingSize (the wing-graphic minimum)" \
  "$(printf '%s' "$visible_bar_height_line" | grep -c 'Math\.max(root\.barSize + root\.shoulderWingSize, root\.notchCollapsedBottomEdge)' || true)" "1"

# implicitHeight itself must stay exactly visibleBarHeight (no reach for
# center, see this file's own header for why that was reverted) -- a
# future edit growing this again needs to bring the input mask back with
# it (see the reverted attempt's own comment in git history), not just
# quietly resurface the agents-popup-at-the-bottom bug.
implicit_height_line="$(grep -m1 'implicitHeight: root.vertical ? 0 : ' "$bar_qml")"
check "implicitHeight is exactly visibleBarHeight, not a further-grown value" \
  "$implicit_height_line" "    implicitHeight: root.vertical ? 0 : visibleBarHeight"

# The docked/floating split top margin (reverted from #29's own attempt
# to unify it) is unrelated to this fix and must stay untouched by it.
# frameInset/topInset/screenMarginTop moved from BarPanel onto root
# itself (a later fix, see below) so widgets could read the bar's own
# current screen offset -- still exactly one definition each.
check "root.frameInset (docked's own top margin) still exists, exactly once" \
  "$(grep -c 'readonly property int frameInset:' "$bar_qml" || true)" "1"
check "root.topInset (floating's own, separately-tuned top margin) still exists, exactly once" \
  "$(grep -c 'readonly property int topInset:' "$bar_qml" || true)" "1"
margins_top_line="$(grep -m1 'position === "top".*root.screenMarginTop' "$bar_qml")"
check "margins.top still resolves per-mode via root.screenMarginTop" \
  "$(printf '%s' "$margins_top_line" | grep -c 'root\.screenMarginTop' || true)" "1"

# --- screenMarginTop / ruixen.quickactions' own popup Y (direct live
# report: "our more actions seems to be low now") -------------------
#
# PopupCard (ruixen.quickactions' own popup component) is a real
# xdg-popup anchored to ruixen.bar's own surface, so its "top" position
# math is relative to that surface's own origin -- which sits at
# root.screenMarginTop on screen, not at screen y=0. KeyboardPanel-based
# popups (weather/clock/agents) are each their own separate, always-at-
# origin full-screen window, with no such offset. Confirmed live: after
# switching quickactions to centerOnBar, its popup opened noticeably
# lower than weather/clock's, by exactly this machine's own
# screenMarginTop value.
check "root.screenMarginTop exists, exactly once (the value quickactions compensates for)" \
  "$(grep -c 'readonly property int screenMarginTop:' "$bar_qml" || true)" "1"
screen_margin_top_line="$(grep -m1 'readonly property int screenMarginTop:' "$bar_qml")"
check "screenMarginTop is docked ? frameInset : topInset (mirrors margins.top's own per-mode split)" \
  "$screen_margin_top_line" "  readonly property int screenMarginTop: docked ? frameInset : topInset"

qa_qml="$repo_dir/ruixen.quickactions/QuickActions.qml"
qa_margin_line="$(grep -m1 'margin: Style.gapsOut' "$qa_qml")"
check "ruixen.quickactions' own popup backs screenMarginTop out of its margin, not a hardcoded offset" \
  "$qa_margin_line" "    margin: Style.gapsOut - (root.bar ? root.bar.screenMarginTop : 0)"
check "ruixen.quickactions' own popup is still centerOnBar (the earlier fix this one builds on)" \
  "$(grep -c 'centerOnBar: true' "$qa_qml" || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
