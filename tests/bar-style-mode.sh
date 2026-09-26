#!/usr/bin/env bash
# Guards the bar.style split:
# - "notch" remains the default current skin.
# - "fullbar" is the saved old full-strip/statusline skin.
# - Hyprland sharp/rounded curvature must not select fullbar.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
bar_qml="$repo_dir/bars/v2/ruixen.bar/Bar.qml"
notch_qml="$repo_dir/bars/widgets/ruixen.notch/Overlay.qml"
style_script="$repo_dir/ruixen-bar-style.sh"
readme="$repo_dir/README.md"
install_sh="$repo_dir/install.sh"

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

check "fallback bar config defaults to notch style" \
  "$(grep -m1 'style: "notch"' "$bar_qml")" '    style: "notch",'

check "Bar.qml declares barStyle state" \
  "$(grep -m1 'property string barStyle: "notch"' "$bar_qml")" '  property string barStyle: "notch"'

check "Bar.qml exposes fullbarStyle as the only fullbar flag" \
  "$(grep -m1 'readonly property bool fullbarStyle: barStyle === "fullbar"' "$bar_qml")" '  readonly property bool fullbarStyle: barStyle === "fullbar"'

check "bar.style, not the lookfeel variant, selects fullbar" \
  "$(grep -m1 'barStyle = config.style === "fullbar" ? "fullbar" : "notch"' "$bar_qml")" '    barStyle = config.style === "fullbar" ? "fullbar" : "notch"'

check "fullbar removes the notch center reservation" \
  "$(grep -m1 'root.fullbarStyle ? 0 : root.notchReservedWidth' "$bar_qml")" '    var r = BarModel.reservedCenterRect(root.fullbarStyle ? 0 : root.notchReservedWidth, containerWidth, root.barSize)'

check "fullbar restores the saved full-width docked strip" \
  "$(grep -m1 'width: root.fullbarStyle ? parent.width' "$bar_qml")" '          width: root.fullbarStyle ? parent.width : (settingsPill.x + settingsPill.width)'

check "fullbar restores the saved right-edge corner patch" \
  "$(grep -A4 'Historical sharp+docked full-strip corner patch' "$bar_qml" | grep -m1 'visible: root.docked && root.fullbarStyle')" '          visible: root.docked && root.fullbarStyle'

check "normal right docked background is disabled in fullbar" \
  "$(grep -A5 'id: rightDockedBg$' "$bar_qml" | grep -m1 'visible: root.docked && !root.fullbarStyle')" '          visible: root.docked && !root.fullbarStyle'

check "notch reads shell.json to learn bar.style" \
  "$(grep -m1 'readonly property string shellConfigPath:' "$notch_qml")" '  readonly property string shellConfigPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"'

check "notch hides itself in fullbar style" \
  "$(grep -m1 'visible: !root.fullscreenActive && !root.barHidden && !root.fullbarStyle' "$notch_qml")" '    visible: !root.fullscreenActive && !root.barHidden && !root.fullbarStyle'

check "bar style helper supports fullbar" \
  "$(grep -m1 'Usage: ruixen-bar-style <notch|fullbar|status>' "$style_script")" 'Usage: ruixen-bar-style <notch|fullbar|status>'

check "bar style helper writes bar.style" \
  "$(grep -m1 -F "d.setdefault('bar', {})['style'] = '\$style'" "$style_script")" "d.setdefault('bar', {})['style'] = '\$style'"

check "README documents fullbar style" \
  "$(grep -m1 './ruixen-bar-style.sh fullbar' "$readme")" './ruixen-bar-style.sh fullbar    # full-width statusline skin, no notch'

check "install output mentions fullbar helper" \
  "$(grep -m1 'ruixen-bar-style.sh fullbar' "$install_sh")" "  \$script_dir/ruixen-bar-style.sh fullbar"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
