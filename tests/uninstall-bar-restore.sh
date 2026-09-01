#!/usr/bin/env bash
# Covers the acceptance criteria of "[P0] Make full uninstall restore
# the user's pre-Ruixen shell configuration" that can be tested without
# faking the real `omarchy` CLI: exercises
# lib/pick-pristine-bar.sh directly with synthetic snapshot fixtures.
# Run directly: ./tests/uninstall-bar-restore.sh
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
pick="$script_dir/../lib/pick-pristine-bar.sh"

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

# --- Case 1: a real customized bar existed before Ruixen -----------
customized="$work/customized.json"
printf '%s' '{"bar":{"id":"local.neon-bar","position":"bottom","transparent":false}}' > "$customized"
if out1="$("$pick" "$customized")"; then
  check "customized pre-Ruixen bar: exit 0" "0" "0"
  check "customized pre-Ruixen bar: prints the exact original bar object" \
    "$out1" '{"id":"local.neon-bar","position":"bottom","transparent":false}'
else
  printf 'FAIL - customized pre-Ruixen bar should have exited 0\n'
  fail_count=$((fail_count + 1))
fi

# --- Case 2: fresh install, nothing existed before Ruixen at all ---
empty="$work/empty.json"
printf '{}' > "$empty"
if "$pick" "$empty" >/dev/null 2>&1; then
  printf 'FAIL - empty snapshot should not be usable\n'
  fail_count=$((fail_count + 1))
else
  printf 'ok   - empty snapshot (fresh install): falls back, does not exit 0\n'
  pass=$((pass + 1))
fi

# --- Case 3: snapshot missing entirely (pre-dates #1's own fix) ----
missing="$work/does-not-exist.json"
if "$pick" "$missing" >/dev/null 2>&1; then
  printf 'FAIL - a missing snapshot file should not be usable\n'
  fail_count=$((fail_count + 1))
else
  printf 'ok   - missing snapshot file: falls back, does not exit 0\n'
  pass=$((pass + 1))
fi

# --- Case 4: snapshot recorded bar.id already as ruixen.bar (should
# never restore Ruixen's own bar as if it were "the original") ------
already_ruixen="$work/already-ruixen.json"
printf '%s' '{"bar":{"id":"ruixen.bar","position":"top"}}' > "$already_ruixen"
if "$pick" "$already_ruixen" >/dev/null 2>&1; then
  printf 'FAIL - a snapshot whose bar is already ruixen.bar should not be usable\n'
  fail_count=$((fail_count + 1))
else
  printf 'ok   - snapshot bar already ruixen.bar: falls back, does not exit 0\n'
  pass=$((pass + 1))
fi

# --- Case 5: corrupt/invalid JSON snapshot fails safely, not loudly
corrupt="$work/corrupt.json"
printf 'not json at all' > "$corrupt"
if "$pick" "$corrupt" >/dev/null 2>&1; then
  printf 'FAIL - a corrupt snapshot should not be usable\n'
  fail_count=$((fail_count + 1))
else
  printf 'ok   - corrupt snapshot: falls back safely, does not exit 0\n'
  pass=$((pass + 1))
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
