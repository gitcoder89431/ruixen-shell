#!/usr/bin/env bash
# Static contract for Bjarneo Themes' Tab-opened actions menu + pin
# layer -- direct follow-up: "i noticed we have no tab support for the
# left panel. can we do it anyways for consistency, we can do Install
# Pin and Uninstall if installed for the tab." Mirrors the shape
# launcher-clipboard-extension.sh/launcher-cliamp-extension.sh already
# pin for their own extensions' actions menus, not a re-test of the
# whole theme browser (catalog fetch, install pipeline, etc. already
# covered by tests/js/ThemeCatalog.test.js).
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
launcher_qml="$repo_dir/ruixen.launcher/Launcher.qml"
content_qml="$repo_dir/ruixen.launcher/extensions/theme-browser/ThemeBrowserContent.qml"
pins_js="$repo_dir/ruixen.launcher/extensions/theme-browser/ThemePins.js"

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

check "ThemeBrowserContent reuses the same actions-menu shape Clipboard/Cliamp Radio already use" \
  "$(( $(grep -c 'ResultActionsMenu {' "$content_qml") + $(grep -c 'function focusRightPanel' "$content_qml") + $(grep -c 'function blurToLeftPanel' "$content_qml") + $(grep -c 'onRowActionsRequested' "$content_qml") + $(grep -c 'function runThemeAction' "$content_qml") + $(grep -c 'readonly property bool rightFocused: root.actionsMenuOpen' "$content_qml") ))" "6"
check "Tab opens the menu through the generic duck-typed focusRightPanel contract, same as every other extension" \
  "$(grep -c 'if (root.activeExtensionContent && root.activeExtensionContent.focusRightPanel)' "$launcher_qml")" "1"
check "Launcher passes glass props to ThemeBrowserContent's own menu" \
  "$(grep -A30 'ThemeBrowserContent {' "$launcher_qml" | grep -cE 'glassTint: root.glassTint|glassBorder: root.glassBorder')" "2"

check "Actions menu offers Install/Switch, Pin/Unpin, and Uninstall only once installed" \
  "$(( $(grep -c 'id: "install", label: installed ? "Switch" : "Install"' "$content_qml") + $(grep -c 'id: "pin", label: root.selectedIsPinned ? "Unpin" : "Pin"' "$content_qml") + $(grep -c 'id: "uninstall", label:' "$content_qml") ))" "3"
check "Uninstall shares the right panel's own two-step arm/confirm state, not a second one" \
  "$(( $(grep -c 'root.removeArmed && root.removeArmedSlug ===' "$content_qml") + $(grep -c 'root.requestRemove(ThemeCatalog.installedSlugFor' "$content_qml") ))" "4"
check "Right panel's own button uses the same Uninstall wording as the Tab menu now, not a separate 'Remove'" \
  "$(( $(grep -c '"Confirm" : "Uninstall"' "$content_qml") + $(grep -c '"Remove"' "$content_qml") ))" "1"

check "Enter dispatches through the open actions menu first, falls back to install/switch otherwise" \
  "$(grep -A6 'function activateSelection' "$content_qml" | grep -c 'root.installOrSwitchSelected()')" "1"
check "Up/Down navigate the actions menu while it's open, the theme list otherwise" \
  "$(( $(grep -A4 'function moveSelectionUp' "$content_qml" | grep -c 'root.actionsMenuOpen') + $(grep -A4 'function moveSelectionDown' "$content_qml" | grep -c 'root.actionsMenuOpen') ))" "2"

check "Pinned themes get their own section, newest-pinned-irrelevant -- stays in whatever Name/Style sort is active, just ahead of the rest" \
  "$(( $(grep -c 'readonly property var pinnedThemes:' "$content_qml") + $(grep -c 'readonly property var unpinnedThemes:' "$content_qml") + $(grep -c 'sectionLabel: "Pinned"' "$content_qml") ))" "3"
check "selectedIndex tracks orderedThemes (pinned-first), not filteredThemes directly, so the highlight can't land on the wrong theme once something's pinned" \
  "$(( $(grep -c 'readonly property var orderedThemes: root.pinnedThemes.concat(root.unpinnedThemes)' "$content_qml") + $(grep -c 'root.orderedThemes\[root.selectedIndex\]' "$content_qml") + $(grep -c 'root.orderedThemes.length' "$content_qml") ))" "6"

check "Pin state persists to its own Ruixen state file, mkdir -p'd first like every other local store here" \
  "$(( $(grep -c 'pinnedStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/theme-browser-pinned.json"' "$content_qml") + $(grep -c 'id: ensurePinnedDirProc' "$content_qml") + $(grep -c 'id: pinnedFile' "$content_qml") + $(grep -c 'atomicWrites: true' "$content_qml") ))" "4"
check "ThemePins keys by collectionId+baseSlug, not a bare install slug that isn't guaranteed unique across collections" \
  "$(grep -c 'collectionId + ":" + theme.baseSlug' "$pins_js")" "1"
check "ThemePins stores a plain boolean, not a snapshot -- the theme catalog is permanent, unlike a clipboard entry" \
  "$(grep -c 'next\[k\] = true' "$pins_js")" "1"

check "Row hover does not reselect (and so can't close the actions menu out from under a mouse click) while rightFocused -- see KanbanBoardContent.qml's own onRowHovered comment for the full bug this fixes" \
  "$(grep -c 'onRowHovered: (idx) => { if (root.hoverArmed && !root.rightFocused) root.selectedIndex = idx }' "$content_qml")" "1"

check "run-all includes the theme browser actions-menu contract" \
  "$(grep -c 'launcher-theme-browser-extension\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
