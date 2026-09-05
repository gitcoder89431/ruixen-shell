#!/usr/bin/env bash
# Covers a real bug found live on the actual dev machine during the
# project's own uninstall/reinstall acceptance test: after a
# "successful" ./uninstall.sh run, shell.json's top-level plugins[]
# array still listed {"id":"ruixen.media"} even though `omarchy plugin
# remove ruixen.media --yes` had reported success and the plugin's own
# files were genuinely gone.
#
# Root cause, confirmed by reading PluginRegistry.qml directly (not
# assumed): ruixen.media declares `omarchy.clonedFrom: "omarchy.media"`
# (so Settings can offer it as a drop-in replacement for the stock
# widget) -- setPluginEnabled(id, false) for a clone-flagged plugin
# routes through PluginRegistry's clone-restore code path instead of a
# plain plugins[] splice, and that path did not reliably clean the
# entry up on this machine.
#
# uninstall.sh now sweeps any surviving ruixen.* id out of plugins[]
# directly as a second, defensive step, rather than depending
# exclusively on `omarchy plugin remove`'s own internal behavior. The
# fake `omarchy plugin remove` stub used by this test suite (fixtures/
# fake-bin/omarchy) only ever does `rm -rf` on the plugin's own
# directory -- it never touches shell.json's plugins[] at all, so it
# cannot reproduce the real registry's clone-restore path either way.
# That's actually what makes it a faithful regression test for the
# FIX specifically: before uninstall.sh's own sweep existed, this
# exact scenario (a stray ruixen.* entry the plugin-remove step never
# cleans up) would have been left behind here too.
#
# Sources the REAL /usr/bin/omarchy-shell-config, same as
# tests/uninstall-preserve-thirdparty.sh, for the same reason: that's
# what actually performs the atomic shell.json write uninstall.sh's
# new sweep step depends on (`commit`/$NORMALIZE), and a
# re-implementation here would risk drifting from the real thing.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'uninstall-plugin-sweep: jq is required (command "jq" not found)\n' >&2
  exit 1
}
command -v omarchy-shell-config >/dev/null 2>&1 || {
  printf 'uninstall-plugin-sweep: this test sources the real omarchy-shell-config, not found on PATH -- skipping (not a real Omarchy machine)\n' >&2
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
check "baseline install: exits 0" "$status1" "0"
if [[ "$status1" -ne 0 ]]; then
  cat "$home/install.out" >&2
fi

shell_json="$home/.config/omarchy/shell.json"

# A real install already puts ruixen.media (and other non-bar-widget
# plugins) into plugins[] on its own -- confirm that baseline, then
# add one genuinely foreign entry that must survive the sweep
# untouched (the sweep is scoped to "ruixen." ids only, same as every
# other plugin-removal step in this script).
check "fixture: a real install already put ruixen.media in plugins[]" \
  "$(jq -c '.plugins | map(select(.id == "ruixen.media"))' "$shell_json")" \
  '[{"id":"ruixen.media"}]'
tmp="$(mktemp)"
jq '.plugins += [{"id":"example.thirdparty"}]' \
  "$shell_json" > "$tmp" && mv "$tmp" "$shell_json"

if run_uninstall "$home"; then status2=0; else status2=$?; fi
check "uninstall: exits 0" "$status2" "0"
if [[ "$status2" -ne 0 ]]; then
  cat "$home/uninstall.out" >&2
fi

check "uninstall: ruixen.media was swept out of plugins[] (the real bug, found live)" \
  "$(jq -c '.plugins | map(select(.id == "ruixen.media"))' "$shell_json")" '[]'
check "uninstall: no ruixen.* id survives anywhere in plugins[]" \
  "$(jq -c '.plugins | map(select(.id | startswith("ruixen.")))' "$shell_json")" '[]'
check "uninstall: the genuinely foreign plugin entry was left alone" \
  "$(jq -c '.plugins | map(select(.id == "example.thirdparty"))' "$shell_json")" \
  '[{"id":"example.thirdparty"}]'

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
