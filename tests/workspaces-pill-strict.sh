#!/usr/bin/env bash
# Covers issue #36: a tester's workspace pill looked broken (dots
# "floating/misaligned" inside the black pill, with unrelated icons
# sitting beside them). Root cause was not the workspace indicator's
# own geometry -- workspacesContent (Bar.qml) used to render anything
# in the "left" region except a short exclusion list (applauncher,
# settingsbutton, pinnedapps), an accidental catch-all. Any stale or
# hand-dragged foreign bar-widget left in "left" rendered sharing that
# Row with the real ~11px-tall workspace dots.
#
# Fix: workspacesContent is now a strict single-id match, so it can
# never host an arbitrary foreign id even if a malformed/stale
# shell.json puts one in "left" -- the matching migration that moves
# such legacy entries into ruixen.pluginpins' own group instead lives
# in lib/build-shell-json.sh (see tests/shell-json-merge.sh's own
# issue #36 cases for that half).
#
# Can't drive a real Quickshell instance here (no compositor in CI), so
# this is a static invariant check against the actual QML source, same
# style as tests/bar-right-side-groups.sh's own pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
bar_qml="$repo_dir/ruixen.bar/Bar.qml"

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

check "workspacesContent is a strict single-id match on ruixen.workspaces, not an exclusion list" \
  "$(grep -A16 'id: workspacesContent$' "$bar_qml" | grep -c 'root\.entryId(e) === "ruixen\.workspaces"' || true)" "1"

check "workspacesContent no longer excludes by a negative id list (the old accidental catch-all)" \
  "$(grep -A16 'id: workspacesContent$' "$bar_qml" | grep -c 'entryId(e) !==' || true)" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
