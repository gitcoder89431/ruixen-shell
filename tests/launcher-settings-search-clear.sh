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
#
# Issue #104: the 12 separate per-extension activateSelected() branches
# this test used to pin one by one (6 providerId branches + 6 synthetic
# omarchy:ruixen.* branches, each with its own activeExtensionId/
# searchHeader.text/root.query/recordLaunch triplet) collapsed into one
# generic block keyed through ExtensionRegistry -- see Launcher.qml's
# own extMatch comment. There is now exactly one place in the whole file
# that clears searchHeader.text/root.query on an extension jump, not 12,
# so this test's own job shrank to matching: that one generic block
# really does still clear both, and the file-wide total reflects that
# collapse (2, not 13) rather than quietly still being 13 some other way.
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

# The one generic block (keyed by ExtensionRegistry.byProviderId/
# byOmarchyActionId, see Launcher.qml's own extMatch comment) that now
# covers every extension -- both strings cleared right after
# activeExtensionId is set, same as every one of the 12 branches it
# replaced always did.
check "the generic extension-jump block clears searchHeader.text" \
  "$(grep -A3 'root.activeExtensionId = extMatch.id$' "$launcher_qml" | grep -c 'searchHeader.text = ""')" "1"
check "the generic extension-jump block clears root.query" \
  "$(grep -A4 'root.activeExtensionId = extMatch.id$' "$launcher_qml" | grep -c 'root.query = ""')" "1"

# 3 total across the file: finishClosing()'s own pre-existing pair, the
# one generic extension-jump block, and Kanban's own onQueryClearRequested
# after creating a card from typed search text -- that handler clears
# BOTH halves of the alias pair (searchHeader.text is the actual visible
# input; root.query alone leaves the typed title still showing on
# screen, since nothing mirrors root.query back into searchHeader.text).
check "searchHeader.text is cleared exactly 3 times total (finishClosing + the one generic extension jump + Kanban's own onQueryClearRequested)" \
  "$(grep -c 'searchHeader.text = ""' "$launcher_qml")" "3"
check "root.query is cleared exactly 3 times total (finishClosing + the one generic extension jump + Kanban's own onQueryClearRequested after creating a card from typed search text)" \
  "$(grep -c 'root.query = ""' "$launcher_qml")" "3"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
