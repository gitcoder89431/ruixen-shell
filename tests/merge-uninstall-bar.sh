#!/usr/bin/env bash
# Covers "[P0/P1] Preserve third-party bar widgets added while Ruixen
# is installed during uninstall" (#26): exercises
# lib/merge-uninstall-bar.sh directly against every fixture category
# the issue's own comment lists, plus two more found while building
# this function (stale inline settings surviving, a moved widget
# duplicating across regions) that its own comment now documents as
# real bugs an earlier, simpler per-region version of this script had.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
merge="$repo_dir/lib/merge-uninstall-bar.sh"
canon="$(cat "$repo_dir/lib/ruixen-bar-canonical.json")"

command -v jq >/dev/null 2>&1 || {
  printf 'merge-uninstall-bar: jq is required (command "jq" not found)\n' >&2
  exit 1
}

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

run_merge() {
  "$merge" "$1" "$2" "$canon"
}

# --- Case: pristine bar with no .layout key at all is returned
# completely unchanged -- a genuinely different bar implementation
# that never used this {left,center,right} convention (matches
# tests/uninstall-bar-restore.sh's own local.neon-bar fixture shape).
# Injecting a .layout key it doesn't understand wouldn't make any
# preserved widget actually appear anywhere real anyway. ------------
out="$(run_merge '{"id":"local.neon-bar","position":"bottom","transparent":false}' \
  '{"layout":{"left":[{"id":"ruixen.applauncher"},{"id":"test.thirdparty.left"}],"center":[],"right":[]}}')"
check "no-layout pristine bar: returned byte-for-byte unchanged" \
  "$(jq -c . <<<"$out")" '{"id":"local.neon-bar","position":"bottom","transparent":false}'

# --- Case: third-party added after install -------------------------
out="$(run_merge \
  '{"id":"local.old-bar","layout":{"left":[{"id":"local.launcher"}],"center":[],"right":[]}}' \
  '{"layout":{"left":[{"id":"ruixen.applauncher"},{"id":"ruixen.workspaces"},{"id":"test.thirdparty.left"}],"center":[{"id":"omarchy.menu"},{"id":"ruixen.media"},{"id":"ruixen.weather"},{"id":"omarchy.clock"}],"right":[{"id":"omarchy.keyboard-layout"},{"id":"omarchy.system-update"},{"id":"ruixen.tray"},{"id":"ruixen.stayawake"},{"id":"ruixen.quickactions"},{"id":"omarchy.agents"},{"id":"omarchy.power"},{"id":"ruixen.settingsbutton"}]}}')"
check "third-party added after install: appended after the baseline entry" \
  "$(jq -c '.layout.left' <<<"$out")" '[{"id":"local.launcher"},{"id":"test.thirdparty.left"}]'
check "third-party added after install: every Ruixen-owned entry is gone (center)" \
  "$(jq -c '.layout.center' <<<"$out")" '[]'
check "third-party added after install: every Ruixen-owned entry is gone (right)" \
  "$(jq -c '.layout.right' <<<"$out")" '[]'

# --- Case: third-party already present before install (baseline
# already has it too) -- must appear exactly once, not duplicated ---
out="$(run_merge \
  '{"id":"local.old-bar","layout":{"left":[{"id":"local.launcher"},{"id":"test.thirdparty.left"}],"center":[],"right":[]}}' \
  '{"layout":{"left":[{"id":"ruixen.applauncher"},{"id":"test.thirdparty.left"}],"center":[],"right":[]}}')"
check "third-party pre-existing before install: appears exactly once" \
  "$(jq -c '.layout.left' <<<"$out")" '[{"id":"local.launcher"},{"id":"test.thirdparty.left"}]'

# --- Case: third-party moved to a different region while Ruixen was
# active -- must appear ONLY in its new (current) region, not
# duplicated across both. A naive per-region-only merge gets this
# wrong (real bug this exact test caught before this file was ever
# wired into uninstall.sh). ------------------------------------------
out="$(run_merge \
  '{"id":"local.old-bar","layout":{"left":[{"id":"test.thirdparty.left"}],"center":[],"right":[]}}' \
  '{"layout":{"left":[{"id":"ruixen.applauncher"}],"center":[{"id":"omarchy.menu"},{"id":"test.thirdparty.left"}],"right":[]}}')"
