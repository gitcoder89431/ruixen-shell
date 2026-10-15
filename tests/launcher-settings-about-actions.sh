#!/usr/bin/env bash
# Static contract for the About page's Restart Shell / Open on GitHub
# buttons -- direct asks: "above the uninstall component, is it safe
# or possible to add an omarchy restart shell button?" (confirmed
# safe: `omarchy restart shell` already fires from a live Settings
# button elsewhere in this same file, setCornerCurvature's own
# trailing restart, so this reuses that exact precedent) and "on the
# same row or above it... one Open on Github" (omarchy-launch-browser
# is the same real open-in-default-browser helper Clipboard History's
# own link/QR opening already uses).
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

check "openRepoInBrowser() uses the same omarchy-launch-browser helper Clipboard History already uses, not a second mechanism" \
  "$(( $(grep -Fc 'command: ["omarchy-launch-browser", root.repoUrl]' "$content_qml") + $(grep -Fc 'function openRepoInBrowser() { openRepoProc.running = true }' "$content_qml") ))" "2"

check "repoUrl matches the real repo the version card already shows as plain text" \
  "$(( $(grep -Fc 'readonly property string repoUrl: "https://github.com/gitcoder89431/ruixen-shell"' "$content_qml") + $(grep -Fc 'github.com/gitcoder89431/ruixen-shell' "$about_qml") ))" "2"

check "aboutItems has four entries now -- Restart Shell and Open on GitHub (both select, no gate) ahead of the uninstall confirm field/button" \
  "$(( $(grep -Fc 'activate: function() { root.restartOmarchyShell() }' "$content_qml") + $(grep -Fc 'activate: function() { root.openRepoInBrowser() }' "$content_qml") ))" "2"

check "focusedItemVisual's About mapping includes both buttons ahead of the uninstall pair" \
  "$(grep -Fc 'return [aboutPage.restartShellButton, aboutPage.openGithubButton, aboutPage.uninstallConfirmRow, aboutPage.uninstallButtonRow][root.focusedItemIndex]' "$content_qml")" "1"

check "AboutPage exposes both buttons the same way it already exposes the uninstall row/button for cross-page keyboard nav" \
  "$(( $(grep -Fc 'readonly property alias restartShellButton: restartShellItem' "$about_qml") + $(grep -Fc 'readonly property alias openGithubButton: openGithubItem' "$about_qml") ))" "2"

check "Both buttons exist, wired to their real actions, not just decorative Rectangles" \
  "$(( $(grep -c 'id: restartShellItem' "$about_qml") + $(grep -Fc 'onClicked: settingsRoot.restartOmarchyShell()' "$about_qml") + $(grep -Fc 'text: "Restart Shell"' "$about_qml") + $(grep -c 'id: openGithubItem' "$about_qml") + $(grep -Fc 'onClicked: settingsRoot.openRepoInBrowser()' "$about_qml") + $(grep -Fc 'text: "Open on GitHub"' "$about_qml") ))" "6"

check "Restart Shell and Open on GitHub are both half-width, side by side in one Row -- same pairing shape Plugins' own Check/Update row uses" \
  "$(grep -c 'width: (parent.width - 8) / 2' "$about_qml")" "2"

check "The pair sits above the danger zone in source order, not inside or below it" \
  "$(( $(grep -n 'id: restartShellItem' "$about_qml" | head -1 | cut -d: -f1) < $(grep -n 'id: dangerZoneItem' "$about_qml" | head -1 | cut -d: -f1) ))" "1"

check "Focus ring order: Restart Shell 0, Open on GitHub 1, uninstall confirm 2, uninstall button 3" \
  "$(( $(grep -c 'focusedItemIndex === 0' "$about_qml") + $(grep -c 'focusedItemIndex === 1' "$about_qml") + $(grep -c 'focusedItemIndex === 2' "$about_qml") + $(grep -c 'focusedItemIndex === 3' "$about_qml") ))" "4"

check "Both buttons use the plain bare-button weight Plugins' own Check/Update buttons use, not Uninstall's red destructive styling" \
  "$(( $(grep -A5 'id: restartShellItem' "$about_qml" | grep -c 'color: restartShellMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)') + $(grep -A5 'id: openGithubItem' "$about_qml" | grep -c 'color: openGithubMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)') ))" "2"

check "run-all includes this contract" \
  "$(grep -c 'launcher-settings-about-actions\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
