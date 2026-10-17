#!/usr/bin/env bash
# Direct request: "since we have the cava visualizer now... click it
# and it switch between cava and seeker" -- landed as a scroll toggle
# on the collapsed notch pill's fixed 140x20 "now playing" slot,
# scoped to ONLY the two media-present modes (seeker, cava). Cava
# reacts to real audio, so with nothing playing it would just sit at
# its own flat idle bars, no different from showing nothing at all --
# the "no media" state keeps its existing, unconditional active-window-
# name display instead, no toggle.
#
# Static QML checks only -- verifying the actual on-screen switch and
# live cava bars needs a real running shell with real audio, not
# something a CI fixture can measure cheaply.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
overlay_qml="$repo_dir/bars/widgets/ruixen.notch/Overlay.qml"
# The window's own visible content (collapsed pill, cava mini feed,
# bars/wave rendering) now lives in its own per-screen file -- see
# NotchWindow.qml's own header for why. mediaVizMode/cavaWarmColor/etc.
# themselves stay genuinely singleton on Overlay.qml's own root; only
# their RENDERING (the checks below that read this file) moved.
notch_window_qml="$repo_dir/bars/widgets/ruixen.notch/NotchWindow.qml"
notch_feed="$repo_dir/bars/widgets/ruixen.notch/CavaFeed.qml"
cava_feed="$repo_dir/ruixen.cava/CavaFeed.qml"

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

# --- CavaFeed.qml: a new byte-identical pair, alongside AppSearch.js/
# AppLibrary.qml/LauncherFrecency.js's own existing ones -----------------

check "ruixen.notch/CavaFeed.qml exists" "$([[ -f "$notch_feed" ]] && echo yes)" "yes"
check "ruixen.notch/CavaFeed.qml is byte-identical to ruixen.cava's own copy" \
  "$(diff -q "$notch_feed" "$cava_feed" >/dev/null 2>&1 && echo same || echo different)" "same"

# --- mode state: property, persistence, toggle ---------------------------

check "mediaVizMode property exists, defaulting to seeker" \
  "$(grep -c 'property string mediaVizMode: "seeker"' "$overlay_qml")" "1"
check "setMediaVizMode persists via writeMediaVizMode" \
  "$(grep -A4 'function setMediaVizMode' "$overlay_qml" | grep -c 'root.writeMediaVizMode()')" "1"
check "writeMediaVizMode is what actually writes the state file" \
  "$(grep -A1 'function writeMediaVizMode' "$overlay_qml" | grep -c 'mediaVizModeFile.setText')" "1"
check "toggleMediaVizMode flips between the two media-present modes only" \
  "$(grep -c 'function toggleMediaVizMode' "$overlay_qml")" "1"
check "the state file lives under ~/.local/state/ruixen/, same convention as every other bit of state" \
  "$(grep -c 'notch-media-viz-mode.json' "$overlay_qml")" "1"

# --- compactCavaFeed: separate, scoped instance ---------------------------

check "compactCavaFeed only enables while media is playing AND cava mode is selected" \
  "$(grep -c 'enabled: root.hasMedia && root.mediaVizMode === "cava"' "$overlay_qml")" "1"
check "a missing cava binary (cavaAvailable false) auto-falls back to the seeker" \
  "$(grep -A1 'onCavaAvailableChanged' "$overlay_qml" | grep -c 'root.setMediaVizMode("seeker")')" "1"
check "the mini feed uses a smaller band count than the full edge-docked overlay" \
  "$(grep -A2 'id: compactCavaFeed' "$overlay_qml" | grep -c 'bands: root.cavaMirrorBands')" "1"

# --- mirroring: real bass-on-both-edges/treble-in-the-center, not a sweep --

check "displayBars doubles the real band count for the mirror fold" \
  "$(grep -c 'readonly property int displayBars: panel.notchRoot.compactCavaFeed.bands \* 2' "$notch_window_qml")" "1"
check "mirrorBandAt folds the display index around the center (distance from nearest edge)" \
  "$(grep -A2 'function mirrorBandAt' "$notch_window_qml" | grep -c 'Math.min(i, cavaMiniSlot.displayBars - 1 - i)')" "1"
check "each rendered bar reads its level through the mirror fold, not a direct 1:1 index" \
  "$(grep -c 'panel.notchRoot.compactCavaFeed.levels\[cavaMiniSlot.mirrorBandAt(index)\]' "$notch_window_qml")" "1"

# --- warm/cool theme color, same mechanism ruixen.cava/Overlay.qml uses --

check "cavaWarmColor/cavaCoolColor default to Color.accent" \
  "$(grep -c 'property color cavaWarmColor: Color.accent' "$overlay_qml")$(grep -c 'property color cavaCoolColor: Color.accent' "$overlay_qml")" "11"
check "colors are parsed from the real active theme file" \
  "$(grep -c 'current/theme/colors.toml' "$overlay_qml")" "1"
check "a load failure falls back to Color.accent AND schedules the one-shot retry" \
  "$(grep -A10 'onLoadFailed: {' "$overlay_qml" | grep -c 'cavaThemeColorsRetryTimer.restart()')" "1"
check "each bar's color comes from the warm/cool gradient function, not a flat accent" \
  "$(grep -c 'color: cavaMiniSlot.barColor(index, level)' "$notch_window_qml")" "1"

# --- nowPlayingSlot: exactly 3 mutually-exclusive children + the scroll toggle --

check "the seeker is scoped to media present AND seeker mode selected" \
  "$(grep -c 'visible: panel.notchRoot.hasMedia && panel.notchRoot.mediaVizMode === "seeker"' "$notch_window_qml")" "1"
