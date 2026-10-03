#!/usr/bin/env bash
# Static contract: the Settings UI must not strand GUI users when the
# lifecycle journal guard asks for --acknowledge-interrupted. The CLI
# stays conservative; the GUI Update button auto-acknowledges stale
# journals so non-terminal users get a simple two-button flow.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
service_qml="$repo_dir/ruixen.launcher/extensions/settings/services/PluginService.qml"
settings_qml="$repo_dir/ruixen.launcher/extensions/settings/SettingsContent.qml"

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

check "PluginService tracks whether update needs interruption acknowledgment" \
  "$(grep -c 'property bool pluginUpdateNeedsAcknowledge' "$service_qml")" "1"
check "PluginService detects the lifecycle interruption guard from stderr" \
  "$(( $(grep -c 'raw.indexOf("--acknowledge-interrupted")' "$service_qml") + $(grep -c 'raw.indexOf("appears to have been interrupted")' "$service_qml") ))" "2"
check "PluginService uses a distinct interrupted update status" \
  "$(grep -c 'pluginUpdateStatus = interrupted ? "interrupted" : "error"' "$service_qml")" "1"
check "PluginService keeps more generic error context than the old three-line truncation" \
  "$(grep -c 'errLines.length - 5' "$service_qml")" "1"
check "PluginService GUI update always passes --acknowledge-interrupted" \
  "$(grep -c './update.sh --acknowledge-interrupted' "$service_qml")" "1"
check "PluginService clears stale check status when update starts" \
  "$(awk '/function updateRuixenShell/ { in_fn = 1 } in_fn && /function checkForUpdates/ { in_fn = 0 } in_fn && /pluginCheckStatus = ""|pluginCheckError = ""/ { count++ } END { print count + 0 }' "$service_qml")" "2"
check "PluginService clears stale update status when check starts" \
  "$(awk '/function checkForUpdates/ { in_fn = 1 } in_fn && /checkUpdatesProc.command/ { in_fn = 0 } in_fn && /pluginUpdateStatus = ""|pluginUpdateError = ""/ { count++ } END { print count + 0 }' "$service_qml")" "2"

check "SettingsContent exposes pluginUpdateNeedsAcknowledge" \
  "$(grep -c 'property alias pluginUpdateNeedsAcknowledge' "$settings_qml")" "1"
check "SettingsContent status line names interrupted updates" \
  "$(grep -c 'Update Interrupted' "$settings_qml")" "1"
check "SettingsContent status line names generic update and check failures" \
  "$(( $(grep -c 'Update Failed' "$settings_qml") + $(grep -c 'Check Failed' "$settings_qml") ))" "2"
check "SettingsContent update button remains plain Update" \
  "$(( $(grep -c 'text: "Update"' "$settings_qml") + $(grep -c 'Acknowledge & Update' "$settings_qml") ))" "1"
check "SettingsContent update button calls the simple GUI update function" \
  "$(grep -c 'root.updateRuixenShell()' "$settings_qml")" "2"
check "run-all includes Settings update interruption recovery contract" \
  "$(grep -c 'settings-update-interruption\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
