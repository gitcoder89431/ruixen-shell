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
favorites_js="$repo_dir/ruixen.launcher/extensions/cliamp/CliampFavorites.js"
result_row_qml="$repo_dir/ruixen.launcher/ResultRow.qml"

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
  "$(grep -c '\["cliamp"' "$content_qml")" "6"
check "CliampContent uses the v2 remote-call envelope, not raw socket writes" \
  "$(grep -c '"remote", "call"' "$content_qml")" "4"
check "CliampContent's four remote-call Processes all capture stderr, not just stdout" \
  "$(( $(grep -c 'stderr: StdioCollector' "$content_qml") + $(grep -c 'parseJobResult(.*Stdout.text, .*Stderr.text)' "$content_qml") ))" "8"
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
check "CliampContent never calls cliamp's own provider.favorite -- favorites are local-only now" \
  "$(grep -c '"provider.favorite"' "$content_qml")" "0"
check "CliampContent toggles favorites through the local JSON layer, for any row (catalog or search)" \
  "$(( $(grep -c 'function toggleFavoriteSelected' "$content_qml") + $(grep -c 'CliampFavorites.toggleFavorite' "$content_qml") + $(grep -A4 'function toggleFavoriteSelected' "$content_qml" | grep -c 'favoritesFile.setText') ))" "3"
check "CliampContent records a last-played timestamp only on a genuine successful play" \
  "$(grep -c 'CliampFavorites.recordPlayed' "$content_qml")" "2"
check "CliampContent threads a search hit's real stream path through to both toggle and recordPlayed" \
  "$(( $(grep -c 'property string lastPlayAttemptPath' "$content_qml") + $(grep -c 'root.lastPlayAttemptPath = row.trackPath' "$content_qml") + $(grep -c 'CliampFavorites.toggleFavorite(root.favoriteStats, row.fullName, row.trackPath' "$content_qml") + $(grep -c 'CliampFavorites.recordPlayed(root.favoriteStats, root.lastPlayAttemptName, root.lastPlayAttemptPath)' "$content_qml") ))" "5"
check "CliampContent persists favorites to its own state file, mkdir -p'd first like every other Ruixen local store" \
  "$(( $(grep -c 'favoritesStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/cliamp-favorites.json"' "$content_qml") + $(grep -c 'id: ensureFavoritesDirProc' "$content_qml") + $(grep -c 'id: favoritesFile' "$content_qml") ))" "3"
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
check "Favorite is always offered on Tab, catalog row or search hit alike -- no favoritable gate left" \
  "$(( $(grep -c 'id: "favorite", label: root.selectedRow.favorite' "$content_qml") + $(grep -c 'favoritable' "$content_qml") ))" "1"

check "CliampStations dedupes a catalog entry that appears as both its favorite and plain id" \
  "$(grep -c 'if (seen\[name\]) continue' "$model_js")" "1"
check "CliampStations strips cliamp's own star prefix before using it as a plain label" \
  "$(grep -c 'function stripStar' "$model_js")" "1"
check "CliampStations treats a plain-text job failure the same as a JSON one" \
  "$(grep -c 'function parseJobResult' "$model_js")" "1"
check "CliampStations parses country/bitrate back out of a station's own name, not invented fields" \
  "$(grep -c 'function parseStationMeta' "$model_js")" "1"
check "CliampStations strips the country suffix from list row labels, keeping the full name for the right panel" \
  "$(( $(grep -c 'function stripCountry' "$model_js") + $(grep -c 'label: stripCountry' "$model_js") + $(grep -c 'fullName' "$model_js") ))" "11"
check "CliampStations flags the currently-playing row with a play glyph, matched through parseStationMeta's clean name (not a raw fullName compare, which status's own bare station name would never match against a catalog row's bitrate/country suffix)" \
  "$(( $(grep -c 'function markNowPlaying' "$model_js") + $(grep -c 'parseStationMeta(row.fullName).name' "$model_js") ))" "2"
check "The currently-playing row's play icon uses ResultRow's own round accent badge (iconBg), not a bare colored glyph" \
  "$(( $(grep -c 'icon: .*iconBg: accentColor' "$model_js") + $(grep -c 'iconColor: accentColor' "$model_js") ))" "1"
