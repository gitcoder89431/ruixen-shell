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

check "Launcher.qml imports the extension folder" \
  "$(grep -c 'import "extensions/wallpaper-shuffle"' "$launcher_qml")" "1"

check "Launcher.qml's activeExtensionContent dispatch includes wallpaper-shuffle" \
  "$(grep -Fc 'root.activeExtensionId === "wallpaper-shuffle" ? wallpaperShuffleContent' "$launcher_qml")" "1"

check "the extension is instantiated in the content area" \
  "$(grep -c 'WallpaperShuffleContent {' "$launcher_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
