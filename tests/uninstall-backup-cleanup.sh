#!/usr/bin/env bash
# Covers a real bug found live on the actual dev machine during the
# same final uninstall/reinstall acceptance test as
# tests/uninstall-plugin-sweep.sh, prompted by a direct ask: "can you
# check the file system to see if any trace or spam or leftover?"
#
# Two separate things found, both fixed in uninstall.sh:
#
# 1. install.sh's own rollback-safety backups (issue #20/#10: bounded
#    to the last 5 runs, kept so a FAILED install/update can undo
#    itself) had no lifecycle end -- nothing ever deleted
#    ~/.local/state/ruixen/backups/ or the stray timestamped
#    looknfeel.lua.bak.*/shell.json.bak.* files sitting directly in
#    the user's real config dirs, even after a full uninstall left
#    nothing for any of them to roll back to. Five install cycles on
#    the dev machine had left ~75 backup folders behind.
#
# 2. The fix for #1 initially used a plain `[[ -e "$stray_backup" ]]`
#    existence check before deleting each stray backup -- which is
#    FALSE for a dangling symlink. A looknfeel.lua.bak.* backup is
#    itself a symlink whenever the looknfeel.lua it backed up was one
#    (apply-looknfeel.sh moves the symlink, never follows it) -- and
#    its target is the stable-deployed-assets path
#    (~/.local/share/ruixen-shell/hyprland/...) that this SAME
#    uninstall run also removes. `-e` alone silently skipped 4 of 5
#    real backups on the dev machine because of exactly this. Fixed to
#    `[[ -e "$stray_backup" || -L "$stray_backup" ]]`, the same guard
#    apply-looknfeel.sh already uses for the live target.
#
# Sources the REAL /usr/bin/omarchy-shell-config and runs the REAL
# install.sh/uninstall.sh against a throwaway fake $HOME, same
# conventions as tests/uninstall-preserve-thirdparty.sh and
# tests/uninstall-plugin-sweep.sh -- installs TWICE back to back so
# the second install backs up the first install's own looknfeel.lua
# symlink (reproducing the exact dangling-symlink-backup shape found
# live), then uninstalls and confirms nothing is left behind anywhere.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'uninstall-backup-cleanup: jq is required (command "jq" not found)\n' >&2
  exit 1
}
command -v omarchy-shell-config >/dev/null 2>&1 || {
  printf 'uninstall-backup-cleanup: this test sources the real omarchy-shell-config, not found on PATH -- skipping (not a real Omarchy machine)\n' >&2
  exit 0
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

run_install() {
  ( HOME="$1" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) >"$1/install.out" 2>&1
}
run_uninstall() {
  ( HOME="$1" PATH="$fake_bin:$PATH" "$repo_dir/uninstall.sh" ) >"$1/uninstall.out" 2>&1
}

home="$(mktemp -d)"
homes+=("$home")

if run_install "$home"; then status1=0; else status1=$?; fi
check "first install: exits 0" "$status1" "0"
if [[ "$status1" -ne 0 ]]; then cat "$home/install.out" >&2; fi

# Second install: looknfeel.lua is already Ruixen's own symlink at
# this point, so apply-looknfeel.sh backs THAT UP too -- a symlink
# backup pointing at the stable-deployed-assets path, the exact shape
# that went missing on the real machine.
if run_install "$home"; then status2=0; else status2=$?; fi
check "second install (reinstall): exits 0" "$status2" "0"
if [[ "$status2" -ne 0 ]]; then cat "$home/install.out" >&2; fi

looknfeel_backups_before=("$home"/.config/hypr/looknfeel.lua.bak.*)
check "fixture: the second install left a looknfeel.lua.bak.* backup" \
  "$([[ -e "${looknfeel_backups_before[0]}" || -L "${looknfeel_backups_before[0]}" ]] && echo yes)" "yes"
check "fixture: that backup is itself a symlink (not a plain copy)" \
  "$([[ -L "${looknfeel_backups_before[0]}" ]] && echo yes)" "yes"
check "fixture: install/update rollback backups dir exists before uninstall" \
  "$([[ -d "$home/.local/state/ruixen/backups" ]] && echo yes)" "yes"

if run_uninstall "$home"; then status3=0; else status3=$?; fi
check "uninstall: exits 0" "$status3" "0"
if [[ "$status3" -ne 0 ]]; then cat "$home/uninstall.out" >&2; fi

# `find -maxdepth 1` lists a symlink entry regardless of whether its
# target still resolves -- the correct way to check "is anything
# matching this name still here", unlike a bare `[[ -e glob ]]` (the
# exact mistake this test exists to pin down).
check "uninstall: no looknfeel.lua.bak.* left anywhere, dangling or not" \
  "$(find "$home/.config/hypr" -maxdepth 1 -iname 'looknfeel.lua.bak.*' 2>/dev/null | wc -l)" "0"
check "uninstall: no shell.json.bak.* left behind" \
  "$(find "$home/.config/omarchy" -maxdepth 1 -iname 'shell.json.bak.*' 2>/dev/null | wc -l)" "0"
check "uninstall: the install/update rollback backups dir is gone entirely" \
  "$([[ -e "$home/.local/state/ruixen/backups" ]] && echo present || echo gone)" "gone"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