check "ResultRow renders an opt-in round accent badge behind the icon glyph, unused by every other row/extension" \
  "$(( $(grep -c 'visible: !!row.modelData.iconBg' "$result_row_qml") + $(grep -c 'radius: width / 2' "$result_row_qml") + $(grep -c 'row.modelData.iconBg ? "#000000"' "$result_row_qml") ))" "3"
check "CliampStations no longer sets a favorite/favoritable field on any row -- that's CliampFavorites' job now" \
  "$(grep -c 'favorite:\|favoritable:' "$model_js")" "0"

check "CliampFavorites keys by station name, not a catalog id or URL -- the only identity stable across catalog and search" \
  "$(( $(grep -c 'function favoriteKey' "$favorites_js") + $(grep -c 'function isFavorite' "$favorites_js") + $(grep -c 'function lastPlayedAt' "$favorites_js") ))" "3"
check "CliampFavorites mutates immutably, same Object.assign convention LauncherFrecency.js already uses" \
  "$(( $(grep -c 'function toggleFavorite' "$favorites_js") + $(grep -c 'function recordPlayed' "$favorites_js") + $(grep -c 'Object.assign({}' "$favorites_js") ))" "5"
check "CliampFavorites layers favorite/lastPlayedAt/icon onto already-shaped rows, splitting catalog into Favorites/Stations but leaving search as one section" \
  "$(( $(grep -c 'function applyFavoriteState' "$favorites_js") + $(grep -c 'searchMode' "$favorites_js") + $(grep -c '"Favorites"' "$favorites_js") + $(grep -c '"Stations"' "$favorites_js") + $(grep -c '"Search Results"' "$favorites_js") ))" "11"
check "Favorites surface on the all-station landing as a Favorites group at the top, conditional on there being any" \
  "$(( $(grep -c 'favorites.push(next)' "$favorites_js") + $(grep -c 'favorites.concat(rest)' "$favorites_js") ))" "2"
check "A favorite missing from this catalog fetch (e.g. search-only, never in cliamp's own curated catalog at all) is still synthesized into Favorites, playable via its own stored stream path" \
  "$(( $(grep -c 'seenFavoriteKeys' "$favorites_js") + $(grep -c 'trackPath: stats\[key\].trackPath' "$favorites_js") + $(grep -c 'favorites.push({' "$favorites_js") ))" "5"
check "CliampFavorites formats a coarse relative last-played time" \
  "$(grep -c 'function formatLastPlayed' "$favorites_js")" "1"

check "CliampContent's rows are a reactive computed binding over raw fetch data + favoriteStats, not an imperative assignment" \
  "$(( $(grep -c 'readonly property var rows: CliampStations.markNowPlaying(' "$content_qml") + $(grep -c 'CliampFavorites.applyFavoriteState(' "$content_qml") + $(grep -c 'property var rawCatalog' "$content_qml") + $(grep -c 'property var rawTracks' "$content_qml") + $(grep -c 'readonly property bool searchMode' "$content_qml") ))" "5"
check "CliampContent marks the currently-playing row with a play icon, only while genuinely playing (paused/stopped never leaves a stale row marked playing)" \
  "$(( $(grep -c 'CliampStations.markNowPlaying(' "$content_qml") + $(grep -c 'root.nowPlaying && root.nowPlaying.state === "playing"' "$content_qml") ))" "2"

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
check "CliampStationPanel puts Now Playing in a featured card at the top" \
  "$(( $(grep -c 'id: nowPlayingCard' "$station_panel_qml") + $(grep -c 'id: nowPlayingContent' "$station_panel_qml") ))" "2"
check "CliampStationPanel renders station metadata as zebra-striped rows, same convention as Search Files" \
  "$(( $(grep -c 'property var metadataFields' "$station_panel_qml") + $(grep -c 'field.index % 2 === 0' "$station_panel_qml") + $(grep -c 'anchors.topMargin: -4' "$station_panel_qml") ))" "3"
