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
overlay_qml="$repo_dir/bars/widgets/ruixen.notch/Overlay.qml"
notch_window_qml="$repo_dir/bars/widgets/ruixen.notch/NotchWindow.qml"

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

# --- FrameWindow.qml: the edge-band compromise (direct live report after
# the plain on/off version: "all our notch shelf etc is mising the top
# part cause the frame is gone") wasn't well received live either, and
# the notch/shelf no longer need it -- they now collapse their own
# reserved top space instead (see notch-window/shelf-plugin tests). Bar's
# own floating padding is untouched for now, deliberately, so frameCanvas
# is back to a plain visible: gate with no onPaint branch. Only dockChrome
# stays untouched by any of this, same as before.
check "frameCanvas is a plain visible: gate again, no edge-band branch left in onPaint" \
  "$(grep -A20 'id: frameCanvas' "$frame_qml" | grep -c 'visible: frameWindow.barRoot.resolvedFrameEnabled')" "1"
check "no leftover paintEdgeBand function or band-painting branch" \
  "$(( $(grep -c 'function paintEdgeBand' "$frame_qml") + $(grep -c 'if (!frameWindow.barRoot.resolvedFrameEnabled) {' "$frame_qml") ))" "0"
check "frameShadowCanvas stays gated the same way as frameCanvas" \
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
check "barItems' own Frame Border toggle sits right after Bar Layout, not appended at the end" \
  "$(grep -A9 'options: \["floating", "docked"\]' "$settings_qml" | grep -c 'kind: "toggle"')" "1"
check "focusedItemVisual's own bar-section array has frameEnabledItem right after barLayoutItem" \
  "$(grep -c 'barPage.barLayoutItem, barPage.frameEnabledItem, barPage.frameColorModeItem,' "$settings_qml")" "1"

# --- BarPage.qml: the actual control, dimmed + explained while docked
check "BarPage.qml exposes frameEnabledItem through the same alias convention as its siblings" \
  "$(grep -c 'readonly property alias frameEnabledItem: frameEnabledItem' "$barpage_qml")" "1"
check "the toggle is dimmed (toggleEnabled false) while docked, not just silently inert" \
  "$(grep -c 'toggleEnabled: root.settingsRoot.barMode !== "docked"' "$barpage_qml")" "1"
check "a subtitle explains why, instead of leaving a dimmed toggle with no explanation" \
  "$(grep -c 'subtitle: root.settingsRoot.barMode === "docked" ? "Always on while docked" : ""' "$barpage_qml")" "1"
check "the toggle reflects and writes through the real frameEnabled state, not a local copy" \
  "$(( $(grep -c 'checked: root.settingsRoot.frameEnabled' "$barpage_qml") + $(grep -c 'onToggled: root.settingsRoot.setFrameEnabled(!root.settingsRoot.frameEnabled)' "$barpage_qml") ))" "2"
check "direct follow-up honored: the toggle sits at keyboard index 1, right under Bar Layout (index 0)" \
  "$(grep -c 'rowFocused: root.settingsRoot.rightFocused && root.settingsRoot.focusedItemIndex === 1' "$barpage_qml")" "1"
check "every later item on the page was renumbered to make room (0,1,2,3,4,5,6,6 -- no gaps or dupes)" \
  "$(grep -oP 'focusedItemIndex === \K[0-9]' "$barpage_qml" | sort -n | tr '\n' ',')" "0,1,2,3,4,5,6,6,"

# --- Bar.qml: live Hyprland gaps_out sync, direct follow-up after the
# toggle itself worked: "the side and bottom gap from hyprland window
# is a bit much now" once the frame no longer visually fills it.
check "resolvedFrameEnabled transitions fire the live gap sync, but only once state has genuinely loaded" \
  "$(grep -c 'onResolvedFrameEnabledChanged: if (root.barSurfaceStateLoaded) root.syncFrameGaps()' "$bar_qml")" "1"
check "barSurfaceStateLoaded becoming true fires the initial sync -- confirmed live this is the one reliable trigger for the startup transition" \
  "$(grep -c 'onBarSurfaceStateLoadedChanged: if (root.barSurfaceStateLoaded) root.syncFrameGaps()' "$bar_qml")" "1"
check "re-enabling restores the real file-defined gaps via a plain reload, nothing hardcoded to remember/undo" \
  "$(grep -c 'command = \["bash", "-c", "hyprctl reload >/dev/null 2>&1 || true"\]' "$bar_qml")" "1"
check "disabling reads the CURRENT top gap live rather than hardcoding today's configured value" \
  "$(grep -c 'top=\$(hyprctl -j getoption general:gaps_out' "$bar_qml")" "1"
check "disabling applies via hl.config eval, confirmed the real mechanism -- this version's Hyprland rejects legacy hyprctl keyword outright" \
  "$(grep -c 'hyprctl eval \\"hl.config({ general = { gaps_out = { top = \$top, right = \$top, bottom = \$top, left = \$top } } })\\"' "$bar_qml")" "1"
check "syncFrameGaps stops any in-flight run before reassigning -- confirmed live, two near-simultaneous calls at real startup otherwise race and the second one's command silently never takes effect" \
  "$(grep -A2 'function syncFrameGaps() {' "$bar_qml" | grep -c 'if (frameGapSyncProc.running) frameGapSyncProc.running = false')" "1"

# --- Overlay.qml / NotchWindow.qml: direct follow-up -- the painted
# edge-band fix above wasn't well received live ("the user kinda didnt
# like the the top frame only"), so the notch instead collapses its own
# reserved top space when the frame is off, sitting flush against the
# true screen edge instead of keeping a gap nothing visually justifies.
check "Overlay.qml declares its own frameEnabled, defaulting to on, mirroring Bar.qml's shape" \
  "$(grep -c 'property bool frameEnabled: true' "$overlay_qml")" "1"
check "applyBarSurfaceState takes frameEnabled as a third argument" \
  "$(grep -c 'function applyBarSurfaceState(colorMode, material, frameEnabled)' "$overlay_qml")" "1"
check "a missing/non-false frameEnabled value in the state file still defaults to on" \
  "$(grep -c 'root.frameEnabled = frameEnabled !== false' "$overlay_qml")" "1"
check "loadBarSurfaceState passes the parsed frameEnabled field through" \
  "$(grep -c 'root.applyBarSurfaceState(p && p.color, p && p.material, p && p.frameEnabled)' "$overlay_qml")" "1"
check "notchOuter's restY collapses to 0 with the frame off instead of keeping the 4px resting gap" \
  "$(grep -A20 'id: notchOuter' "$notch_window_qml" | grep -c 'readonly property int restY: panel.notchRoot.frameEnabled ? 4 : 0')" "1"

# --- Bar.qml: direct follow-up -- the painted edge-band compromise
# wasn't well received live either ("the user kinda didnt like the the
# top frame only"), so the bar's own floating pills get the same
# flush-edge treatment as the notch/shelf instead, routed through the
# one property (contentTopInset) everything else already derives the
# real on-screen top position from -- not a second condition threaded
# through every call site.
check "contentTopInset collapses the floating branch to 0 with the frame off; docked is untouched" \
  "$(grep -c 'readonly property int contentTopInset: docked ? frameInset : (resolvedFrameEnabled ? topInset : 0)' "$bar_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
