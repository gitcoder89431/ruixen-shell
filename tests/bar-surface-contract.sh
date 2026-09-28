#!/usr/bin/env bash
# Contract for issue #78: define semantic bar surface tokens before splitting
# Bar.qml into smaller components.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
bar_qml="$repo_dir/bars/v2/ruixen.bar/Bar.qml"
notch_qml="$repo_dir/bars/widgets/ruixen.notch/Overlay.qml"
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

check "Bar.qml declares the black surface identity token" \
  "$(grep -c 'readonly property color surfaceBlack: "#000000"' "$bar_qml")" "1"

check "floating surface color follows the shared frame appearance mode" \
  "$(grep -c 'readonly property string floatingSurfaceColorMode: root.frameColorMode' "$bar_qml")" "1"

check "floating surface material follows the bar surface state" \
  "$(grep -c 'readonly property string floatingSurfaceMaterial: root.barSurfaceMaterial' "$bar_qml")" "1"

check "floating pills resolve their fill through the surface resolver" \
  "$(grep -c 'readonly property color floatingPillSurface: resolveSurfaceColor(floatingSurfaceColorMode)' "$bar_qml")" "1"

check "floating pills resolve material opacity in one helper" \
  "$(grep -c 'readonly property color floatingPillFill: surfaceFillForMaterial(floatingPillSurface, floatingSurfaceMaterial)' "$bar_qml")" "1"

check "glass material uses a translucent fill" \
  "$(grep -A4 'function surfaceFillForMaterial' "$bar_qml" | grep -c 'material === "glass" ? 0.78')" "1"

check "surface color identity is resolved in one helper" \
  "$(grep -A2 'function resolveSurfaceColor' "$bar_qml" | grep -c 'mode === "theme" ? Color.background : root.surfaceBlack')" "1"

check "foreground readability is derived from the resolved surface" \
  "$(grep -c 'readonly property color pillForeground: readableForegroundForSurface(floatingPillSurface, themeForeground)' "$bar_qml")" "1"

check "readableForegroundForSurface handles light surfaces explicitly" \
  "$(grep -A5 'function readableForegroundForSurface' "$bar_qml" | grep -c 'surfaceIsLight')" "2"

check "light surfaces fall back to a dark safe foreground when needed" \
  "$(grep -A6 'function readableForegroundForSurface' "$bar_qml" | grep -c 'surfaceSafeDarkForeground')" "1"

check "dark surfaces fall back to a light safe foreground when needed" \
  "$(grep -A6 'function readableForegroundForSurface' "$bar_qml" | grep -c 'surfaceSafeLightForeground')" "1"

check "frame color uses the shared surface resolver" \
  "$(grep -c 'readonly property color frameColor: resolveSurfaceColor(root.frameColorMode)' "$bar_qml")" "1"

check "docked content surface uses the shared content clamp" \
  "$(grep -c 'readonly property color dockedBarColor: contentSurfaceFor(root.frameColor)' "$bar_qml")" "1"

check "notch reads the shared bar surface state file" \
  "$(grep -c 'readonly property string barSurfaceStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/bar-surface.json"' "$notch_qml")" "1"

check "notch keeps frame appearance as a compatibility fallback" \
  "$(( $(grep -c 'readonly property string frameColorStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/frame-appearance.json"' "$notch_qml") + $(grep -c 'if (root.barSurfaceStateLoaded) return' "$notch_qml") ))" "2"

check "notch color uses the same surface resolver and content clamp pattern" \
  "$(( $(grep -c 'readonly property color resolvedFrameColor: resolveSurfaceColor(root.frameColorMode)' "$notch_qml") + $(grep -c 'readonly property color notchColor: contentSurfaceFor(resolvedFrameColor)' "$notch_qml") ))" "2"

check "notch stores but does not render glass material yet" \
  "$(( $(grep -c 'property string notchSurfaceMaterial: "solid"' "$notch_qml") + $(grep -c 'root.notchSurfaceMaterial = normalizeSurfaceMaterial(material)' "$notch_qml") + $(grep -c 'coupled frame/notch glass' "$notch_qml") ))" "3"

check "GroupPill no longer owns a raw black fill" \
  "$(grep -A10 'component GroupPill' "$bar_qml" | grep -c 'color: root.floatingPillFill')" "1"

check "GroupPill shadow uses the semantic shadow token" \
  "$(grep -A55 'component GroupPill' "$bar_qml" | grep -c 'shadowColor: root.surfaceShadow')" "1"

check "launcher settings labels the shared control as Surface Color" \
  "$(grep -c 'label: "Surface Color"' "$settings_qml")" "1"

check "launcher settings exposes the independent Surface Material control" \
  "$(grep -c 'label: "Surface Material"' "$settings_qml")" "1"

check "launcher settings offers Solid and Glass material options" \
  "$(( $(grep -c '{ id: "solid", label: "Solid" }' "$settings_qml") + $(grep -c '{ id: "glass", label: "Glass" }' "$settings_qml") ))" "2"

check "bar reads the new bar surface state file" \
  "$(grep -c 'readonly property string barSurfaceStatePath: root.stateHome + "/ruixen/bar-surface.json"' "$bar_qml")" "1"

check "launcher writes the new bar surface state file" \
  "$(grep -c 'bar-surface.json' "$settings_qml")" "2"

check "new bar-surface state wins over frame-appearance fallback" \
  "$(grep -h -c 'if (root.barSurfaceStateLoaded) return' "$bar_qml" "$settings_qml" | awk '{ total += $1 } END { print total }')" "2"

check "launcher settings keeps frame-appearance as color compatibility state" \
  "$(grep -c 'frame-appearance.json is still mirrored for compatibility' "$settings_qml")" "1"

# shellcheck disable=SC2016 # deliberately literal: expected run-all entry contains $script_dir.
check "tests/run-all.sh runs this suite" \
  "$(grep -m1 'bar-surface-contract.sh' "$run_all")" \
  '  "$script_dir/bar-surface-contract.sh"'

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
