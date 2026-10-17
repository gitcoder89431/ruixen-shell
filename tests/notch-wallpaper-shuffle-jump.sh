#!/usr/bin/env bash
# Direct ask: "on the notch wallpaper panel, next to the Top arrow
# that comes active when we scroll, to the left of it, can you add
# the wallpaper shuffle icon there and then clicking it would open
# the wallpaper shuffle extension from the expanded notch". Direct
# follow-up: "can we do one for the wallpapers effect icon too that
# does that so users know we have these 2 other menus" -- same shape,
# the launcher's Wallpapers Effects extension, placed one step further
# left so Wallpaper mode's row reads left-to-right as [Wallpapers
# Effects] [Wallpaper Shuffle] [Back to top]. One more direct
# follow-up: "for the theme, next to that up button we can add icon
# to the bjaneo themes too" -- Theme mode's own equivalent, [Bjarneo
# Themes] [Back to top], mutually exclusive with the two wallpaper
# buttons (mediaMode is never both at once).
#
# Can't drive a real Quickshell instance here (no compositor in CI),
# so this is a static invariant check against the actual source, same
# style as tests/wallpaper-sidebar-style.sh's own pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
wallpapers_qml="$repo_dir/bars/widgets/ruixen.notch/WallpapersContent.qml"
# These close-requests are wired on the window content now --
# see NotchWindow.qml's own header.
notch_window_qml="$repo_dir/bars/widgets/ruixen.notch/NotchWindow.qml"

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

check "both wallpaper jump buttons only show in wallpapers mode, not themes" \
  "$(( $(grep -A1 'id: openWallpaperEffectsButton' "$wallpapers_qml" | grep -Fc 'visible: root.mediaMode === "wallpapers"') + $(grep -A1 'id: openWallpaperShuffleButton' "$wallpapers_qml" | grep -Fc 'visible: root.mediaMode === "wallpapers"') ))" "2"

check "the Bjarneo Themes jump button sits before (left of) Back to top" \
  "$(awk '/id: openThemeBrowserButton/ { found = 1 } found && /id: backToTopButton/ { print "yes"; exit }' "$wallpapers_qml")" "yes"

check "the Bjarneo Themes jump button only shows in themes mode, not wallpapers" \
  "$(grep -A1 'id: openThemeBrowserButton' "$wallpapers_qml" | grep -Fc 'visible: root.mediaMode === "themes"')" "1"

check "clicking Wallpaper Shuffle's button runs the launcher jump AND bubbles a close-notch signal, not just one or the other" \
  "$(grep -A4 'onClicked: {' "$wallpapers_qml" | grep -c 'openWallpaperShuffleProc.running = true\|root.openWallpaperShuffleRequested()')" "2"

check "clicking Wallpapers Effects' button runs the launcher jump AND bubbles a close-notch signal too" \
  "$(grep -A4 'onClicked: {' "$wallpapers_qml" | grep -c 'openWallpaperEffectsProc.running = true\|root.openWallpaperEffectsRequested()')" "2"

check "clicking Bjarneo Themes' button runs the launcher jump AND bubbles a close-notch signal too" \
  "$(grep -A4 'onClicked: {' "$wallpapers_qml" | grep -c 'openThemeBrowserProc.running = true\|root.openThemeBrowserRequested()')" "2"

check "Wallpaper Shuffle's jump targets that extension specifically, same toggle+payload shape the launcher's own keybind recipes use" \
  "$(grep -Fc 'command: ["omarchy-shell", "shell", "toggle", "ruixen.launcher", "{\"extension\":\"wallpaper-shuffle\"}"]' "$wallpapers_qml")" "1"

check "Wallpapers Effects' jump targets the \"wallpapers\" extension id -- the rename to \"Wallpapers Effects\" was display-text only, the real id never changed" \
  "$(grep -Fc 'command: ["omarchy-shell", "shell", "toggle", "ruixen.launcher", "{\"extension\":\"wallpapers\"}"]' "$wallpapers_qml")" "1"

check "Bjarneo Themes' jump targets the \"theme-browser\" extension id" \
  "$(grep -Fc 'command: ["omarchy-shell", "shell", "toggle", "ruixen.launcher", "{\"extension\":\"theme-browser\"}"]' "$wallpapers_qml")" "1"

check "all three jumps go through omarchy-shell, not a raw IPC call (resolved OMARCHY_PATH, a real timeout)" \
  "$(( $(grep -A2 'id: openWallpaperShuffleProc' "$wallpapers_qml" | grep -Fc '"omarchy-shell"') + $(grep -A2 'id: openWallpaperEffectsProc' "$wallpapers_qml" | grep -Fc '"omarchy-shell"') + $(grep -A2 'id: openThemeBrowserProc' "$wallpapers_qml" | grep -Fc '"omarchy-shell"') ))" "3"

check "Overlay.qml collapses the notch when any of the three jumps fire, so the launcher doesn't open with the notch still expanded underneath it" \
  "$(( $(grep -Fc 'onOpenWallpaperShuffleRequested: panel.notchRoot.pinnedOpen = false' "$notch_window_qml") + $(grep -Fc 'onOpenWallpaperEffectsRequested: panel.notchRoot.pinnedOpen = false' "$notch_window_qml") + $(grep -Fc 'onOpenThemeBrowserRequested: panel.notchRoot.pinnedOpen = false' "$notch_window_qml") ))" "3"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
