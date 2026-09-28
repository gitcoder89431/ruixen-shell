#!/usr/bin/env bash
# Contract for the Bar page's Icon Tone setting: Mono keeps the existing
# readable foreground, Accent colors only icon-specific call sites.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
bar_qml="$repo_dir/bars/v2/ruixen.bar/Bar.qml"
settings_qml="$repo_dir/ruixen.launcher/SettingsContent.qml"
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

check "Bar.qml exposes an iconTone state with mono default" \
  "$(grep -c 'property string iconTone: "mono"' "$bar_qml")" "1"

check "Bar.qml resolves Accent icons through Color.accent only at iconForeground" \
  "$(grep -c 'readonly property color iconForeground: iconTone === "accent" ? Color.accent : pillForeground' "$bar_qml")" "1"

check "PluginBarFacade exposes iconForeground to bar widgets" \
  "$(grep -A8 'component PluginBarFacade' "$bar_qml" | grep -c 'readonly property color iconForeground: root.iconForeground')" "1"

check "Bar.qml exposes semantic status colors independent of Icon Tone" \
  "$(( $(grep -c 'readonly property color semanticGood: themeGreen' "$bar_qml") + $(grep -c 'readonly property color semanticWarn: themeYellow' "$bar_qml") + $(grep -c 'readonly property color semanticBad: themeRed' "$bar_qml") ))" "3"

check "PluginBarFacade exposes semantic status colors to widgets" \
  "$(( $(grep -A12 'component PluginBarFacade' "$bar_qml" | grep -c 'readonly property color semanticGood: root.semanticGood') + $(grep -A12 'component PluginBarFacade' "$bar_qml" | grep -c 'readonly property color semanticWarn: root.semanticWarn') + $(grep -A12 'component PluginBarFacade' "$bar_qml" | grep -c 'readonly property color semanticBad: root.semanticBad') ))" "3"

check "PluginBarFacade exposes secondary theme token to widgets" \
  "$(grep -A16 'component PluginBarFacade' "$bar_qml" | grep -c 'readonly property color themeSecondary: root.themeSecondary')" "1"

check "Bar.qml keeps global text/popup foreground readable, not accent-driven" \
  "$(grep -c 'property color foreground: pillForeground' "$bar_qml")" "1"

check "Bar.qml separates popup foreground from bar pill foreground" \
  "$(grep -c 'readonly property color popupForeground: Color.popups.text' "$bar_qml")" "1"

check "PluginBarFacade exposes popup foreground through bar.foreground" \
  "$(grep -A8 'component PluginBarFacade' "$bar_qml" | grep -c 'readonly property color foreground: root.popupForeground')" "1"

check "Bar.qml reads the independent icon tone state file" \
  "$(grep -c 'bar-icon-tone.json' "$bar_qml")" "1"

check "SettingsContent.qml exposes Icon Tone on the Bar page" \
  "$(grep -c 'label: "Icon Tone"' "$settings_qml")" "1"

check "SettingsContent.qml offers exactly Mono and Accent" \
  "$(( $(grep -c '{ id: "mono", label: "Mono" }' "$settings_qml") + $(grep -c '{ id: "accent", label: "Accent" }' "$settings_qml") ))" "2"

check "SettingsContent.qml writes the same icon tone state file" \
  "$(grep -c 'bar-icon-tone.json' "$settings_qml")" "1"

check "decorative Ruixen BarIconButtons use iconForeground" \
  "$(grep -R -c 'foreground: root\.bar ? root\.bar\.iconForeground : "#ffffff"' "$repo_dir/bars/widgets" | awk -F: '{ total += $2 } END { print total }')" "5"

# ruixen.weather deliberately does NOT use iconForeground -- direct live
# follow-up: it shares clockPill with the stock omarchy.clock widget,
# whose own color can't be overridden without cloning it, so weather
# alone picking up Icon Tone's accent read as mismatched within the pill.
check "ruixen.weather does not override foreground with iconForeground (mismatched clock pill)" \
  "$(grep -c 'foreground: root\.bar ? root\.bar\.iconForeground' "$repo_dir/bars/widgets/ruixen.weather/BarWidget.qml" || true)" "0"

