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
# geometry instead (notchCollapsedBottomEdge) -- max(barSize,
# notchCollapsedBottomEdge). Originally sourced live from ruixen.notch's
# own NotchGeometry.qml service via shell.firstPartyServiceFor(); Omarchy
# v4.0.3 restricts that call to a fixed allowlist "ruixen.notch" was never
# going to be in (ruixen-shell issue #41/#38), so this is now a plain
# constant, manually kept in sync with Overlay.qml's own real numbers
# instead (same convention this file's own cornerSize already uses for a
# different pair of plugins' shared numbers). NotchGeometry.qml itself --
# the now-unconsumed service this used to read live -- was deleted
# entirely once ruixen.bar became its last reader (ruixen-shell issue
# #38's own cleanup pass); Overlay.qml was always the real source of
# truth these numbers mirrored, so this file reads directly from there
# now instead of through a middleman nothing else uses. Docked keeps a
# higher floor
# (barSize + shoulderWingSize) regardless of the Notch's numbers:
# leftFrameHemWing/rightFrameHemWing (the frame-hem corner wing graphics,
# docked only) occupy this window's own [barSize, barSize +
# shoulderWingSize] band, and sizing the window any shorter when docked
# would clip their bottom edge against the window's own Wayland surface
# bounds.
#
# Originally a per-mode split (docked used the taller floor, floating used
# the shorter one -- both cleared the Notch either way). Unified to the
# SAME floor in both modes after a direct follow-up report: floating's
# shorter height happened to line up with where Hyprland windows actually
# tile, but docked's couldn't safely come down to match (the wing-clip
# constraint above), so the two modes opened popups at two different
# heights -- "it looks kinda sloppy... i think its better they either
# lower or higher rather than having its own thing". Docked's floor can't
# move, so floating moved up to match it instead: consistent behavior
# across both modes over exactly hugging the window-tiling boundary in
# floating alone.
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
bar_qml="$repo_dir/bars/v2/ruixen.bar/Bar.qml"
notch_overlay_qml="$repo_dir/bars/widgets/ruixen.notch/Overlay.qml"

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
shoulder_wing_size="$(grep -oP 'property int shoulderWingSize:\s*\K[0-9]+' "$bar_qml")"
# The old single margins.top (4) split into two pieces once "On Hover"
# mode needed the surface itself to reach the true top edge (closing a
# real dead zone -- see margins.top's own comment in Overlay.qml): the
# PanelWindow's own margins.top (now 0, a real Wayland surface inset)
# and notchOuter's own restY (4, a plain property -- anchors.top/
# topMargin were dropped entirely once notchOuter needed to animate
# its own y for the slide-down reveal, see its own comment) -- their
# SUM is still the pill's real on-screen resting top offset, which is
# what notchCollapsedBottomEdge actually needs. Scoped to the few
# lines right after notchOuter's own `id:` (grep -A10) since a bare
# file-wide match on a name as short as restY would be too easy to
# collide with something unrelated later.
notch_top_margin="$(grep -oP 'margins\.top:\s*\K[0-9]+' "$notch_overlay_qml")"
notch_outer_top_margin="$(grep -A16 'id: notchOuter' "$notch_overlay_qml" | grep -oP 'property int restY:\s*\K[0-9]+')"
notch_collapsed_height="$(grep -oP 'panel\.pinnedOpen \? 400 : \K[0-9]+' "$notch_overlay_qml")"
notch_body_width="$(grep -oP 'panel\.pinnedOpen \? 900 : \K[0-9]+' "$notch_overlay_qml")"
notch_corner_size="$(grep -oP 'readonly property int cornerSize:\s*\K[0-9]+' "$notch_overlay_qml")"

check "barSize is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$bar_size" | wc -l | tr -d ' ')" "0"
check "shoulderWingSize is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$shoulder_wing_size" | wc -l | tr -d ' ')" "0"
check "Overlay.qml's own collapsed margins.top is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$notch_top_margin" | wc -l | tr -d ' ')" "0"
check "Overlay.qml's own notchOuter restY is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$notch_outer_top_margin" | wc -l | tr -d ' ')" "0"
check "Overlay.qml's own collapsed notchOuter height is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$notch_collapsed_height" | wc -l | tr -d ' ')" "0"

