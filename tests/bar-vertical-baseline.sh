#!/usr/bin/env bash
# Covers "[P1] Align floating-mode bar widgets to the docked vertical
# baseline" (#29): floating-mode bar widgets used to sit ~7px lower than
# docked's, because BarPanel's own top margin was the only thing that
# actually differed between the two modes (dockedRow -- the Item every
# pill and every widget's ModuleSlot is hosted under -- anchors identically
# regardless of root.docked; confirmed live via a temporary debug IPC dump
# of ModuleSlot.mapToItem(null,...), which came back byte-identical in
# both modes). The fix collapses BOTH modes onto the SAME top margin
# (frameInset) rather than floating carrying its own separately-tuned
# value (was: topInset).
#
# Can't drive a real Quickshell instance here (no compositor in CI), so
# this is a static invariant check against the actual QML source instead
# -- same style as tests/lint-shell.sh's own pattern-based guards. It
# exists specifically so a future, unrelated change to frameInset,
# barSize, or the exclusiveZone math can't silently reintroduce a
# per-mode split without at least one test failing.
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

frame_inset="$(grep -oP 'readonly property int frameInset:\s*\K[0-9]+' "$bar_qml")"
notch_clearance="$(grep -oP 'readonly property int notchClearance:\s*\K[0-9]+' "$bar_qml")"
bar_size="$(grep -oP 'readonly property int barSize:\s*\K[0-9]+' "$bar_qml")"

check "frameInset is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$frame_inset" | wc -l | tr -d ' ')" "0"
check "notchClearance is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$notch_clearance" | wc -l | tr -d ' ')" "0"

# The Hyprland reservation total (margin.top + exclusiveZone) has to land
# on 44 -- the notch's own collapsed height -- regardless of mode. This is
# the invariant the old topInset/notchClearance pair was hand-tuned to
# preserve every time one of them moved; now there's only one margin to
# check it against.
check "frameInset + notchClearance reservation invariant equals 44 (notch's own collapsed height)" \
  "$((frame_inset + notch_clearance))" "44"

# The actual #29 bug: margins.top used to read `root.docked ? frameInset :
# topInset` -- a real per-mode branch. It must now be a single value with
# no docked conditional and no second inset name.
margins_top_line="$(grep -m1 'position === "top".*frameInset' "$bar_qml" | grep 'top:')"
check "margins.top no longer branches on root.docked" \
  "$(printf '%s' "$margins_top_line" | grep -c 'root\.docked ?' || true)" "0"
check "topInset (the old, separately-tuned floating-only value) no longer exists anywhere in Bar.qml" \
  "$(grep -c 'topInset' "$bar_qml" || true)" "0"

# exclusiveZone must resolve the same way regardless of docked -- the
# per-mode ternary (`root.docked ? (44 - frameInset) : root.notchClearance`)
# is exactly the kind of change that would silently reintroduce a split
# margin.top computed to a *different* reservation total than intended.
exclusive_zone_line="$(grep -m1 'exclusiveZone:' "$bar_qml")"
check "exclusiveZone no longer branches on root.docked" \
  "$(printf '%s' "$exclusive_zone_line" | grep -c 'root\.docked ?' || true)" "0"

# dockedRow -- the Item every pill (and therefore every ModuleSlot,
# Ruixen's own and any third-party bar-widget alike) is hosted under --
# must anchor to its own window's top unconditionally. This is *why* a
# single shared frameInset is sufficient to fix #29: if this ever grows a
# docked-conditional y/anchor of its own, frameInset alone stops being
# the whole story and this guard (and the one above) need revisiting
# together, not in isolation.
dockedrow_anchor="$(grep -A2 'id: dockedRow' "$bar_qml" | grep 'anchors.top:')"
check "dockedRow anchors unconditionally to its own window's top (no docked branch)" \
  "$(printf '%s' "$dockedrow_anchor" | grep -c 'root\.docked' || true)" "0"
check "dockedRow's own top anchor is parent.top, not a computed/offset value" \
  "$dockedrow_anchor" "          anchors.top: parent.top"

# dockedRow's height is what every pill's own verticalCenter anchor
# ultimately measures against (see rightPill/leftPill/etc, all
# `anchors.verticalCenter: parent.verticalCenter` chained up to this Item)
# -- it has to stay root.barSize, mode-independent, or the two modes'
# shared frameInset stops being sufficient on its own to keep their
# centerlines equal.
dockedrow_height="$(grep -A4 'id: dockedRow' "$bar_qml" | grep 'height:')"
check "dockedRow's height is root.barSize (bar_size=$bar_size), not a docked-conditional value" \
  "$dockedrow_height" "          height: root.barSize"

# --- floating-mode popups colliding with the Notch (direct live report) --
#
# Separate from #29's own centerline bug, found right after: weather's own
# popup and stock Omarchy's clock calendar popup (qs.Ui KeyboardPanel,
# centerOnBar: true) open at `anchorWindow.height + gap` -- that's this
# window's own `height` (== implicitHeight, since it's never set
# explicitly), read directly by a file we don't own
# (/usr/share/omarchy/shell/Ui/KeyboardPanel.qml) and can't patch. It has
# no notion of ruixen.notch at all.
#
# Docked already cleared the Notch's collapsed footprint by accident --
# its implicitHeight already carried +shoulderWingSize (24) for an
# unrelated reason (room for the frame-hem corner wing graphic), and that
# was enough slack. Floating had none, so popups opened inside the
# Notch's own [4, 48] band and visibly cut through it (confirmed live,
# screenshotted, before this fix).
shoulder_wing_size="$(grep -oP 'readonly property int shoulderWingSize:\s*\K[0-9]+' "$bar_qml")"
check "shoulderWingSize is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$shoulder_wing_size" | wc -l | tr -d ' ')" "0"

implicit_height_line="$(grep -m1 'implicitHeight: root.vertical ? 0' "$bar_qml")"
check "BarPanel's implicitHeight no longer branches on root.docked (both modes get the same popup-clearing height)" \
  "$(printf '%s' "$implicit_height_line" | grep -c 'root\.docked ?' || true)" "0"
check "BarPanel's implicitHeight is barSize + shoulderWingSize in both modes (bar_size=$bar_size, shoulder_wing_size=$shoulder_wing_size)" \
  "$implicit_height_line" "    implicitHeight: root.vertical ? 0 : root.barSize + root.shoulderWingSize"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
