#!/usr/bin/env bash
# Static contract for the About page's Restart Shell button -- direct
# ask: "above the uninstall component, is it safe or possible to add
# an omarchy restart shell button?" Confirmed safe: `omarchy restart
# shell` already fires from a live Settings button elsewhere in this
# same file (setCornerCurvature's own trailing restart), so this reuses
# that exact precedent rather than inventing a new mechanism.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
content_qml="$repo_dir/ruixen.launcher/extensions/settings/SettingsContent.qml"
about_qml="$repo_dir/ruixen.launcher/extensions/settings/pages/AboutPage.qml"

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

check "restartOmarchyShell() drives the same real command the corner-curvature/bar-style restarts already use, no confirmation gate unlike Uninstall" \
  "$(( $(grep -Fc 'omarchy restart shell >/dev/null 2>&1 || true' "$content_qml") + $(grep -Fc 'function restartOmarchyShell() { restartShellProc.running = true }' "$content_qml") ))" "4"

check "aboutItems has three entries now -- Restart Shell (select, no gate) ahead of the uninstall confirm field/button" \
  "$(grep -Fc 'activate: function() { root.restartOmarchyShell() }' "$content_qml")" "1"

check "focusedItemVisual's About mapping includes restartShellButton ahead of the uninstall pair" \
  "$(grep -Fc 'return [aboutPage.restartShellButton, aboutPage.uninstallConfirmRow, aboutPage.uninstallButtonRow][root.focusedItemIndex]' "$content_qml")" "1"

check "AboutPage exposes restartShellButton the same way it already exposes the uninstall row/button for cross-page keyboard nav" \
  "$(grep -Fc 'readonly property alias restartShellButton: restartShellItem' "$about_qml")" "1"

check "Restart Shell button exists, wired to the real action, not just a decorative Rectangle" \
  "$(( $(grep -c 'id: restartShellItem' "$about_qml") + $(grep -Fc 'onClicked: settingsRoot.restartOmarchyShell()' "$about_qml") + $(grep -Fc 'text: "Restart Shell"' "$about_qml") ))" "3"

check "Restart Shell sits above the danger zone in source order, not inside or below it" \
  "$(( $(grep -n 'id: restartShellItem' "$about_qml" | head -1 | cut -d: -f1) < $(grep -n 'id: dangerZoneItem' "$about_qml" | head -1 | cut -d: -f1) ))" "1"

check "Restart Shell's own focus ring uses index 0; uninstall confirm/button shifted to 1/2" \
  "$(( $(grep -c 'focusedItemIndex === 0' "$about_qml") + $(grep -c 'focusedItemIndex === 1' "$about_qml") + $(grep -c 'focusedItemIndex === 2' "$about_qml") ))" "3"

check "Restart Shell uses the plain bare-button weight Plugins' own Check/Update buttons use, not Uninstall's red destructive styling" \
  "$(grep -A5 'id: restartShellItem' "$about_qml" | grep -c 'color: restartShellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
