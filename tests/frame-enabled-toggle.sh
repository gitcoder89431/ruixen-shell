#!/usr/bin/env bash
# Issue #114, direct request: "on float mode to be able to disable the
# frame [...] but the problem is on dock mode we need to not have this
# cause i think the docked mode needs the frame". Investigation
# confirmed FrameWindow.qml draws two separate things in one window --
# the decorative hole-punch border (frameCanvas/frameShadowCanvas,
# previously unconditional in both floating and docked) and dockChrome
# (already docked-only) -- and that the notch/floating pill both paint
# their own fully opaque backgrounds in their own separate windows, so
# disabling the border in floating mode is purely cosmetic. Also
# confirmed via the real math: both the notch and the floating pill's
# own surfaces are independent of this border already existing or not.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
bar_qml="$repo_dir/bars/v2/ruixen.bar/Bar.qml"
frame_qml="$repo_dir/bars/v2/ruixen.bar/FrameWindow.qml"
settings_qml="$repo_dir/ruixen.launcher/extensions/settings/SettingsContent.qml"
barpage_qml="$repo_dir/ruixen.launcher/extensions/settings/pages/BarPage.qml"

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

# --- Bar.qml: the resolved property and its forced-on-while-docked rule
check "Bar.qml declares frameEnabled, defaulting to on" \
  "$(grep -c 'property bool frameEnabled: true' "$bar_qml")" "1"
check "resolvedFrameEnabled forces on whenever docked, regardless of the stored preference" \
  "$(grep -c 'readonly property bool resolvedFrameEnabled: root.docked || root.frameEnabled' "$bar_qml")" "1"
check "applyBarSurfaceState takes frameEnabled as a third argument" \
  "$(grep -c 'function applyBarSurfaceState(colorMode, material, frameEnabled)' "$bar_qml")" "1"
check "a missing/non-false frameEnabled value in the state file still defaults to on" \
  "$(grep -c 'root.frameEnabled = frameEnabled !== false' "$bar_qml")" "1"
check "loadBarSurfaceState passes the parsed frameEnabled field through" \
  "$(grep -c 'root.applyBarSurfaceState(p && p.color, p && p.material, p && p.frameEnabled)' "$bar_qml")" "1"

# --- FrameWindow.qml: only the decorative border is gated, not dockChrome
check "frameCanvas (the decorative border) is gated on resolvedFrameEnabled" \
  "$(grep -A5 'id: frameCanvas' "$frame_qml" | grep -c 'visible: frameWindow.barRoot.resolvedFrameEnabled')" "1"
check "frameShadowCanvas (the border's own inner shadow) is gated the same way" \
  "$(grep -A4 'id: frameShadowCanvas' "$frame_qml" | grep -c 'visible: frameWindow.barRoot.resolvedFrameEnabled')" "1"
check "dockChrome stays independently gated on docked alone, untouched by this feature" \
  "$(grep -c 'visible: frameWindow.barRoot.docked && frameWindow.barRoot.position === "top"' "$frame_qml")" "1"

# --- SettingsContent.qml: persistence, no-op-while-docked setter, nav wiring
check "SettingsContent.qml declares its own frameEnabled, defaulting to on" \
  "$(grep -c 'property bool frameEnabled: true' "$settings_qml")" "1"
check "writeBarSurfaceState persists frameEnabled alongside color/material" \
  "$(grep -A5 'function writeBarSurfaceState' "$settings_qml" | grep -c 'frameEnabled: root.frameEnabled')" "1"
check "setFrameEnabled is a no-op while docked -- the click would otherwise silently do nothing" \
  "$(grep -A4 'function setFrameEnabled' "$settings_qml" | grep -c 'if (root.barMode === "docked") return')" "1"
check "the bar settings page's keyboard-nav list (barItems) includes the new toggle" \
  "$(grep -A10 'options: AppLauncherGlyphs.iconIds()' "$settings_qml" | grep -c 'kind: "toggle"')" "1"
check "focusedItemVisual's own bar-section array includes frameEnabledItem" \
  "$(grep -c 'barPage.frameEnabledItem\]\[root.focusedItemIndex\]' "$settings_qml")" "1"

# --- BarPage.qml: the actual control, dimmed + explained while docked
check "BarPage.qml exposes frameEnabledItem through the same alias convention as its siblings" \
  "$(grep -c 'readonly property alias frameEnabledItem: frameEnabledItem' "$barpage_qml")" "1"
check "the toggle is dimmed (toggleEnabled false) while docked, not just silently inert" \
  "$(grep -c 'toggleEnabled: root.settingsRoot.barMode !== "docked"' "$barpage_qml")" "1"
check "a subtitle explains why, instead of leaving a dimmed toggle with no explanation" \
  "$(grep -c 'subtitle: root.settingsRoot.barMode === "docked" ? "Always on while docked" : ""' "$barpage_qml")" "1"
check "the toggle reflects and writes through the real frameEnabled state, not a local copy" \
  "$(( $(grep -c 'checked: root.settingsRoot.frameEnabled' "$barpage_qml") + $(grep -c 'onToggled: root.settingsRoot.setFrameEnabled(!root.settingsRoot.frameEnabled)' "$barpage_qml") ))" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