check "Now Playing card appears before the metadata rows in source order" \
  "$(( $(grep -n 'id: nowPlayingCard' "$station_panel_qml" | head -1 | cut -d: -f1) < $(grep -n 'text: "Metadata"' "$station_panel_qml" | head -1 | cut -d: -f1) ))" "1"
check "CliampStationPanel shows an avatar tile standing in for the art cliamp doesn't have" \
  "$(grep -c 'id: avatarTile' "$station_panel_qml")" "1"
check "Avatar tile is read-only status, not a transport button -- it carries no click handler" \
  "$(grep -c 'onClicked' "$station_panel_qml")" "0"
check "Avatar shows a play glyph while paused, nothing playing falls back to a music note" \
  "$(( $(grep -c 'visible: root.hasNowPlaying && !root.playing' "$station_panel_qml") + $(grep -c 'visible: !root.hasNowPlaying' "$station_panel_qml") ))" "2"
check "While actually playing, the avatar shows an animated equalizer instead of a static pause glyph" \
  "$(( $(grep -c 'id: eqBars' "$station_panel_qml") + $(grep -c 'visible: root.playing' "$station_panel_qml") + $(grep -c 'SequentialAnimation on height' "$station_panel_qml") ))" "3"
check "Equalizer bars run on their own fixed per-bar duration, not a shared/randomized one" \
  "$(( $(grep -c 'id: eqBar$' "$station_panel_qml") + $(grep -c 'loops: Animation.Infinite' "$station_panel_qml") + $(grep -c 'Math.random' "$station_panel_qml") ))" "2"
check "CliampStationPanel shows a LIVE/PAUSED badge" \
  "$(grep -c 'root.playing ? "LIVE" : "PAUSED"' "$station_panel_qml")" "1"
check "LIVE/clock sit grouped in one pill, with only the live segment keeping the accent color" \
  "$(( $(grep -c 'id: statusPill' "$station_panel_qml") + $(grep -c 'id: pillRow' "$station_panel_qml") + $(grep -c 'color: root.playing ? root.accent' "$station_panel_qml") ))" "3"
check "Pill segments use real per-corner radius, not a clip:true mask that only clips to the bounding box" \
  "$(( $(grep -c 'topLeftRadius: height / 2' "$station_panel_qml") + $(grep -c 'bottomLeftRadius: height / 2' "$station_panel_qml") + $(grep -c 'topRightRadius: height / 2' "$station_panel_qml") + $(grep -c 'bottomRightRadius: height / 2' "$station_panel_qml") + $(grep -c 'clip: true' "$station_panel_qml") ))" "4"
check "LIVE/PAUSED badge and clock sit on the title line itself, not a row that appears/disappears" \
  "$(( $(grep -c 'id: titleRow' "$station_panel_qml") + $(grep -c 'id: titleText' "$station_panel_qml") + $(grep -c "visible: root.hasNowPlaying\$" "$station_panel_qml") ))" "3"
check "CliampStationPanel ticks a real elapsed-listening clock, re-synced from cliamp's own position each poll" \
  "$(( $(grep -c 'function formatElapsed' "$model_js") + $(grep -c 'function syncElapsed' "$station_panel_qml") + $(grep -c 'onNowPlayingChanged: root.syncElapsed()' "$station_panel_qml") ))" "3"
check "Elapsed clock freezes while paused instead of counting through a pause" \
  "$(grep -A2 'interval: 1000' "$station_panel_qml" | grep -c 'running: root.playing')" "1"
check "CliampStationPanel shows a Last Played field from our own local layer, omitted for a never-played station" \
  "$(( $(grep -c 'CliampFavorites.formatLastPlayed(root.selectedRow.lastPlayedAt)' "$station_panel_qml") + $(grep -c 'label: "Last Played"' "$station_panel_qml") + $(grep -c 'if (lastPlayed !== "")' "$station_panel_qml") ))" "3"

check "Cliamp Radio is documented in the launcher docs" \
  "$(grep -c 'Cliamp Radio' "$repo_dir/docs/LAUNCHER.md")" "1"

check "run-all includes launcher cliamp extension contract" \
  "$(grep -c 'launcher-cliamp-extension\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
