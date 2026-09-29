#!/usr/bin/env bash
# Guards the notch Wallpapers tab's Theme mode: a WALLPAPER/THEME sliding
# tab that shares one row with the search box, search on the left and the
# tab pill on the right (through several direct follow-ups -- two stacked
# rows collapsed into one, two separate chips merged into one sliding
# pill, then the pill moved from before the search box to after it) --
# plus the SUPER+CTRL+SPACE keybind that summons the tab (toggleWallpapers).
# Three layers must stay in agreement or the feature silently breaks
# somewhere:
#   - bars/widgets/ruixen.notch/list-themes.sh -- the shipped discovery
#     script the live picker AND this test both run (same
#     extract-so-tests-cannot-drift rationale as
#     tests/wallpaper-discovery-format.sh, #17),
#   - WallpapersContent.qml / Overlay.qml -- the sliding tab, the
#     theme grid, the placeholder swap, and the IPC toggle,
#   - install.sh -- the recommended-keybind wiring.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
list_themes="$repo_dir/bars/widgets/ruixen.notch/list-themes.sh"
content_qml="$repo_dir/bars/widgets/ruixen.notch/WallpapersContent.qml"
overlay_qml="$repo_dir/bars/widgets/ruixen.notch/Overlay.qml"
install_sh="$repo_dir/install.sh"
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

# --- The shipped discovery script, run for real against a fixture -----
# Fixture layout exercises every preview rule the script implements:
#   alpha  -- user theme with its own preview.png
#   beta   -- user theme with only backgrounds/ images (falls through
#             to the first sorted background)
#   gamma  -- user theme with NO preview of its own, same-name system
#             theme WITH one (falls back to the system copy)
#   delta  -- system-only theme
#   shared -- exists in BOTH dirs with different previews (one record,
#             user copy wins)
US=$'\x1f'
fake_home="$(mktemp -d)"
fake_omarchy="$(mktemp -d)"
trap 'rm -rf "$fake_home" "$fake_omarchy"' EXIT

mkdir -p "$fake_home/.config/omarchy/themes/alpha"
printf 'png' > "$fake_home/.config/omarchy/themes/alpha/preview.png"
mkdir -p "$fake_home/.config/omarchy/themes/beta/backgrounds"
printf 'png' > "$fake_home/.config/omarchy/themes/beta/backgrounds/zzz-late.png"
printf 'png' > "$fake_home/.config/omarchy/themes/beta/backgrounds/aaa-early.jpg"
mkdir -p "$fake_home/.config/omarchy/themes/gamma"
mkdir -p "$fake_home/.config/omarchy/themes/shared"
printf 'png' > "$fake_home/.config/omarchy/themes/shared/preview.png"
mkdir -p "$fake_omarchy/themes/gamma"
printf 'png' > "$fake_omarchy/themes/gamma/preview.jpeg"
mkdir -p "$fake_omarchy/themes/delta"
printf 'png' > "$fake_omarchy/themes/delta/preview.png"
mkdir -p "$fake_omarchy/themes/shared"
printf 'png' > "$fake_omarchy/themes/shared/preview.png"
# decoys that must never appear: non-image preview names are only
# matched by the exact extension list, and dot-dirs are not themes.
mkdir -p "$fake_home/.config/omarchy/themes/.hidden"

out="$(HOME="$fake_home" OMARCHY_PATH="$fake_omarchy" bash "$list_themes")"

check "list-themes.sh lists every theme exactly once" \
  "$(printf '%s\n' "$out" | grep -c 'delta\|alpha\|beta\|gamma\|shared')" "5"

check "list-themes.sh emits name<US>display<US>preview with title-cased display" \
  "$(printf '%s\n' "$out" | grep -F "alpha${US}Alpha${US}$fake_home/.config/omarchy/themes/alpha/preview.png")" \
  "alpha${US}Alpha${US}$fake_home/.config/omarchy/themes/alpha/preview.png"

check "list-themes.sh title-cases multi-word names" \
  "$(printf '%s\n' "$out" | grep -oF "delta${US}Delta${US}$fake_omarchy/themes/delta/preview.png")" \
  "delta${US}Delta${US}$fake_omarchy/themes/delta/preview.png"

check "list-themes.sh falls back to first sorted background" \
  "$(printf '%s\n' "$out" | grep -F "beta${US}Beta${US}$fake_home/.config/omarchy/themes/beta/backgrounds/aaa-early.jpg")" \
  "beta${US}Beta${US}$fake_home/.config/omarchy/themes/beta/backgrounds/aaa-early.jpg"

