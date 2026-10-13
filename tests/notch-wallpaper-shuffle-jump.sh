#!/usr/bin/env bash
# Direct ask: "on the notch wallpaper panel, next to the Top arrow
# that comes active when we scroll, to the left of it, can you add
# the wallpaper shuffle icon there and then clicking it would open
# the wallpaper shuffle extension from the expanded notch". Direct
# follow-up: "can we do one for the wallpapers effect icon too that
# does that so users know we have these 2 other menus" -- same shape,
# the launcher's Wallpapers Effects extension, placed one step further
# left so the row reads left-to-right as [Wallpapers Effects]
# [Wallpaper Shuffle] [Back to top].
#
# Can't drive a real Quickshell instance here (no compositor in CI),
# so this is a static invariant check against the actual source, same
# style as tests/wallpaper-sidebar-style.sh's own pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
wallpapers_qml="$repo_dir/bars/widgets/ruixen.notch/WallpapersContent.qml"
overlay_qml="$repo_dir/bars/widgets/ruixen.notch/Overlay.qml"

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

check "the Wallpapers Effects jump button sits before (left of) the Wallpaper Shuffle jump button" \
  "$(awk '/id: openWallpaperEffectsButton/ { found = 1 } found && /id: openWallpaperShuffleButton/ { print "yes"; exit }' "$wallpapers_qml")" "yes"

check "the Wallpaper Shuffle jump button sits before (left of, in a left-to-right RowLayout) the Back to top button" \
  "$(awk '/id: openWallpaperShuffleButton/ { found = 1 } found && /id: backToTopButton/ { print "yes"; exit }' "$wallpapers_qml")" "yes"

check "both jump buttons only show in wallpapers mode, not themes" \
  "$(( $(grep -A1 'id: openWallpaperEffectsButton' "$wallpapers_qml" | grep -Fc 'visible: root.mediaMode === "wallpapers"') + $(grep -A1 'id: openWallpaperShuffleButton' "$wallpapers_qml" | grep -Fc 'visible: root.mediaMode === "wallpapers"') ))" "2"

check "clicking Wallpaper Shuffle's button runs the launcher jump AND bubbles a close-notch signal, not just one or the other" \
  "$(grep -A4 'onClicked: {' "$wallpapers_qml" | grep -c 'openWallpaperShuffleProc.running = true\|root.openWallpaperShuffleRequested()')" "2"

check "clicking Wallpapers Effects' button runs the launcher jump AND bubbles a close-notch signal too" \
  "$(grep -A4 'onClicked: {' "$wallpapers_qml" | grep -c 'openWallpaperEffectsProc.running = true\|root.openWallpaperEffectsRequested()')" "2"

check "Wallpaper Shuffle's jump targets that extension specifically, same toggle+payload shape the launcher's own keybind recipes use" \
  "$(grep -Fc 'command: ["omarchy-shell", "shell", "toggle", "ruixen.launcher", "{\"extension\":\"wallpaper-shuffle\"}"]' "$wallpapers_qml")" "1"

check "Wallpapers Effects' jump targets the \"wallpapers\" extension id -- the rename to \"Wallpapers Effects\" was display-text only, the real id never changed" \
  "$(grep -Fc 'command: ["omarchy-shell", "shell", "toggle", "ruixen.launcher", "{\"extension\":\"wallpapers\"}"]' "$wallpapers_qml")" "1"

check "both jumps go through omarchy-shell, not a raw IPC call (resolved OMARCHY_PATH, a real timeout)" \
  "$(( $(grep -A2 'id: openWallpaperShuffleProc' "$wallpapers_qml" | grep -Fc '"omarchy-shell"') + $(grep -A2 'id: openWallpaperEffectsProc' "$wallpapers_qml" | grep -Fc '"omarchy-shell"') ))" "2"

check "Overlay.qml collapses the notch when either jump fires, so the launcher doesn't open with the notch still expanded underneath it" \
  "$(( $(grep -Fc 'onOpenWallpaperShuffleRequested: panel.pinnedOpen = false' "$overlay_qml") + $(grep -Fc 'onOpenWallpaperEffectsRequested: panel.pinnedOpen = false' "$overlay_qml") ))" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
