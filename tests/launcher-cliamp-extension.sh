#!/usr/bin/env bash
# Static contract for the Ruixen Launcher cliamp (radio) extension --
# it should drive the real omarchy-bundled `cliamp` CLI/IPC socket
# rather than a second radio backend, and never act on a catalog/search
# id it didn't just fetch itself (see CliampContent.qml's own header
# comment for why that's safe here).
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
launcher_qml="$repo_dir/ruixen.launcher/Launcher.qml"
content_qml="$repo_dir/ruixen.launcher/extensions/cliamp/CliampContent.qml"
station_panel_qml="$repo_dir/ruixen.launcher/extensions/cliamp/CliampStationPanel.qml"
model_js="$repo_dir/ruixen.launcher/extensions/cliamp/CliampStations.js"

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

check "Launcher imports the cliamp extension folder" \
  "$(grep -c 'import "extensions/cliamp"' "$launcher_qml")" "1"
check "Launcher has a Cliamp Radio landing row" \
  "$(grep -c 'label: "Cliamp Radio"' "$launcher_qml")" "1"
check "Launcher activates cliamp-extension in-process" \
  "$(grep -A6 'result.providerId === "cliamp-extension"' "$launcher_qml" | grep -c 'activeExtensionId = "cliamp"')" "1"
check "Launcher records cliamp frecency" \
  "$(grep -c 'recordLaunch("ruixen.cliamp")\|frecencyFor("ruixen.cliamp")' "$launcher_qml")" "2"
check "Launcher instantiates CliampContent" \
  "$(grep -c 'CliampContent {' "$launcher_qml")" "1"

check "CliampContent never shells out to a second radio backend" \
  "$(grep -Rhi 'mpv\|vlc\|mopidy\|radiobrowser' "$repo_dir/ruixen.launcher/extensions/cliamp" | wc -l)" "0"
check "CliampContent drives cliamp exclusively via the cliamp binary" \
  "$(grep -c '\["cliamp"' "$content_qml")" "7"
check "CliampContent uses the v2 remote-call envelope, not raw socket writes" \
  "$(grep -c '"remote", "call"' "$content_qml")" "5"
check "CliampContent's five remote-call Processes all capture stderr, not just stdout" \
  "$(( $(grep -c 'stderr: StdioCollector' "$content_qml") + $(grep -c 'parseJobResult(.*Stdout.text, .*Stderr.text)' "$content_qml") ))" "10"
check "CliampStations.parseJobResult reads both streams, since every cliamp failure (including not-running) goes to stderr" \
  "$(grep -c 'function parseJobResult(stdoutText, stderrText)' "$model_js")" "1"
check "CliampContent fetches the radio catalog and falls back to it on empty search" \
  "$(( $(grep -c 'function runCatalog' "$content_qml") + $(grep -c '"provider.catalog"' "$content_qml") ))" "2"
check "CliampContent searches the radio provider by free-text query" \
  "$(( $(grep -c 'function runSearch' "$content_qml") + $(grep -c '"provider.search"' "$content_qml") ))" "2"
check "CliampContent debounces search input instead of firing per keystroke" \
  "$(grep -c 'id: searchDebounce' "$content_qml")" "1"
check "CliampContent plays a catalog/favorite row via provider.load" \
  "$(grep -c '"provider.load"' "$content_qml")" "1"
check "CliampContent plays a raw search hit via track.play" \
  "$(grep -c '"track.play"' "$content_qml")" "1"
check "CliampContent toggles favorites via provider.favorite, only for favoritable rows" \
  "$(( $(grep -c '"provider.favorite"' "$content_qml") + $(grep -c 'if (!row || !row.favoritable) return' "$content_qml") ))" "2"
check "CliampContent reads live status for the read-only Now Playing line" \
  "$(grep -c '"status", "--json"' "$content_qml")" "1"
check "CliampContent has no transport-control machinery -- the notch's MPRIS widget owns that" \
  "$(( $(grep -c 'function sendTransport\|function adjustVolume\|transportProc' "$content_qml") + $(grep -c 'function handleShortcut' "$content_qml") ))" "0"
check "CliampContent can cold-start a headless daemon on first use" \
  "$(grep -c 'execDetached(\["cliamp", "--daemon", "--no-auto-play"' "$content_qml")" "1"
