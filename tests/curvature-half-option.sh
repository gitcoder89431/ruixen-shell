#!/usr/bin/env bash
# Guards the third Window Curvature option ("Half" -- half the full
# curve's radius, rounding 24 -> 12): direct request for an adjustable
# border curve was declined upstream ("its something about the frame"),
# so the compromise is one discrete half step. Every layer of the chain
# must know about it or the option silently breaks somewhere: the lua
# variant itself, ruixen-lookfeel.sh, install.sh's deploy/rollback/
# prune loops, BOTH settings UIs (ruixen.settings + ruixen.launcher's
# ported copy), and ruixen.bar's own frame corner mask (which must keep
# matching the real window corners or they clip under the frame -- the
# exact bug the square variant already hit once, see
# hyprland/looknfeel.square.lua's own header).
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
half_lua="$repo_dir/hyprland/looknfeel.half.lua"
lookfeel="$repo_dir/hyprland/ruixen-lookfeel.sh"
install_sh="$repo_dir/install.sh"
settings_qml="$repo_dir/ruixen.settings/Settings.qml"
general_qml="$repo_dir/ruixen.settings/GeneralContent.qml"
launcher_settings_qml="$repo_dir/ruixen.launcher/SettingsContent.qml"
bar_qml="$repo_dir/bars/v2/ruixen.bar/Bar.qml"
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

# --- The lua variant itself -------------------------------------------
check "looknfeel.half.lua exists" \
  "$([[ -f "$half_lua" ]] && echo yes || echo no)" "yes"

check "looknfeel.half.lua pins rounding to 12" \
  "$(grep -m1 'rounding = 12' "$half_lua")" "    rounding = 12,"

check "looknfeel.half.lua has no leftover full/sharp rounding" \
  "$(grep -c 'rounding = 24\|rounding = 0' "$half_lua")" "0"

check "looknfeel.half.lua keeps the shared profile readers" \
  "$(grep -c 'readSpacingProfile\|readGlassProfile\|readAnimationProfile' "$half_lua" | awk '{print ($1 >= 6) ? "yes" : "no"}')" "yes"

check "looknfeel.half.lua keeps the launcher frost layer rule" \
  "$(grep -m1 'namespace = "ruixen-launcher"' "$half_lua")" \
  '  match = { namespace = "ruixen-launcher" },'

# --- The CLI ----------------------------------------------------------
check "ruixen-lookfeel.sh usage documents half" \
  "$(grep -m1 'Usage: ruixen-lookfeel <on|off|half|square|status>' "$lookfeel")" 'Usage: ruixen-lookfeel <on|off|half|square|status>'

check "ruixen-lookfeel.sh applies the half variant" \
  "$(grep -m1 'looknfeel.half.lua' "$lookfeel")" \
  '    apply "half (rounded at half the radius, 12)" "$looknfeel_data_dir/looknfeel.half.lua"'

# --- install.sh deploy/rollback/prune loops + kept-choice message -----
check "install.sh: all three variant loops include looknfeel.half.lua" \
  "$(grep -c 'for variant in looknfeel.ruixen.lua looknfeel.square.lua looknfeel.default.lua looknfeel.half.lua; do' "$install_sh")" "3"

check "install.sh: kept-choice message covers half" \
  "$(grep -c 'kept your existing choice: rounded corners at half the radius (12px)' "$install_sh")" "1"

# --- ruixen.settings (the General page) --------------------------------
check "Settings.qml: read proc detects the half variant" \
  "$(grep -m1 'root.cornerCurvature = "half"' "$settings_qml")" \
  '          root.cornerCurvature = "half"'

check "Settings.qml: setCornerCurvature accepts half" \
  "$(grep -m1 'curvature !== "sharp" && curvature !== "half" && curvature !== "rounded"' "$settings_qml")" \
  '    if (curvature !== "sharp" && curvature !== "half" && curvature !== "rounded") return'

check "Settings.qml: half maps to the half variant" \
  "$(grep -m1 'curvature === "half" ? "half"' "$settings_qml")" \
  '    var variant = curvature === "sharp" ? "square" : curvature === "half" ? "half" : "on"'

check "GeneralContent.qml: Half button in the segmented model" \
  "$(grep -m1 '{ id: "half", label: "Half" }' "$general_qml")" \
  '            { id: "half", label: "Half" },'

# --- ruixen.launcher (the ported Profile page) --------------------------
check "SettingsContent.qml: read proc detects the half variant" \
  "$(grep -m1 'root.cornerCurvature = "half"' "$launcher_settings_qml")" \
  '          root.cornerCurvature = "half"'

check "SettingsContent.qml: setCornerCurvature accepts half" \
  "$(grep -m1 'curvature !== "sharp" && curvature !== "half" && curvature !== "rounded"' "$launcher_settings_qml")" \
  '    if (curvature !== "sharp" && curvature !== "half" && curvature !== "rounded") return'

check "SettingsContent.qml: half symlinks looknfeel.half.lua" \
  "$(grep -m1 'curvature === "half" ? "looknfeel.half.lua"' "$launcher_settings_qml")" \
  '              : curvature === "half" ? "looknfeel.half.lua"'

check "SettingsContent.qml: keyboard-nav options include half" \
  "$(grep -m1 'options: \["rounded", "half", "sharp"\]' "$launcher_settings_qml")" \
  '      options: ["rounded", "half", "sharp"],'

check "SettingsContent.qml: Window Curvature item offers Half" \
  "$(grep -m1 '{ id: "half", label: "Half" }' "$launcher_settings_qml")" \
  '      { id: "half", label: "Half" },'

# --- ruixen.bar (the frame corner mask) ---------------------------------
check "Bar.qml: tracks the variant as a string, not a bool" \
  "$(grep -m1 'property string lookFeelVariant: "rounded"' "$bar_qml")" \
  '  property string lookFeelVariant: "rounded"'

check "Bar.qml: read proc detects looknfeel.half.lua" \
  "$(grep -m1 'root.lookFeelVariant = "half"' "$bar_qml")" \
  '          root.lookFeelVariant = "half"'

check "Bar.qml: both frame corner masks map half to 12" \
  "$(grep -c 'root.lookFeelVariant === "half" ? 12' "$bar_qml")" "2"

check "Bar.qml: no stale sharpCorners left behind (any case -- catches onSharpCornersChanged handlers too)" \
  "$(grep -ci 'sharpcorners' "$bar_qml")" "0"

# --- The suite itself is registered -------------------------------------
check "tests/run-all.sh runs this suite" \
  "$(grep -m1 'curvature-half-option.sh' "$run_all")" \
  '  "$script_dir/curvature-half-option.sh"'

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
