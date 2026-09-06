#!/usr/bin/env bash
# Covers update.sh --check-json -- the machine-readable sibling of
# --dry-run that ruixen.settings' Plugins page "check for updates" icon
# actually parses. Same local bare-upstream + second-clone technique
# tests/update-dry-run.sh already established.
set -Eeuo pipefail

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
mkdir -p "$checkout/ruixen.notch" "$checkout/ruixen.bar"
printf 'v1\n' >"$checkout/ruixen.notch/VERSION"
printf 'v1\n' >"$checkout/ruixen.bar/VERSION"
git -C "$checkout" add ruixen.notch ruixen.bar
git -C "$checkout" commit -q -m "initial"
git -C "$checkout" push -q -u origin master

cp "$repo_dir/update.sh" "$checkout/update.sh"
git -C "$checkout" add update.sh
git -C "$checkout" commit -q -m "add update.sh"
git -C "$checkout" push -q origin master

# --- Case 1: already up to date -----------------------------------------
out1="$(HOME="$fake_home" "$checkout/update.sh" --check-json 2>&1)"
check "up to date: reports upToDate true" "$out1" '{"upToDate": true, "changedPlugins": []}'

# --- Case 2: a second clone changes only ruixen.notch --------------------
other_clone="$fake_home/other-clone"
git clone -q "$upstream" "$other_clone"
git -C "$other_clone" config user.email test@example.com
git -C "$other_clone" config user.name test
printf 'v2\n' >"$other_clone/ruixen.notch/VERSION"
git -C "$other_clone" add ruixen.notch
git -C "$other_clone" commit -q -m "bump notch"
git -C "$other_clone" push -q origin master

out2="$(HOME="$fake_home" "$checkout/update.sh" --check-json 2>&1)"
check "one plugin changed: upToDate is false" "$(grep -c '"upToDate": false' <<<"$out2")" "1"
check "one plugin changed: names ruixen.notch" "$(grep -c '"ruixen.notch"' <<<"$out2")" "1"
check "one plugin changed: does not name ruixen.bar" "$(grep -c '"ruixen.bar"' <<<"$out2")" "0"
check "one plugin changed: HEAD is unchanged (no pull happened)" \
  "$(git -C "$checkout" rev-parse HEAD)" "$(git -C "$other_clone" rev-parse HEAD^)"

# --- Case 3: a dirty checkout is reported as an error, not silently ------
printf 'local edit\n' >>"$checkout/ruixen.notch/VERSION"
out3="$(HOME="$fake_home" "$checkout/update.sh" --check-json 2>&1)"
check "dirty checkout: reported as an error" "$out3" '{"error":"dirty checkout"}'

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
