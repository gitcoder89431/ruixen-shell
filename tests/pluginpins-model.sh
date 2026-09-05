#!/usr/bin/env bash
# Covers ruixen.pluginpins -- direct request: "instead of the AI icon,
# its a dropdown icon that shows the name of the available plugins you
# have... clicking or toggling them pins it onto the icons group". Lets
# any installed bar-widget plugin be pinned/unpinned from a dropdown
# instead of needing to live in the bar permanently.
#
# Can't drive a real Quickshell instance here (no compositor in CI), so
# this is a static invariant check against the actual QML source, same
# style as tests/lint-shell.sh's own pattern-based guards. Deploy-time
# behavior (the candidate list's real contents, an actual pin/unpin
# round trip) was verified live via a temporary debug IpcHandler, since
# removed -- see the commit message, not this file, for those results.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
widget_qml="$repo_dir/ruixen.pluginpins/BarWidget.qml"
manifest_json="$repo_dir/ruixen.pluginpins/manifest.json"

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

check "manifest declares kind bar-widget" \
  "$(grep -c '"bar-widget"' "$manifest_json")" "1"
check "manifest defaults to the right section (curatedRightIds places it explicitly either way)" \
  "$(grep -c '"defaultSection": "right"' "$manifest_json")" "1"

# Structural ruixen ids this widget must never offer to unpin -- doing so
# through this generic mechanism would silently break the bar's own
# curated layout (the app launcher, workspace switcher, tray, its own
# settings/quickactions group) rather than just hiding an optional widget.
required_exclusions=(
  "ruixen.applauncher" "ruixen.workspaces" "ruixen.pinnedapps" "ruixen.tray"
  "ruixen.quickactions" "ruixen.settingsbutton" "ruixen.stayawake"
  "ruixen.weather" "ruixen.media" "ruixen.pluginpins" "omarchy.clock"
  "omarchy.system-update" "omarchy.power" "omarchy.keyboard-layout"
  "omarchy.indicators"
)
excluded_block="$(grep -A20 'readonly property var excludedIds:' "$widget_qml")"
missing=0
for id in "${required_exclusions[@]}"; do
  if ! grep -qF "\"$id\"" <<<"$excluded_block"; then
    printf 'FAIL - excludedIds is missing required id: %s\n' "$id"
    missing=$((missing + 1))
  fi
done
if [[ "$missing" -eq 0 ]]; then
  printf 'ok   - excludedIds covers every structural ruixen id, omarchy.clock (shares clockPill with weather), system-update/power (already handled by curatedRightIds), keyboard-layout (self-hides on a single layout), and indicators (redundant + a real IPC collision)\n'
  pass=$((pass + 1))
else
  fail_count=$((fail_count + 1))
fi

check "candidates filters to kind bar-widget only" \
  "$(grep -c 'kinds\.indexOf("bar-widget")' "$widget_qml")" "1"
check "candidates excludes excludedIds" \
  "$(grep -c 'excludedIds\.indexOf(id)' "$widget_qml")" "1"
check "candidates re-evaluates on registry changes (registryRevision read for its binding dependency)" \
  "$(grep -c 'reg\.registryRevision' "$widget_qml")" "1"
check "pinned state reads the registry's own inBar(), not a hand-rolled layout scan" \
  "$(grep -c 'reg\.inBar(id)' "$widget_qml")" "1"

# Unpin has to search every section, not just "right" -- a plugin someone
# dragged elsewhere (the bar's own drag-to-reorder feature) must still be
# removable from here.
togglepin_block="$(grep -A20 'function togglePin' "$widget_qml")"
check "togglePin sweeps all three sections (left/center/right), not just right" \
  "$(grep -c '\["left", "center", "right"\]' <<<"$togglepin_block")" "1"
check "togglePin uses mutateShellConfig, the same primitive the bar's own drag-reorder already uses" \
  "$(grep -c 'bar\.shell\.mutateShellConfig(function' "$widget_qml")" "1"

# The trigger/checkmark glyphs must be QML \u escapes, not pasted Nerd
# Font characters -- direct precedent for why: a hidden/corrupted glyph
# byte has broken this exact thing twice already elsewhere in this repo
# (ruixen.pinnedapps' own fallback glyph, Bar.qml's sidebar label).
check "trigger glyph is a \\u escape, not a raw pasted character" \
  "$(grep -c 'text: "\\uf00a"' "$widget_qml")" "1"
check "checkmark glyph is a \\u escape, not a raw pasted character" \
  "$(grep -c 'text: "\\uf00c"' "$widget_qml")" "1"

# No debug scaffolding left behind from live verification.
check "no leftover console.log debug statements" \
  "$(grep -c 'console\.log' "$widget_qml")" "0"
check "no leftover debug IpcHandler declaration (a mention of the word in a comment is fine)" \
  "$(grep -c 'IpcHandler {' "$widget_qml")" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
