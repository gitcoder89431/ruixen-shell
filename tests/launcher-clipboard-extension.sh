#!/usr/bin/env bash
# Static contract for the Ruixen Launcher clipboard extension. It should
# reuse Omarchy's native clipboard history and paste helpers rather than
# introducing a second clipboard backend.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
launcher_qml="$repo_dir/ruixen.launcher/Launcher.qml"
content_qml="$repo_dir/ruixen.launcher/extensions/clipboard/ClipboardContent.qml"
details_qml="$repo_dir/ruixen.launcher/extensions/clipboard/ClipboardDetailsPanel.qml"
model_js="$repo_dir/ruixen.launcher/extensions/clipboard/ClipboardHistory.js"

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

check "Launcher imports the clipboard extension folder" \
  "$(grep -c 'import "extensions/clipboard"' "$launcher_qml")" "1"
check "Launcher has a Clipboard History landing row" \
  "$(grep -c 'label: "Clipboard History"' "$launcher_qml")" "1"
check "Launcher activates clipboard-extension in-process" \
  "$(grep -A8 'result.providerId === "clipboard-extension"' "$launcher_qml" | grep -c 'activeExtensionId = "clipboard"')" "1"
check "Launcher records clipboard frecency" \
  "$(grep -c 'recordLaunch("ruixen.clipboard")\|frecencyFor("ruixen.clipboard")' "$launcher_qml")" "2"
check "Launcher instantiates ClipboardContent" \
  "$(grep -c 'ClipboardContent {' "$launcher_qml")" "1"

check "ClipboardContent reads Omarchy native clipboard history" \
  "$(grep -c '/.local/state/omarchy/clipboard-history.json' "$content_qml")" "1"
check "ClipboardContent uses native text paste helper by history index" \
  "$(grep -c 'omarchy-clipboard-paste-text.*--history-index' "$content_qml")" "2"
check "ClipboardContent uses native image paste helper" \
  "$(grep -c 'omarchy-clipboard-paste-file' "$content_qml")" "2"
check "ClipboardContent does not use cliphist" \
  "$(grep -Rhi 'cliphist' "$repo_dir/ruixen.launcher/extensions/clipboard" | wc -l)" "0"
check "ClipboardContent uses compact icon+name rows, with no subtitle/kind columns" \
  "$(grep -c 'filesMode: true' "$content_qml")" "1"
check "Clipboard model classifies URL-shaped text as Link with a link icon" \
  "$(( $(grep -c 'looksLikeLink' "$model_js") + $(grep -c '"\\uf0c1"' "$model_js") + $(grep -c 'kind: isLink ? "Link" : "Text"' "$model_js") ))" "4"
check "Clipboard model labels image rows by dimensions instead of filename" \
  "$(grep -c 'Image (" + dims + ")"' "$model_js")" "1"
check "ClipboardDetailsPanel exposes an image path action" \
  "$(grep -c 'onPastePathRequested' "$content_qml")$(grep -c 'label: "Path"' "$details_qml")" "11"
check "ClipboardDetailsPanel omits temporary/internal path metadata rows" \
  "$(grep -c 'value: root.entry.path' "$details_qml")" "0"
check "ClipboardContent fetches image dimensions through the shared file parser" \
  "$(grep -c 'FileSearchRanking.parseFileDimensions' "$content_qml")" "1"
check "ClipboardContent fetches image byte size with stat" \
  "$(grep -Fc '["stat", "--format=%s|%n"' "$content_qml")" "1"
check "ClipboardDetailsPanel shows image dimensions and size metadata" \
  "$(( $(grep -c 'label: "Dimensions"' "$details_qml") + $(grep -c 'label: "Size"' "$details_qml") ))" "2"
check "ClipboardDetailsPanel shows text character and word counts" \
  "$(( $(grep -c 'function characterCount' "$details_qml") + $(grep -c 'function wordCount' "$details_qml") + $(grep -c 'label: "Characters"' "$details_qml") + $(grep -c 'label: "Words"' "$details_qml") ))" "4"
check "ClipboardDetailsPanel previews links through the same text preview surface" \
  "$(grep -c 'root.entry.type === "text" || root.entry.type === "link"' "$details_qml")" "1"
check "Clipboard model preserves source history indexes" \
  "$(grep -c 'sourceIndex: index' "$model_js")" "2"

check "run-all includes launcher clipboard extension contract" \
  "$(grep -c 'launcher-clipboard-extension\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