# ruixen.bar's own manually-synced constant has to track Overlay.qml's
# real numbers, or a future change to either file silently drifts the two
# out of sync (see ruixen-shell issue #41: this was a live service read
# with a fallback constant before Omarchy v4.0.3 broke that read; now it
# is just the constant, so this check matters more than it used to, not
# less -- there is no live path left to mask a drift). NotchGeometry.qml,
# the service this used to read live through, was deleted once ruixen.bar
# became its last consumer -- Overlay.qml was always the real source of
# truth those numbers mirrored, so this reads it directly now.
notch_bottom_edge_fallback="$(grep -oP 'readonly property int notchCollapsedBottomEdge: \K[0-9]+' "$bar_qml")"
check "ruixen.bar's own notchCollapsedBottomEdge matches Overlay.qml's real collapsed margins.top + notchOuter restY + notchOuter height" \
  "$notch_bottom_edge_fallback" "$((notch_top_margin + notch_outer_top_margin + notch_collapsed_height))"

# Same drift risk, same fix, for the OTHER constant ruixen.bar used to
# read live from NotchGeometry.qml (issue #28's own horizontal-space
# reservation, not this file's own popup-clearance feature, but broken
# by the exact same v4.0.3 change and fixed the exact same way -- worth
# checking here since this file already parses Overlay.qml's own values).
check "Overlay.qml's own collapsed bodyWidth is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$notch_body_width" | wc -l | tr -d ' ')" "0"
check "Overlay.qml's own notchOuter cornerSize is a single, real value (not empty/multiple matches)" \
  "$(printf '%s' "$notch_corner_size" | wc -l | tr -d ' ')" "0"
notch_reserved_width="$(grep -oP 'readonly property int notchReservedWidth:\s*\K[0-9]+' "$bar_qml")"
check "ruixen.bar's own notchReservedWidth matches Overlay.qml's real collapsed bodyWidth + cornerSize * 2" \
  "$notch_reserved_width" "$((notch_body_width + notch_corner_size * 2))"

# Same floor in BOTH modes now (see this file's own header for why the
# per-mode split was unified) -- docked's own wing-clip constraint sets
# the shared value, since it's the one that can't come down.
visible_bar_height_line="$(grep -m1 'readonly property int visibleBarHeight:' "$bar_qml")"
check "visibleBarHeight no longer branches on root.docked (both modes share one floor)" \
  "$(printf '%s' "$visible_bar_height_line" | grep -c 'root\.docked ?' || true)" "0"
check "visibleBarHeight still floors at barSize + shoulderWingSize (the wing-graphic minimum, now shared)" \
  "$(printf '%s' "$visible_bar_height_line" | grep -c 'Math\.max(root\.barSize + root\.shoulderWingSize, root\.notchCollapsedBottomEdge)' || true)" "1"

# implicitHeight must stay EITHER exactly visibleBarHeight OR
# visibleBarHeight + root.seamOverlap -- not some other, larger reach
# (still guarding against the "reach for center" regression this file's
# own header describes; a future edit growing this again some OTHER way
# needs to bring the input mask back with it, same as that reverted
# attempt needed). The "+ seamOverlap" branch is new, v2-era: BarPanel is
# a real small window again (not the fullscreen one v2 first tried), but
# its own top edge intentionally starts a few px higher than v1's ever
# did, painting a small insurance-overlap band into where the shell
# frame's own separate surface edge is (see BarPanel's own seamOverlap
# comment) -- implicitHeight grows by that same small, fixed amount so
# the window's real BOTTOM edge (and thus anchorWindow.height for every
# popup this whole file is about) lands exactly where v1's always did,
# regardless of the extra room claimed at the top.
implicit_height_line="$(grep -m1 'implicitHeight: root.vertical ? 0 : ' "$bar_qml")"
check "implicitHeight is visibleBarHeight, optionally + root.seamOverlap -- not some other, larger reach" \
  "$implicit_height_line" "    implicitHeight: root.vertical ? 0 : visibleBarHeight + root.seamOverlap"

