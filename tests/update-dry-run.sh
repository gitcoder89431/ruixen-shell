#!/usr/bin/env bash
# Covers issue #31's update half: update.sh --dry-run. Uses the same
# local bare-upstream + second-clone technique tests/lifecycle-lock.sh
# already established to simulate "someone else pushed new commits"
# without touching the real network.
set -Eeuo pipefail
trap 'printf "DIAG: failed at line %s: %s\n" "$LINENO" "$BASH_COMMAND" >&2' ERR

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"

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

fake_home="$(mktemp -d)"
trap 'rm -rf "$fake_home"' EXIT

upstream="$fake_home/upstream.git"
checkout="$fake_home/checkout"
git init --bare -q -b master "$upstream"
git clone -q "$upstream" "$checkout"
git -C "$checkout" config user.email test@example.com
git -C "$checkout" config user.name test
printf 'v1\n' >"$checkout/VERSION"
git -C "$checkout" add VERSION
git -C "$checkout" commit -q -m "initial"
git -C "$checkout" push -q -u origin master

# update.sh's own script_dir always resolves to wherever the script
# FILE itself lives, not $repo_dir -- it must be the fake checkout's
# own copy for this test to exercise the right tree at all (a first
# draft of this test invoked $repo_dir/update.sh directly and silently
# reported this real repo's own revision instead of the fake
# checkout's, never actually testing anything). install.sh/lib/
# hyprland are also copied in so update.sh's own final `exec
# install.sh --dry-run` has something real to call.
cp "$repo_dir/update.sh" "$checkout/update.sh"
cp "$repo_dir/install.sh" "$checkout/install.sh"
cp -r "$repo_dir/lib" "$checkout/lib"
mkdir -p "$checkout/hyprland"
cp -r "$repo_dir/hyprland/." "$checkout/hyprland/" 2>/dev/null || true
git -C "$checkout" add update.sh install.sh lib hyprland
git -C "$checkout" commit -q -m "add update.sh/install.sh"
git -C "$checkout" push -q origin master

before_head="$(git -C "$checkout" rev-parse HEAD)"

# --- Case 1: already up to date ---------------------------------------
out1="$(HOME="$fake_home" "$checkout/update.sh" --dry-run 2>&1)"
check "up to date: reports already up to date" "$(grep -c 'already up to date, nothing would be pulled' <<<"$out1")" "1"
check "up to date: HEAD is unchanged (no pull happened)" "$(git -C "$checkout" rev-parse HEAD)" "$before_head"

# --- Case 2: a second clone pushes a new commit, checkout is now behind
other_clone="$fake_home/other-clone"
git clone -q "$upstream" "$other_clone"
git -C "$other_clone" config user.email test@example.com
git -C "$other_clone" config user.name test
printf 'v2\n' >"$other_clone/VERSION"
git -C "$other_clone" add VERSION
git -C "$other_clone" commit -q -m "bump version"
git -C "$other_clone" push -q origin master

out2="$(HOME="$fake_home" "$checkout/update.sh" --dry-run 2>&1)"
check "behind: reports 1 commit ahead" "$(grep -c '1 commit(s) ahead of current' <<<"$out2")" "1"
check "behind: HEAD is STILL unchanged (dry-run never pulls the working tree)" "$(git -C "$checkout" rev-parse HEAD)" "$before_head"
check "behind: local VERSION file is still v1, not v2 (worktree untouched)" "$(cat "$checkout/VERSION")" "v1"

# --- Case 3: a dirty checkout is reported, not silently ignored -------
printf 'local edit\n' >>"$checkout/VERSION"
out3="$(HOME="$fake_home" "$checkout/update.sh" --dry-run 2>&1)"
check "dirty checkout: reported explicitly" "$(grep -c 'Local changes: yes' <<<"$out3")" "1"
check "dirty checkout: still says no files changed" "$(grep -c '^No files changed\.$' <<<"$out3")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
