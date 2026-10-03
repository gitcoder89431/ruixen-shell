#!/usr/bin/env bash
# Static contract: the Settings UI must not strand GUI users when the
# lifecycle journal guard asks for --acknowledge-interrupted. The shell
# scripts stay conservative, but the frontend has to expose the retry.
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
check "PluginService reruns update.sh with --acknowledge-interrupted when requested" \
  "$(grep -c 'acknowledgeInterrupted ? " --acknowledge-interrupted" : ""' "$service_qml")" "1"

check "SettingsContent exposes pluginUpdateNeedsAcknowledge" \
  "$(grep -c 'property alias pluginUpdateNeedsAcknowledge' "$settings_qml")" "1"
check "SettingsContent status line names interrupted updates" \
  "$(grep -c 'Update Interrupted' "$settings_qml")" "1"
check "SettingsContent shows interrupted update messages in warning color" \
  "$(grep -c 'pluginUpdateStatus === "interrupted" ? "#e8c34a" : "#e05252"' "$settings_qml")" "1"
check "SettingsContent update button becomes Acknowledge & Update" \
  "$(grep -c 'Acknowledge & Update' "$settings_qml")" "1"
check "SettingsContent passes the acknowledge flag back to PluginService on retry" \
  "$(grep -c 'root.updateRuixenShell(root.pluginUpdateNeedsAcknowledge)' "$settings_qml")" "1"
check "run-all includes Settings update interruption recovery contract" \
  "$(grep -c 'settings-update-interruption\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
