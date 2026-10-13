#!/usr/bin/env bash
# Static contract for the launcher's Wallpaper Shuffle extension --
# ordering the rotation queue, separate from the Wallpapers extension's
# own grid-based appearance panel (that layout is a real structural
# constraint for a reorderable list, per ExtensionTwoPanel.qml's own
# header comment calling Wallpapers out as "its own thing on purpose").
#
# Can't drive a real Quickshell instance here (no compositor in CI), so
# this is a static invariant check against the actual QML source, same
# style as tests/workspaces-pill-strict.sh's own pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
content_qml="$repo_dir/ruixen.launcher/extensions/wallpaper-shuffle/WallpaperShuffleContent.qml"
details_qml="$repo_dir/ruixen.launcher/extensions/wallpaper-shuffle/WallpaperQueueDetailsPanel.qml"
launcher_qml="$repo_dir/ruixen.launcher/Launcher.qml"

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

check "the extension's content file exists" \
  "$([[ -f "$content_qml" ]] && echo yes || echo no)" "yes"
check "the extension's detail panel exists" \
  "$([[ -f "$details_qml" ]] && echo yes || echo no)" "yes"

check "discovery reuses ruixen.notch's deployed list-wallpapers.sh, same cross-plugin path the Wallpapers extension already relies on" \
  "$(grep -c '/.config/omarchy/plugins/ruixen.notch' "$content_qml")" "1"

check "reordering writes the shared order file directly, no IPC round-trip" \
  "$(grep -c '.local/state/ruixen/wallpaper-order.json' "$content_qml")" "2"

check "Tab (focusRightPanel) opens the actions menu, not a second meaning of its own" \
  "$(grep -c 'function focusRightPanel' "$content_qml")" "1"

check "only legal directions are ever offered -- no disabled-but-visible Move up/down" \
  "$(grep -c 'if (root.selectedIndex > 0) out.push' "$content_qml")" "1"

check "applying a wallpaper dispatches by kind (video/gif/image), same three-way split WallpapersContent.qml's own select() uses" \
  "$(grep -c '"omarchy-shell", "ruixen.wallpaper", "playVideo"' "$content_qml")" "1"

check "ignoring writes the shared ignored file directly, no IPC round-trip" \
  "$(grep -c '.local/state/ruixen/wallpaper-ignored.json' "$content_qml")" "1"

check "the Tab menu's Ignore entry toggles its own label between Ignore and Un-ignore" \
  "$(grep -Fc 'Un-ignore" : "Ignore"' "$content_qml")" "1"

check "ignored wallpapers stay visible in the list (not hidden), so there's a way back to Un-ignore" \
  "$(grep -c 'ignored: ignored' "$content_qml")" "1"

check "rotation itself (not just the UI) excludes ignored wallpapers, both shuffle and sequential" \
  "$(grep -c 'def load_ignored' "$repo_dir/ruixen.wallpaper/wallpaper-rotation.py")" "1"

check "the extension carries its own copy of WallpaperRotationState.qml (third copy, same plugin-folders-can't-share-files convention)" \
  "$([[ -f "$repo_dir/ruixen.launcher/extensions/wallpaper-shuffle/WallpaperRotationState.qml" ]] && echo yes || echo no)" "yes"

check "the first chip is a merged Shuffle On/Off toggle, not a fifth peer interval option" \
  "$(grep -Fc 'text: shuffleToggleChip.on ? "On" : "Off"' "$content_qml")" "1"

check "the Shuffle side is a solid accent-filled segment, not just accent-colored text" \
  "$(grep -A3 'width: shuffleToggleChip.shuffleSegmentWidth' "$content_qml" | grep -Fc 'color: root.accent')" "1"

check "the Shuffle segment is independently rounded on all four corners, not clipped to a hard-cornered box (the seam curve depends on this)" \
  "$(grep -A3 'width: shuffleToggleChip.shuffleSegmentWidth' "$content_qml" | grep -Fc 'radius: 6')" "1"

check "the On/Off side stays a flat neutral segment, not accent -- the interval chips below are what carry the accent-means-selected look" \
  "$(grep -A8 'id: shuffleToggleStateLabel' "$content_qml" | grep -c 'root.accent')" "0"

check "the Shuffle toggle turns off when on, and resumes the last remembered interval when off" \
  "$(grep -Fc 'onClicked: shuffleToggleChip.on ? rotationState.turnOff() : rotationState.selectInterval(rotationState.settings.intervalMinutes || 15)' "$content_qml")" "1"

check "the interval chip row offers the same four interval options as the Wallpaper Appearance panel's own chips (5m/15m/30m/60m)" \
  "$(grep -Fc '{minutes: 5, label: "5m"}, {minutes: 15, label: "15m"},' "$content_qml")" "1"

check "interval chips drive rotationState.selectInterval(), the same IPC-backed call the Wallpaper Appearance panel's own chips use" \
  "$(grep -Fc 'onClicked: rotationState.selectInterval(intervalChip.modelData.minutes)' "$content_qml")" "1"

check "the chip row sits above the two-panel layout, not overlapping it" \
  "$(grep -Fc 'anchors.top: chipRow.bottom' "$content_qml")" "1"

check "Launcher.qml imports the extension folder" \
  "$(grep -c 'import "extensions/wallpaper-shuffle"' "$launcher_qml")" "1"

check "Launcher.qml's activeExtensionContent dispatch includes wallpaper-shuffle" \
  "$(grep -Fc 'root.activeExtensionId === "wallpaper-shuffle" ? wallpaperShuffleContent' "$launcher_qml")" "1"

check "the extension is instantiated in the content area" \
  "$(grep -c 'WallpaperShuffleContent {' "$launcher_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
