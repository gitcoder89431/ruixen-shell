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
implicit_height_line="$(grep -m1 'implicitHeight: root.vertical ? 0 : (root.docked' "$bar_qml")"
check "BarPanel's implicitHeight still branches on root.docked (docked keeps its own wing-graphic floor)" \
  "$(printf '%s' "$implicit_height_line" | grep -c 'root\.docked ?' || true)" "1"
check "BarPanel's implicitHeight derives from notchCollapsedBottomEdge in both branches, not a flat reused constant" \
  "$(printf '%s' "$implicit_height_line" | grep -o 'root\.notchCollapsedBottomEdge' | wc -l | tr -d ' ')" "2"
check "BarPanel's docked branch still floors at barSize + shoulderWingSize (the wing-graphic minimum)" \
  "$(printf '%s' "$implicit_height_line" | grep -c 'Math\.max(root\.barSize + root\.shoulderWingSize, root\.notchCollapsedBottomEdge)' || true)" "1"

# The docked/floating split top margin (reverted from #29's own attempt
# to unify it) is unrelated to this fix and must stay untouched by it.
check "topInset (floating's own, separately-tuned top margin) still exists" \
  "$(grep -c 'readonly property int topInset:' "$bar_qml" || true)" "1"
margins_top_line="$(grep -m1 'position === "top".*root.docked ? frameInset : topInset' "$bar_qml")"
check "margins.top still branches on root.docked (frameInset when docked, topInset when floating)" \
  "$(printf '%s' "$margins_top_line" | grep -c 'root\.docked ? frameInset : topInset' || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
