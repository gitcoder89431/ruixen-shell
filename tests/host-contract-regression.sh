#!/usr/bin/env bash
# Issue #34: the CI-level host-contract regression gate. COMPATIBILITY.md
# already records which Omarchy revision this repo has been reviewed
# against (reviewed_omarchy/reviewed_omarchy_commit); this script fetches
# that EXACT pinned commit's real source from github.com/basecamp/omarchy
# and verifies the specific host contracts this repo depends on directly
# still exist there, in the expected shape.
#
# This is deliberately a repo-only source check, not a live-runtime
# compatibility claim -- per the issue's own acceptance criteria: "A
# repository-only contract check should report only that source matches
# the pinned reviewed contract; it should not imply live runtime
# compatibility has been proven." It answers one narrow question: does
# the SPECIFIC revision COMPATIBILITY.md says was reviewed still actually
# contain what that review checked -- catching an accidental re-tag or a
# ledger transcription error, not "is the latest Omarchy compatible."
#
# Deliberately NOT wired into tests/run-all.sh's own suite list -- every
# other test in this directory is a pure static-file grep with zero
# network dependency, runnable offline anywhere. This one fetches real
# files from a public GitHub repo via `gh api`, so it needs network
# access and GitHub API auth (CI's own GITHUB_TOKEN, or a local
# `gh auth login` session) -- a plain `./tests/run-all.sh` should never
# fail just because a dev machine happens to be offline. Run directly,
# or via .github/workflows/ci.yml's own dedicated step.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
compat_md="$repo_dir/COMPATIBILITY.md"
upstream_repo="basecamp/omarchy"

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

if ! command -v gh >/dev/null 2>&1; then
  printf 'SKIP - gh CLI not available, cannot fetch pinned upstream source (this is expected on an offline/no-gh dev machine; CI always has it)\n'
  exit 0
fi

# reviewed_omarchy_commit lives in the ## Entries table's own newest
# (first) row, one column over from reviewed_omarchy -- one ledger to
# keep in sync by hand, not two files. The newest row's own 40-hex-char
# commit hash is the only such token within that section (older rows
# predate this column and say "not backfilled" instead), so pulling the
# first match out of just the Entries section, not the whole file, is
# both simple and correct without needing a real markdown table parser.
entries_section="$(awk '/^## Entries/{flag=1; next} /^## /{flag=0} flag' "$compat_md")"
pinned_sha="$(grep -m1 -oE '[0-9a-f]{40}' <<< "$entries_section")"
if [[ -z "$pinned_sha" ]]; then
  printf 'FAIL - COMPATIBILITY.md has no reviewed_omarchy_commit pin to check against\n'
  exit 1
fi

fetch() {
  local path="$1"
  gh api "repos/$upstream_repo/contents/$path?ref=$pinned_sha" --jq '.content' 2>/dev/null | base64 -d 2>/dev/null || true
}

plugin_registry="$(fetch shell/services/PluginRegistry.qml)"
bar_widget_registry="$(fetch shell/services/BarWidgetRegistry.qml)"
widget_button="$(fetch shell/Ui/WidgetButton.qml)"
shell_qml="$(fetch shell/shell.qml)"

# --- shell/services/PluginRegistry.qml ----------------------------------
# ruixen.pluginpins and this repo's own bar-placement migration logic
# read these four directly (see COMPATIBILITY.md's own "Updating this
# ledger" checklist).

check "pinned source: PluginRegistry.qml fetched" \
  "$([[ -n "$plugin_registry" ]] && echo yes || echo no)" "yes"
check "pinned source: PluginRegistry.qml still has isEnabled(id)" \
  "$(grep -c 'function isEnabled(id)' <<< "$plugin_registry")" "1"
check "pinned source: PluginRegistry.qml still has inBar(id)" \
  "$(grep -c 'function inBar(id)' <<< "$plugin_registry")" "1"
check "pinned source: PluginRegistry.qml still has findBarLocation(config, id, section)" \
  "$(grep -c 'function findBarLocation(config, id, section)' <<< "$plugin_registry")" "1"
check "pinned source: PluginRegistry.qml still has defaultBarWidgetSection(manifest)" \
  "$(grep -c 'function defaultBarWidgetSection(manifest)' <<< "$plugin_registry")" "1"

# --- shell/services/BarWidgetRegistry.qml -------------------------------

check "pinned source: BarWidgetRegistry.qml fetched" \
  "$([[ -n "$bar_widget_registry" ]] && echo yes || echo no)" "yes"
check "pinned source: BarWidgetRegistry.qml still has register(id, component, metadata)" \
  "$(grep -c 'function register(id, component, metadata)' <<< "$bar_widget_registry")" "1"
check "pinned source: BarWidgetRegistry.qml still has availableIds()" \
  "$(grep -c 'function availableIds()' <<< "$bar_widget_registry")" "1"

# --- shell/Ui/WidgetButton.qml -------------------------------------------
# Every stock bar-widget's scroll-to-adjust behavior depends on this
# signal shape.

check "pinned source: WidgetButton.qml fetched" \
  "$([[ -n "$widget_button" ]] && echo yes || echo no)" "yes"
check "pinned source: WidgetButton.qml still has signal wheelMoved(int delta)" \
  "$(grep -c 'signal wheelMoved(int delta)' <<< "$widget_button")" "1"

# --- shell/shell.qml -- the "shell" IpcHandler --------------------------
# omarchy-shell (bin/omarchy-shell) is the CLI wrapper around this exact
# IPC target; ruixen-shell's own install/status tooling calls through
# that CLI, not this QML directly, but the CLI's own surface only exists
# because these functions do. ping() appears twice in this file (a
# second, unrelated handler also defines one), so it's scoped to the
# "shell" target's own block specifically rather than grepped file-wide.

check "pinned source: shell.qml fetched" \
  "$([[ -n "$shell_qml" ]] && echo yes || echo no)" "yes"
check "pinned source: an IpcHandler still targets \"shell\"" \
  "$(grep -c 'target: "shell"' <<< "$shell_qml")" "1"
check "pinned source: shell IPC still has ping() right after target: \"shell\"" \
  "$(grep -A3 'target: "shell"' <<< "$shell_qml" | grep -c 'function ping(): string')" "1"
check "pinned source: shell IPC still has listPlugins()" \
  "$(grep -c 'function listPlugins(): string' <<< "$shell_qml")" "1"
check "pinned source: shell IPC still has setPluginEnabled(id, enabled)" \
  "$(grep -c 'function setPluginEnabled(id: string, enabled: string): string' <<< "$shell_qml")" "1"
check "pinned source: shell IPC still has toggle(id, payloadJson)" \
  "$(grep -c 'function toggle(id: string, payloadJson: string): void' <<< "$shell_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