check "list-themes.sh falls back to same-name system preview" \
  "$(printf '%s\n' "$out" | grep -F "gamma${US}Gamma${US}$fake_omarchy/themes/gamma/preview.jpeg")" \
  "gamma${US}Gamma${US}$fake_omarchy/themes/gamma/preview.jpeg"

check "list-themes.sh user preview wins over system" \
  "$(printf '%s\n' "$out" | grep -oF "shared${US}Shared${US}$fake_home/.config/omarchy/themes/shared/preview.png")" \
  "shared${US}Shared${US}$fake_home/.config/omarchy/themes/shared/preview.png"

check "list-themes.sh skips dot-dirs" \
  "$(printf '%s\n' "$out" | grep -c 'hidden')" "0"

# --- The picker QML ----------------------------------------------------
check "WallpapersContent carries the mediaMode state" \
  "$(grep -c 'property string mediaMode: "wallpapers"' "$content_qml")" "1"

check "sliding tab offers both switchers" \
  "$(grep -c '"WALLPAPER"\|"THEME"' "$content_qml")" "2"

check "search box sits ahead of the mode tab in the layout (tab on the right)" \
  "$(awk 'BEGIN{box=0;tab=0} /id: searchInput/ && box==0 {box=NR} /id: modeTab/ && tab==0 {tab=NR} END{if (box>0 && tab>0 && box<tab) print "yes"; else print "no"}' "$content_qml")" "yes"

check "placeholder follows the mode" \
  "$(grep -c 'root.mediaMode === "themes" ? "Search themes..." : "Search wallpapers..."' "$content_qml")" "1"

check "theme discovery runs the shipped script, not an inline copy" \
  "$(grep -c 'ruixen.notch/list-themes.sh' "$content_qml")" "1"

check "applyTheme whitelists the theme name before it reaches argv" \
  "$(grep -cF '/^[A-Za-z0-9][A-Za-z0-9_-]*$/.test(entry.name)' "$content_qml")" "1"

check "applyTheme routes through the real omarchy-theme-set" \
  "$(grep -c 'themeSetProc.command = \["omarchy-theme-set", entry.name\]' "$content_qml")" "1"

check "theme click stops any playing video/gif with a fresh generation" \
  "$(grep -c '"ruixen.wallpaper", "stop", String(root.selectGeneration)' "$content_qml")" "1"

check "theme grid renders labels as PlainText" \
  "$(grep -c 'textFormat: Text.PlainText' "$content_qml" | awk '{print ($1 >= 2) ? "yes" : "no"}')" "yes"

check "theme grid shows only in theme mode" \
  "$(grep -c 'visible: root.mediaMode === "themes" && root.filteredThemes.length > 0' "$content_qml")" "1"

check "wallpaper block shows only in wallpaper mode" \
  "$(grep -c 'visible: root.mediaMode === "wallpapers"' "$content_qml")" "1"

check "theme grid fills the row instead of leaving a dead right strip" \
  "$(grep -c 'readonly property int columns: Math.max(1, Math.floor(themeGridWrap.width / 170))' "$content_qml")" "1"

check "theme grid width is exactly columns*cellWidth, not a smaller value that would undercount columns" \
  "$(grep -c 'width: themeGrid.columns \* themeGrid.cellWidth' "$content_qml")" "1"

check "theme grid is centered on its used width, not panel-wide" \
  "$(grep -c 'anchors.horizontalCenter: parent.horizontalCenter' "$content_qml")" "1"

check "theme tiles scale with the stretched cells" \
  "$(grep -c 'width: themeGrid.tileWidth' "$content_qml")" "1"

# --- The IPC toggle ----------------------------------------------------
check "Overlay exposes toggleWallpapers on the notch IPC target" \
  "$(grep -c 'function toggleWallpapers(): void' "$overlay_qml")" "1"

check "toggleWallpapers lands on the wallpapers tab when closed" \
  "$(grep -A2 'function toggleWallpapers' "$overlay_qml" | grep -c 'panel.dashboardTab = 1')" "1"

# --- The installer -----------------------------------------------------
check "install.sh recommends the wallpapers keybind" \
  "$(grep -c 'SUPER + CTRL + SPACE.*ruixen.notch toggleWallpapers' "$install_sh")" "1"

check "dry-run previews the wallpapers keybind too" \
  "$(grep -cF '"SUPER+CTRL+SPACE|SUPER+CTRL+SPACE -> Ruixen wallpapers"' "$install_sh")" "1"

check "suite is registered in run-all.sh" \
  "$(grep -c 'notch-theme-switcher.sh' "$run_all")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
