#!/usr/bin/env bash
# Direct ask: "on the notch wallpaper panel, next to the Top arrow
# that comes active when we scroll, to the left of it, can you add
# the wallpaper shuffle icon there and then clicking it would open
# the wallpaper shuffle extension from the expanded notch".
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

check "the jump button sits before (left of, in a left-to-right RowLayout) the Back to top button" \
  "$(awk '/id: openWallpaperShuffleButton/ { found = 1 } found && /id: backToTopButton/ { print "yes"; exit }' "$wallpapers_qml")" "yes"

check "the jump button only shows in wallpapers mode, not themes" \
  "$(grep -A1 'id: openWallpaperShuffleButton' "$wallpapers_qml" | grep -Fc 'visible: root.mediaMode === "wallpapers"')" "1"

check "clicking it runs the launcher jump AND bubbles a close-notch signal, not just one or the other" \
  "$(grep -A4 'onClicked: {' "$wallpapers_qml" | grep -c 'openWallpaperShuffleProc.running = true\|root.openWallpaperShuffleRequested()')" "2"

check "the jump targets the Wallpaper Shuffle extension specifically, same toggle+payload shape the launcher's own keybind recipes use" \
  "$(grep -Fc 'command: ["omarchy-shell", "shell", "toggle", "ruixen.launcher", "{\"extension\":\"wallpaper-shuffle\"}"]' "$wallpapers_qml")" "1"

check "the jump goes through omarchy-shell, not a raw IPC call (resolved OMARCHY_PATH, a real timeout)" \
  "$(grep -A2 'id: openWallpaperShuffleProc' "$wallpapers_qml" | grep -Fc '"omarchy-shell"')" "1"

check "Overlay.qml collapses the notch when the jump fires, so the launcher doesn't open with the notch still expanded underneath it" \
  "$(grep -Fc 'onOpenWallpaperShuffleRequested: panel.pinnedOpen = false' "$overlay_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
