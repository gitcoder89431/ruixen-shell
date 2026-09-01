#!/usr/bin/env bash
# Covers the installer-lifecycle half of "[P1] Add automated QA/CI...
# installer lifecycle": runs the REAL install.sh against a throwaway
# fake $HOME, with `omarchy`/`hyprctl` replaced by minimal stubs (see
# fixtures/fake-bin/) that give install.sh just enough surface to run
# to completion without a real Omarchy/Hyprland environment -- the
# issue's own stated non-goal is not fully emulating that environment,
# so these stubs are deliberately minimal, not a reimplementation.
#
# Covers: clean install, install over a customized existing
# shell.json, a second reinstall being idempotent, and a plugin
# validation failure aborting before any later step runs. Symlink
# preservation has its own dedicated, more thorough test
# (looknfeel-preserve.sh) so isn't re-covered deeply here.
# "Rollback" from the original issue's list is #5's own scope
# (install/update isn't transactional yet) and isn't testable until
# that lands.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'install-lifecycle: jq is required (command "jq" not found)\n' >&2
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

homes=()
cleanup() { rm -rf "${homes[@]}"; }
trap cleanup EXIT

# --- Case 1: clean install (nothing existed before) ------------------
home1="$(mktemp -d)"
homes+=("$home1")
if run_install "$home1"; then status1=0; else status1=$?; fi
check "clean install: exits 0" "$status1" "0"
if [[ "$status1" -eq 0 ]]; then
  check "clean install: bar.id is ruixen.bar" \
    "$(jq -r '.bar.id' "$home1/.config/omarchy/shell.json")" "ruixen.bar"
  check "clean install: all 4 canonical ruixen plugin ids present" \
    "$(jq -c '[.plugins[].id] | sort' "$home1/.config/omarchy/shell.json")" \
    '["ruixen.frame-widget","ruixen.notch","ruixen.settings","ruixen.wallpaper"]'
  check "clean install: looknfeel.lua points at ruixen's own file" \
    "$(readlink "$home1/.config/hypr/looknfeel.lua")" "$repo_dir/hyprland/looknfeel.ruixen.lua"
  check "clean install: a real plugin directory was actually copied" \
    "$([[ -f "$home1/.config/omarchy/plugins/ruixen.notch/manifest.json" ]] && echo yes)" "yes"
  check "clean install: repo-path state file points at this checkout" \
    "$(cat "$home1/.local/state/ruixen/repo-path")" "$repo_dir"
else
  cat "$home1/install.out" >&2
fi

# --- Case 2: install over a customized existing shell.json -----------
home2="$(mktemp -d)"
homes+=("$home2")
mkdir -p "$home2/.config/omarchy"
printf '%s' '{"version":1,"some_third_party_key":"left alone","bar":{"id":"local.other-bar"},"plugins":[{"id":"third.party","hidden":[]}],"idle":{"lock":42,"screensaver":7}}' \
  > "$home2/.config/omarchy/shell.json"
if run_install "$home2"; then status2=0; else status2=$?; fi
check "customized install: exits 0" "$status2" "0"
if [[ "$status2" -eq 0 ]]; then
  check "customized install: unrelated top-level key survived" \
    "$(jq -r '.some_third_party_key' "$home2/.config/omarchy/shell.json")" "left alone"
  check "customized install: unrelated plugin entry survived" \
    "$(jq -c '.plugins[] | select(.id == "third.party")' "$home2/.config/omarchy/shell.json")" \
    '{"id":"third.party","hidden":[]}'
  check "customized install: user's own idle values survived" \
    "$(jq -c '.idle' "$home2/.config/omarchy/shell.json")" '{"lock":42,"screensaver":7}'
  check "customized install: ruixen still took over the bar slot" \
    "$(jq -r '.bar.id' "$home2/.config/omarchy/shell.json")" "ruixen.bar"

  # Reinstalling over its own prior output must be a true no-op.
  before_reinstall="$(jq -S . "$home2/.config/omarchy/shell.json")"
  if run_install "$home2"; then status2b=0; else status2b=$?; fi
  check "reinstall: exits 0" "$status2b" "0"
  if [[ "$status2b" -eq 0 ]]; then
    after_reinstall="$(jq -S . "$home2/.config/omarchy/shell.json")"
    check "reinstall: shell.json is byte-for-byte unchanged (idempotent)" "$after_reinstall" "$before_reinstall"
  fi
else
  cat "$home2/install.out" >&2
fi

# --- Case 3: a plugin validation failure aborts before any later step
home3="$(mktemp -d)"
homes+=("$home3")
if ( HOME="$home3" PATH="$fake_bin:$PATH" FAKE_OMARCHY_FAIL_VALIDATE_FOR="ruixen.weather" "$repo_dir/install.sh" ) \
  >"$home3/install.out" 2>&1; then
  status3=0
else
  status3=$?
fi
if [[ "$status3" -eq 0 ]]; then
  printf 'FAIL - a failing plugin validation should abort install.sh\n'
  fail_count=$((fail_count + 1))
else
  printf 'ok   - failing plugin validation aborts install.sh (exit non-zero)\n'
  pass=$((pass + 1))
fi
check "validation failure: shell.json was never written (aborted before step [4/6])" \
  "$([[ -e "$home3/.config/omarchy/shell.json" ]] && echo exists || echo absent)" "absent"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
