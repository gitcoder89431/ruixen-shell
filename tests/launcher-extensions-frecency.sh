#!/usr/bin/env bash
# Direct follow-up to the app/Omarchy-Actions frecency work: "so for
# settings and wallpapers, our extensions, i dont think these are
# included in the ranking thing yet cause setting is always below
# wallpapers... should we do that for these too."
#
# Two real gaps, both fixed here:
#
# 1. Recording never happened. activateSelected() returns early for
#    all 4 ways of reaching Settings/Wallpapers (the "settings-
#    extension"/"wallpapers-extension" landing-list rows, and the
#    "omarchy:ruixen.settings"/"omarchy:ruixen.wallpapers" synthetic
#    typed-search rows) -- well above the point where a normal result
#    would fall through to provider.activate(), which is what actually
#    calls recordLaunch() for every other Omarchy Action. So even
#    though scoreEntry() already supported a frecency boost for these
#    two synthetic rows, the stats behind it were always empty.
#
# 2. The landing list's own "Extensions" group was a fixed
#    [Wallpapers, Settings] array, never reordered by anything.
#
# Static QML checks only -- verifying the actual on-screen reorder
# needs a live launcher and real launch history, not something a CI
# fixture can measure cheaply.
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

check "Launcher.qml imports the shared frecency module" \
  "$(grep -c 'import "LauncherFrecency.js" as Frecency' "$launcher_qml")" "1"

# --- recording: all 4 activation paths now call recordLaunch ------------

check "wallpapers-extension landing row records a launch" \
  "$(grep -A5 'result.providerId === "wallpapers-extension"' "$launcher_qml" | grep -c 'recordLaunch("ruixen.wallpapers")')" "1"
check "settings-extension landing row records a launch" \
  "$(grep -A5 'result.providerId === "settings-extension"' "$launcher_qml" | grep -c 'recordLaunch("ruixen.settings")')" "1"
check "omarchy:ruixen.settings synthetic row records a launch" \
  "$(grep -A5 'result.id === "omarchy:ruixen.settings"' "$launcher_qml" | grep -c 'recordLaunch("ruixen.settings")')" "1"
check "omarchy:ruixen.wallpapers synthetic row records a launch" \
  "$(grep -A5 'result.id === "omarchy:ruixen.wallpapers"' "$launcher_qml" | grep -c 'recordLaunch("ruixen.wallpapers")')" "1"

# --- ranking: the landing-list Extensions group is now frecency-sorted --

check "the Extensions group looks up frecency for both wallpapers and settings" \
  "$(grep -c 'frecencyFor("ruixen.wallpapers")\|frecencyFor("ruixen.settings")' "$launcher_qml")" "2"
check "the Extensions rows are actually sorted (not just scored and left in place)" \
  "$(grep -c 'extRows.sort(' "$launcher_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
