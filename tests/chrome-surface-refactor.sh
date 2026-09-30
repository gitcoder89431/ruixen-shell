#!/usr/bin/env bash
# Contract for the dock/frame chrome refactor bridge: BarPanel still owns
# widget layout, but publishes per-screen dock geometry for FrameWindow to
# consume before any visual chrome is moved across surfaces.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
bar_qml="$repo_dir/bars/v2/ruixen.bar/Bar.qml"
frame_qml="$repo_dir/bars/v2/ruixen.bar/FrameWindow.qml"
barpanel_qml="$repo_dir/bars/v2/ruixen.bar/BarPanel.qml"
run_all="$repo_dir/tests/run-all.sh"

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

check "root stores dock chrome metrics per screen, not as one global scalar" \
  "$(grep -c 'property var dockChromeMetricsByScreen: ({})' "$bar_qml")" "1"

check "root exposes a serial so var-map metric updates notify frame bindings" \
  "$(grep -c 'property int dockChromeMetricsSerial: 0' "$bar_qml")" "1"

check "frame is the single active owner for dock chrome visuals" \
  "$(grep -c 'readonly property bool frameOwnsDockChrome: true' "$bar_qml")" "1"

check "dock chrome metrics are keyed by the real layer-window screen name" \
  "$(grep -c 'function screenNameForWindow(window)' "$bar_qml")" "1"

check "publishing dock metrics copies the map before replacing one screen entry" \
  "$(( $(grep -A18 'function publishDockChromeMetrics' "$bar_qml" | grep -F -c 'var next = {}') + $(grep -A18 'function publishDockChromeMetrics' "$bar_qml" | grep -F -c 'next[existing] = root.dockChromeMetricsByScreen[existing]') + $(grep -A22 'function publishDockChromeMetrics' "$bar_qml" | grep -F -c 'root.dockChromeMetricsByScreen = next') ))" "3"

check "FrameWindow consumes the same per-screen dock metric channel" \
  "$(( $(grep -c 'dockChromeScreenName: barRoot.screenNameForWindow(frameWindow)' "$frame_qml") + $(grep -c 'dockChromeSerial: barRoot.dockChromeMetricsSerial' "$frame_qml") + $(grep -c 'return barRoot.dockChromeMetrics(dockChromeScreenName)' "$frame_qml") ))" "3"

check "FrameWindow renders the dock chrome skin from published metrics" \
  "$(( $(grep -c 'x: frameWindow.barRoot.frameInset - frameWindow.barRoot.seamOverlap' "$frame_qml") + $(grep -c 'width: frameWindow.dockChromeMetrics.screenWidth + frameWindow.barRoot.seamOverlap' "$frame_qml") + $(grep -c 'readonly property int leftWidth: frameWindow.dockChromeMetrics.leftWidth + dockChrome.overlap' "$frame_qml") + $(grep -c 'readonly property int rightX: frameWindow.dockChromeMetrics.rightX + dockChrome.overlap' "$frame_qml") ))" "4"

check "FrameWindow dock chrome is painted as one continuous canvas path, not stacked patches" \
  "$(( $(grep -c 'function dockPath' "$frame_qml") + $(grep -c 'id: dockChromeFillCanvas' "$frame_qml") + $(grep -c 'ctx.arc(leftEnd' "$frame_qml") + $(grep -c 'ctx.arc(rightStart' "$frame_qml") + $(grep -c 'ctx.quadraticCurveTo(leftEnd' "$frame_qml") + $(grep -c 'ctx.quadraticCurveTo(rightStart' "$frame_qml") ))" "6"

check "FrameWindow dock chrome path owns overlap" \
  "$(( $(grep -c 'readonly property int overlap: frameWindow.barRoot.seamOverlap' "$frame_qml") + $(grep -c -- '-dockChrome.overlap' "$frame_qml") ))" "3"

