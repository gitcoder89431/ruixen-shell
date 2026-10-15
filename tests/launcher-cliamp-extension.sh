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
# Issue #104: row id/providerId/label and the activation dispatch all
# moved out of Launcher.qml into ExtensionRegistry.js / its one generic
# extMatch block -- see that file's own header and
# launcher-settings-search-clear.sh's for the before/after.
registry_js="$repo_dir/ruixen.launcher/extensions/ExtensionRegistry.js"
check "ExtensionRegistry has a Cliamp Radio landing row" \
  "$(grep -c 'label: "Cliamp Radio"' "$registry_js")" "1"
check "Launcher activates cliamp-extension in-process, through the generic registry lookup" \
  "$(grep -c 'ExtensionRegistry.byProviderId(result.providerId)' "$launcher_qml")" "1"
check "Launcher records cliamp frecency, through the generic registry lookup" \
  "$(grep -c 'omarchyActionId: "ruixen.cliamp"' "$registry_js")" "1"
check "Launcher instantiates CliampContent" \
  "$(grep -c 'CliampContent {' "$launcher_qml")" "1"

check "CliampContent never shells out to a second radio backend" \
  "$(grep -Rhi 'mpv\|vlc\|mopidy\|radiobrowser' "$repo_dir/ruixen.launcher/extensions/cliamp" | wc -l)" "0"
check "CliampContent drives cliamp exclusively via the cliamp binary" \
  "$(grep -c '\["cliamp"' "$content_qml")" "7"
check "CliampContent uses the v2 remote-call envelope, not raw socket writes" \
  "$(grep -c '"remote", "call"' "$content_qml")" "5"
check "CliampContent's remote-call Processes all capture stderr, not just stdout (eqProc captures it too but doesn't run it through parseJobResult -- see its own comment for why)" \
  "$(( $(grep -c 'stderr: StdioCollector' "$content_qml") + $(grep -c 'parseJobResult(.*Stdout.text, .*Stderr.text)' "$content_qml") ))" "9"
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

check "CliampContent guards mouse hover against keyboard-nav scroll snapback -- direct report: pointing/focusing a row, switching to keyboard, then scrolling snapped selection back to whatever row ended up under the still cursor" \
  "$(( $(grep -c 'property bool hoverArmed: false' "$content_qml") + $(grep -c 'property point hoverArmBaseline: Qt.point(-1, -1)' "$content_qml") + $(grep -c 'if (root.hoverArmed) root.selectedIndex = idx' "$content_qml") + $(grep -c 'HoverHandler {' "$content_qml") ))" "4"
check "hoverArmed resets on every selectedIndex change AND on (re)open, same as Launcher.qml/ThemeBrowserContent.qml's own copies of this fix" \
  "$(( $(grep -c 'root.hoverArmed = false' "$content_qml") + $(grep -c 'root.hoverArmBaseline = Qt.point(-1, -1)' "$content_qml") ))" "4"

check "CliampStations dedupes a catalog entry that appears as both its favorite and plain id" \
  "$(grep -c 'if (seen\[name\]) continue' "$model_js")" "1"
check "CliampStations strips cliamp's own star prefix before using it as a plain label" \
  "$(grep -c 'function stripStar' "$model_js")" "1"
check "CliampStations treats a plain-text job failure the same as a JSON one" \
  "$(grep -c 'function parseJobResult' "$model_js")" "1"
check "CliampStations parses country/bitrate back out of a station's own name, not invented fields" \
  "$(grep -c 'function parseStationMeta' "$model_js")" "1"
check "CliampStations strips the country suffix from list row labels, keeping the full name for the right panel" \
  "$(( $(grep -c 'function stripCountry' "$model_js") + $(grep -c 'label: stripCountry' "$model_js") + $(grep -c 'fullName' "$model_js") ))" "13"
