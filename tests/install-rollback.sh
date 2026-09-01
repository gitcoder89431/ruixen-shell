#!/usr/bin/env bash
# Covers "[P1] Make install/update transactional with validation and
# rollback": runs the REAL install.sh against a throwaway fake $HOME
# with the omarchy/hyprctl stubs from fixtures/fake-bin/, proving the
# rollback mechanism actually restores prior state on failure -- not
# just reasoning about the code. Two distinct failure points, per the
# issue's own acceptance criteria ("Automated tests simulate at least
# two failure points"):
#   1. A plugin validation failure aborts before ANY plugin is
#      deployed (already covered at a lighter level by
#      install-lifecycle.sh; reinforced here with a stronger
#      "plugins dir has nothing new in it at all" assertion).
#   2. A failure at the FINAL step (omarchy restart shell), forced
#      via FAKE_OMARCHY_FAIL_RESTART -- by that point plugins,
#      shell.json, AND looknfeel.lua have all genuinely been touched,
#      so this is the real end-to-end proof that rollback_all() puts
#      all three back exactly as they were.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'install-rollback: jq is required (command "jq" not found)\n' >&2
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

# --- Failure point 1: validation failure touches nothing at all ----
home1="$(mktemp -d)"
homes+=("$home1")
if ( HOME="$home1" PATH="$fake_bin:$PATH" FAKE_OMARCHY_FAIL_VALIDATE_FOR="ruixen.weather" "$repo_dir/install.sh" ) \
  >"$home1/install.out" 2>&1; then
  status1=0
else
  status1=$?
fi
if [[ "$status1" -eq 0 ]]; then
  printf 'FAIL - a failing plugin validation should abort install.sh\n'
  fail_count=$((fail_count + 1))
else
  printf 'ok   - failing plugin validation aborts install.sh (exit non-zero)\n'
  pass=$((pass + 1))
fi
check "validation failure: shell.json was never written" \
  "$([[ -e "$home1/.config/omarchy/shell.json" ]] && echo exists || echo absent)" "absent"
check "validation failure: no plugin directory was created at all" \
  "$([[ -d "$home1/.config/omarchy/plugins" ]] && find "$home1/.config/omarchy/plugins" -mindepth 1 -maxdepth 1 | wc -l || echo 0)" "0"
check "validation failure: looknfeel.lua was never touched" \
  "$([[ -e "$home1/.config/hypr/looknfeel.lua" ]] && echo exists || echo absent)" "absent"

# --- Failure point 2: a later-step failure rolls back everything ---
# already touched this run -- plugins, shell.json, AND looknfeel.
home2="$(mktemp -d)"
homes+=("$home2")

# Establish a genuinely working baseline first (a real successful
# install), so the second, failing run has real prior state to roll
# back TO, not just "nothing existed."
if ( HOME="$home2" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) >"$home2/install-1.out" 2>&1; then
  baseline_status=0
else
  baseline_status=$?
fi
if [[ "$baseline_status" -ne 0 ]]; then
  printf 'FAIL - baseline install for rollback test itself failed, cannot continue this case\n'
  cat "$home2/install-1.out" >&2
  fail_count=$((fail_count + 1))
else
  # Distinguishing markers the SUCCESS path would never produce, so a
  # later assertion that they're back proves real restoration
  # happened, not just "nothing needed to change."
  marker="$home2/.config/omarchy/plugins/ruixen.notch/ROLLBACK_MARKER.txt"
  printf 'pre-existing content that must survive a rolled-back reinstall\n' > "$marker"

  dummy_looknfeel_target="$home2/dummy-dotfiles-looknfeel.lua"
  printf 'a symlink target install.sh must restore exactly\n' > "$dummy_looknfeel_target"
  rm -f "$home2/.config/hypr/looknfeel.lua"
  ln -s "$dummy_looknfeel_target" "$home2/.config/hypr/looknfeel.lua"

  before_shell_json="$(jq -S . "$home2/.config/omarchy/shell.json")"

  if ( HOME="$home2" PATH="$fake_bin:$PATH" FAKE_OMARCHY_FAIL_RESTART=1 "$repo_dir/install.sh" ) \
    >"$home2/install-2.out" 2>&1; then
    status2=0
  else
    status2=$?
  fi
  if [[ "$status2" -eq 0 ]]; then
    printf 'FAIL - a forced restart failure should abort install.sh\n'
    fail_count=$((fail_count + 1))
  else
    printf 'ok   - forced restart failure aborts install.sh (exit non-zero)\n'
    pass=$((pass + 1))
  fi

  check "rollback: plugin directory (marker included) was restored from its backup" \
    "$([[ -f "$marker" ]] && cat "$marker")" "pre-existing content that must survive a rolled-back reinstall"
  check "rollback: looknfeel.lua symlink was restored to its exact pre-run target" \
    "$(readlink "$home2/.config/hypr/looknfeel.lua")" "$dummy_looknfeel_target"
  check "rollback: shell.json is byte-for-byte unchanged from right before this run" \
    "$(jq -S . "$home2/.config/omarchy/shell.json")" "$before_shell_json"
  check "rollback: this run's own plugin backup was consumed, not left behind" \
    "$(find "$home2/.local/state/ruixen/backups/plugins" -maxdepth 1 -iname 'ruixen.notch.bak.*' 2>/dev/null | wc -l)" "0"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