check "the cava mini slot is scoped to media present AND cava mode selected" \
  "$(grep -c 'visible: panel.notchRoot.hasMedia && panel.notchRoot.mediaVizMode === "cava"' "$notch_window_qml")" "1"
check "the window name stays unconditional on media absence, no mode gating" \
  "$(grep -c 'visible: !panel.notchRoot.hasMedia' "$notch_window_qml")" "1"
# Wheel no longer toggles mode -- the seeker's own MouseArea (visible
# only in seeker mode) repurposes wheel to seek instead, and right
# click is now the only way to switch modes (see the seek-support PR's
# own follow-up commit for why: wheel scrolling the seeker used to
# accidentally jump to the visualizer).
check "right click toggles the mode on the always-present now-playing slot" \
  "$(grep -c 'if (mouse.button === Qt.RightButton) {' "$notch_window_qml")" "1"
check "right click toggles the mode on the seeker's own MouseArea too" \
  "$(grep -c 'if (mouse.button === Qt.RightButton) panel.notchRoot.toggleMediaVizMode()' "$notch_window_qml")" "1"
check "wheel on the seeker seeks instead of switching modes" \
  "$(grep -c 'wheel.angleDelta.y > 0 ? 5 : -5' "$notch_window_qml")" "1"
check "no MouseArea wheel handler still toggles the mode" \
  "$(grep -c 'onWheel:.*toggleMediaVizMode' "$overlay_qml")" "0"

# --- bars/wave click toggle, within cava mode only ------------------------
# Segments deliberately excluded -- see cavaMiniStyle's own comment for
# the sub-pixel-per-segment math (20px slot height / 10 segments / 2px
# gaps) that ruled it out at this size.

check "cavaMiniStyle property exists, defaulting to bars" \
  "$(grep -c 'property string cavaMiniStyle: "bars"' "$overlay_qml")" "1"
check "no segments option actually implemented -- bars/wave only (comments may still explain why)" \
  "$(grep -c 'cavaMiniStyle === "segments"\|cavaMiniStyle: "segments"' "$overlay_qml")" "0"
check "toggleCavaMiniStyle flips bars/wave and persists" \
  "$(grep -A3 'function toggleCavaMiniStyle' "$overlay_qml" | grep -c 'writeMediaVizMode()')" "1"
# 2, not 1 -- both left click AND wheel now reach the same toggle
# (identical guard text in each handler), not just click alone.
check "left click AND wheel on the slot toggle style, but only while already in cava mode" \
  "$(grep -c 'if (panel.notchRoot.mediaVizMode === "cava") panel.notchRoot.toggleCavaMiniStyle()' "$notch_window_qml")" "2"
check "the mode/style state file round-trips both fields together" \
  "$(grep -c 'mode: root.mediaVizMode, style: root.cavaMiniStyle' "$overlay_qml")" "1"

# --- bars vs. wave rendering: mutually exclusive, same mirrored data ------

check "the bars Repeater only populates in bars style (0 delegates otherwise)" \
  "$(grep -c 'model: panel.notchRoot.cavaMiniStyle === "bars" ? cavaMiniSlot.displayBars : 0' "$notch_window_qml")" "1"
check "the wave Canvas is scoped to wave style" \
  "$(grep -c 'visible: panel.notchRoot.cavaMiniStyle === "wave"' "$notch_window_qml")" "1"
check "the wave reads through the exact same mirror fold the bars use, not a separate index scheme" \
  "$(grep -c 'panel.notchRoot.compactCavaFeed.levels\[cavaMiniSlot.mirrorBandAt(i)\]' "$notch_window_qml")" "1"
check "the wave repaints when new cava data arrives" \
  "$(grep -A1 'function onLevelsChanged() { if (cavaMiniWave.visible)' "$notch_window_qml" | grep -c 'requestPaint()')" "1"
check "the wave forces a fresh paint on becoming visible, not stale cached content" \
  "$(grep -c 'onVisibleChanged: if (visible) requestPaint()' "$notch_window_qml")" "1"
check "the wave is a FILLED area, not just a stroked line -- direct correction" \
  "$(grep -c 'ctx.fillStyle = grad' "$notch_window_qml")" "1"
check "the fill curve is smoothed via quadratic-through-midpoints, same technique the desktop wave uses, not raw straight segments" \
  "$(grep -c 'ctx.quadraticCurveTo(pts\[j\].x, pts\[j\].y, mx, my)' "$notch_window_qml")" "1"
check "the fill starts and closes down to the bottom edge (same baseline bars grow up from)" \
  "$(grep -c 'ctx.moveTo(pts\[0\].x, height)' "$notch_window_qml")$(grep -c 'ctx.lineTo(pts\[n - 1\].x, height)' "$notch_window_qml")" "11"
check "a brighter stroke is retraced on top of the fill for definition" \
  "$(grep -c 'ctx.strokeStyle = grad' "$notch_window_qml")" "1"

# --- edge fade: opacity tapers at the outermost couple of positions -------

check "edgeFade exists, scaled down from the desktop's own fixed 6 to fit displayBars=12" \
  "$(grep -c 'readonly property int edgeFadeBands: 2' "$notch_window_qml")" "1"
check "each bar's own opacity is driven by edgeFade, not always full-strength" \
  "$(grep -c 'opacity: cavaMiniSlot.edgeFade(index)' "$notch_window_qml")" "1"
check "the wave gradient is an 8-step ramp (not 3 flat stops), each step scaled by edgeFade too" \
  "$(grep -c '0.85 \* fade' "$notch_window_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