check "CliampStations flags the currently-playing row with playingIndicator, matched through parseStationMeta's clean name (not a raw fullName compare, which status's own bare station name would never match against a catalog row's bitrate/country suffix)" \
  "$(( $(grep -c 'function markNowPlaying' "$model_js") + $(grep -c 'parseStationMeta(row.fullName).name' "$model_js") + $(grep -c 'playingIndicator: true' "$model_js") ))" "3"
check "ResultRow renders an opt-in animated three-bar equalizer (not a static badge -- two earlier attempts never sat right) for the currently-playing row, unused by every other row/extension" \
  "$(( $(grep -c 'visible: !!row.modelData.playingIndicator' "$result_row_qml") + $(grep -c 'id: playingBars' "$result_row_qml") + $(grep -c 'SequentialAnimation on height' "$result_row_qml") ))" "3"
check "Equalizer bars run on their own fixed per-bar duration, not a shared/randomized one -- same convention as the avatar's own eqBars" \
  "$(( $(grep -c 'id: bar' "$result_row_qml") + $(grep -c 'loops: Animation.Infinite' "$result_row_qml") + $(grep -c 'Math.random' "$result_row_qml") ))" "2"
check "Equalizer bars Row is fixed-height, not implicit off the bars' own animated heights -- the exact jumpy-container bug already fixed once this session for the Now Playing card" \
  "$(grep -c 'height: 14' "$result_row_qml")" "1"
check "Playing-row bars are centered in their icon slot via the same self-centering leftMargin math, not a second hardcoded copy" \
  "$(grep -c 'anchors.leftMargin: 8 + (22 - width) / 2' "$result_row_qml")" "1"
check "CliampStations no longer sets a favorite/favoritable field on any row -- that's CliampFavorites' job now" \
  "$(grep -c 'favorite:\|favoritable:' "$model_js")" "0"

check "CliampFavorites keys by station name, not a catalog id or URL -- the only identity stable across catalog and search" \
  "$(( $(grep -c 'function favoriteKey' "$favorites_js") + $(grep -c 'function isFavorite' "$favorites_js") + $(grep -c 'function lastPlayedAt' "$favorites_js") ))" "3"
check "CliampFavorites mutates immutably, same Object.assign convention LauncherFrecency.js already uses" \
  "$(( $(grep -c 'function toggleFavorite' "$favorites_js") + $(grep -c 'function recordPlayed' "$favorites_js") + $(grep -c 'Object.assign({}' "$favorites_js") ))" "5"
check "CliampFavorites layers favorite/lastPlayedAt/icon onto already-shaped rows, splitting non-search rows into Favorites/Catalogues/Stations and leaving search as one section" \
  "$(( $(grep -c 'function applyFavoriteState' "$favorites_js") + $(grep -c 'searchMode' "$favorites_js") + $(grep -c '"Favorites"' "$favorites_js") + $(grep -c '"Catalogues"' "$favorites_js") + $(grep -c '"Stations"' "$favorites_js") + $(grep -c '"Search Results"' "$favorites_js") ))" "13"
check "The Stations/Catalogues split is keyed off row.bundled (named curated stations go to Stations, the plain world list to Catalogues), not provider-level, so a favorited bundled station still moves to Favorites same as any other" \
  "$(grep -c 'next.sectionLabel = row.bundled ? "Stations" : "Catalogues"' "$favorites_js")" "1"
check "Stations (bundled) and Catalogues (plain world list) get different icons, not the same plain note -- direct follow-up: give them different icons" \
  "$(grep -c 'icon: favorite ? .\{3,6\} : (row.bundled ?' "$favorites_js")" "1"
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
check "Avatar tile is read-only status, not a transport button -- it carries no click handler (the EQ chips further down the panel are a separate, deliberate exception -- see their own section)" \
  "$(grep -A70 'id: avatarTile' "$station_panel_qml" | grep -c 'onClicked')" "0"
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
check "Last Played is the final metadata row, below Source" \
  "$(( $(grep -n 'label: "Source"' "$station_panel_qml" | head -1 | cut -d: -f1) < $(grep -n 'label: "Last Played"' "$station_panel_qml" | head -1 | cut -d: -f1) ))" "1"

