#!/usr/bin/env bash
# Read-only diagnostic report -- makes zero changes to anything. Built
# for exactly the situation that motivated it: a tester's update
# looked like it didn't take effect, and walking them through several
# separate commands one at a time over chat was slow and error-prone.
# This runs all of it in one shot and prints a single block they can
# paste back, with no filesystem paths, hostnames, or config content
# that would identify them -- only ids, versions, counts, and
# relative timestamps.
#
# Usage: from an existing ruixen-shell checkout, same as update.sh:
#   ./ruixen-doctor.sh
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
state_dir="$HOME/.local/state/ruixen"

human_ago() {
  local seconds="$1"
  if (( seconds < 60 )); then printf '%ds' "$seconds"
  elif (( seconds < 3600 )); then printf '%dm' "$((seconds / 60))"
  elif (( seconds < 86400 )); then printf '%dh' "$((seconds / 3600))"
  else printf '%dd' "$((seconds / 86400))"
  fi
}
plugins_dir="$HOME/.config/omarchy/plugins"

printf '=== Ruixen Shell Doctor ===\n\n'

# --- Omarchy itself -----------------------------------------------
printf -- '-- Omarchy --\n'
if command -v omarchy >/dev/null 2>&1; then
  printf 'version: %s\n' "$(omarchy version 2>/dev/null || echo unknown)"
else
  printf 'version: omarchy command not found\n'
fi
printf '\n'

# --- This checkout ---------------------------------------------------
printf -- '-- This checkout --\n'
if [[ -d "$script_dir/.git" ]]; then
  branch="$(git -C "$script_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  commit="$(git -C "$script_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  commit_date="$(git -C "$script_dir" log -1 --format=%cd --date=relative 2>/dev/null || echo unknown)"
  printf 'branch: %s\n' "$branch"
  printf 'commit: %s (%s)\n' "$commit" "$commit_date"

  if [[ -n "$(git -C "$script_dir" status --porcelain 2>/dev/null)" ]]; then
    dirty_count="$(git -C "$script_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    printf 'local changes: yes (%s file(s) modified -- update.sh will refuse to run until this is clean)\n' "$dirty_count"
  else
    printf 'local changes: none\n'
  fi

  # A REAL fetch, not --dry-run -- direct correction after --dry-run
  # was found to never refresh the local origin/<branch> tracking ref
  # at all, so this comparison could silently run against whatever
  # that ref last happened to be (potentially from days ago), reporting
  # "up to date" based on stale information rather than the actual
  # current state of the remote. This is the one check in the whole
  # report that reaches the network -- everything else is local-only.
  if git -C "$script_dir" fetch --quiet origin "$branch" >/dev/null 2>&1; then
    ahead_behind="$(git -C "$script_dir" rev-list --left-right --count HEAD...origin/"$branch" 2>/dev/null || echo "? ?")"
    ahead="$(awk '{print $1}' <<<"$ahead_behind")"
    behind="$(awk '{print $2}' <<<"$ahead_behind")"
    if [[ "$behind" == "0" ]]; then
      printf 'vs origin/%s: up to date (just fetched)\n' "$branch"
    else
      printf 'vs origin/%s: %s commit(s) behind -- run git pull, or ./update.sh\n' "$branch" "$behind"
    fi
    [[ "$ahead" != "0" ]] && printf 'vs origin/%s: %s local commit(s) not on origin\n' "$branch" "$ahead"
  else
    printf 'vs origin: could not reach remote (offline?) -- this check needs real network access, everything else in this report is local-only\n'
  fi
else
  printf 'not a git checkout -- update.sh and this doctor script both need one\n'
fi

recorded_path="$(cat "$state_dir/repo-path" 2>/dev/null || echo "")"
if [[ -z "$recorded_path" ]]; then
  printf 'last successful install ran from: no record found (install.sh predates this, or never completed)\n'
elif [[ "$recorded_path" == "$script_dir" ]]; then
  printf 'last successful install ran from: this same checkout\n'
else
  printf 'last successful install ran from: a DIFFERENT checkout than this one -- you may have more than one ruixen-shell folder on disk\n'
fi
printf '\n'