check "symbolic tray icons use iconForeground" \
  "$(grep -c 'colorizationColor: root.iconForeground' "$repo_dir/bars/widgets/ruixen.tray/Tray.qml")" "1"

check "screen recording indicator uses semantic bad, not decorative icon tone" \
  "$(grep -c 'foreground: root.bar ? root.bar.semanticBad : Color.urgent' "$repo_dir/bars/widgets/ruixen.capturestatus/BarWidget.qml")" "1"

check "peripheral battery indicator keeps semantic charge colors" \
  "$(grep -c 'foreground: root.percentColor(root.selectedDevice)' "$repo_dir/bars/widgets/ruixen.peripherals/BarWidget.qml")" "1"

check "peripheral battery tiers consume the shared semantic signal colors" \
  "$(( $(grep -c 'root.bar.semanticGood' "$repo_dir/bars/widgets/ruixen.peripherals/BarWidget.qml") + $(grep -c 'root.bar.semanticWarn' "$repo_dir/bars/widgets/ruixen.peripherals/BarWidget.qml") + $(grep -c 'root.bar.semanticBad' "$repo_dir/bars/widgets/ruixen.peripherals/BarWidget.qml") ))" "3"

check "laptop battery icon uses semantic good for full/idle state" \
  "$(grep -c 'if (root.batteryFlowIdle) return root.bar.semanticGood' "$repo_dir/bars/widgets/ruixen.power/Panel.qml")" "1"

check "laptop battery icon uses semantic good while charging" \
  "$(grep -c 'if (root.charging && !root.batteryFlowIdle) return root.bar.semanticGood' "$repo_dir/bars/widgets/ruixen.power/Panel.qml")" "1"

check "laptop battery icon never falls back to semanticNeutral accent tone" \
  "$(grep -A8 'readonly property color batteryIconColor' "$repo_dir/bars/widgets/ruixen.power/Panel.qml" | grep -c 'semanticNeutral' || true)" "0"

check "laptop battery icon ignores active accent override" \
  "$(grep -A10 'foreground: root.batteryGlyphColor' "$repo_dir/bars/widgets/ruixen.power/Panel.qml" | grep -c 'useActiveColor: false')" "1"

check "laptop battery icon uses a horizontal semantic fill meter" \
  "$(( $(grep -F -c 'id: batteryMeterIcon' "$repo_dir/bars/widgets/ruixen.power/Panel.qml") + $(grep -F -c 'iconComponent: root.showPercentage && !vertical ? null : batteryMeterIcon' "$repo_dir/bars/widgets/ruixen.power/Panel.qml") + $(grep -F -c 'color: root.batteryIconColor' "$repo_dir/bars/widgets/ruixen.power/Panel.qml") ))" "3"

check "laptop battery outline and charging mark share the outline color" \
  "$(( $(grep -F -c 'readonly property color batteryGlyphColor: root.bar ? root.bar.semanticInfo : Color.accent' "$repo_dir/bars/widgets/ruixen.power/Panel.qml") + $(grep -F -c 'readonly property color batteryChargingColor: root.batteryGlyphColor' "$repo_dir/bars/widgets/ruixen.power/Panel.qml") + $(grep -F -c 'color: root.batteryChargingColor' "$repo_dir/bars/widgets/ruixen.power/Panel.qml") ))" "3"

check "laptop battery fill is level-based and charging bolt is static" \
  "$(( $(grep -A8 'readonly property color batteryIconColor' "$repo_dir/bars/widgets/ruixen.power/Panel.qml" | grep -F -c 'if (!root.discharging)' || true) + $(grep -A70 'id: batteryMeterIcon' "$repo_dir/bars/widgets/ruixen.power/Panel.qml" | grep -c 'SequentialAnimation on opacity' || true) ))" "0"

# shellcheck disable=SC2016 # deliberately literal: expected run-all entry contains $script_dir.
check "tests/run-all.sh runs this suite" \
  "$(grep -m1 'bar-icon-tone-contract.sh' "$run_all")" \
  '  "$script_dir/bar-icon-tone-contract.sh"'

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
