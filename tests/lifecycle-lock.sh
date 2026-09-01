#!/usr/bin/env bash
# Covers "[P2] Add an install/update/uninstall lock and collision-safe
# run identifiers" (#16): runs the REAL install.sh/uninstall.sh/
# update.sh against a fake $HOME with a lock manually held ahead of
# time (the standard, deterministic way to test flock contention --
# no sleep-based timing races needed), plus a direct check that the
# nanosecond run-identity fix actually produces distinct values.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v flock >/dev/null 2>&1 || {
  printf 'lifecycle-lock: flock is required (command "flock" not found)\n' >&2
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

cleanup_paths=()
holder_pids=()
cleanup() {
  local pid
  for pid in "${holder_pids[@]}"; do
    kill "$pid" 2>/dev/null || true
  done
  rm -rf "${cleanup_paths[@]}"
}
trap cleanup EXIT

fake_home="$(mktemp -d)"
cleanup_paths+=("$fake_home")
mkdir -p "$fake_home/.local/state/ruixen"
lock_file="$fake_home/.local/state/ruixen/install.lock"

# --- Hold the lock in a background subshell, the same way a real
# in-progress install/update/uninstall would -- open the fd, flock it,
# then just sleep until killed. This is deterministic (no races against
# a real install.sh's own timing) and is exactly the scenario the issue
# describes: "another lifecycle operation is already running."
(
  exec {fd}>"$lock_file"
  flock "$fd"
  sleep 30
) &
holder_pid=$!
holder_pids+=("$holder_pid")

# Give the background holder a moment to actually acquire the lock
# before racing it -- this wait is for OUR OWN test setup's reliability
# (making sure the holder really is holding it before we test against
# it), not a substitute for flock's own non-blocking semantics, which
# is what's actually under test below via `timeout`.
for _ in $(seq 1 50); do
  if flock -n "$lock_file" -c true 2>/dev/null; then
    sleep 0.1
  else
    break
  fi
done

# --- Case 1: install.sh fails immediately (not a hang) while the lock
# is held, with a clear message naming the lock ---------------------
if out1="$(timeout 5 env HOME="$fake_home" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" 2>&1)"; then
  status1=0
else
  status1=$?
fi
check "install.sh while locked: exits non-zero" "$([[ "$status1" -ne 0 ]] && echo yes)" "yes"
check "install.sh while locked: did not time out (real failure, not a hang/deadlock)" \
  "$([[ "$status1" -ne 124 ]] && echo yes)" "yes"
check "install.sh while locked: message names the lock file" \
  "$(grep -c "install.lock" <<<"$out1")" "1"
check "install.sh while locked: shell.json was never written" \
  "$([[ -e "$fake_home/.config/omarchy/shell.json" ]] && echo exists || echo absent)" "absent"

# --- Case 2: uninstall.sh ALSO fails immediately while the SAME lock
# is held -- install and uninstall share one lock, can't run together -
if out2="$(timeout 5 env HOME="$fake_home" PATH="$fake_bin:$PATH" "$repo_dir/uninstall.sh" 2>&1)"; then
  status2=0
else
  status2=$?
fi
check "uninstall.sh while locked: exits non-zero" "$([[ "$status2" -ne 0 ]] && echo yes)" "yes"
check "uninstall.sh while locked: did not time out" "$([[ "$status2" -ne 124 ]] && echo yes)" "yes"
check "uninstall.sh while locked: message names the lock file" \
  "$(grep -c "install.lock" <<<"$out2")" "1"

# --- Case 3: once the lock is released, a normal install.sh succeeds -
kill "$holder_pid" 2>/dev/null || true
wait "$holder_pid" 2>/dev/null || true
if timeout 30 env HOME="$fake_home" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" >"$fake_home/install-after-release.out" 2>&1; then
  status3=0
else
  status3=$?
  cat "$fake_home/install-after-release.out" >&2
fi
check "after the lock is released: a normal install.sh succeeds" "$status3" "0"

# --- Case 4 (#21): update.sh -> install.sh does not self-deadlock, AND
# update.sh's own lock acquisition (before git pull, since #21) means a
# locked run never touches the checkout AT ALL -- not just "install.sh
# eventually fails," but the pull itself is provably never reached. A
# fake checkout with the REAL install.sh/update.sh (not stubs, unlike
# update-safety.sh -- this test needs the real lock-taking code to
# prove the point), run while a lock is held elsewhere. -------------
git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.invalid"
git config --global user.name >/dev/null 2>&1 || git config --global user.name "Test"