# --- Deployed plugin FILES vs this checkout own source ---------------
# Direct correction after a real report proved this wrong: comparing
# manifest.json "version" strings looked reassuring ("all OK") while
# the actual deployed Bar.qml was hours of commits behind, because
# most plugin edits that whole night never bumped that version field
# at all -- a version match said nothing real about whether the file
# CONTENT matched. This hashes every real file in each plugin
# directory instead (recursive, sorted so enumeration order never
# matters, manifest.json included) -- a single changed byte anywhere,
# bumped version or not, shows up here.
dir_hash() {
  local dir="$1"
  [[ -d "$dir" ]] || { echo "(missing)"; return; }
  # cd into the directory first, not `find "$dir"` -- sha256sum's own
  # output includes the path it hashed, and source/deployed live at
  # two different absolute locations by design. Hashing absolute paths
  # would make every single plugin report a false mismatch regardless
  # of content (caught live: it did, for all fifteen, before this fix).
  # Relative paths from inside each tree are identical when the
  # content and structure actually match.
  (cd "$dir" && find . -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null) | sha256sum | awk '{print $1}'
}
printf -- '-- Plugin files (source in this checkout vs deployed, by content hash) --\n'
mismatch_count=0
for dir in "$script_dir"/ruixen.*/; do
  [[ -d "$dir" ]] || continue
  id="$(basename "$dir")"
  source_version="$(jq -r '.version // "?"' "$dir/manifest.json" 2>/dev/null || echo "?")"

  if [[ ! -e "$plugins_dir/$id" ]]; then
    printf '%-24s v%-8s deployed MISSING (never installed here)\n' "$id" "$source_version"
    mismatch_count=$((mismatch_count + 1))
  else
    source_hash="$(dir_hash "$dir")"
    deployed_hash="$(dir_hash "$plugins_dir/$id")"
    if [[ "$source_hash" == "$deployed_hash" ]]; then
      printf '%-24s v%-8s -- OK, file contents match exactly\n' "$id" "$source_version"
    else
      printf '%-24s v%-8s -- CONTENT MISMATCH (deployed files differ from this checkout, regardless of version number -- install.sh did not update this one)\n' "$id" "$source_version"
      mismatch_count=$((mismatch_count + 1))
    fi
  fi
done
if [[ "$mismatch_count" -eq 0 ]]; then
  printf '(every plugin file exactly matches this checkout own source)\n'
fi
printf '\n'

# --- Backups -- presence proves whether install.sh own copy step ever
# ran for a given plugin at all, regardless of what version it left
# behind. -----------------------------------------------------------
printf -- '-- Plugin backups (proves whether a reinstall/update actually touched each one) --\n'
any_backup=0
for dir in "$script_dir"/ruixen.*/; do
  [[ -d "$dir" ]] || continue
  id="$(basename "$dir")"
  count=0
  newest=""
  for b in "$plugins_dir"/."$id".bak.*; do
    [[ -e "$b" ]] || continue
    count=$((count + 1))
    [[ -z "$newest" || "$b" -nt "$newest" ]] && newest="$b"
  done
  if [[ "$count" -gt 0 ]]; then
    any_backup=1
    age_seconds=$(( $(date +%s) - $(stat -c %Y "$newest" 2>/dev/null || echo 0) ))
    printf '%-24s %s backup(s), most recent %s ago\n' "$id" "$count" "$(human_ago "$age_seconds")"
  fi
done
[[ "$any_backup" -eq 0 ]] && printf '(no backups found for any ruixen.* plugin -- install.sh has never replaced an existing copy of any of them)\n'
printf '\n'

# --- Bar layout shape -- ids only, never inline settings values, so
# nothing personal (a custom clock format, a hidden app list) ever
# prints here. -------------------------------------------------------
printf -- '-- Bar layout (ids only) --\n'
shell_json="$HOME/.config/omarchy/shell.json"
if [[ -f "$shell_json" ]] && jq empty "$shell_json" >/dev/null 2>&1; then
  bar_id="$(jq -r '.bar.id // "(none set -- stock Omarchy default)"' "$shell_json")"
  printf 'active bar: %s\n' "$bar_id"
  if [[ "$bar_id" == "ruixen.bar" ]]; then
    printf 'docked: %s\n' "$(jq -r '.bar.docked // false' "$shell_json")"
    for section in left center right; do
      ids="$(jq -r --arg s "$section" '(.bar.layout[$s] // []) | map(.id) | join(", ")' "$shell_json")"
      printf '%-7s [%s]\n' "$section:" "$ids"
    done
  fi
else
  printf 'shell.json missing or not valid JSON\n'
fi
printf '\n'

# --- Runtime health ---------------------------------------------------
printf -- '-- Runtime --\n'
qs_count="$(pgrep -c -f '^quickshell -n' 2>/dev/null || echo 0)"
printf 'quickshell processes running: %s%s\n' "$qs_count" "$( [[ "$qs_count" -gt 1 ]] && echo ' (expected 1 -- an old instance may be stuck)' )"
if command -v omarchy-shell >/dev/null 2>&1 && OMARCHY_SHELL_IPC_TIMEOUT=1s omarchy-shell shell ping >/dev/null 2>&1; then
  printf 'shell IPC: responding\n'
else
  printf 'shell IPC: NOT responding -- try omarchy restart shell\n'
fi

printf '\n=== end of report -- safe to paste, contains no paths, hostnames, or personal config values ===\n'
