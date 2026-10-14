#!/usr/bin/env bash
# Covers issue #103: a few always-on recurring Timers kept spawning
# subprocesses (or just kept ticking) regardless of whether the state
# they existed to catch was even possible at that moment.
#
# Three specific cases fixed:
#
# 1. ruixen.wallpaper/Service.qml's 1s readCurrentBgProc poll used to
#    run: true unconditionally, with the actual "is this even worth
#    checking" guard buried inside onTriggered -- the Timer itself still
#    ticked once a second forever even with no video/gif active. Now
#    gated on `running: root.videoPath !== "" || root.gifPath !== ""`,
#    same pattern this repo already uses elsewhere for this exact class
#    of fix (see tests/cava-idle-quiesce.sh for the precedent).
#
# 2. ruixen.background/Service.qml's 2s readlink safety-net poll (~1,800
#    spawns/hour while the native renderer is enabled, even completely
#    idle) was slowed to 15s. This one isn't gated on a boolean -- it's
#    a safety net for a background change that bypassed both of this
#    service's own normal paths (its own set()/transition() IPC methods,
#    or omarchy-theme-bg-set's `omarchy-shell -q background set` call),
#    which is rare enough that a long interval costs nothing real. A
#    file-watch alternative was tried and rejected: an isolated
#    Quickshell FileView probe against a symlink confirmed watchChanges
#    does not reliably refire after that same symlink's target is later
#    atomically replaced (ln -nsf, what every writer here does) --only
#    the first real change (nonexistent -> existing) was ever observed.
#
# 3. bars/widgets/ruixen.quickactions/QuickActions.qml's recording-status
#    Timer ran unconditionally every 2s even while its own popup was
#    closed, even though root.recording only ever feeds the popup's own
#    Screen Recording row (the always-visible bar button stopped
#    reflecting it a while back -- see that button's own comment). Now
#    gated on `running: root.popupOpen`.
#
# Static QML checks only, same reasoning as cava-idle-quiesce.sh's own
# header. Live CPU/spawn-rate comparisons were not re-measured here;
# the wallpaper/quickactions cases are boolean-gated Timers (the exact
# shape already validated live in #70), and the background interval
# change is a plain constant with no new conditional logic to verify
# behaviorally live.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
wallpaper_service="$repo_dir/ruixen.wallpaper/Service.qml"
background_service="$repo_dir/ruixen.background/Service.qml"
quickactions_qml="$repo_dir/bars/widgets/ruixen.quickactions/QuickActions.qml"

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

# --- ruixen.wallpaper/Service.qml: readCurrentBgProc Timer is gated ---

check "readCurrentBgProc's own Timer is gated on videoPath/gifPath, not unconditional" \
  "$(grep -c 'running: root.videoPath !== "" || root.gifPath !== ""' "$wallpaper_service")" "1"
check "onTriggered no longer needs its own redundant active-state check" \
  "$(grep -A2 'onTriggered: {' "$wallpaper_service" | grep -c 'videoPath !== "" || root.gifPath !== ""')" "0"

# --- ruixen.background/Service.qml: refresh() poll interval is slow --

check "the readlink safety-net Timer is no longer a 2000ms interval" \
  "$(grep -c 'interval:2000' "$background_service")" "0"
check "the readlink safety-net Timer still exists, now much slower" \
  "$(grep -c 'interval:15000; repeat:true; running:true; onTriggered:root.refresh()' "$background_service")" "1"

# --- QuickActions.qml: recording poll Timer is gated on popupOpen ----

check "the recording-status Timer is gated on popupOpen, not unconditional" \
  "$(grep -B3 'onTriggered: root.refreshRecording()' "$quickactions_qml" | grep -c 'running: root.popupOpen')" "1"
check "Component.onCompleted still does an immediate refresh regardless" \
  "$(grep -A3 'Component.onCompleted: {' "$quickactions_qml" | grep -c 'refreshRecording()')" "1"
check "onPopupOpenChanged still does an immediate refresh when opened" \
  "$(grep -A3 'onPopupOpenChanged: if (popupOpen) {' "$quickactions_qml" | grep -c 'refreshRecording()')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