# The docked/floating split top margin (reverted from #29's own attempt
# to unify it) is unrelated to this fix and must stay untouched by it.
# frameInset/topInset/screenMarginTop moved from BarPanel onto root
# itself (a later fix, see below) so widgets could read the bar's own
# current screen offset -- still exactly one definition each.
check "root.frameInset (docked's own top margin) still exists, exactly once" \
  "$(grep -c 'readonly property int frameInset:' "$bar_qml" || true)" "1"
check "root.topInset (floating's own, separately-tuned top margin) still exists, exactly once" \
  "$(grep -c 'readonly property int topInset:' "$bar_qml" || true)" "1"
# v2: margins.top resolves per-mode via root.contentTopInset now, not
# root.screenMarginTop directly -- BarPanel's own seam-overlap trick
# (see its own comment) needed a DIFFERENT number for "how far content
# sits from this window's own top edge" than screenMarginTop's own
# (now separate) job of "this window's real final on-screen offset,
# overlap included". Same docked/floating split either property carries,
# just renamed/split apart for the two different jobs.
margins_top_line="$(grep -m1 'position === "top".*root.contentTopInset' "$bar_qml")"
check "margins.top still resolves per-mode via root.contentTopInset" \
  "$(printf '%s' "$margins_top_line" | grep -c 'root\.contentTopInset' || true)" "1"
check "root.contentTopInset exists, exactly once (docked ? frameInset : topInset)" \
  "$(grep -c 'readonly property int contentTopInset: docked ? frameInset : topInset' "$bar_qml" || true)" "1"

# --- root.screenMarginTop (bar hosting infra) --------------------------
#
# v2: this window's own REAL final on-screen top offset, i.e.
# contentTopInset with the seam-overlap trick's own reduction already
# applied for a top-positioned bar (0 for left/right/bottom, unaffected
# by the trick). Real, reusable bar-hosting infrastructure -- currently
# unconsumed (a past attempt to use it for quickactions'/pluginpins' own
# PopupCard.margin, calibrated for centerOnBar's different Y formula,
# was verified live to be wrong for the target.height-based formula
# these actually use -- see either widget's own popup.margin comment for
# the real fix).
check "root.screenMarginTop exists, exactly once (bar-hosting infra)" \
  "$(grep -c 'readonly property int screenMarginTop: position === "top" ? contentTopInset - seamOverlap : contentTopInset' "$bar_qml" || true)" "1"

# ruixen.quickactions'/ruixen.pluginpins' own popups: centerOnBar stays
# reverted (e0429b7 was purely visual, correctly dropped). The Y position
# needed real live tuning, not a derived formula -- direct live report +
# screenshot confirmed PopupCard's own plain default (target.height +
# margin) landed overlapping the bar's own reserved height above the
# icon row; a since-abandoned analytical fix (fully cancelling
# target.height via PopupCard's own exposed barH) overshot the opposite
# way, into the bar's own reserved-but-invisible padding. 17 is the
# real, live-measured value in between (via a temporary debug hook
# reading popup.anchor.rect.y directly) -- both widgets share this exact
# value since both use the same BarIconButton icon (same real height).
qa_qml="$repo_dir/bars/widgets/ruixen.quickactions/QuickActions.qml"
pp_qml="$repo_dir/bars/widgets/ruixen.pluginpins/BarWidget.qml"
check "ruixen.quickactions' own popup still has no centerOnBar override" \
  "$(grep -c 'centerOnBar:' "$qa_qml" || true)" "0"
check "ruixen.quickactions' own popup uses the live-measured margin" \
  "$(grep -c '    margin: 17' "$qa_qml" || true)" "1"
check "ruixen.pluginpins' own popup uses the live-measured margin" \
  "$(grep -c '    margin: 17' "$pp_qml" || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
