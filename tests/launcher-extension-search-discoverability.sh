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
# Issue #104: label/icon/providerId/omarchyActionId for every extension's
# own landing row moved out of Launcher.qml into this registry -- see
# that file's own header. Checks below that used to grep Launcher.qml
# directly for these now grep here instead.
registry_js="$repo_dir/ruixen.launcher/extensions/ExtensionRegistry.js"

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
check "OmarchyActionsProvider has a synthetic ruixen.kanban entry" \
  "$(( $(grep -c '"ruixen.kanban": {' "$actions_qml") + $(grep -c 'label: "Kanban Board"' "$actions_qml") + $(grep -c 'extension\\":\\"kanban\\"' "$actions_qml") ))" "3"
check "Every synthetic extension entry (including the new Kanban Board one) is tagged Extension, same kind as every other extension row" \
  "$(grep -c 'kind: "Extension"' "$actions_qml")" "7"

check "the Wallpapers extension is renamed to Wallpapers Effects in both the registry and the search entry" \
  "$(( $(grep -Fc 'label: "Wallpapers Effects"' "$registry_js") + $(grep -Fc 'label: "Wallpapers Effects"' "$actions_qml") ))" "2"
check "the search entry's own aliases still include wallpaper/background, plus effects/fx for the new name" \
  "$(grep -Fc 'aliases: ["wallpaper", "background", "effects", "fx"]' "$actions_qml")" "1"

check "the ruixen.wallpaper-shuffle synthetic entry has a real icon, not an empty string -- direct follow-up after this entry already existed" \
  "$(grep -A1 '"ruixen.wallpaper-shuffle": {' "$actions_qml" | grep -Fc 'icon: "",')" "0"
check "ExtensionRegistry's own wallpaper-shuffle icon is non-empty too, same gap in the same two places (#104)" \
  "$(grep -A5 'id: "wallpaper-shuffle",' "$registry_js" | grep -Fc 'icon: "",')" "0"

# Issue #104: the 4 separate "result.id === omarchy:ruixen.X" branches
# these checks used to pin were replaced by one generic lookup
# (ExtensionRegistry.byOmarchyActionId) -- per-id correctness of that
# lookup is unit-tested directly in tests/js/ExtensionRegistry.test.js
# (byOmarchyActionId: finds the real entry / null for an unknown one).
# What's worth pinning here is that the generic mechanism itself is
# actually wired into activateSelected(), and that every extension this
# suite cares about really is registered under the omarchyActionId its
# own synthetic OmarchyActionsProvider row above uses -- so the generic
# lookup genuinely covers all four, not just some.
check "Launcher.qml resolves a synthetic omarchy:ruixen.X row through ExtensionRegistry.byOmarchyActionId, not a per-id branch" \
  "$(grep -Fc 'ExtensionRegistry.byOmarchyActionId(String(result.id || "").replace(/^omarchy:/, ""))' "$launcher_qml")" "1"
check "that generic match still sets activeExtensionId and records the launch" \
  "$(grep -A7 'var extMatch = ExtensionRegistry.byProviderId' "$launcher_qml" | grep -c 'activeExtensionId = extMatch.id\|recordLaunch(extMatch.omarchyActionId)')" "2"
for ext_id in cliamp clipboard theme-browser wallpaper-shuffle kanban; do
  check "ExtensionRegistry has a ruixen.$ext_id entry for the generic lookup to find" \
    "$(grep -c "omarchyActionId: \"ruixen.$ext_id\"" "$registry_js")" "1"
done

check "run-all includes the extension search discoverability contract" \
  "$(grep -c 'launcher-extension-search-discoverability\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
