#!/usr/bin/env bash
# Direct report: "can you make this show up in launcher search result,
# clipboard history, and bjaneo themes should show up too, we only have
# settings and wallpapers working on search lol" -- Cliamp Radio,
# Clipboard History and Bjarneo Themes each only ever appeared as a
# landing-list row (q === ""), never as a typed-query match, the exact
# gap Settings/Wallpapers already had their own synthetic
# OmarchyActionsProvider entries built to close (see
# launcher-extensions-frecency.sh's own header for that earlier fix).
# Same fix, same pattern, for the three remaining extensions.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
launcher_qml="$repo_dir/ruixen.launcher/Launcher.qml"
actions_qml="$repo_dir/ruixen.launcher/search/OmarchyActionsProvider.qml"

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

check "OmarchyActionsProvider has a synthetic ruixen.cliamp entry, same shape as ruixen.settings/ruixen.wallpapers" \
  "$(( $(grep -c '"ruixen.cliamp": {' "$actions_qml") + $(grep -c 'label: "Cliamp Radio"' "$actions_qml") + $(grep -c 'extension\\":\\"cliamp\\"' "$actions_qml") ))" "3"
check "OmarchyActionsProvider has a synthetic ruixen.clipboard entry" \
  "$(( $(grep -c '"ruixen.clipboard": {' "$actions_qml") + $(grep -c 'label: "Clipboard History"' "$actions_qml") + $(grep -c 'extension\\":\\"clipboard\\"' "$actions_qml") ))" "3"
check "OmarchyActionsProvider has a synthetic ruixen.theme-browser entry" \
  "$(( $(grep -c '"ruixen.theme-browser": {' "$actions_qml") + $(grep -c 'label: "Bjarneo Themes"' "$actions_qml") + $(grep -c 'extension\\":\\"theme-browser\\"' "$actions_qml") ))" "3"
check "OmarchyActionsProvider has a synthetic ruixen.wallpaper-shuffle entry" \
  "$(( $(grep -c '"ruixen.wallpaper-shuffle": {' "$actions_qml") + $(grep -c 'label: "Wallpaper Shuffle"' "$actions_qml") + $(grep -c 'extension\\":\\"wallpaper-shuffle\\"' "$actions_qml") ))" "3"
check "All four new synthetic entries are tagged Extension, same kind as every other extension row" \
  "$(grep -c 'kind: "Extension"' "$actions_qml")" "6"

check "Launcher.qml jumps in-process for the synthetic Cliamp Radio row, same as Settings/Wallpapers, instead of shelling out and closing itself" \
  "$(grep -A5 'result.id === "omarchy:ruixen.cliamp"' "$launcher_qml" | grep -c 'activeExtensionId = "cliamp"\|recordLaunch("ruixen.cliamp")')" "2"
check "Launcher.qml jumps in-process for the synthetic Clipboard History row" \
  "$(grep -A5 'result.id === "omarchy:ruixen.clipboard"' "$launcher_qml" | grep -c 'activeExtensionId = "clipboard"\|recordLaunch("ruixen.clipboard")')" "2"
check "Launcher.qml jumps in-process for the synthetic Bjarneo Themes row" \
  "$(grep -A5 'result.id === "omarchy:ruixen.theme-browser"' "$launcher_qml" | grep -c 'activeExtensionId = "theme-browser"\|recordLaunch("ruixen.theme-browser")')" "2"
check "Launcher.qml jumps in-process for the synthetic Wallpaper Shuffle row" \
  "$(grep -A5 'result.id === "omarchy:ruixen.wallpaper-shuffle"' "$launcher_qml" | grep -c 'activeExtensionId = "wallpaper-shuffle"\|recordLaunch("ruixen.wallpaper-shuffle")')" "2"

check "run-all includes the extension search discoverability contract" \
  "$(grep -c 'launcher-extension-search-discoverability\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