check "CliampContent auto-starts cliamp as soon as the extension opens, not on a user action" \
  "$(( $(grep -c 'function handleNotRunning' "$content_qml") + $(grep -c 'root.startCliamp()' "$content_qml") + $(grep -c 'root.notRunningAttempts = 0' "$content_qml") ))" "3"
check "CliampContent retries more than once before giving up -- a single 1.2s check is too tight a margin" \
  "$(( $(grep -c 'property int notRunningAttempts' "$content_qml") + $(grep -c 'readonly property int maxNotRunningAttempts: 4' "$content_qml") + $(grep -c 'startRetryTimer.start()' "$content_qml") ))" "4"
check "CliampContent leaves the extension only after exhausting every retry" \
  "$(( $(grep -c 'signal exitRequested' "$content_qml") + $(grep -c 'root.exitRequested()' "$content_qml") ))" "2"
check "Launcher returns to the landing list when cliamp gives up starting" \
  "$(grep -c 'onExitRequested: root.activeExtensionId = ""' "$launcher_qml")" "1"
check "CliampStations distinguishes 'not running' from a real job failure while connected" \
  "$(grep -c 'notRunning' "$model_js")" "2"
check "CliampContent only auto-starts/bails on a genuine not-running signal, not any failed job" \
  "$(grep -c 'if (parsed.notRunning)' "$content_qml")" "4"
check "A transient job failure (e.g. a network timeout) never flips cliampRunning false while connected" \
  "$(grep -c 'root.cliampRunning = parsed.ok' "$content_qml")" "0"

check "CliampContent uses the same panel split ratio as every other 2-panel extension" \
  "$(grep -c 'detailRatio: 0.6' "$content_qml")" "1"
check "CliampContent uses compact icon+name rows, with no subtitle/kind columns" \
  "$(grep -c 'filesMode: true' "$content_qml")" "1"
check "CliampContent reuses the Search Files action menu for Tab and right-click row actions" \
  "$(( $(grep -c 'ResultActionsMenu {' "$content_qml") + $(grep -c 'function focusRightPanel' "$content_qml") + $(grep -c 'onRowActionsRequested' "$content_qml") + $(grep -c 'function runStationAction' "$content_qml") ))" "4"

check "CliampStations dedupes a catalog entry that appears as both its favorite and plain id" \
  "$(grep -c 'if (seen\[name\]) continue' "$model_js")" "1"
check "CliampStations strips cliamp's own star prefix before using it as a plain label" \
  "$(grep -c 'function stripStar' "$model_js")" "1"
check "CliampStations treats a plain-text job failure the same as a JSON one" \
  "$(grep -c 'function parseJobResult' "$model_js")" "1"
check "CliampStations parses country/bitrate back out of a station's own name, not invented fields" \
  "$(grep -c 'function parseStationMeta' "$model_js")" "1"
check "CliampStations strips the country suffix from list row labels, keeping the full name for the right panel" \
  "$(( $(grep -c 'function stripCountry' "$model_js") + $(grep -c 'label: stripCountry' "$model_js") + $(grep -c 'fullName' "$model_js") ))" "8"
check "CliampStationPanel parses station meta from the row's untrimmed fullName, not the list's stripped label" \
  "$(grep -c 'parseStationMeta(root.selectedRow.fullName' "$station_panel_qml")" "1"
check "CliampStationPanel is a dumb display+signal component, no Process of its own" \
  "$(grep -c '^import Quickshell.Io' "$station_panel_qml")" "0"
check "CliampStationPanel has no transport controls -- it shows station info, not a controller" \
  "$(grep -c 'signal playPauseRequested\|signal stopRequested\|signal nextRequested\|signal prevRequested\|signal volumeDownRequested\|signal volumeUpRequested' "$station_panel_qml")" "0"
check "CliampStationPanel has no 'cliamp isn't running' state of its own -- it's silent now" \
  "$(( $(grep -c 'signal startRequested' "$station_panel_qml") + $(grep -c "Cliamp isn't running" "$station_panel_qml") + $(grep -c 'cliampRunning' "$station_panel_qml") ))" "0"
check "CliampStationPanel shows station info for the selected row" \
  "$(grep -c 'selectedRow' "$station_panel_qml")" "9"

check "Cliamp Radio is documented in the launcher docs" \
  "$(grep -c 'Cliamp Radio' "$repo_dir/docs/LAUNCHER.md")" "1"

check "run-all includes launcher cliamp extension contract" \
  "$(grep -c 'launcher-cliamp-extension\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
