#!/usr/bin/env bash
# Covers issue #71's test-coverage ask for ruixen.cava beyond what
# tests/cava-missing-dependency.sh and tests/cava-idle-quiesce.sh
# already exercise (the retry-loop fix and the idle-work fix
# specifically). manifest validity generically (every plugin's
# manifest.json parses and matches its own schema) and shell.json
# merge/install inclusion of ruixen.cava are already covered by
# tests/validate-manifests.sh and tests/shell-json-merge.sh /
# tests/install-lifecycle.sh respectively -- not duplicated here.
#
# What's specific to this plugin and not covered elsewhere:
# - manifest.json's own keepLoaded overlay wiring (this plugin has to
#   stay resident so toggling Enable in Settings -- a pure state-file
#   write -- takes effect live, the same reasoning ruixen.frame-widget's
#   own manifest already established).
# - the writer (SettingsContent.qml) and the reader (Overlay.qml) agree
#   on exactly which style/position/band values are valid -- these are
#   two independently hand-maintained validation arrays in two
#   different plugin folders, with nothing at the language level
#   keeping them in sync, so a value added to one and not the other
#   would silently mean the reader falls back to its own default
#   forever for that specific value instead of ever applying it.
#
# Static QML/JSON checks only, same reasoning the other two cava test
# files already document.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
manifest_json="$repo_dir/ruixen.cava/manifest.json"
overlay_qml="$repo_dir/ruixen.cava/Overlay.qml"
settings_qml="$repo_dir/ruixen.launcher/SettingsContent.qml"

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

# --- manifest.json: keepLoaded overlay wiring --------------------------

check "manifest.json is valid JSON" \
  "$(jq -e . "$manifest_json" >/dev/null 2>&1 && echo yes || echo no)" "yes"
check "manifest declares kind overlay" \
  "$(jq -r '.kinds[0]' "$manifest_json")" "overlay"
check "manifest is keepLoaded (so Settings' Enable toggle takes effect live)" \
  "$(jq -r '.keepLoaded' "$manifest_json")" "true"
check "manifest's overlay entry point is Overlay.qml" \
  "$(jq -r '.entryPoints.overlay' "$manifest_json")" "Overlay.qml"

# --- style ids: reader and writer agree --------------------------------

check "Overlay.qml validates style against exactly bars/segments/wave" \
  "$(grep -c '\["bars", "segments", "wave"\].indexOf(p.style)' "$overlay_qml")" "1"
check "SettingsContent.qml validates the same style set on load" \
  "$(grep -c '\["bars", "segments", "wave"\].indexOf(p.style)' "$settings_qml")" "1"
check "SettingsContent.qml's own Style picker offers exactly those three ids" \
  "$(grep -A4 'options: \[' "$settings_qml" | grep -c '{ id: "bars", label: "Bars" }\|{ id: "segments", label: "Segments" }\|{ id: "wave", label: "Wave" }' || true)" \
  "$(grep -c '{ id: "bars", label: "Bars" }\|{ id: "segments", label: "Segments" }\|{ id: "wave", label: "Wave" }' "$settings_qml")"

# --- positions: reader and writer agree --------------------------------

check "Overlay.qml validates position against exactly top/bottom/left/right" \
  "$(grep -c '\["top", "bottom", "left", "right"\].indexOf(p.position)' "$overlay_qml")" "1"
check "SettingsContent.qml validates the same position set on load" \
  "$(grep -c '\["top", "bottom", "left", "right"\].indexOf(p.position)' "$settings_qml")" "1"

# --- band presets: reader and writer agree ------------------------------

check "Overlay.qml validates bands against exactly 32/48/64/96" \
  "$(grep -c '\[32, 48, 64, 96\].indexOf(p.bands)' "$overlay_qml")" "1"
check "SettingsContent.qml validates the same band presets on load" \
  "$(grep -c '\[32, 48, 64, 96\].indexOf(p.bands)' "$settings_qml")" "1"
check "SettingsContent.qml's own Bands picker offers exactly those four values" \
  "$(grep -c '{ id: 32, label: "32" }\|{ id: 48, label: "48" }\|{ id: 64, label: "64" }\|{ id: 96, label: "96" }' "$settings_qml")" "4"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
