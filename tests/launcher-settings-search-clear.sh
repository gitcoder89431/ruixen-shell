#!/usr/bin/env bash
# Direct report: searching "settings" in the launcher, hitting Enter,
# landed inside the Settings extension with "settings" still sitting
# in the search box. SettingsContent/WallpapersContent's own
# searchText binding (Launcher.qml: "root.activeExtensionId === ... ?
# root.query : """) reuses whatever's in the search box as a live
# filter over the LEFT-side category list -- a real, separate feature
# for typing WHILE already inside the extension ("does search work for
# menu items on the left too?"), but wrong for whatever query got you
# there in the first place: it hid every category that doesn't happen
# to contain the word "settings", i.e. all of them.
#
# Fix: every activateSelected() branch that jumps into Settings or
# Wallpapers now clears both searchHeader.text and root.query, same
# two-way alias pair finishClosing() already clears together on
# dismiss (searchHeader.text is a `property alias text: searchInput.text`,
# so setting it also fires the onTextChanged that mirrors into
# root.query -- both are set explicitly here anyway, matching
# finishClosing()'s own belt-and-suspenders style rather than relying
# on that signal chain alone).
#
# Static QML checks only -- verifying the actual on-screen "side panels
# reappear" result needs a live launcher and a real query, not
# something a CI fixture can measure cheaply.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
launcher_qml="$repo_dir/ruixen.launcher/Launcher.qml"

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

# Each of the 4 activateSelected() branches that enter Settings/
# Wallpapers sets activeExtensionId then clears both -- 3 lines each,
# so grep -A2 right after the activeExtensionId assignment catches all
# of them individually.

check "wallpapers-extension result clears searchHeader.text" \
  "$(grep -A2 'activeExtensionId = "wallpapers"$' "$launcher_qml" | grep -c 'searchHeader.text = ""')" "2"
check "wallpapers-extension result clears root.query" \
  "$(grep -A3 'activeExtensionId = "wallpapers"$' "$launcher_qml" | grep -c 'root.query = ""')" "2"
check "settings-extension result clears searchHeader.text" \
  "$(grep -A2 'activeExtensionId = "settings"$' "$launcher_qml" | grep -c 'searchHeader.text = ""')" "2"
check "settings-extension result clears root.query" \
  "$(grep -A3 'activeExtensionId = "settings"$' "$launcher_qml" | grep -c 'root.query = ""')" "2"

# 5 total across the file: finishClosing()'s own pre-existing pair, plus
# one for each of the 4 activateSelected() jump branches.
check "searchHeader.text is cleared exactly 5 times total (finishClosing + the 4 extension jumps)" \
  "$(grep -c 'searchHeader.text = ""' "$launcher_qml")" "5"
check "root.query is cleared exactly 5 times total (finishClosing + the 4 extension jumps)" \
  "$(grep -c 'root.query = ""' "$launcher_qml")" "5"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
