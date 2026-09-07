#!/usr/bin/env bash
# Regression test for a real bug found live via direct report ("Looks
# and Feel turns back on after a restart"): install.sh used to point
# looknfeel.lua at the "on" (ruixen) variant unconditionally on every
# run, silently overriding an explicit `ruixen-lookfeel.sh off` from a
# previous install the moment update.sh (which calls install.sh) ran
# again. Runs the REAL install.sh twice against a throwaway fake
# $HOME, same harness technique as install-lifecycle.sh -- "off" must
# survive a reinstall, not just a plain Hyprland/shell restart (which
# was already fine, since off is a real symlink on disk).
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'looknfeel-choice-persist: jq is required (command "jq" not found)\n' >&2
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

run_install() {
  local fake_home="$1"
  ( HOME="$fake_home" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) >"$fake_home/install.out" 2>&1
}

fake_home="$(mktemp -d)"
trap 'rm -rf "$fake_home"' EXIT

# --- Case 1: fresh install defaults to "on" ---------------------------
run_install "$fake_home" || { cat "$fake_home/install.out" >&2; exit 1; }
looknfeel_link="$fake_home/.config/hypr/looknfeel.lua"
check "fresh install: defaults to the ruixen (on) variant" \
  "$(basename "$(readlink "$looknfeel_link")")" "looknfeel.ruixen.lua"

# --- Case 2: user turns it off (same real effect as ruixen-lookfeel.sh
# off -- a plain re-symlink to the already-deployed default variant,
# no need to invoke the wrapper script itself here) ---------------------
default_variant="$fake_home/.local/share/ruixen-shell/hyprland/looknfeel.default.lua"
ln -sf "$default_variant" "$looknfeel_link"
check "off: now points at the default (off) variant" \
  "$(basename "$(readlink "$looknfeel_link")")" "looknfeel.default.lua"

# --- Case 3: reinstall (what update.sh actually does) must NOT revert
# this back to "on" -- the exact bug reported live ----------------------
run_install "$fake_home" || { cat "$fake_home/install.out" >&2; exit 1; }
check "reinstall: off choice survives, NOT reverted back to on" \
  "$(basename "$(readlink "$looknfeel_link")")" "looknfeel.default.lua"
check "reinstall: reports keeping the stock look, not applying rounded+blur" \
  "$(grep -c 'kept your existing choice' "$fake_home/install.out")" "1"

# --- Case 4: a THIRD install (idempotent) also keeps it off -----------
run_install "$fake_home" || { cat "$fake_home/install.out" >&2; exit 1; }
check "second reinstall: still off" \
  "$(basename "$(readlink "$looknfeel_link")")" "looknfeel.default.lua"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