check "moved third-party widget: gone from its old region" \
  "$(jq -c '.layout.left' <<<"$out")" '[]'
check "moved third-party widget: present in its new region, not duplicated" \
  "$(jq -c '.layout.center' <<<"$out")" '[{"id":"test.thirdparty.left"}]'

# --- Case: inline settings changed while Ruixen was active -- the
# CURRENT settings must win, not the stale baseline ones. A naive
# per-region-only merge also gets this wrong (same real bug as above,
# different symptom: "already in baseline" alone was wrongly treated
# as "nothing to update"). -------------------------------------------
out="$(run_merge \
  '{"id":"local.old-bar","layout":{"left":[],"center":[],"right":[{"id":"test.thirdparty.right","opacity":0.5}]}}' \
  '{"layout":{"left":[],"center":[],"right":[{"id":"ruixen.tray"},{"id":"test.thirdparty.right","opacity":0.9,"extra":"field"}]}}')"
check "inline settings changed while active: current (edited) settings win" \
  "$(jq -c '.layout.right' <<<"$out")" '[{"id":"test.thirdparty.right","opacity":0.9,"extra":"field"}]'

# --- Case: a Ruixen-injected omarchy.* entry must NOT be mistaken for
# a foreign addition -- ownership is by id, not by "ruixen." prefix -
out="$(run_merge \
  '{"id":"local.old-bar","layout":{"left":[],"center":[],"right":[]}}' \
  "$(jq -c -n --argjson c "$canon" '{layout: $c.layout}')")"
check "current bar is EXACTLY Ruixen's own canonical layout: nothing survives (left)" \
  "$(jq -c '.layout.left' <<<"$out")" '[]'
check "current bar is EXACTLY Ruixen's own canonical layout: nothing survives (center, incl. omarchy.menu/omarchy.clock)" \
  "$(jq -c '.layout.center' <<<"$out")" '[]'
check "current bar is EXACTLY Ruixen's own canonical layout: nothing survives (right, incl. omarchy.keyboard-layout etc.)" \
  "$(jq -c '.layout.right' <<<"$out")" '[]'

# --- Case: duplicate ids within the same live region are collapsed to
# one (last-seen wins), never duplicated in the restored output -----
out="$(run_merge \
  '{"id":"x","layout":{"left":[],"center":[],"right":[]}}' \
  '{"layout":{"left":[{"id":"test.dup"},{"id":"test.dup","later":true}],"center":[],"right":[]}}')"
check "duplicate id in current region: collapsed to one entry, last-seen settings" \
  "$(jq -c '.layout.left' <<<"$out")" '[{"id":"test.dup","later":true}]'

# --- Case: malformed (id-less) entries are handled conservatively --
# preserved rather than silently dropped, since they can't be
# correlated across baseline/current for real deduplication. --------
out="$(run_merge \
  '{"id":"x","layout":{"left":[{"weird":"no-id-baseline"}],"center":[],"right":[]}}' \
  '{"layout":{"left":[{"weird":"no-id-current"}],"center":[],"right":[]}}')"
check "malformed id-less entries: both preserved conservatively, neither dropped" \
  "$(jq -c '.layout.left | sort' <<<"$out")" '[{"weird":"no-id-baseline"},{"weird":"no-id-current"}]'

# --- Case: uninstall rerun/idempotency -- feeding this function's own
# output back in as the new "current" bar (same pristine) produces the
# exact same result again, not further drift or duplication. --------
pristine='{"id":"local.old-bar","layout":{"left":[{"id":"local.launcher"}],"center":[],"right":[]}}'
current='{"layout":{"left":[{"id":"ruixen.applauncher"},{"id":"test.thirdparty.left"}],"center":[],"right":[]}}'
result1="$(run_merge "$pristine" "$current")"
result2="$(run_merge "$pristine" "$result1")"
check "rerun/idempotency: a second merge over the first result is byte-for-byte identical" \
  "$(jq -S . <<<"$result2")" "$(jq -S . <<<"$result1")"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
