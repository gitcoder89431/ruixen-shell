#!/usr/bin/env bash
# LIVE end-to-end check for ruixen.shelf's IPC surface -- the one thing the
# static/JS suite cannot prove. It drives the real `omarchy-shell ruixen.shelf
# ...` boundary against a RUNNING Omarchy shell, so it catches what only a
# live host shows: arguments the host splits or mangles before our handler
# ever runs.
#
# Why this exists: addMany once took a JSON array. Every static check was
# green, the JS model tests were green, and the notch quick-drop was still
# 100% broken, because the host split '["/a","/b"]' into three arguments and
# refused the call (and a one-element array arrived as a bare scalar and
# silently added nothing). Only a call through the real boundary shows that.
#
# Deliberately NOT in run-all.sh or CI (there is no shell there) -- same
# status as tests/host-contract-regression.sh. Run it by hand after any
# change to ruixen.shelf/Shelf.qml's IpcHandler or the notch's relay, after
# a real `omarchy restart shell`:
#
#   ./tests/live-shelf-ipc.sh
#
# Safe to run on your real shelf: it only ever adds paths under its own
# throwaway temp directory, removes exactly those (also on failure, via the
# EXIT trap), and never calls `clear`. Skips (exit 0, clearly labeled) when
# there is no omarchy-shell, jq, or no ruixen.shelf target responding.
set -Eeuo pipefail

skip() {
  printf 'live-shelf-ipc: SKIPPED -- %s\n' "$1"
  exit 0
}

command -v omarchy-shell >/dev/null 2>&1 || skip "omarchy-shell not found (needs a live Omarchy shell)"
command -v jq >/dev/null 2>&1 || skip "jq not found"

shelf() {
  omarchy-shell ruixen.shelf "$@"
}

if ! shelf list >/dev/null 2>&1; then
  skip "no ruixen.shelf IPC target responding (enable the plugin and run: omarchy restart shell)"
fi

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

work="$(mktemp -d)"

# Removes only the items this run added (everything under $work), then the
# temp dir. Never touches the user's other shelf items.
cleanup() {
  local ids id
  ids="$(shelf list 2>/dev/null | jq -r --arg w "$work/" '.items[] | select(.path | startswith($w)) | .id' 2>/dev/null || true)"
  while IFS= read -r id; do
    if [[ -n "$id" ]]; then
      shelf remove "$id" >/dev/null 2>&1 || true
    fi
  done <<<"$ids"
  rm -rf "$work"
}
trap cleanup EXIT

# Awkward-on-purpose names: spaces, #, parentheses, %, Unicode, a folder, and
# symlinks to both a file and a folder.
printf 'x' > "$work/plain.txt"
mkdir "$work/dir with spaces"
printf 'x' > "$work/dir with spaces/file #1 (2).txt"
printf 'x' > "$work/ü ñ 100%.txt"
mkdir "$work/folder"
ln -s "$work/plain.txt" "$work/link-to-file"
ln -s "$work/folder" "$work/link-to-folder"
printf 'x' > "$work/agent (added) #2.txt"

summary() {
  jq -c '[.ok, .added, .rejected]' <<<"$1"
}

# --- addMany: newline-delimited, one argument -------------------------------
batch="$(printf '%s\n' "$work/plain.txt" "$work/dir with spaces/file #1 (2).txt" "$work/ü ñ 100%.txt" "$work/folder")"
resp="$(shelf addMany "$batch" user 2>&1 || true)"
check "addMany: a four-path newline batch arrives as ONE argument and all four are added" "$(summary "$resp")" "[true,4,0]"

resp="$(shelf addMany "$(printf '%s\n' "$work/link-to-file" "relative/nope")" user 2>&1 || true)"
check "addMany: a bad (relative) path is counted as rejected, the good one is still added" "$(summary "$resp")" "[true,1,1]"

resp="$(shelf addMany "$work/link-to-folder" user 2>&1 || true)"
check "addMany: a single path (no delimiter at all) is added -- not silently dropped as a scalar" "$(summary "$resp")" "[true,1,0]"

resp="$(shelf addMany "$work/plain.txt"$'\n' user 2>&1 || true)"
check "addMany: a trailing newline is harmless" "$(summary "$resp")" "[true,1,0]"

resp="$(shelf addMany "relative/only" user 2>&1 || true)"
check "addMany: a batch with nothing acceptable reports ok:false, rejected:1" "$(summary "$resp")" "[false,0,1]"

# --- add (the agent-facing single path) --------------------------------------
resp="$(shelf add relative/path 2>&1 || true)"
check "add: a relative path is refused" "$(jq -r '.ok' <<<"$resp")" "false"

resp="$(shelf add "$work/agent (added) #2.txt" 2>&1 || true)"
check "add: an absolute path with spaces, # and parentheses is accepted" "$(jq -r '.ok' <<<"$resp")" "true"

# --- list: the stat pass is async, so wait for it to cover our paths ---------
list_json=""
for _ in $(seq 1 24); do
  list_json="$(shelf list)"
  pending="$(jq --arg w "$work/" '[.items[] | select(.path | startswith($w)) | select(.exists == null)] | length' <<<"$list_json")"
  if [[ "$pending" == "0" ]]; then
    break
  fi
  sleep 0.25
done

describe() {
  jq -r --arg p "$1" '.items[] | select(.path == $p) | "\(.kind)/\(.exists)/\(.source)"' <<<"$list_json"
}

check "list: a plain file reads kind file, exists, source user" "$(describe "$work/plain.txt")" "file/true/user"
check "list: a folder reads kind folder" "$(describe "$work/folder")" "folder/true/user"
check "list: a symlink to a file follows through to kind file" "$(describe "$work/link-to-file")" "file/true/user"
check "list: a symlink to a folder follows through to kind folder" "$(describe "$work/link-to-folder")" "folder/true/user"
check "list: a name with spaces, # and parentheses round-trips exactly (batch-added, source user)" "$(describe "$work/dir with spaces/file #1 (2).txt")" "file/true/user"
check "list: an agent-added path (via add) carries source agent" "$(describe "$work/agent (added) #2.txt")" "file/true/agent"
check "list: a Unicode name with a % round-trips exactly" "$(describe "$work/ü ñ 100%.txt")" "file/true/user"
check "list: our seven distinct paths are all present, none duplicated" \
  "$(jq --arg w "$work/" '[.items[] | select(.path | startswith($w)) | .path] | unique | length' <<<"$list_json")" "7"

# --- remove: by path and by id -------------------------------------------------
resp="$(shelf remove "$work/plain.txt" 2>&1 || true)"
check "remove: by path" "$(jq -r '.ok' <<<"$resp")" "true"
resp="$(shelf remove "$work/plain.txt" 2>&1 || true)"
check "remove: the same path again changes nothing" "$(jq -r '.ok' <<<"$resp")" "false"

folder_id="$(shelf list | jq -r --arg p "$work/folder" '.items[] | select(.path == $p) | .id')"
resp="$(shelf remove "$folder_id" 2>&1 || true)"
check "remove: by id (from list)" "$(jq -r '.ok' <<<"$resp")" "true"

check "remove: both are gone from list" \
  "$(shelf list | jq --arg a "$work/plain.txt" --arg b "$work/folder" '[.items[] | select(.path == $a or .path == $b)] | length')" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
