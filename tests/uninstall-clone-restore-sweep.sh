#!/usr/bin/env bash
# Covers a real bug found live on the same dev machine, one layer
# deeper than tests/uninstall-plugin-sweep.sh's own plugins[] leak:
# after a "successful" ./uninstall.sh run, shell.json still had
#   "cloneSourceRestores": ["ruixen.media"]
#   "disabledPlugins": ["omarchy.media"]
# even though ruixen.media's own files and its plugins[] entry were
# genuinely gone. Confirmed by reading PluginRegistry.qml directly:
# ruixen.bar/media/tray/weather all declare omarchy.clonedFrom (so
# Settings can offer each as a drop-in replacement for its stock
# original) -- while a clone is active, the live shell tracks which
# stock plugin it disabled (disabledPlugins) and which clone owes it a
# re-enable once removed (cloneSourceRestores). Nothing ever cleaned
# either array up on uninstall, so Omarchy's OWN stock omarchy.media
# widget was left disabled forever, with nothing left that would ever
# re-enable it.
#
# uninstall.sh now captures each removed ruixen.* plugin's own
# omarchy.clonedFrom from its manifest.json (before the file is gone),
# and only un-disables a stock original if cloneSourceRestores says
# THAT SPECIFIC removed clone is the one that disabled it -- mirroring
# PluginRegistry's own restoreCloneSource() check exactly, so a widget
# the user disabled themselves, unrelated to any Ruixen clone, is
# never touched (the fixture below plants exactly that alongside the
# real bug, in the same disabledPlugins array).
#
# Sources the REAL /usr/bin/omarchy-shell-config and runs the REAL
# install.sh/uninstall.sh against a throwaway fake $HOME, same
# conventions as tests/uninstall-plugin-sweep.sh.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'uninstall-clone-restore-sweep: jq is required (command "jq" not found)\n' >&2
  exit 1
}
command -v omarchy-shell-config >/dev/null 2>&1 || {
  printf 'uninstall-clone-restore-sweep: this test sources the real omarchy-shell-config, not found on PATH -- skipping (not a real Omarchy machine)\n' >&2
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
if [[ "$status1" -ne 0 ]]; then cat "$home/install.out" >&2; fi

check "fixture: ruixen.media's manifest really does declare clonedFrom omarchy.media" \
  "$(jq -r '.omarchy.clonedFrom' "$home/.config/omarchy/plugins/ruixen.media/manifest.json")" "omarchy.media"

shell_json="$home/.config/omarchy/shell.json"

# Simulate exactly the live shell's own bookkeeping for an active
# clone, plus one unrelated widget the user disabled for their own
# reasons (same id shape, must NOT be touched by the sweep).
tmp="$(mktemp)"
jq '.cloneSourceRestores = ["ruixen.media"]
    | .disabledPlugins = ["omarchy.media", "omarchy.some-other-widget"]' \
  "$shell_json" > "$tmp" && mv "$tmp" "$shell_json"
check "fixture: cloneSourceRestores/disabledPlugins are set before uninstall" \
  "$(jq -c '{cloneSourceRestores, disabledPlugins}' "$shell_json")" \
  '{"cloneSourceRestores":["ruixen.media"],"disabledPlugins":["omarchy.media","omarchy.some-other-widget"]}'

if run_uninstall "$home"; then status2=0; else status2=$?; fi
check "uninstall: exits 0" "$status2" "0"
if [[ "$status2" -ne 0 ]]; then cat "$home/uninstall.out" >&2; fi

check "uninstall: cloneSourceRestores no longer mentions ruixen.media" \
  "$(jq -c '.cloneSourceRestores // []' "$shell_json")" '[]'
check "uninstall: omarchy.media (the clone's stock original) was un-disabled" \
  "$(jq -c '(.disabledPlugins // []) | map(select(. == "omarchy.media"))' "$shell_json")" '[]'
check "uninstall: the unrelated user-disabled widget was left alone" \
  "$(jq -c '(.disabledPlugins // []) | map(select(. == "omarchy.some-other-widget"))' "$shell_json")" \
  '["omarchy.some-other-widget"]'

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
