#!/usr/bin/env bash
# Covers issue #70: the visualizer kept doing unnecessary steady-state
# work after playback settled to silence, on an always-loaded desktop
# shell process.
#
# Two specific cases fixed:
#
# 1. CavaFeed.qml's 120ms idle timer used to reassign root.levels/
#    prevLevels to fresh flat() arrays (two allocations) every single
#    tick for as long as the feed stayed idle, forever -- not just
#    once when it first went idle. idleSettled now latches after the
#    first flatten, and readBars() clears it the moment a real frame
#    arrives again.
#
# 2. Wave's 16ms (~60fps) Canvas timer used to run continuously
#    whenever the Wave canvas was simply visible, even once the
#    interpolated curve had fully converged to flat silence. settled
#    now gates the timer itself (running: visible && !settled), with
#    an event-driven Connections listener on feed.onLevelsChanged (not
#    a second polling loop) waking it the instant new data arrives.
#
# Static QML checks only, same reasoning tests/cava-missing-dependency.sh's
# own header documents -- live verification (a precise /proc/[pid]/stat
# CPU-time-delta measurement, not the noisy lifetime-average `ps %CPU`
# column, comparing the same quickshell process actively playing vs.
# fully settled) was done manually against the actual running shell
# this session: ~52% during active playback vs. ~5-6% once settled,
# with CPU jumping straight back up the instant playback resumed.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
feed_qml="$repo_dir/ruixen.cava/CavaFeed.qml"
overlay_qml="$repo_dir/ruixen.cava/Overlay.qml"

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

# --- CavaFeed.qml: idleTimer only flattens once per transition -------

check "idleSettled property exists" \
  "$(grep -c 'property bool idleSettled' "$feed_qml")" "1"
check "idleTimer's own onTriggered bails out early once already settled" \
  "$(grep -A2 'onTriggered: {' "$feed_qml" | grep -c 'if (root.idleSettled) return')" "1"
check "idleTimer latches idleSettled after flattening" \
  "$(grep -A6 'if (Date.now() - root.lastReadMs > 260)' "$feed_qml" | grep -c 'root.idleSettled = true')" "1"
check "idleSettled is reset to false in 3 places (readBars, onEnabledChanged, onBandsChanged)" \
  "$(grep -c 'idleSettled = false' "$feed_qml")" "3"
check "onEnabledChanged resets idleSettled too" \
  "$(grep -A10 'onEnabledChanged: {' "$feed_qml" | grep -c 'idleSettled = false')" "1"
check "onBandsChanged resets idleSettled too" \
  "$(grep -A5 'onBandsChanged: {' "$feed_qml" | grep -c 'idleSettled = false')" "1"

# --- Overlay.qml: Wave's own timer is gated by settled ----------------

check "waveCanvas has a settled property" \
  "$(grep -c 'property bool settled: false' "$overlay_qml")" "1"
check "Wave's 16ms Timer is gated by !waveCanvas.settled, not just visible" \
  "$(grep -c 'running: waveCanvas.visible && !waveCanvas.settled' "$overlay_qml")" "1"
check "a Connections listener on feed.onLevelsChanged wakes the timer" \
  "$(grep -A6 'Connections {' "$overlay_qml" | grep -c 'function onLevelsChanged() {')" "1"
check "the wake listener un-settles rather than repainting directly" \
  "$(grep -A8 'function onLevelsChanged() {' "$overlay_qml" | grep -c 'waveCanvas.settled = false')" "1"
check "tick() only repaints when something actually changed" \
  "$(grep -c 'if (changed) waveCanvas.requestPaint()' "$overlay_qml")" "1"
check "tick() snaps fully-decayed values to an exact 0, so settled can cleanly become true" \
  "$(grep -c 'if (t === 0 && Math.abs(next) < 0.01) next = 0' "$overlay_qml")" "1"
check "tick() writes back the computed settled state" \
  "$(grep -c 'waveCanvas.settled = isSettled' "$overlay_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
