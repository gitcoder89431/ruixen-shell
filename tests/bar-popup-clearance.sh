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
# The exact numbers, confirmed live: Notch's own collapsed bottom edge is
# margin.top(4) + height(44) = 48. Docked's own window height already
# carried +shoulderWingSize(24) for an unrelated reason (room for the
# frame-hem corner wing graphic below the pill row), which put its popups
# at 34 + 24 + gap(5) = 63 -- clear of 48 by accident. Floating had none
# of that slack: popups opened at 34 + gap(5) = 39, inside the Notch's own
# [4, 48] band -- a direct, screenshotted overlap.
#
# Fix: floating's BarPanel now carries the same +shoulderWingSize height
# docked already had, purely a window-height change -- it does NOT touch
# margins.top/frameInset/topInset, so it doesn't move any pill's own
# on-screen position. (A separate, broader attempt to also unify
# margins.top between docked/floating -- filed as #29 -- was tried and
# reverted: the actual complaint was always this popup overlap, never the
# icons' own padding, and unifying the margin made floating's spacing
# look unbalanced for no real benefit. See Bar.qml's own notchClearance/
# topInset comments for that history.)
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

bar_size="$(grep -oP 'readonly property int barSize:\s*\K[0-9]+' "$bar_qml")"
shoulder_wing_size="$(grep -oP 'readonly property int shoulderWingSize:\s*\K[0-9]+' "$bar_qml")"

check "barSize is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$bar_size" | wc -l | tr -d ' ')" "0"
check "shoulderWingSize is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$shoulder_wing_size" | wc -l | tr -d ' ')" "0"

implicit_height_line="$(grep -m1 'implicitHeight: root.vertical ? 0' "$bar_qml")"
check "BarPanel's implicitHeight no longer branches on root.docked (both modes get the same popup-clearing height)" \
  "$(printf '%s' "$implicit_height_line" | grep -c 'root\.docked ?' || true)" "0"
check "BarPanel's implicitHeight is barSize + shoulderWingSize in both modes (bar_size=$bar_size, shoulder_wing_size=$shoulder_wing_size)" \
  "$implicit_height_line" "    implicitHeight: root.vertical ? 0 : root.barSize + root.shoulderWingSize"

# The docked/floating split top margin is intentional again (see this
# file's own header) -- guard that a future edit doesn't silently
# re-unify it while "fixing" something else. Both topInset and the
# docked ternary must still be present.
check "topInset (floating's own, separately-tuned top margin) still exists" \
  "$(grep -c 'readonly property int topInset:' "$bar_qml" || true)" "1"
margins_top_line="$(grep -m1 'position === "top".*root.docked ? frameInset : topInset' "$bar_qml")"
check "margins.top still branches on root.docked (frameInset when docked, topInset when floating)" \
  "$(printf '%s' "$margins_top_line" | grep -c 'root\.docked ? frameInset : topInset' || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