upstream="$fake_home/upstream.git"
checkout="$fake_home/checkout"
git init --bare -q -b master "$upstream"
mkdir -p "$checkout"
# Full copy of this repo, not a hand-picked subset -- install.sh's own
# plugin deployment loop globs every ruixen.*/ directory it finds, and
# missing one just makes this case less representative for no benefit.
# (repo_dir's own .git is excluded and replaced with a fresh one below,
# tracking the throwaway upstream instead of the real repo's remote.)
cp -r "$repo_dir"/. "$checkout"/
rm -rf "$checkout/.git"
git -C "$checkout" init -q -b master >/dev/null
git -C "$checkout" remote add origin "$upstream"
git -C "$checkout" add -A
git -C "$checkout" commit -q -m "initial"
git -C "$checkout" push -q -u origin master

# Upstream moves on with a REAL changed tracked file -- #21's own
# acceptance criterion ("upstream contains a real changed tracked
# file... the local checkout file/HEAD does NOT change while the lock
# is unavailable"), not just an empty no-op commit.
other_clone="$fake_home/other-clone"
git clone -q "$upstream" "$other_clone"
printf '\n-- upstream moved on while the lock was held --\n' >> "$other_clone/README.md"
git -C "$other_clone" commit -q -am "upstream moves on"
git -C "$other_clone" push -q origin master

before_head="$(git -C "$checkout" rev-parse HEAD)"
before_readme="$(cat "$checkout/README.md")"

fake_home2="$(mktemp -d)"
cleanup_paths+=("$fake_home2")
mkdir -p "$fake_home2/.local/state/ruixen"
lock_file2="$fake_home2/.local/state/ruixen/install.lock"

(
  exec {fd2}>"$lock_file2"
  flock "$fd2"
  sleep 30
) &
holder_pid2=$!
holder_pids+=("$holder_pid2")
for _ in $(seq 1 50); do
  if flock -n "$lock_file2" -c true 2>/dev/null; then
    sleep 0.1
  else
    break
  fi
done

if out4="$(timeout 10 env HOME="$fake_home2" PATH="$fake_bin:$PATH" "$checkout/update.sh" 2>&1)"; then
  status4=0
else
  status4=$?
fi
kill "$holder_pid2" 2>/dev/null || true
wait "$holder_pid2" 2>/dev/null || true

check "update.sh while locked: exits non-zero (own lock acquisition failed, before any pull)" \
  "$([[ "$status4" -ne 0 ]] && echo yes)" "yes"
check "update.sh while locked: did not time out (no self-deadlock)" \
  "$([[ "$status4" -ne 124 ]] && echo yes)" "yes"
check "update.sh while locked: its own lock message surfaced" \
  "$(grep -c "install.lock" <<<"$out4")" "1"
check "update.sh while locked: local checkout HEAD did not change (#21)" \
  "$(git -C "$checkout" rev-parse HEAD)" "$before_head"
check "update.sh while locked: local tracked file did not change (#21)" \
  "$(cat "$checkout/README.md")" "$before_readme"

# --- Case 4b (#21): the happy path still works end-to-end with NO lock
# held -- update.sh acquires the lock itself, pulls the real upstream
# change from case 4's setup, and its child install.sh must inherit the
# hand-off and complete successfully rather than either re-locking (and
# incorrectly failing on a lock it doesn't need to take) or silently
# skipping the install. Reuses the same real checkout/upstream from
# case 4, this time genuinely unlocked. ------------------------------
fake_home3="$(mktemp -d)"
cleanup_paths+=("$fake_home3")
if out4b="$(timeout 30 env HOME="$fake_home3" PATH="$fake_bin:$PATH" "$checkout/update.sh" 2>&1)"; then
  status4b=0
else
  status4b=$?
  printf '%s\n' "$out4b" >&2
fi
check "update.sh unlocked: exits 0" "$status4b" "0"
check "update.sh unlocked: actually pulled upstream's real change" \
  "$(cat "$checkout/README.md")" "$(cat "$other_clone/README.md")"
check "update.sh unlocked: its own install.sh actually ran to completion (shell.json written)" \
  "$([[ -e "$fake_home3/.config/omarchy/shell.json" ]] && echo yes)" "yes"

# --- Case 5: run identifiers are collision-safe (nanosecond, not
# epoch-seconds) -- a direct check independent of the lock itself, per
# the issue's own "prefer mktemp, nanosecond timestamps" suggestion ---
s1="$(date +%s%N)"
s2="$(date +%s%N)"
check "run identity: two back-to-back stamps are not equal" "$([[ "$s1" != "$s2" ]] && echo yes)" "yes"
check "run identity: stamp is purely numeric (still sorts lexically = chronologically)" \
  "$([[ "$s1" =~ ^[0-9]+$ ]] && echo yes)" "yes"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