check "CliampStations derives sorted distinct countries from the catalog, and filters rows by one (country data search results never carry)" \
  "$(( $(grep -c 'function countryOptions' "$model_js") + $(grep -c 'function filterByCountry' "$model_js") ))" "2"
check "CliampContent exposes a country filter + its derived options for Launcher.qml's own dropdown to read/write" \
  "$(( $(grep -c 'property string countryFilter: ""' "$content_qml") + $(grep -c 'readonly property var countryOptions: CliampStations.countryOptions' "$content_qml") ))" "2"
check "Country filter only ever applies to catalog rows, never search results" \
  "$(grep -c 'CliampStations.filterByCountry' "$content_qml")" "1"
check "Launcher's own All-Types/All dropdown mechanism (Wallpapers, Theme Browser) gained a Country branch for Cliamp Radio, direct follow-up: a dropdown in the search row's top-right rather than a second chip row" \
  "$(( $(grep -c 'label: "All Countries"' "$launcher_qml") + $(grep -c 'cliampContent.countryFilter = opt.path' "$launcher_qml") + $(grep -c 'cliampContent.countryFilter$' "$launcher_qml") + $(grep -c 'cliampContent.countryOptions.map' "$launcher_qml") ))" "6"
check "Dropdown list is a real scrollable ListView, capped to 7 visible rows -- direct report Country's 20+ entries overflowed the launcher's own bottom edge" \
  "$(( $(grep -c 'id: sourceFilterListView' "$launcher_qml") + $(grep -c 'Math.min(sourceFilterListView.count, 7)' "$launcher_qml") + $(grep -c 'clip: true' "$launcher_qml") ))" "4"
# Issue #104: was its own independent, drifting copy of the exact same
# OR-chain showSourceFilter below used -- both now read the one
# ExtensionRegistry.usesSourceFilter flag.
check "Shift+Tab (the dropdown's own keyboard entry point) opens Cliamp Radio's Country dropdown too, not just Wallpapers/Theme Browser/Search Files" \
  "$(grep -c 'if (root.filesMode || ExtensionRegistry.usesSourceFilter(root.activeExtensionId)) root.openDropdown()' "$launcher_qml")" "1"
# Issue #104: this OR-chain became ExtensionRegistry's own per-entry
# usesSourceFilter flag -- cliamp's entry sets it true, same as before.
check "Cliamp Radio's search row shows the Country dropdown, same control Wallpapers/Theme Browser already use" \
  "$(grep -c 'showSourceFilter: root.filesMode || ExtensionRegistry.usesSourceFilter(root.activeExtensionId)' "$launcher_qml")" "1"
check "ExtensionRegistry marks cliamp as usesSourceFilter: true" \
  "$(grep -A5 'id: "cliamp",' "$registry_js" | grep -c 'usesSourceFilter: true')" "1"

check "CliampStations expands cliamp's own bundled station bouquet (Lofi, Omarchy, the NCS family, etc.) from its M3U, flagged bundled:true for its own Stations section, since provider.catalog's l:0 entry only ever hands back one dead pointer row, never the real stations inside" \
  "$(( $(grep -c 'function parseBundledPlaylist' "$model_js") + $(grep -c 'bundled: true' "$model_js") ))" "2"
check "bucketCatalog skips l:<n> pointer entries now that parseBundledPlaylist expands the real thing" \
  "$(grep -c 'p.id || \"\").indexOf(\"l:\") === 0' "$model_js")" "1"
check "CliampContent fetches the bundled bouquet over plain HTTP (independent of cliamp's own daemon/radio-browser.info) and caches it once fetched" \
  "$(( $(grep -c 'property var rawBundled: \[\]' "$content_qml") + $(grep -c 'function runBundled' "$content_qml") + $(grep -c 'id: bundledProc' "$content_qml") + $(grep -c 'CliampStations.parseBundledPlaylist' "$content_qml") + $(grep -c 'if (root.rawBundled.length === 0) root.runBundled()' "$content_qml") ))" "5"
