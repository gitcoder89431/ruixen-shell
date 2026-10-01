#!/usr/bin/env bash
# Static UI contract for the expanded-notch wallpaper layout. The
# picker/discovery logic itself is covered by wallpaper-discovery-format.sh;
# this pins the top-row Back-to-top affordance and the responsive
# wallpaper grid sizing that replaced the old right-sidebar stat cards.
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

check "WallpapersContent exposes a secondary color token for the Top affordance" \
  "$(grep -c 'property color secondary: accent' "$wallpapers_qml")" "1"
check "Overlay reads the active theme's secondary color" \
  "$(grep -c 'themeSecondaryColor = root.parseCavaThemeColor(t, "secondary", Color.accent)' "$overlay_qml")" "1"
check "Overlay passes theme secondary into WallpapersContent" \
  "$(grep -A8 'WallpapersContent {' "$overlay_qml" | grep -c 'secondary: root.themeSecondaryColor')" "1"
# The old image/video/gif count tiles are gone -- direct follow-up
# ("convert that side panel stuff we have into the chips here instead
# for wallpaper"): the kind filter moved to the shared top chip row
# (plain All/Images/Video/Gif labels, no counts, same style as the
# Theme-mode Omarchy/Custom chips it shares a row with), and the
# Back-to-top affordance moved into that row too.
check "back-to-top arrow uses secondary at rest and accent on hover" \
  "$(grep -A8 'text: "↑"' "$wallpapers_qml" | grep -c 'color: backToTopArea.containsMouse ? root.accent : root.secondary')" "1"
check "chip row keeps the same right inset as the search/tab row" \
  "$(awk 'index($0, "activeFilterChips/activeFilterValue") { in_block = 1 } in_block && /Layout.rightMargin: 12/ { count++ } in_block && /id: backToTopButton/ { in_block = 0 } END { print count + 0 }' "$wallpapers_qml")" "1"
check "wallpaper grid wrapper fills the row like the theme grid" \
  "$(grep -A10 'id: wallpaperGridWrap' "$wallpapers_qml" | grep -c 'Layout.fillWidth: true')" "1"
check "wallpaper grid derives columns from the wrapper width" \
  "$(grep -c 'readonly property int columns: Math.max(1, Math.floor(wallpaperGridWrap.width / 170))' "$wallpapers_qml")" "1"
check "wallpaper grid stretches tile width from the wrapper, not a fixed 160px tile" \
  "$(grep -c 'readonly property int tileWidth: Math.max(160, Math.floor(wallpaperGridWrap.width / grid.columns) - 10)' "$wallpapers_qml")" "1"
check "wallpaper grid centers exactly columns*cellWidth like the theme grid" \
  "$(grep -c 'Layout.preferredWidth: grid.columns \* grid.cellWidth' "$wallpapers_qml")" "1"
check "tests/run-all.sh runs this suite" \
  "$(grep -c 'wallpaper-sidebar-style\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
