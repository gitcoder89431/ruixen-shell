#!/usr/bin/env bash
# Covers "[P3] ruixen.launcher: prune stale shared video poster cache
# entries" (#66): runs the REAL ruixen.wallpaper/prune-poster-cache.sh
# (byte-identical to ruixen.notch/prune-poster-cache.sh -- see
# app-launcher-relay.sh's own byte-identity check for that pair) against
# a throwaway poster cache directory, exercising the two-tier retention
# policy directly rather than needing a real wallpaper/launcher session
# to generate real posters first.
#
# RUIXEN_POSTER_STALE_GRACE_DAYS/RUIXEN_POSTER_LEGACY_GRACE_DAYS are
# test-only env overrides the real script itself never sets (production
# always gets its real 30/90-day defaults) -- set small here so mtimes
# can be backdated by a few days with `touch -d` instead of needing to
# wait real months for a legacy-policy case to actually go stale.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
prune_script="$repo_dir/ruixen.wallpaper/prune-poster-cache.sh"

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

exists() { [[ -e "$1" ]] && echo yes || echo no; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
poster_dir="$work/posters"
mkdir -p "$poster_dir" "$work/sources" "$work/outside"

export RUIXEN_POSTER_STALE_GRACE_DAYS=1
export RUIXEN_POSTER_LEGACY_GRACE_DAYS=2

# Direct regression coverage for a real CI-only failure this suite
# itself originally missed: the script used to end a loop iteration
# with a bare `cond && action` as its very last statement, whose own
# exit status IS the condition's -- a FALSE condition (nothing to prune
# for that file, the ordinary/common case) made the whole script exit
# 1 for doing exactly what it should, whenever `find`'s own directory
# iteration order (never guaranteed/stable across filesystems) happened
# to hand it that file last. Passed consistently in local testing
# purely by luck of local filesystem ordering, then failed on push --
# every run_prune call below now asserts the exit code explicitly, not
# just resulting file state, specifically so this class of bug can
# never ship unnoticed again.
run_prune() {
  local rc=0
  set +e
  "$prune_script" "$poster_dir"
  rc=$?
  set -e
  check "prune-poster-cache.sh always exits 0 on a normal pass" "$rc" "0"
}

# --- exit code / missing dir -------------------------------------------

check "missing poster dir: exits 0, not an error" \
  "$(bash "$prune_script" "$work/does-not-exist" >/dev/null 2>&1; echo $?)" "0"

# Deliberately a SEPARATE, single-file directory (not $poster_dir, which
# accumulates files across every case in this suite) -- with exactly one
# candidate file, `find`'s own directory iteration order (never
# guaranteed/stable across filesystems) can't hide the bug behind
# "happened to end on a file that took the true branch." This is the
# exact minimal shape of the real CI failure this suite originally
# missed: reproduces the exit-1 regression deterministically against
# the old buggy code, confirmed directly before landing this fix.
single_file_dir="$work/single-file-check"
mkdir -p "$single_file_dir"
touch "$single_file_dir/recent-legacy.jpg"
single_rc=0
set +e
"$prune_script" "$single_file_dir"
single_rc=$?
set -e
check "single recent legacy poster, nothing to prune: script still exits 0" "$single_rc" "0"
check "single recent legacy poster: kept (can't prove it's stale)" \
  "$(exists "$single_file_dir/recent-legacy.jpg")" "yes"

# --- new-style poster (has a .src sidecar) ------------------------------

# Still-referenced source: kept regardless of age (poster backdated well
# past both grace periods).
touch "$work/sources/still-here.mp4"
printf '%s' "$work/sources/still-here.mp4" > "$poster_dir/referenced.jpg.src"
touch "$poster_dir/referenced.jpg"
touch -d '10 days ago' "$poster_dir/referenced.jpg"
run_prune
check "new-style poster: source still exists -> kept even though old" \
  "$(exists "$poster_dir/referenced.jpg")" "yes"
check "new-style poster: its own sidecar survives alongside it" \
  "$(exists "$poster_dir/referenced.jpg.src")" "yes"

# Source gone, but poster is RECENT (within the grace period) -- must be
# kept, not aggressively pruned. This is the exact "disconnected
# removable/network source" case the issue itself calls out.
printf '%s' "$work/sources/never-existed.mp4" > "$poster_dir/recent-orphan.jpg.src"
touch "$poster_dir/recent-orphan.jpg"
run_prune
check "new-style poster: source gone but still within grace period -> kept" \
  "$(exists "$poster_dir/recent-orphan.jpg")" "yes"

# Source gone AND the poster has aged past the grace period -- safely
# identifiable as stale, prunable.
printf '%s' "$work/sources/long-gone.mp4" > "$poster_dir/stale-orphan.jpg.src"
touch "$poster_dir/stale-orphan.jpg"
touch -d '5 days ago' "$poster_dir/stale-orphan.jpg"
run_prune
check "new-style poster: source gone AND past the grace period -> pruned" \
  "$(exists "$poster_dir/stale-orphan.jpg")" "no"
check "new-style poster: its own sidecar is pruned along with it" \
  "$(exists "$poster_dir/stale-orphan.jpg.src")" "no"

# --- legacy poster (no sidecar at all) -----------------------------------

# Recent legacy poster -- can't be proven stale OR active, kept.
touch "$poster_dir/legacy-recent.jpg"
run_prune
check "legacy poster (no sidecar): recent -> kept (can't prove it's stale)" \
  "$(exists "$poster_dir/legacy-recent.jpg")" "yes"

# Old legacy poster, past the (more generous) legacy grace period.
touch "$poster_dir/legacy-old.jpg"
touch -d '10 days ago' "$poster_dir/legacy-old.jpg"
run_prune
check "legacy poster (no sidecar): past its own, more generous grace period -> pruned" \
  "$(exists "$poster_dir/legacy-old.jpg")" "no"

# --- safety: bounded to exactly the poster cache root --------------------

touch -d '10 days ago' "$work/outside/decoy.jpg"
run_prune
check "safety: a file OUTSIDE the poster cache root is never touched, even a name/age match" \
  "$(exists "$work/outside/decoy.jpg")" "yes"

# A subdirectory inside the poster dir (maxdepth 1) is never descended into.
mkdir -p "$poster_dir/nested"
touch -d '10 days ago' "$poster_dir/nested/decoy.jpg"
run_prune
check "safety: -maxdepth 1 never descends into a subdirectory of the poster cache" \
  "$(exists "$poster_dir/nested/decoy.jpg")" "yes"

# A symlinked .jpg (however it got there) is never followed or deleted --
# -type f (no -L) excludes it outright.
touch -d '10 days ago' "$work/outside/link-target.jpg"
ln -s "$work/outside/link-target.jpg" "$poster_dir/symlinked.jpg"
run_prune
check "safety: a symlinked .jpg inside the poster dir is left alone (not followed/deleted)" \
  "$(exists "$poster_dir/symlinked.jpg")" "yes"
check "safety: the symlink's own real target is untouched too" \
  "$(exists "$work/outside/link-target.jpg")" "yes"

# --- failure tolerance ----------------------------------------------------

# A malformed/empty sidecar must not abort the whole pass -- every other
# case above still needs to keep working in the same run.
: > "$poster_dir/empty-sidecar.jpg.src"
touch -d '10 days ago' "$poster_dir/empty-sidecar.jpg"
touch "$poster_dir/legacy-recent-2.jpg"
run_prune
check "failure tolerance: an empty/malformed sidecar doesn't abort the whole pass" \
  "$(exists "$poster_dir/legacy-recent-2.jpg")" "yes"

if (( fail_count > 0 )); then
  printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
  exit 1
fi
printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