check "Bundled stations are concatenated ahead of the (country-filtered) world catalog, before CliampFavorites splits them into their own Catalogues section" \
  "$(grep -c 'root.rawBundled.concat' "$content_qml")" "1"

check "CliampStations.parseStatus reads cliamp's own eq_preset field from status --json" \
  "$(grep -c 'eqPreset: parsed.eq_preset' "$model_js")" "1"
check "CliampContent exposes a preset list and a setEqPreset() that drives cliamp's own eq IPC op" \
  "$(( $(grep -c 'readonly property var eqPresets:' "$content_qml") + $(grep -c 'function setEqPreset' "$content_qml") + $(grep -c 'id: eqProc' "$content_qml") ))" "3"
check "eqPresets carries all 15 of cliamp's own real presets, not a curated subset" \
  "$(( $(grep -c '"Flat", "Rock", "Pop", "Jazz", "Classical", "Vocal"' "$content_qml") + $(grep -c '"Electronic", "Acoustic", "Loudness", "Bass Boost", "Treble Boost", "Podcast", "R&B"' "$content_qml") + $(grep -c '"Hip-Hop", "Small Speakers"' "$content_qml") ))" "3"
check "CliampStationPanel draws the EQ chips after Now Playing, not inside it" \
  "$(( $(grep -n 'id: nowPlayingCard' "$station_panel_qml" | head -1 | cut -d: -f1) < $(grep -n 'id: eqColumn' "$station_panel_qml" | head -1 | cut -d: -f1) ))" "1"
check "CliampStationPanel draws the EQ chips before Metadata, not inside it" \
  "$(( $(grep -n 'id: eqColumn' "$station_panel_qml" | head -1 | cut -d: -f1) < $(grep -n 'text: "Metadata"' "$station_panel_qml" | head -1 | cut -d: -f1) ))" "1"
check "EQ section has no standalone label row anymore (removed for a cleaner, more-centered chip block)" \
  "$(grep -c 'text: "Equalizer"' "$station_panel_qml")" "0"
check "EQ chip highlights the currently active preset and reports a tap back up via a signal, same split as every other piece of state in this panel" \
  "$(( $(grep -c 'readonly property bool isActive: root.eqPreset === modelData' "$station_panel_qml") + $(grep -c 'signal eqPresetSelected(string name)' "$station_panel_qml") + $(grep -c 'onClicked: root.eqPresetSelected(eqChip.modelData)' "$station_panel_qml") ))" "3"
check "CliampContent wires the panel's EQ signal back to setEqPreset" \
  "$(grep -c 'onEqPresetSelected: (name) => root.setEqPreset(name)' "$content_qml")" "1"
check "EQ chips are packed into rows by real measured text width (FontMetrics), not a plain left-aligned Flow" \
  "$(( $(grep -c 'function packEqRows' "$station_panel_qml") + $(grep -c 'id: eqFontMetrics' "$station_panel_qml") + $(grep -c 'eqFontMetrics.advanceWidth' "$station_panel_qml") + $(grep -c 'root.packEqRows(root.eqPresets, eqColumn.width)' "$station_panel_qml") ))" "4"
check "Each packed EQ row centers itself, so a short last row doesn't sit flush-left with a ragged gap" \
  "$(grep -A2 'id: eqChipRow' "$station_panel_qml" | grep -c 'anchors.horizontalCenter: parent.horizontalCenter')" "1"

check "Cliamp Radio is documented in the launcher docs" \
  "$(grep -c 'Cliamp Radio' "$repo_dir/docs/LAUNCHER.md")" "1"

check "run-all includes launcher cliamp extension contract" \
  "$(grep -c 'launcher-cliamp-extension\.sh' "$script_dir/run-all.sh")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