check "dock chrome shadow is enabled but clipped out of the frame's own border strip when docked at the top" \
  "$(( $(grep -A5 'id: dockChromeShadowCanvas' "$frame_qml" | grep -c 'visible: true') + $(grep -c 'anchors.topMargin: frameWindow.barRoot.integratedTopDockSurface ? frameWindow.barRoot.frameInset : -40' "$frame_qml") + $(grep -c 'ctx.translate(40, frameWindow.barRoot.integratedTopDockSurface ? -frameWindow.barRoot.frameInset : 40)' "$frame_qml") ))" "3"

check "old BarPanel dock chrome layers are disabled while frame owns the skin" \
  "$(( $(grep -A3 'id: leftShoulderShadowClip' "$barpanel_qml" | grep -c 'visible: !barWindow.barRoot.frameOwnsDockChrome') + $(grep -A3 'id: rightShoulderShadowClip' "$barpanel_qml" | grep -c 'visible: !barWindow.barRoot.frameOwnsDockChrome') + $(grep -A3 'id: dockedShoulderShadow' "$barpanel_qml" | grep -c 'visible: !barWindow.barRoot.frameOwnsDockChrome') ))" "3"

check "old BarPanel seam-cover strips are disabled while frame owns dock chrome" \
  "$(grep -c 'visible: barWindow.barRoot.docked && barWindow.barRoot.position === "top" && !barWindow.barRoot.frameOwnsDockChrome' "$barpanel_qml")" "3"

check "horizontal dock layout publishes measured left and right extents" \
  "$(( $(grep -A30 'id: horizontalBarRoot' "$barpanel_qml" | grep -c 'leftWidth: settingsPill.x + settingsPill.width') + $(grep -A30 'id: horizontalBarRoot' "$barpanel_qml" | grep -c 'rightX: rightDockedBg.x') + $(grep -A30 'id: horizontalBarRoot' "$barpanel_qml" | grep -c 'rightWidth: horizontalBarRoot.width - rightDockedBg.x') ))" "3"

# The docked/top guard lives in publishDockChromeMetricsNow() (the
# actual publish), not publishDockChromeMetrics() itself -- that
# wrapper now also restarts a settle-recheck Timer (see its own
# comment: a live-reload race where a late-settling widget's width
# change could land after the last onXChanged/onWidthChanged fired,
# permanently freezing the chrome one step short of the real width).
check "dock metric publishing is scoped to top docked mode only for this first refactor slice" \
  "$(grep -A5 'function publishDockChromeMetricsNow()' "$barpanel_qml" | grep -c 'if (!barWindow.barRoot.docked || barWindow.barRoot.position !== "top") return')" "1"

# The settle timer's own lifecycle safety -- direct live report after a
# rapid-fire live-reload stress test crashed the whole bar: a Timer
# left ticking past its own parent's destruction threw repeated
# "attempted to evaluate a function in an invalid context" errors.
# Component.onDestruction must stop it before that window opens.
check "the dock chrome settle timer is explicitly stopped before its own Item is destroyed" \
  "$(grep -c 'Component.onDestruction: settleTimer.stop()' "$barpanel_qml")" "1"

check "dock metric updates are triggered by both left and right dock geometry changes" \
  "$(( $(grep -A5 'id: leftDockedBg' "$barpanel_qml" | grep -c 'onWidthChanged: horizontalBarRoot.publishDockChromeMetrics') + $(grep -A8 'id: rightDockedBg' "$barpanel_qml" | grep -c 'horizontalBarRoot.publishDockChromeMetrics') + $(grep -A20 'id: trayPill' "$barpanel_qml" | grep -c 'horizontalBarRoot.publishDockChromeMetrics') ))" "5"

# shellcheck disable=SC2016 # deliberately literal: expected run-all entry contains $script_dir.
check "tests/run-all.sh runs this suite" \
  "$(grep -m1 'chrome-surface-refactor.sh' "$run_all")" \
  '  "$script_dir/chrome-surface-refactor.sh"'

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
