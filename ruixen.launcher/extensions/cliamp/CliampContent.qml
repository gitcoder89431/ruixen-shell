import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "CliampStations.js" as CliampStations

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

  readonly property string searchPlaceholder: "Search Radio Stations"
  readonly property bool showsEnterHint: true
  readonly property bool interceptsArrowKeys: true
  readonly property bool rightFocused: root.actionsMenuOpen

  property bool cliampRunning: true
  property var rows: []
  property int selectedIndex: 0
  readonly property var selectedRow: root.rows[root.selectedIndex] || null
  readonly property int scrollOff: 2
  property var nowPlaying: null

  property bool actionsMenuOpen: false
  property int actionsSelectedIndex: 0
  property real actionsMenuX: 0
  property real actionsMenuY: 0
  readonly property var stationActions: root.selectedRow ? (function() {
    var out = [{ id: "play", label: "Play" }]
    if (root.selectedRow.favoritable) out.push({ id: "favorite", label: root.selectedRow.favorite ? "Unfavorite" : "Favorite" })
    return out
  })() : []

  function runCatalog() {
    catalogProc.exec(["cliamp", "remote", "call", "provider.catalog", "--params",
      JSON.stringify({ provider: "radio", offset: 0, limit: 50 }), "--wait"])
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

  function playSelected() {
    if (!root.selectedRow) { root.startCliamp(); return }
    var row = root.selectedRow
    if (row.providerId === "cliamp-track") {
      trackPlayProc.exec(["cliamp", "remote", "call", "track.play", "--params",
        JSON.stringify({ track: { title: row.trackTitle, path: row.trackPath, stream: true, realtime: true } }), "--wait"])
    } else {
      loadProc.exec(["cliamp", "remote", "call", "provider.load", "--params",
        JSON.stringify({ provider: "radio", playlist: row.stationId }), "--wait"])
    }
  }

  function toggleFavoriteSelected() {
    var row = root.selectedRow
    if (!row || !row.favoritable) return
    favoriteProc.exec(["cliamp", "remote", "call", "provider.favorite", "--params",
      JSON.stringify({ provider: "radio", playlist: row.stationId }), "--wait"])
  }

  function runStationAction(id) {
    if (id === "play") root.playSelected()
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
    root.playSelected()
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
    root.actionsMenuOpen = false
    root.ensureSelectionVisible()
  }

  onActiveChanged: {
    if (root.active) {
      root.selectedIndex = 0
      root.runSearch()
      root.refreshStatus()
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

  // Single-shot retry after startCliamp() detaches the daemon process
  // -- the socket isn't accepting connections the instant the process
  // forks, a fixed short delay is simpler than polling for the socket
  // file to appear for a cold-start path that only runs once per
  // session anyway.
  Timer {
    id: startRetryTimer
    interval: 1200
    onTriggered: { root.runSearch(); root.refreshStatus() }
  }

  Process {
    id: catalogProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = CliampStations.parseJobResult(text)
        if (!parsed.ok) { root.cliampRunning = false; root.rows = []; return }
        root.cliampRunning = true
        root.rows = CliampStations.bucketCatalog(parsed.result.playlists, root.accent)
      }
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = CliampStations.parseJobResult(text)
        if (!parsed.ok) { root.cliampRunning = false; root.rows = []; return }
        root.cliampRunning = true
        root.rows = CliampStations.searchRows(parsed.result.tracks)
      }
    }
  }

  Process {
    id: loadProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = CliampStations.parseJobResult(text)
        root.cliampRunning = parsed.ok
        root.refreshStatus()
      }
    }
  }

  Process {
    id: trackPlayProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = CliampStations.parseJobResult(text)
        root.cliampRunning = parsed.ok
        root.refreshStatus()
      }
    }
  }

  Process {
    id: favoriteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = CliampStations.parseJobResult(text)
        // Only catalog rows are ever favoritable, so a favorite toggle
        // only ever needs to refresh the catalog view, never a search.
        if (parsed.ok && root.searchText.trim() === "") root.runCatalog()
      }
    }
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

  ExtensionTwoPanel {
    id: panel
    anchors.fill: parent
    detailRatio: 0.42
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
    onRowHovered: (idx) => root.selectedIndex = idx
    onRowActivated: (idx) => { root.selectedIndex = idx; root.playSelected() }
    onRowActionsRequested: (idx) => {
      root.selectedIndex = idx
      root.openActionsMenu()
    }
  }

  Text {
    parent: panel.leftPane
    anchors.centerIn: parent
    visible: root.rows.length === 0 && root.cliampRunning
    text: root.searchText.trim() !== "" ? "No stations found for “" + root.searchText.trim() + "”" : "Loading stations…"
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
    cliampRunning: root.cliampRunning
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onStartRequested: root.startCliamp()
  }
}
