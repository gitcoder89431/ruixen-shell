#!/usr/bin/env bash
# Covers the update-safety half of "[P2] Add runtime dependency/
# version preflight and safer release update behavior": runs the REAL
# update.sh against throwaway local git repos (a fake "upstream" plus
# a fake checkout cloned from it), not the real ruixen-shell repo or a
# real Omarchy install. update.sh's own install.sh call at the end is
# stubbed to a trivial no-op script in the fake checkout, since this
# suite only cares about update.sh's own git-safety logic (already
# covered separately by install-lifecycle.sh / install-rollback.sh).
#
# Every update.sh invocation below runs under an isolated $HOME
# ($fake_home) -- since #21, update.sh acquires its own lifecycle lock
# under $HOME/.local/state/ruixen/ before pulling, so without this it
# would touch this dev machine's OWN real lock file/state dir on every
# test run, not just a throwaway sandbox.
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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

fake_home="$work/fake-home"
mkdir -p "$fake_home"

git config --global user.email >/dev/null 2>&1 || git config --global user.email "test@example.invalid"
git config --global user.name >/dev/null 2>&1 || git config --global user.name "Test"

setup_upstream_and_checkout() {
  local upstream="$1" checkout="$2"
  # Explicit -b master throughout -- doesn't rely on the runner's own
  # init.defaultBranch (CI images increasingly default to "main"),
  # so this suite behaves the same everywhere.
  git init --bare -q -b master "$upstream"
  git clone -q "$upstream" "$checkout"
  printf 'v1\n' > "$checkout/VERSION"
  # A trivial stand-in for install.sh -- update.sh's own logic is what
  # this suite tests, not install.sh's (covered elsewhere).
  printf '#!/usr/bin/env bash\necho "install.sh ran"\n' > "$checkout/install.sh"
  chmod +x "$checkout/install.sh"
  cp "$repo_dir/update.sh" "$checkout/update.sh"
  chmod +x "$checkout/update.sh"
  # update.sh sources this directly (#21) -- the real file, not another
  # stub, since acquire_lifecycle_lock's own idempotent-hand-off
  # behavior is exactly what lets update.sh safely call the stubbed
  # install.sh above without either of them contending for the lock.
  mkdir -p "$checkout/lib"
  cp "$repo_dir/lib/acquire-lifecycle-lock.sh" "$checkout/lib/acquire-lifecycle-lock.sh"
  git -C "$checkout" add -A
  git -C "$checkout" commit -q -m "initial"
  git -C "$checkout" push -q origin master 2>/dev/null || git -C "$checkout" push -q origin HEAD:master
}

run_update() {
  ( HOME="$fake_home" "$1/update.sh" )
}

# --- Case 1: a real, clean fast-forward update succeeds -------------
u1="$work/case1-upstream.git"
c1="$work/case1-checkout"
setup_upstream_and_checkout "$u1" "$c1"

# Simulate someone else pushing a new commit upstream.
other_clone="$work/case1-other"
git clone -q "$u1" "$other_clone"
printf 'v2\n' > "$other_clone/VERSION"
git -C "$other_clone" commit -q -am "v2"
git -C "$other_clone" push -q origin master

before_sha="$(git -C "$c1" rev-parse --short HEAD)"
output1="$(run_update "$c1" 2>&1)"
status1=$?
check "clean fast-forward: exits 0" "$status1" "0"
check "clean fast-forward: pulled the new content" "$(cat "$c1/VERSION")" "v2"
check "clean fast-forward: reported the before sha" \
  "$(printf '%s' "$output1" | grep -q "$before_sha" && echo yes)" "yes"
check "clean fast-forward: delegated to install.sh" "$(printf '%s' "$output1" | grep -c "install.sh ran")" "1"

# --- Case 2: already up to date is a harmless no-op ------------------
output1b="$(run_update "$c1" 2>&1)"
status1b=$?
check "already up to date: exits 0" "$status1b" "0"
check "already up to date: says so explicitly" "$(printf '%s' "$output1b" | grep -c "already up to date")" "1"

# --- Case 3: dirty checkout refuses before touching anything --------
u3="$work/case3-upstream.git"
c3="$work/case3-checkout"
setup_upstream_and_checkout "$u3" "$c3"
printf 'local edit\n' >> "$c3/VERSION"
if run_update "$c3" >"$work/case3.out" 2>&1; then
  status3=0
else
  status3=$?
fi
check "dirty checkout: exits non-zero" "$([[ "$status3" -ne 0 ]] && echo yes)" "yes"
check "dirty checkout: local edit was left untouched, not overwritten" \
  "$(cat "$c3/VERSION")" "$(printf 'v1\nlocal edit')"
check "dirty checkout: install.sh was never reached" \
  "$(grep -c "install.sh ran" "$work/case3.out" || true)" "0"

# --- Case 4: diverged history refuses rather than silently merging --
u4="$work/case4-upstream.git"
c4="$work/case4-checkout"
setup_upstream_and_checkout "$u4" "$c4"
# Upstream moves on...
other4="$work/case4-other"
git clone -q "$u4" "$other4"
printf 'upstream v2\n' > "$other4/VERSION"
git -C "$other4" commit -q -am "upstream v2"
git -C "$other4" push -q origin master
# ...while the local checkout ALSO has its own commit upstream never saw.
printf 'v1\n' > "$c4/VERSION"
printf 'local-only change\n' >> "$c4/VERSION"
git -C "$c4" commit -q -am "local-only commit"

before_c4="$(git -C "$c4" rev-parse --short HEAD)"
if run_update "$c4" >"$work/case4.out" 2>&1; then
  status4=0
else
  status4=$?
fi
check "diverged history: exits non-zero (refuses to merge)" "$([[ "$status4" -ne 0 ]] && echo yes)" "yes"
check "diverged history: HEAD is untouched, not merged or reset" \
  "$(git -C "$c4" rev-parse --short HEAD)" "$before_c4"
check "diverged history: install.sh was never reached" \
  "$(grep -c "install.sh ran" "$work/case4.out" || true)" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
