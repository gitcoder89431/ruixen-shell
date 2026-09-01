#!/usr/bin/env bash
# Covers "[P1] Reset pristine install snapshots after a successful full
# uninstall" (#13): lib/reset-pristine-baseline.sh in isolation (exactly
# what it removes vs. leaves alone), plus a composed regression test
# against the REAL install.sh proving the actual bug this issue
# describes -- a second install/uninstall cycle picking up a fresh
# baseline instead of silently reusing the first cycle's one.
#
# The plugin-remove/bar-restore half of uninstall.sh isn't re-faked
# here (tests/uninstall-bar-restore.sh already covers the bar-restore
# logic in isolation, same reasoning: faking the whole omarchy CLI just
# for this would be a lot of harness for a concern this file doesn't
# touch) -- this file is scoped to the baseline-reset behavior only.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
reset_script="$repo_dir/lib/reset-pristine-baseline.sh"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'uninstall-pristine-reset: jq is required (command "jq" not found)\n' >&2
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

homes=()
cleanup() { rm -rf "${homes[@]}"; }
trap cleanup EXIT

# --- Case 1: reset removes both baseline records, leaves real state --
state1="$(mktemp -d)"
homes+=("$state1")
printf '{"bar":{"id":"local.neon-bar"}}' > "$state1/shell.json.pre-ruixen"
mkdir -p "$state1/looknfeel-pristine"
printf '/home/dev/.dotfiles/hypr/looknfeel.lua' > "$state1/looknfeel-pristine/target"
printf '{"favorites":["firefox.desktop"]}' > "$state1/launcher-favorites.json"
printf 'balanced' > "$state1/animation-profile"
printf '%s' "$repo_dir" > "$state1/repo-path"
mkdir -p "$state1/backups/plugins"
printf 'x' > "$state1/backups/plugins/ruixen.notch.bak.123"

"$reset_script" "$state1"

check "reset: shell.json.pre-ruixen removed" \
  "$([[ -e "$state1/shell.json.pre-ruixen" ]] && echo present || echo gone)" "gone"
check "reset: looknfeel-pristine/ removed" \
  "$([[ -e "$state1/looknfeel-pristine" ]] && echo present || echo gone)" "gone"
check "reset: launcher-favorites.json survives (real user data)" \
  "$(cat "$state1/launcher-favorites.json")" '{"favorites":["firefox.desktop"]}'
check "reset: animation-profile survives (real user preference)" \
  "$(cat "$state1/animation-profile")" "balanced"
check "reset: repo-path marker survives (install metadata, not rollback baseline)" \
  "$(cat "$state1/repo-path")" "$repo_dir"
check "reset: plugin install backups survive" \
  "$([[ -e "$state1/backups/plugins/ruixen.notch.bak.123" ]] && echo present || echo gone)" "present"

# --- Case 2: an "absent" pristine record (nothing existed before
# Ruixen touched looknfeel.lua) is removed the same way as a real one -
state2="$(mktemp -d)"
homes+=("$state2")
mkdir -p "$state2/looknfeel-pristine"
: > "$state2/looknfeel-pristine/absent"
"$reset_script" "$state2"
check "reset: absent-marker pristine record removed too" \
  "$([[ -e "$state2/looknfeel-pristine" ]] && echo present || echo gone)" "gone"

# --- Case 3: idempotent -- a state dir that never had a baseline (or
# already had it reset) is not an error -----------------------------
state3="$(mktemp -d)"
homes+=("$state3")
printf 'kept' > "$state3/launcher-favorites.json"
if "$reset_script" "$state3" >/dev/null 2>&1; then status3=0; else status3=$?; fi
check "reset: exits 0 with nothing to remove" "$status3" "0"
check "reset: unrelated file untouched" "$(cat "$state3/launcher-favorites.json")" "kept"

# --- Case 4 (composed regression, the actual bug this issue reports):
# install (baseline A) -> uninstall's new reset step -> the user's real
# bar changes (config B) -> install again -> the fresh baseline is B,
# not a stale A. Exercises the REAL install.sh, not a re-implementation
# of its snapshot-write guard. --------------------------------------
run_install() {
  local fake_home="$1"
  ( HOME="$fake_home" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) >"$fake_home/install.out" 2>&1
}

home4="$(mktemp -d)"
homes+=("$home4")
mkdir -p "$home4/.config/omarchy"
printf '%s' '{"bar":{"id":"config.A"}}' > "$home4/.config/omarchy/shell.json"

if run_install "$home4"; then status4a=0; else status4a=$?; fi
check "cycle 1 install: exits 0" "$status4a" "0"
check "cycle 1 install: pristine baseline captured config A" \
  "$(jq -r '.bar.id' "$home4/.local/state/ruixen/shell.json.pre-ruixen")" "config.A"

# Simulate uninstall.sh's full completion: the bar restore steps this
# test doesn't re-fake would have already run by this point, so only
# the new reset step (the part #13 actually adds) needs to run here.
"$reset_script" "$home4/.local/state/ruixen"
check "after uninstall reset: no stale baseline left behind" \
  "$([[ -e "$home4/.local/state/ruixen/shell.json.pre-ruixen" ]] && echo present || echo gone)" "gone"

# User changes their real bar setup in between the two install cycles.
printf '%s' '{"bar":{"id":"config.B"}}' > "$home4/.config/omarchy/shell.json"

if run_install "$home4"; then status4b=0; else status4b=$?; fi
check "cycle 2 install: exits 0" "$status4b" "0"
check "cycle 2 install: fresh baseline captured config B, not stale config A" \
  "$(jq -r '.bar.id' "$home4/.local/state/ruixen/shell.json.pre-ruixen")" "config.B"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
