import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "CliampStations.js" as CliampStations
import "CliampFavorites.js" as CliampFavorites

// Browse/search/play Omarchy's bundled cliamp radio directory from the
// launcher. All real state lives here (Process calls, catalog/search
// rows, now-playing status) -- CliampStationPanel.qml and the shared
// ResultsList/ExtensionTwoPanel/ResultActionsMenu just draw it, same
// root-owns-state split every other extension in this plugin already
// uses.
//
// No transport controls here on purpose -- direct follow-up: "we dont
// need a controller... we have the notch to control the music
// already". Cliamp registers org.mpris.MediaPlayer2.cliamp on D-Bus
// the moment it starts (confirmed live), so the notch's existing
// MPRIS-driven media widget already plays/pauses/skips it; this
// extension's own job is picking WHAT plays, via provider.load/
// track.play, not controlling it once it has.
//
// cliamp's own IPC (`cliamp remote call <op> --params '<json>' --wait`)
// is a long-lived Unix-socket daemon, not a stateless CLI -- every
// `provider.catalog`/`provider.search` call hands back ids (c:<n>/f:<n>)
// that are only valid against whichever catalog page the daemon most
// recently built. Since the row list ON SCREEN is always exactly that
// most recent fetch, acting on a row the user can see is safe; this
// extension never acts on a stale id from an older fetch.
//
// Favorites run through CliampFavorites.js's own small local JSON
// layer entirely, not cliamp's native provider.favorite -- direct
// follow-up: "in the search result i can only play it, is there a way
// to tab to play and favorite it as well". Investigated live first:
// provider.favorite only ever takes {provider, playlist}, an id
// provider.search's raw results never carry (bare {title, path}
// tracks, confirmed against the raw JSON and cliamp's own `remote
// capabilities` listing), and playing a search hit via track.play
// doesn't hand one back either. So cliamp's own favorite system
// genuinely can't reach a search hit -- direct decision, given that:
// one favorite system everywhere (catalog AND search), ours, rather
// than cliamp's native one for catalog rows and a second, different
// one bolted on for search rows. Our favorites won't show starred in
// cliamp's own TUI as a result -- a real tradeoff for one consistent
// star everywhere instead of two different stars meaning two
// different things depending on where a station was found.
Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property color glassTint: "#000000"
  property color glassBorder: Qt.rgba(1, 1, 1, 0.08)
  property string fontFamily: "JetBrainsMono Nerd Font"
  property bool active: false
  property string searchText: ""

  readonly property string searchPlaceholder: "Search Stations"
  readonly property bool showsEnterHint: true
  readonly property bool interceptsArrowKeys: true
  readonly property bool rightFocused: root.actionsMenuOpen

  property bool cliampRunning: true
  // Drives handleNotRunning() below -- direct follow-up: "cant
  // openning the extension just start or resume it?", then a further
  // correction once that still showed a button briefly: "its confusing
  // cause people see that start cliamp enter flash and try and press
  // enter... just make it load the cliamp... if it doesnt work then
  // just go back to the launcher". So there's no user-facing "not
  // running" state at all now: the first fetch failure silently spawns
  // cliamp, then a few more checks (socket binding is normally ~0.2s
  // but this gives real headroom under load) before concluding it's
  // genuinely not coming up and leaving the extension (exitRequested)
  // instead of showing a dead screen. A single 1.2s retry turned out
  // too tight a margin on its own -- confirmed live: a real run where
  // cliamp simply hadn't finished binding its socket by the first
  // retry bailed the extension out from under a daemon that was
  // actually still starting. Reset in onActiveChanged so reopening the
  // extension always gets a fresh run of attempts.
  property int notRunningAttempts: 0
  readonly property int maxNotRunningAttempts: 4

  // Raw fetch results only -- CliampStations.bucketCatalog/searchRows
  // just shape cliamp's own JSON, no favorite concept of their own
  // anymore. rows below is a plain computed binding over these plus
  // favoriteStats, so toggling a favorite re-renders instantly with no
  // extra IPC round-trip (previously favoriteProc's own onExited had
  // to re-run runCatalog() just to see the new star).
  property var rawCatalog: []
  property var rawTracks: []
  readonly property bool searchMode: root.searchText.trim() !== ""

  // cliamp's own curated station bouquet ("lofi for omarchy radio...
  // or nsc stations" -- direct follow-up asking what these actually
  // are) -- provider.catalog's own "l:0"/"cliamp radio" entry is just
  // a pointer to an M3U (radio.cliamp.stream/streams.m3u) holding the
  // real individual stations (Lofi, Meditative, Synthwave, EDM,
  // Omarchy, Chiptunes, Amiga, and the eight-station NCS family), which
  // cliamp's own IPC never expands (confirmed live, see
  // CliampStations.bucketCatalog's own comment for the full story).
  // Fetched directly over HTTP rather than through cliamp at all, so
  // it's unaffected by radio-browser.info being up or down. Cached
  // once it succeeds (see onActiveChanged below) rather than
  // refetched on every open -- a fixed, rarely-changing bundle, same
  // as Wallpapers' own type list.
  property var rawBundled: []

  // Country dropdown -- direct follow-up: "similarly to the bjarneo
  // themes, we have chips for Collection and Styles there, can we do
  // chip for Country... if its the only chip, then more like the top
  // right on the search row we have All and dropdowns" -- the same
  // "All <X>" dropdown Wallpapers'/Theme Browser's own filters already
  // use (Launcher.qml's own dropdownOptions/seedDropdownSelection/
  // confirmDropdownSelection, one more branch each), in the search
  // row's top-right spot, replacing the Enter-key hint there rather
  // than a full second chip row for a single dimension. "" is the
  // dropdown's own "All Countries" sentinel -- a no-op in
  // filterByCountry below, same convention wallpapersContent.kindFilter
  // ("all") and themeBrowserContent.installedOnlyFilter (false) each
  // already use for their own "no filter" state.
  property string countryFilter: ""
  // Derived straight from the current catalog fetch, not a fixed list
  // -- whatever countries are actually present right now. Catalog-only
  // (CliampStations.countryOptions reads raw playlist names): search
  // results never carry a country suffix at all (confirmed live), so
  // this never changes while searchMode is true -- the dropdown still
  // shows it, but see filterByCountry's own comment for why selecting
  // one has no effect on search results.
  readonly property var countryOptions: CliampStations.countryOptions(root.rawCatalog)

  // markNowPlaying runs last -- direct follow-up: "a play icon that
  // shows the station that is playing in the left panel instead of
  // the music note too when active", overriding even a favorite's own
  // star since the currently-audible station is more specific than
  // just "saved". Blanked to "" (no row matches an empty fullName) for
  // anything but a genuine playing state, not just gated inside
  // markNowPlaying itself, so paused/stopped never leaves a stale row
  // marked "playing". Country filter only ever applies to catalog rows
  // -- applying it to search rows would just silently empty the list,
  // since none of them have country data to match against. Same
  // reason rawBundled is concatenated ahead of the filtered world
  // catalog rather than filtered itself -- cliamp's own bundled
  // stations carry no country tag, so a country filter has nothing to
  // match there either; they just stay put regardless of the dropdown.
  readonly property var rows: CliampStations.markNowPlaying(
    CliampFavorites.applyFavoriteState(
      root.searchMode ? CliampStations.searchRows(root.rawTracks)
        : root.rawBundled.concat(CliampStations.filterByCountry(CliampStations.bucketCatalog(root.rawCatalog), root.countryFilter)),
      root.favoriteStats, root.accent, root.searchMode),
    (root.nowPlaying && root.nowPlaying.state === "playing") ? (root.nowPlaying.station || root.nowPlaying.title || "") : "")

  property int selectedIndex: 0
  readonly property var selectedRow: root.rows[root.selectedIndex] || null
  readonly property int scrollOff: 2
  property var nowPlaying: null
  // Same playingIndicator markNowPlaying already set on this exact row
  // for the EQ-bars/icon treatment -- direct ask: "theres gotta be a
  // way to pause the radio, so when its playing enter again pauses it.
  // and then tab to pause for the one playing". Reusing it here instead
  // of a second "is this the now-playing one" check keeps both readings
  // of "currently playing" (the row's own icon and this) from ever
  // disagreeing.
  readonly property bool selectedIsPlaying: !!(root.selectedRow && root.selectedRow.playingIndicator)

  // A global player setting (cliamp's own `cliamp eq` command), not
  // per-station -- direct follow-up after the country filter landed:
  // "the equalizer options between the player and metadata might be a
  // nice touch if easy to add in". cliamp's own real preset list
  // (confirmed live via its CLI, not documented anywhere in --help or
  // its own IPC capabilities listing -- there is no per-band slider
  // UI here, cliamp's own "custom" state is only ever reached by
  // hand-tuning individual bands through its own TUI, out of scope).
  // All 15, not a curated subset -- direct follow-up once the first
  // six shipped: "we do have space... theres alot of empty space on
  // the panel anyways", and the chip row already wraps (Flow, not a
  // fixed Row) so more presets is just more lines, no layout change
  // needed.
  readonly property var eqPresets: ["Flat", "Rock", "Pop", "Jazz", "Classical", "Vocal",
    "Electronic", "Acoustic", "Loudness", "Bass Boost", "Treble Boost", "Podcast", "R&B",
    "Hip-Hop", "Small Speakers"]

  // Direct report: "i point and focus on a row then switch to kbd but
  // when i scroll up or down the page snaps back to the cursor focus
  // row" -- a plain MouseArea.onEntered can't tell "the cursor moved
  // onto this row" from "this row scrolled under a cursor that never
  // moved", and ResultRow.qml's own hover signal fires identically
  // either way. Already hit and fixed twice elsewhere in this plugin
  // (Launcher.qml's own main results list, ThemeBrowserContent.qml's
  // own copy of the identical fix) -- same mechanism here rather than
  // inventing a third: onRowHovered below is a no-op until the
  // HoverHandler observes the pointer at a genuinely different
  // position than wherever it last rested, and every selectedIndex
  // change (keyboard nav scrolling the list included) resets that
  // baseline so the very next pointer reading after a scroll is
  // treated as establishing a fresh rest position, not as movement.
  property bool hoverArmed: false
  property point hoverArmBaseline: Qt.point(-1, -1)
  // Captured at the moment playSelected() fires, not read back off
  // selectedRow once loadProc/trackPlayProc's onExited lands -- the
  // user can move the selection while that IPC round-trip is still in
  // flight, and recordPlayed must mark the station that was actually
  // asked to play, not whatever happens to be selected by the time the
  // response comes back. lastPlayAttemptPath is "" for a catalog row
  // (it only has a stationId) and the real stream URL for a search
  // hit -- that URL is what lets a search-only favorite (CliampFavorites.
  // applyFavoriteState's own synthesized Top Stations row) actually be
  // played back later, not just show a star with nothing behind it.
  property string lastPlayAttemptName: ""
  property string lastPlayAttemptPath: ""

  // Our own local favorite/last-played layer -- see this file's own
  // header above for why it replaces cliamp's native favorite system
  // rather than running alongside it. Same small-JSON-file convention
  // (FileView + mkdir -p + atomicWrites) every other bit of Ruixen
  // local state already uses (AppLibrary.qml's own frecency store is
  // the original example).
  readonly property string favoritesStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/cliamp-favorites.json"
  property var favoriteStats: ({})

  function loadFavoriteStats(raw) {
    try {
      var parsed = JSON.parse(String(raw || "").trim() || "{}")
      root.favoriteStats = (parsed && typeof parsed === "object") ? parsed : ({})
    } catch (e) {
      root.favoriteStats = ({})
    }
  }

  property bool actionsMenuOpen: false
  property int actionsSelectedIndex: 0
  property real actionsMenuX: 0
  property real actionsMenuY: 0
  // Favorite is always offered now, catalog row or search hit alike --
  // see this file's own header for why that's a local favorite, not
  // cliamp's own. "play" relabels to "Pause" for whichever row is
  // actually on air right now -- direct ask: "tab to pause for the
  // one playing".
  readonly property var stationActions: root.selectedRow ? [
    { id: "play", label: root.selectedIsPlaying ? "Pause" : "Play" },
    { id: "favorite", label: root.selectedRow.favorite ? "Unfavorite" : "Favorite" }
  ] : []

  // Launcher.qml backs out to the landing list on this -- see
  // handleNotRunning below for when it fires.
  signal exitRequested()

  function runCatalog() {
    catalogProc.exec(["cliamp", "remote", "call", "provider.catalog", "--params",
      JSON.stringify({ provider: "radio", offset: 0, limit: 50 }), "--wait"])
  }

  // Plain HTTP fetch, not a cliamp IPC call -- see rawBundled's own
  // property comment above for why. A failure here just leaves
  // rawBundled empty (retried the next time the extension opens, see
  // onActiveChanged) rather than touching cliampRunning/exitRequested
  // at all -- this list existing or not is independent of whether
  // cliamp itself is up.
  function runBundled() {
    bundledProc.exec(["curl", "-s", "--max-time", "8", "https://radio.cliamp.stream/streams.m3u"])
  }

  function runSearch() {
    var q = root.searchText.trim()
    if (q === "") { root.runCatalog(); return }
    searchProc.exec(["cliamp", "remote", "call", "provider.search", "--params",
      JSON.stringify({ provider: "radio", query: q, offset: 0, limit: 30 }), "--wait"])
  }

  function refreshStatus() {
    statusProc.exec(["cliamp", "status", "--json"])
  }

  function startCliamp() {
    Quickshell.execDetached(["cliamp", "--daemon", "--no-auto-play", "--provider", "radio"])
    startRetryTimer.start()
  }

  // Called from catalogProc/searchProc only when parseJobResult's own
  // notRunning flag is true (the literal "cliamp is not running"
  // text) -- NOT for every fetch failure. A job that fails while
  // cliamp is actually up and connected (confirmed live: a transient
  // radio-browser.info timeout building the station catalog) must
  // never land here, or a plain network blip would spawn a redundant
  // daemon and derail a perfectly good session.
  //
  // First attempt: actually spawn it. Each attempt after that just
  // waits and checks again (startRetryTimer, NOT a second
  // startCliamp() -- re-execing on top of a daemon that's simply still
  // binding its socket is pure downside, never helps). Past
  // maxNotRunningAttempts: genuinely not coming up, so leave instead
  // of sitting on a dead list -- direct follow-up, see
  // notRunningAttempts' own comment above for the exact wording.
  function handleNotRunning() {
    root.cliampRunning = false
    root.rawCatalog = []
    root.rawTracks = []
    root.notRunningAttempts++
    if (root.notRunningAttempts === 1) {
      root.startCliamp()
    } else if (root.notRunningAttempts <= root.maxNotRunningAttempts) {
      startRetryTimer.start()
    } else {
      root.exitRequested()
    }
  }

  function playSelected() {
    if (!root.selectedRow) return
    var row = root.selectedRow
    root.lastPlayAttemptName = row.fullName
    root.lastPlayAttemptPath = row.trackPath || ""
    if (row.providerId === "cliamp-track") {
      trackPlayProc.exec(["cliamp", "remote", "call", "track.play", "--params",
        JSON.stringify({ track: { title: row.trackTitle, path: row.trackPath, stream: true, realtime: true } }), "--wait"])
    } else {
      loadProc.exec(["cliamp", "remote", "call", "provider.load", "--params",
        JSON.stringify({ provider: "radio", playlist: row.stationId }), "--wait"])
    }
  }

  // Real v2 remote op, no params -- confirmed directly against
  // `cliamp remote capabilities` (also lists a generic "toggle", but a
  // plain "pause" is unambiguous here: selectedIsPlaying has already
  // confirmed this exact row is the one on air, so there's nothing to
  // toggle between).
  function pauseSelected() {
    pauseProc.exec(["cliamp", "remote", "call", "pause", "--wait"])
  }

  // Enter/double-click/Tab's own "play" action all go through this now
  // -- direct ask: "so when its playing enter again pauses it". Only
  // the already-playing row's own activation pauses; picking any other
  // row (including a different one while something else plays) still
  // starts it the normal way through playSelected().
  function togglePlayPauseSelected() {
    if (root.selectedIsPlaying) root.pauseSelected()
    else root.playSelected()
  }

  // Local-only now -- no IPC call, no round-trip wait. See this file's
  // own header for why this replaced cliamp's native provider.favorite
  // entirely rather than running alongside it for catalog rows only.
  function toggleFavoriteSelected() {
    var row = root.selectedRow
    if (!row) return
    root.favoriteStats = CliampFavorites.toggleFavorite(root.favoriteStats, row.fullName, row.trackPath || "")
    favoritesFile.setText(JSON.stringify(root.favoriteStats))
  }

  // Fire-and-poll, same shape as playSelected() above -- the real
  // confirmation comes from the next status poll picking up the new
  // eq_preset (statusTimer already runs every 2s), refreshStatus()
  // here just makes it feel instant on tap rather than waiting out
  // that interval.
  function setEqPreset(name) {
    eqProc.exec(["cliamp", "remote", "call", "eq", "--params",
      JSON.stringify({ name: name }), "--wait"])
  }

  function runStationAction(id) {
    if (id === "play") root.togglePlayPauseSelected()
    else if (id === "favorite") root.toggleFavoriteSelected()
    root.closeActionsMenu()
  }

  function moveSelectionUp() {
    if (root.actionsMenuOpen) {
      if (root.actionsSelectedIndex > 0) root.actionsSelectedIndex--
      return
    }
    if (root.selectedIndex > 0) root.selectedIndex--
  }

  function moveSelectionDown() {
    if (root.actionsMenuOpen) {
      if (root.actionsSelectedIndex < root.stationActions.length - 1) root.actionsSelectedIndex++
      return
    }
    if (root.selectedIndex < root.rows.length - 1) root.selectedIndex++
  }

  function activateSelection() {
    if (root.actionsMenuOpen) {
      var action = root.stationActions[root.actionsSelectedIndex]
      if (action) root.runStationAction(action.id)
      return
    }
    root.togglePlayPauseSelected()
  }

  function focusRightPanel() {
    if (root.actionsMenuOpen) { root.closeActionsMenu(); return }
    root.openActionsMenu()
  }

  function blurToLeftPanel() {
    root.closeActionsMenu()
  }

  function openActionsMenu() {
    if (root.stationActions.length === 0) return
    root.actionsSelectedIndex = 0
    root.actionsMenuOpen = true
    root.positionActionsMenuNearSelection()
  }

  function closeActionsMenu() {
    root.actionsMenuOpen = false
  }

  function positionActionsMenuNearSelection() {
    var item = cliampResultsList.itemAtIndex(root.selectedIndex)
    if (!item) return
    var scenePos = item.mapToItem(null, 0, item.height)
    var localPos = root.mapFromItem(null, scenePos.x, scenePos.y)
    var menuHeight = root.stationActions.length * 34 + 8
    root.actionsMenuX = Math.max(8, Math.min(localPos.x + 6, root.width - cliampResultsList.width - 8))
    root.actionsMenuY = Math.max(8, Math.min(localPos.y + 4, root.height - menuHeight - 8))
  }

  function ensureSelectionVisible() {
    if (cliampResultsList.count === 0) return
    cliampResultsList.positionViewAtIndex(Math.min(root.selectedIndex + root.scrollOff, root.rows.length - 1), ListView.Contain)
    cliampResultsList.positionViewAtIndex(Math.max(root.selectedIndex - root.scrollOff, 0), ListView.Contain)
    cliampResultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  onRowsChanged: {
    if (root.selectedIndex >= root.rows.length) root.selectedIndex = Math.max(0, root.rows.length - 1)
    root.ensureSelectionVisible()
  }

  onSelectedIndexChanged: {
    root.hoverArmed = false
    root.hoverArmBaseline = Qt.point(-1, -1)
    root.actionsMenuOpen = false
    root.ensureSelectionVisible()
  }

  onActiveChanged: {
    if (root.active) {
      root.selectedIndex = 0
      root.notRunningAttempts = 0
      root.hoverArmed = false
      root.hoverArmBaseline = Qt.point(-1, -1)
      root.runSearch()
      root.refreshStatus()
      if (root.rawBundled.length === 0) root.runBundled()
      statusTimer.start()
      Qt.callLater(function() { cliampResultsList.positionViewAtBeginning() })
    } else {
      statusTimer.stop()
    }
  }

  onSearchTextChanged: {
    if (!root.active) return
    if (root.searchText.trim() === "") { searchDebounce.stop(); root.runCatalog(); return }
    searchDebounce.restart()
  }

  Timer {
    id: searchDebounce
    interval: 300
    onTriggered: root.runSearch()
  }

  Timer {
    id: statusTimer
    interval: 2000
    repeat: true
    onTriggered: root.refreshStatus()
  }

  // Re-checks after startCliamp() detaches the daemon process, and
  // again for each of handleNotRunning's own follow-up attempts -- the
  // socket isn't accepting connections the instant the process forks,
  // a fixed short delay between checks is simpler than polling for the
  // socket file to actually appear.
  Timer {
    id: startRetryTimer
    interval: 1200
    onTriggered: { root.runSearch(); root.refreshStatus() }
  }

  // Every one of these five reads BOTH streams, not just stdout --
  // `cliamp remote call ... --wait` puts its JSON envelope on stdout
  // only on success; EVERY failure (including "cliamp is not running",
  // the literal signal handleNotRunning needs) goes to stderr instead,
  // confirmed live with the two streams captured separately. A Process
  // bound to stdout alone sees empty text for every failure and can
  // never actually read why it failed -- confirmed live the hard way,
  // see CliampStations.parseJobResult's own header comment for the
  // full story. onExited (not either collector's own onStreamFinished)
  // is the one point both collectors are guaranteed flushed by.
  Process {
    id: catalogProc
    stdout: StdioCollector { id: catalogStdout; waitForEnd: true }
    stderr: StdioCollector { id: catalogStderr; waitForEnd: true }
    onExited: function() {
      var parsed = CliampStations.parseJobResult(catalogStdout.text, catalogStderr.text)
      if (!parsed.ok) {
        if (parsed.notRunning) { root.handleNotRunning(); return }
        // Running, but this one call errored (e.g. a radio-browser.info
        // timeout) -- leave cliampRunning alone and just show no
        // results rather than treating it as "not running".
        root.rawCatalog = []
        return
      }
      root.cliampRunning = true
      root.rawCatalog = parsed.result.playlists || []
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector { id: searchStdout; waitForEnd: true }
    stderr: StdioCollector { id: searchStderr; waitForEnd: true }
    onExited: function() {
      var parsed = CliampStations.parseJobResult(searchStdout.text, searchStderr.text)
      if (!parsed.ok) {
        if (parsed.notRunning) { root.handleNotRunning(); return }
        root.rawTracks = []
        return
      }
      root.cliampRunning = true
      root.rawTracks = parsed.result.tracks || []
    }
  }

  // Plain curl, not cliamp's own job/envelope protocol -- parseJobResult
  // doesn't apply here, this is just raw M3U text on success or empty
  // stdout on failure (bad network, host down). Left empty rather than
  // retried in a loop on failure -- onActiveChanged's own
  // rawBundled.length === 0 check tries again the next time this
  // extension opens instead.
  Process {
    id: bundledProc
    stdout: StdioCollector { id: bundledStdout; waitForEnd: true }
    onExited: function() {
      var parsed = CliampStations.parseBundledPlaylist(bundledStdout.text)
      if (parsed.length > 0) root.rawBundled = parsed
    }
  }

  // recordPlayed() below only fires on parsed.ok -- a station that
  // genuinely failed to load was never actually "played", so it has
  // no business bumping a last-played timestamp.
  Process {
    id: loadProc
    stdout: StdioCollector { id: loadStdout; waitForEnd: true }
    stderr: StdioCollector { id: loadStderr; waitForEnd: true }
    // Only a genuine "not running" flips cliampRunning false here --
    // a dead station URL or similar is a real, run-of-the-mill
    // play failure that still means the daemon is up and responded
    // (same reasoning as catalogProc/searchProc above).
    onExited: function() {
      var parsed = CliampStations.parseJobResult(loadStdout.text, loadStderr.text)
      if (parsed.ok) {
        root.cliampRunning = true
        root.favoriteStats = CliampFavorites.recordPlayed(root.favoriteStats, root.lastPlayAttemptName, root.lastPlayAttemptPath)
        favoritesFile.setText(JSON.stringify(root.favoriteStats))
      } else if (parsed.notRunning) {
        root.cliampRunning = false
      }
      root.refreshStatus()
    }
  }

  Process {
    id: trackPlayProc
    stdout: StdioCollector { id: trackPlayStdout; waitForEnd: true }
    stderr: StdioCollector { id: trackPlayStderr; waitForEnd: true }
    onExited: function() {
      var parsed = CliampStations.parseJobResult(trackPlayStdout.text, trackPlayStderr.text)
      if (parsed.ok) {
        root.cliampRunning = true
        root.favoriteStats = CliampFavorites.recordPlayed(root.favoriteStats, root.lastPlayAttemptName, root.lastPlayAttemptPath)
        favoritesFile.setText(JSON.stringify(root.favoriteStats))
      } else if (parsed.notRunning) {
        root.cliampRunning = false
      }
      root.refreshStatus()
    }
  }

  // Not gated on parseJobResult's own notRunning/ok split like every
  // other Process above -- a failed EQ change (bad preset name, say)
  // is never worth spawning a redundant daemon or flipping
  // cliampRunning over. refreshStatus() either way picks the real
  // current preset back up regardless of whether this call actually
  // landed.
  Process {
    id: eqProc
    stdout: StdioCollector { id: eqStdout; waitForEnd: true }
    stderr: StdioCollector { id: eqStderr; waitForEnd: true }
    onExited: function() { root.refreshStatus() }
  }

  // Same fire-and-poll shape as eqProc above -- the real confirmation
  // comes from the next status poll picking up state: "paused"
  // (statusTimer already runs every 2s), refreshStatus() here just
  // makes the icon/EQ-bars swap feel instant instead of waiting it out.
  Process {
    id: pauseProc
    stdout: StdioCollector { id: pauseStdout; waitForEnd: true }
    stderr: StdioCollector { id: pauseStderr; waitForEnd: true }
    onExited: function() { root.refreshStatus() }
  }

  Process {
    id: statusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var status = CliampStations.parseStatus(text)
        root.nowPlaying = status
        if (status) root.cliampRunning = true
      }
    }
    onExited: function(exitCode) { if (exitCode !== 0) { root.nowPlaying = null; root.cliampRunning = false } }
  }

  // mkdir -p before the FileView's first write rather than assuming
  // ~/.local/state/ruixen already exists -- same belt-and-suspenders
  // pattern FileSearchProvider.qml's own search-config store uses,
  // since plugin load order isn't guaranteed to have created it yet.
  Process {
    id: ensureFavoritesDirProc
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/ruixen"]
  }
  Component.onCompleted: ensureFavoritesDirProc.running = true

  FileView {
    id: favoritesFile
    path: root.favoritesStatePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadFavoriteStats(text())
    onLoadFailed: root.loadFavoriteStats("")
  }

  ExtensionTwoPanel {
    id: panel
    anchors.fill: parent
    // Same 0.6 every other 2-panel extension in this plugin uses
    // (Clipboard, Search Files) -- direct follow-up: the narrower
    // split this extension started with read as inconsistent.
    detailRatio: 0.6
  }

  ResultsList {
    id: cliampResultsList
    parent: panel.leftPane
    anchors.fill: parent
    model: root.rows
    fontFamily: root.fontFamily
    mutedColor: root.muted
    textColor: root.textColor
    accentColor: root.accent
    filesMode: true
    selectedIndex: root.selectedIndex
    rowHeightPx: 40
    sectionHeaderHeight: 26
    // !root.rightFocused -- same fix KanbanBoardContent.qml's own
    // onRowHovered needed (see that file's own comment for the full
    // "why"): opening the actions menu via Tab leaves the real mouse
    // cursor wherever it already was, so reaching for the menu with the
    // mouse crosses other rows first, each one's own hover reselecting
    // and closing the menu before the click could land.
    onRowHovered: (idx) => { if (root.hoverArmed && !root.rightFocused) root.selectedIndex = idx }
    onRowActivated: (idx) => { root.selectedIndex = idx; root.togglePlayPauseSelected() }
    onRowActionsRequested: (idx) => {
      root.selectedIndex = idx
      root.openActionsMenu()
    }

    // Arms hoverArmed (see its own property comment above) on the
    // first REAL pointer movement -- a passive input handler, not a
    // MouseArea, so it observes pointer events over the whole list
    // without stealing anything from each row's own MouseArea
    // beneath it. The first onPointChanged after any reset is
    // captured as a baseline instead of treated as movement, so a
    // content-shift-under-a-still-cursor (this list scrolling itself
    // under the keyboard above) is never mistaken for the user's
    // hand actually moving.
    HoverHandler {
      onPointChanged: {
        if (root.hoverArmed) return
        if (root.hoverArmBaseline.x < 0) {
          root.hoverArmBaseline = point.position
          return
        }
        if (Math.abs(point.position.x - root.hoverArmBaseline.x) > 0.5
            || Math.abs(point.position.y - root.hoverArmBaseline.y) > 0.5)
          root.hoverArmed = true
      }
    }
  }

  Text {
    parent: panel.leftPane
    anchors.centerIn: parent
    // Stays "Loading stations…" through the brief auto-start/retry
    // window too (root.cliampRunning false), not just the very first
    // fetch -- no separate "cliamp isn't running" message exists
    // anymore (see notRunningAttempts' own comment above), so there's
    // nothing else this could say in that gap.
    visible: root.rows.length === 0
    text: root.searchText.trim() !== "" && root.cliampRunning
      ? "No stations found for “" + root.searchText.trim() + "”"
      : "Loading stations…"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: 12
  }

  ResultActionsMenu {
    parent: root
    x: root.actionsMenuX
    y: root.actionsMenuY
    visible: root.actionsMenuOpen
    actions: root.stationActions
    selectedIndex: root.actionsSelectedIndex
    textColor: root.textColor
    accentColor: root.accent
    glassTint: root.glassTint
    glassBorder: root.glassBorder
    fontFamily: root.fontFamily
    menuWidth: cliampResultsList.width - 12
    onActionHovered: (idx) => root.actionsSelectedIndex = idx
    onActionActivated: (id) => root.runStationAction(id)
  }

  CliampStationPanel {
    parent: panel.rightPane
    anchors.fill: parent
    selectedRow: root.selectedRow
    nowPlaying: root.nowPlaying
    eqPresets: root.eqPresets
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onEqPresetSelected: (name) => root.setEqPreset(name)
  }
}
