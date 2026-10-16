#!/usr/bin/env bash
# Issue #104: ExtensionRegistry.js (ruixen.launcher/extensions/) is now
# the one source of truth for every full-screen launcher extension's id/
# providerId/omarchyActionId/label/icon/usesSourceFilter -- see that
# file's own header for the full before/after and
# tests/js/ExtensionRegistry.test.js for its own data-shape unit tests.
#
# One piece of wiring the registry deliberately can NOT absorb:
# Launcher.qml's own extensionContentById map, which binds each
# registry id to the actual QML Item instance that extension's content
# lives in (wallpapersContent, settingsContent, ...). QML has no way to
# resolve an id string to a component instance without either this map
# or dynamic (Loader-based) instantiation, which issue #104 explicitly
# says not to force. This is the one regression class the registry alone
# can't catch: a new entry added to EXTENSIONS without also adding its
# line to extensionContentById (or vice versa) would silently leave that
# extension's activeExtensionContent resolving to null, or an entry in
# the map with no corresponding registry id at all. This test pins that
# the two never drift apart.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
registry_js="$repo_dir/ruixen.launcher/extensions/ExtensionRegistry.js"
launcher_qml="$repo_dir/ruixen.launcher/Launcher.qml"

command -v node >/dev/null 2>&1 || {
  printf 'launcher-extension-registry-consistency: node is required (command "node" not found)\n' >&2
  exit 1
}

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

registry_ids="$(node -e '
const path = require("path");
const { loadModule } = require(path.join("'"$script_dir"'", "js", "harness"));
const M = loadModule("'"$registry_js"'");
console.log(M.ids().slice().sort().join(","));
')"

# extensionContentById's own literal keys, extracted the same shape
# node just gave us (sorted, comma-joined) -- the map body sits between
# its own opening "({" and closing "})", one "id": Item per line.
# LC_ALL=C: a locale-aware sort can order "-" differently than JS's own
# plain code-unit Array.prototype.sort() above (confirmed live -- the
# default locale here sorted "wallpapers" before "wallpaper-shuffle",
# JS does the opposite), which would make this comparison falsely FAIL
# on two sets that actually match.
map_ids="$(awk '
  /readonly property var extensionContentById: \(\{/ { inmap=1; next }
  inmap && /^  \}\)/ { inmap=0 }
  inmap { print }
' "$launcher_qml" | grep -oE '"[a-z-]+":' | tr -d '":' | LC_ALL=C sort | tr '\n' ',' | sed 's/,$//')"

check "ExtensionRegistry.ids() and Launcher.qml's extensionContentById have the exact same set of ids" \
  "$map_ids" "$registry_ids"

# Every registry entry's content Item is wired to something real (not
# left as `null` or a typo'd id that happens to exist nowhere) --
# cross-checked against the extension's own QML component being
# instantiated somewhere in the file, same "<Name>Content {" shape every
# existing extension-specific test (launcher-clipboard-extension.sh,
# launcher-cliamp-extension.sh, ...) already pins individually.
declare -A expected_components=(
  ["wallpapers"]="WallpapersContent {"
  ["settings"]="SettingsContent {"
  ["theme-browser"]="ThemeBrowserContent {"
  ["clipboard"]="ClipboardContent {"
  ["cliamp"]="CliampContent {"
  ["wallpaper-shuffle"]="WallpaperShuffleContent {"
  ["kanban"]="KanbanBoardContent {"
)
for id in "${!expected_components[@]}"; do
  check "registry id '$id' has its own content component instantiated in Launcher.qml" \
    "$(grep -Fc "${expected_components[$id]}" "$launcher_qml")" "1"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
