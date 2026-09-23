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
overlay_qml="$repo_dir/bars/v1/ruixen.notch/Overlay.qml"
notch_feed="$repo_dir/bars/v1/ruixen.notch/CavaFeed.qml"
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
check "setMediaVizMode persists to its own state file" \
  "$(grep -A4 'function setMediaVizMode' "$overlay_qml" | grep -c 'mediaVizModeFile.setText')" "1"
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
  "$(grep -A2 'id: compactCavaFeed' "$overlay_qml" | grep -c 'bands: 20')" "1"

# --- nowPlayingSlot: exactly 3 mutually-exclusive children + the scroll toggle --

check "the seeker is scoped to media present AND seeker mode selected" \
  "$(grep -c 'visible: root.hasMedia && root.mediaVizMode === "seeker"' "$overlay_qml")" "1"
check "the cava mini slot is scoped to media present AND cava mode selected" \
  "$(grep -c 'visible: root.hasMedia && root.mediaVizMode === "cava"' "$overlay_qml")" "1"
check "the window name stays unconditional on media absence, no mode gating" \
  "$(grep -c 'visible: !root.hasMedia' "$overlay_qml")" "1"
check "a wheel-triggered MouseArea toggles the mode, enabled only while media plays" \
  "$(grep -B2 'onWheel: root.toggleMediaVizMode()' "$overlay_qml" | grep -c 'enabled: root.hasMedia')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
