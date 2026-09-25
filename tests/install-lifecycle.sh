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

count_fixed_line() {
  local file="$1"
  local needle="$2"
  [[ -f "$file" ]] || { printf '0\n'; return; }
  grep -F -c "$needle" "$file" || true
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
  check "clean install: all 7 canonical ruixen plugin ids present" \
    "$(jq -c '[.plugins[].id] | sort' "$home1/.config/omarchy/shell.json")" \
    '["ruixen.cava","ruixen.launcher","ruixen.media","ruixen.notch","ruixen.settings","ruixen.wallpaper"]'
  check "clean install: looknfeel.lua points at the stable deployed path, not the checkout (#15)" \
    "$(readlink "$home1/.config/hypr/looknfeel.lua")" "$home1/.local/share/ruixen-shell/hyprland/looknfeel.ruixen.lua"
  check "clean install: deployed looknfeel asset matches this checkout's content" \
    "$(diff -q "$home1/.local/share/ruixen-shell/hyprland/looknfeel.ruixen.lua" "$repo_dir/hyprland/looknfeel.ruixen.lua" >/dev/null 2>&1 && echo same)" "same"
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
check "validation failure: shell.json was never written (aborted before step [4/7])" \
  "$([[ -e "$home3/.config/omarchy/shell.json" ]] && echo exists || echo absent)" "absent"

# --- Case 4: a Ruixen plugin retired from this checkout (no source dir
# left at all, e.g. ruixen.frame-widget once v2 merged it away) must be
# removed from an existing install, not left deployed+referenced forever
home4="$(mktemp -d)"
homes+=("$home4")
mkdir -p "$home4/.config/omarchy/plugins/ruixen.retired-widget"
printf '%s' '{"schemaVersion":1,"id":"ruixen.retired-widget","name":"Retired","version":"1.0.0","author":"ruixen","kinds":["overlay"]}' \
  > "$home4/.config/omarchy/plugins/ruixen.retired-widget/manifest.json"
mkdir -p "$home4/.config/omarchy"
printf '%s' '{"version":1,"bar":{"id":"ruixen.bar","layout":{"left":[{"id":"ruixen.retired-widget"}],"center":[],"right":[]}},"plugins":[{"id":"ruixen.retired-widget"}]}' \
  > "$home4/.config/omarchy/shell.json"
if ( HOME="$home4" PATH="$fake_bin:$PATH" \
     FAKE_OMARCHY_ASSERT_PRESENT_AT_RESTART="$home4/.config/omarchy/plugins/ruixen.retired-widget" \
     "$repo_dir/install.sh" ) >"$home4/install.out" 2>&1; then
  status4=0
else
  status4=$?
fi
check "retired plugin: exits 0" "$status4" "0"
check "retired plugin: directory still existed at restart time (removed after, not before)" \
  "$(grep -c 'still exist at restart time' "$home4/install.out" 2>/dev/null)" "0"
if [[ "$status4" -eq 0 ]]; then
  check "retired plugin: deployed directory was removed" \
    "$([[ -e "$home4/.config/omarchy/plugins/ruixen.retired-widget" ]] && echo present || echo gone)" "gone"
  check "retired plugin: moved to a backup, not just deleted" \
    "$(find "$home4/.local/state/ruixen/backups/plugins" -maxdepth 1 -name 'ruixen.retired-widget.bak.*' 2>/dev/null | wc -l | tr -d ' ')" "1"
  check "retired plugin: stripped from shell.json's plugins[]" \
    "$(jq -c '[.plugins[].id] | any(. == "ruixen.retired-widget")' "$home4/.config/omarchy/shell.json")" "false"
  check "retired plugin: stripped from bar.layout too" \
    "$(jq -c '[.bar.layout.left[].id] | any(. == "ruixen.retired-widget")' "$home4/.config/omarchy/shell.json")" "false"
else
  cat "$home4/install.out" >&2
fi

# --- Case 5: opt-in recommended keybinds append only free recommended keys
home5="$(mktemp -d)"
homes+=("$home5")
if ( HOME="$home5" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" --with-launcher-keybind ) \
  >"$home5/install.out" 2>&1; then
  status5=0
else
  status5=$?
fi
check "recommended keybinds: exits 0 when both keys are free" "$status5" "0"
if [[ "$status5" -eq 0 ]]; then
  check "recommended keybinds: bindings.lua contains Ruixen Launcher on SUPER+R" \
    "$(count_fixed_line "$home5/.config/hypr/bindings.lua" 'o.bind("SUPER + R", "Ruixen Launcher",')" "1"
  check "recommended keybinds: bindings.lua contains Ruixen Settings on SUPER+SHIFT+R" \
    "$(count_fixed_line "$home5/.config/hypr/bindings.lua" 'o.bind("SUPER + SHIFT + R", "Ruixen Settings",')" "1"
  check "recommended keybinds: installer reports the added launcher keybind" \
    "$(grep -c 'added SUPER+R -> Ruixen Launcher' "$home5/install.out" 2>/dev/null || true)" "1"
  check "recommended keybinds: installer reports the added settings keybind" \
    "$(grep -c 'added SUPER+SHIFT+R -> Ruixen Settings' "$home5/install.out" 2>/dev/null || true)" "1"
else
  cat "$home5/install.out" >&2
fi

# --- Case 6: opt-in recommended keybinds never clobber an existing SUPER+R,
# but still install the free Settings key.
home6="$(mktemp -d)"
homes+=("$home6")
if ( HOME="$home6" PATH="$fake_bin:$PATH" FAKE_OMARCHY_KEYBINDINGS='SUPER + R                           → Existing Action' \
     "$repo_dir/install.sh" --with-launcher-keybind ) >"$home6/install.out" 2>&1; then
  status6=0
else
  status6=$?
fi
check "recommended keybind conflict: exits 0 and keeps install usable" "$status6" "0"
if [[ "$status6" -eq 0 ]]; then
  check "recommended keybind conflict: does not add Ruixen Launcher over occupied SUPER+R" \
    "$(count_fixed_line "$home6/.config/hypr/bindings.lua" 'o.bind("SUPER + R", "Ruixen Launcher",')" "0"
  check "recommended keybind conflict: still adds Ruixen Settings on free SUPER+SHIFT+R" \
    "$(count_fixed_line "$home6/.config/hypr/bindings.lua" 'o.bind("SUPER + SHIFT + R", "Ruixen Settings",')" "1"
  check "recommended keybind conflict: reports current binding instead of overwriting" \
    "$(grep -c 'SUPER+R is already bound' "$home6/install.out" 2>/dev/null || true)" "1"
else
  cat "$home6/install.out" >&2
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
