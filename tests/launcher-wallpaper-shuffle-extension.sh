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
search_header_qml="$repo_dir/ruixen.launcher/SearchHeader.qml"
rotation_qml="$repo_dir/ruixen.wallpaper/WallpaperRotation.qml"

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

check "the detail panel imports QtQuick.Effects for the preview's rounded-corner mask" \
  "$(grep -Fc 'import QtQuick.Effects' "$details_qml")" "1"

check "the preview image is masked (genuinely rounded corners), not just clipped (clip never rounds a child Image -- confirmed elsewhere in this repo)" \
  "$(grep -Fc 'maskSource: previewMask' "$details_qml")" "1"

check "the mask's radius is bound to the preview box's own radius, not a separate constant that could drift" \
  "$(grep -Fc 'radius: previewBox.radius' "$details_qml")" "1"

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

# Issue #105: no longer a hand-maintained third copy in this checkout --
# ruixen.wallpaper/WallpaperRotationState.qml is the one real copy now,
# deployed here by install.sh's own inject_shared_wallpaper_files at
# install time (proven against the real install.sh in
# tests/install-shared-wallpaper-files.sh, not just asserted here).
check "this extension no longer carries its own hand-maintained copy of WallpaperRotationState.qml in the checkout" \
  "$([[ -f "$repo_dir/ruixen.launcher/extensions/wallpaper-shuffle/WallpaperRotationState.qml" ]] && echo yes || echo no)" "no"
check "the one real copy lives under ruixen.wallpaper/ instead" \
  "$([[ -f "$repo_dir/ruixen.wallpaper/WallpaperRotationState.qml" ]] && echo yes || echo no)" "yes"

check "the left-edge icon has a per-kind default (video/gif/image), not one glyph for every row" \
  "$(grep -Fc 'function kindIcon(kind)' "$content_qml")" "1"

check "video and gif each branch to their own glyph in kindIcon, not falling through to the same default" \
  "$(grep -A4 'function kindIcon(kind)' "$content_qml" | grep -Fc 'kind === "video"')" "1"

check "rowIcon forwards kind through to kindIcon for the plain (non-current, non-ignored) case" \
  "$(grep -Fc 'return root.kindIcon(kind)' "$content_qml")" "1"

check "the row builder actually passes each entry's own kind, not a hardcoded default" \
  "$(grep -Fc 'root.rowIcon(isCurrent, ignored, e.kind)' "$content_qml")" "1"

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

# Issue #104: the ternary chain this pinned became a plain id -> Item map
# (extensionContentById) -- see Launcher.qml's own comment on why that
# one-line-per-extension wiring is still needed even with the registry.
check "Launcher.qml's activeExtensionContent dispatch includes wallpaper-shuffle" \
  "$(grep -Fc '"wallpaper-shuffle": wallpaperShuffleContent' "$launcher_qml")" "1"

check "the extension is instantiated in the content area" \
  "$(grep -c 'WallpaperShuffleContent {' "$launcher_qml")" "1"

check "the rotation service tracks when the clock will next fire" \
  "$(grep -Fc 'property real nextRotationAt: 0' "$rotation_qml")" "1"

check "nextRotationAt is reset to 0 (not left stale) whenever the clock stops" \
  "$(grep -A8 'function resetClock' "$rotation_qml" | grep -Fc 'nextRotationAt = 0')" "1"

check "nextRotationAt is exposed through the status IPC, so other extensions can poll it" \
  "$(grep -Fc 'nextRotationAt:root.nextRotationAt' "$rotation_qml")" "1"

check "the extension computes a live Shuffle hint text (countdown or Paused)" \
  "$(grep -Fc 'readonly property string shuffleHintText' "$content_qml")" "1"

check "the hint reads Paused whenever Shuffle is off or genuinely paused, not a frozen/negative countdown" \
  "$(grep -Fc 'rotationState.settings.enabled !== true || rotationState.settings.paused === true) return "Paused"' "$content_qml")" "1"

check "SearchHeader exposes a per-mode override for its Enter-hint chip" \
  "$(grep -Fc 'property string settingsHintOverrideText: ""' "$search_header_qml")" "1"

check "the Enter-hint chip falls back to the plain glyph when no mode supplies an override" \
  "$(grep -Fc 'visible: root.settingsHintOverrideText === ""' "$search_header_qml")" "1"

check "Launcher.qml wires the Shuffle hint text into the chip only while Wallpaper Shuffle is the active extension" \
  "$(grep -Fc 'settingsHintOverrideText: root.activeExtensionId === "wallpaper-shuffle" ? wallpaperShuffleContent.shuffleHintText : ""' "$launcher_qml")" "1"

check "the countdown/Paused chip reads accent color, not muted -- direct report: \"the clock and pause is abit hard to read\"" \
  "$(grep -A4 'id: settingsHintOverrideLabel' "$search_header_qml" | grep -Fc 'color: root.accentColor')" "1"

check "the chip's own background/border tint accent too whenever an override is showing, not just the text" \
  "$(grep -Fc 'root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18' "$search_header_qml")" "1"

check "Launcher.qml wires accentColor into SearchHeader" \
  "$(awk '/^      SearchHeader \{/,/^      \}/' "$launcher_qml" | grep -Fc 'accentColor: root.accent')" "1"

# Direct follow-up: "for the other preview images can we show the
# Position. so Current then the next one in rotation is 2 then 3 then
# 4 etc" -- a plain rotation-order number on the row itself, not parsed
# back out of breadcrumb's own "N of M" text, and a matching badge for
# every row but the current wallpaper (position 1, which keeps the
# existing CURRENT badge instead).
check "Each row carries its own plain rotation-order position" \
  "$(grep -Fc 'position: i + 1' "$content_qml")" "1"
check "Preview shows a position badge for every row except the current one" \
  "$(( $(grep -Fc 'visible: !root.isCurrent && !!root.row' "$details_qml") + $(grep -Fc 'text: root.row ? String(root.row.position) : ""' "$details_qml") ))" "2"
check "Position badge sits in the same corner as CURRENT, muted/outlined rather than accent-filled so CURRENT still reads as the active one" \
  "$(( $(grep -c 'anchors.top: parent.top' "$details_qml") + $(grep -c 'anchors.right: parent.right' "$details_qml") + $(grep -Fc 'color: Qt.rgba(0, 0, 0, 0.55)' "$details_qml") ))" "6"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
