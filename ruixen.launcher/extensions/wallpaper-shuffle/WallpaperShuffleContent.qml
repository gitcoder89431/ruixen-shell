import QtQuick
import Quickshell
import Quickshell.Io
import "../.."

// A fifth launcher extension: order the wallpaper shuffle queue.
// Direct ask, after the grid-based Wallpapers extension's own layout
// turned out to be a real structural constraint for this ("the grid
// stuff is causing a design constraint"): "the typical launcher
// layout, so left panel are media inside ruixen-wallpaper, you can
// tab to move and order this list... a one panel list like the
// launcher, and then you just get a list of stuff from ruixen-
// wallpaper you can tab to adjust ordering and see the live queue".
// Same 2-panel ExtensionTwoPanel shape Clipboard/Theme Browser/
// Settings/Cliamp already use (ResultsList left, a detail/preview
// pane right) -- ExtensionTwoPanel.qml's own header comment already
// calls Wallpapers out as "its own thing on purpose... a genuinely
// different shape, not forced through this component", confirming
// the grid really is the outlier here, not the thing to extend.
//
// Discovery reuses ruixen.notch's own deployed list-wallpapers.sh by
// its known install path -- the SAME cross-plugin dependency the
// existing Wallpapers extension's own WallpapersContent.qml already
// relies on for its own discovery, not a new script.
//
// Ordering is a thin layer on top of what rotation already does, not
// a replacement for it: ~/.local/state/ruixen/wallpaper-order.json
// (plain filenames) is written directly here, no IPC round-trip --
// same shared-state-file precedent wallpaper-appearance.json already
// uses for the Wallpaper appearance panels. ruixen.wallpaper/
// wallpaper-rotation.py's own next_artwork() reconciles this same
// file against the live folder on every pick (order wins, a missing
// file drops silently, a new file appends at the end); this file
// reconciles with the IDENTICAL algorithm in JS so what's shown here
// always matches what rotation will actually do next.
//
// Reordering goes through Tab -> the per-row actions menu (Move
// up/Move down), not a new Tab meaning of its own -- Tab already has
// an established, specific meaning in this launcher (opening the
// per-row actions menu / focusing the detail pane), confirmed
// directly in Launcher.qml's own activeExtensionContent contract
// comment; inventing a second meaning for it here would collide with
// that instead of extending it.
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

  readonly property string searchPlaceholder: "Search Wallpaper Queue"
  readonly property bool showsEnterHint: true
  readonly property bool interceptsArrowKeys: true
  readonly property bool rightFocused: root.actionsMenuOpen

  // Direct report: "the kbd scroll doesnt work, doesnt have the smart
  // scroll like the other extensions". Two real, separate pieces,
  // ported verbatim from ClipboardContent.qml (same bug class its own
  // comments already document): ensureSelectionVisible() below keeps
  // the selected row on screen as arrow keys move it past either
  // edge, and hoverArmed/hoverArmBaseline stop a keyboard-driven
  // scroll from fighting back -- without it, the list scrolling under
  // a STILL cursor reads as "the user's hand moved", snapping
  // selection back to whatever row the cursor happened to land on.
  readonly property int scrollOff: 2
  property bool hoverArmed: false
  property point hoverArmBaseline: Qt.point(-1, -1)
  function ensureSelectionVisible() {
    if (shuffleResultsList.count === 0) return
    shuffleResultsList.positionViewAtIndex(Math.min(root.selectedIndex + root.scrollOff, root.rows.length - 1), ListView.Contain)
    shuffleResultsList.positionViewAtIndex(Math.max(root.selectedIndex - root.scrollOff, 0), ListView.Contain)
    shuffleResultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }
  onSelectedIndexChanged: {
    root.hoverArmed = false
    root.hoverArmBaseline = Qt.point(-1, -1)
    root.ensureSelectionVisible()
  }

  // { kind, display, real, identity, source }, same shape
  // WallpapersContent.qml's own listProc already produces -- live
  // discovery, not cached, so a file added/removed in the folder is
  // picked up the next time this extension opens.
  property var mediaEntries: []
  property string currentBackground: ""
  readonly property string helperDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/ruixen.notch"

  // The persisted order, reconciled against mediaEntries -- see this
  // file's own header comment for the exact algorithm, kept identical
  // to wallpaper-rotation.py's own.
  property var storedOrder: []
  readonly property var liveNames: {
    var names = root.mediaEntries.map(function(e) { return e.real.substring(e.real.lastIndexOf("/") + 1) })
    return names.slice().sort()
  }
  readonly property var reconciledNames: {
    var live = {}
    for (var i = 0; i < root.liveNames.length; i++) live[root.liveNames[i]] = true
    var seen = {}
    var out = []
    for (var j = 0; j < root.storedOrder.length; j++) {
      var name = root.storedOrder[j]
      if (live[name] && !seen[name]) { out.push(name); seen[name] = true }
    }
    for (var k = 0; k < root.liveNames.length; k++) {
      var n = root.liveNames[k]
      if (!seen[n]) { out.push(n); seen[n] = true }
    }
    return out
  }
  readonly property var entryByName: {
    var out = {}
    for (var i = 0; i < root.mediaEntries.length; i++) {
      var e = root.mediaEntries[i]
      out[e.real.substring(e.real.lastIndexOf("/") + 1)] = e
    }
    return out
  }
  readonly property var orderedEntries: root.reconciledNames.map(function(name) { return root.entryByName[name] }).filter(function(e) { return !!e })

  function kindLabel(kind) { return kind === "video" ? "Video" : kind === "gif" ? "GIF" : "Image" }

  // Ignored wallpapers -- plain filenames, persisted and reconciled the
  // same way storedOrder is (own header comment above). Still listed
  // here (not hidden), so there's a way back to Un-ignore one; rotation
  // itself is what actually excludes them (wallpaper-rotation.py's own
  // next_artwork, see its header comment), this is just the toggle.
  property var ignoredNames: []
  readonly property var ignoredSet: {
    var out = {}
    for (var i = 0; i < root.ignoredNames.length; i++) out[root.ignoredNames[i]] = true
    return out
  }

  // Stateful left-edge icon -- direct request: three states, current
  // (fa-check-circle, U+F058 -- the SAME glyph ThemeCatalog.js's own
  // currentSlug row already uses for "this is the one actually active
  // right now", not a new pick) beats ignored beats the plain default
  // (fa-file-image-o, U+F1C5, same glyph ClipboardHistory.js's own
  // Image kind already uses) since a wallpaper can't be both at once
  // in a way that matters more than being current.
  function rowIcon(isCurrent, ignored) {
    if (isCurrent) return ""
    if (ignored) return ""
    return ""
  }
  function rowIconColor(isCurrent, ignored) {
    if (isCurrent) return root.accent
    if (ignored) return root.muted
    return root.textColor
  }

  readonly property var rows: {
    var q = root.searchText.trim().toLowerCase()
    var out = []
    for (var i = 0; i < root.orderedEntries.length; i++) {
      var e = root.orderedEntries[i]
      var name = e.real.substring(e.real.lastIndexOf("/") + 1)
      if (q !== "" && name.toLowerCase().indexOf(q) === -1) continue
      var ignored = !!root.ignoredSet[name]
      var isCurrent = e.identity === root.currentBackground
      out.push({
        id: "wallpaper-shuffle:" + e.identity,
        providerId: "wallpaper-shuffle-queue",
        icon: root.rowIcon(isCurrent, ignored),
        iconColor: root.rowIconColor(isCurrent, ignored),
        label: name,
        breadcrumb: (ignored ? "Ignored · " : "") + (i + 1) + " of " + root.orderedEntries.length,
        kind: root.kindLabel(e.kind),
        providerName: "",
        sectionLabel: "Queue",
        score: 0,
        entry: e,
        ignored: ignored
      })
    }
    return out
  }

  property int selectedIndex: 0
  readonly property var selectedRow: root.rows[root.selectedIndex] || null
  readonly property var selectedEntry: root.selectedRow ? root.selectedRow.entry : null

  property bool actionsMenuOpen: false
  property int actionsSelectedIndex: 0
  property real actionsMenuX: 0
  property real actionsMenuY: 0
  // "Set as wallpaper" plus only the directions actually legal from
  // here -- no disabled-but-visible Move entries, same "just don't
  // show it" approach Clipboard's own clipboardActions already takes
  // for its own conditional entries (QR/reveal/etc.). Direct
  // correction: "we dont need a set as wallpaper now [button in the
  // detail panel], maybe put that in the tab dropdown too" -- Enter
  // still does the same thing as a quick default, this just stops
  // being the ONLY way to reach it.
  readonly property var shuffleActions: {
    var out = [{ id: "apply", label: "Set as wallpaper" }]
    if (root.selectedIndex > 0) out.push({ id: "up", label: "Move up" })
    if (root.selectedIndex < root.rows.length - 1) out.push({ id: "down", label: "Move down" })
    out.push({ id: "ignore", label: (root.selectedRow && root.selectedRow.ignored) ? "Un-ignore" : "Ignore" })
    return out
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
      if (root.actionsSelectedIndex < root.shuffleActions.length - 1) root.actionsSelectedIndex++
      return
    }
    if (root.selectedIndex < root.rows.length - 1) root.selectedIndex++
  }

  function activateSelection() {
    if (root.actionsMenuOpen) {
      var action = root.shuffleActions[root.actionsSelectedIndex]
      if (action) root.runAction(action.id)
      return
    }
    root.applySelected()
  }

  function focusRightPanel() {
    if (root.actionsMenuOpen) { root.closeActionsMenu(); return }
    root.openActionsMenu()
  }

  function blurToLeftPanel() {
    root.closeActionsMenu()
  }

  function openActionsMenu() {
    if (root.shuffleActions.length === 0) return
    root.actionsSelectedIndex = 0
    root.actionsMenuOpen = true
    root.positionActionsMenuNearSelection()
  }

  function closeActionsMenu() {
    root.actionsMenuOpen = false
  }

  function positionActionsMenuNearSelection() {
    var item = shuffleResultsList.itemAtIndex(root.selectedIndex)
    if (!item) return
    var scenePos = item.mapToItem(null, 0, item.height)
    var localPos = root.mapFromItem(null, scenePos.x, scenePos.y)
    var menuHeight = root.shuffleActions.length * 34 + 8
    root.actionsMenuX = Math.max(8, Math.min(localPos.x + 6, root.width - shuffleResultsList.width - 8))
    root.actionsMenuY = Math.max(8, Math.min(localPos.y + 4, root.height - menuHeight - 8))
  }

  function runAction(id) {
    if (id === "apply") root.applySelected()
    else if (id === "up") root.moveSelected(-1)
    else if (id === "down") root.moveSelected(1)
    else if (id === "ignore") root.toggleIgnored()
    root.closeActionsMenu()
  }

  // Direct ask: "in the tab dropdown i wanna add a feature for ignore
  // or like to make it not in rotation". Toggles the selected entry's
  // own filename in the persisted ignored set -- excluding it from
  // rotation's candidate pool entirely (both shuffle and sequential,
  // see wallpaper-rotation.py's own next_artwork) without touching the
  // file or removing it from this list.
  function toggleIgnored() {
    var row = root.selectedRow
    if (!row) return
    var name = row.label
    var names = root.ignoredNames.slice()
    var idx = names.indexOf(name)
    if (idx === -1) names.push(name)
    else names.splice(idx, 1)
    root.persistIgnored(names)
  }

  function persistIgnored(names) {
    root.ignoredNames = names
    ignoredFile.setText(JSON.stringify({ version: 1, ignored: names }) + "\n")
  }

  // Swaps the selected row with its neighbor in the RECONCILED order,
  // persists that as the new explicit order, and keeps the selection
  // following the moved item so repeated Tab->Move up/down reads as
  // "drag this one up the list" rather than losing your place.
  function moveSelected(direction) {
    var idx = root.selectedIndex
    var other = idx + direction
    if (other < 0 || other >= root.reconciledNames.length) return
    var names = root.reconciledNames.slice()
    var tmp = names[idx]; names[idx] = names[other]; names[other] = tmp
    root.persistOrder(names)
    root.selectedIndex = other
  }

  function persistOrder(names) {
    root.storedOrder = names
    orderFile.setText(JSON.stringify({ version: 1, order: names }) + "\n")
  }

  // Applies the selected entry as the current wallpaper right now --
  // same three-way kind dispatch WallpapersContent.qml's own select()
  // already uses (image via the plain bg-setter, video/gif through
  // ruixen.wallpaper's own playVideo/playGif IPC), not reinvented.
  property real selectGeneration: Date.now()
  function applySelected() {
    var e = root.selectedEntry
    if (!e) return
    root.currentBackground = e.identity
    root.selectGeneration += 1
    var gen = String(root.selectGeneration)
    if (e.kind === "video") {
      playVideoProc.command = ["omarchy-shell", "ruixen.wallpaper", "playVideo", e.real, gen]
      playVideoProc.running = true
    } else if (e.kind === "gif") {
      playGifProc.command = ["omarchy-shell", "ruixen.wallpaper", "playGif", e.real, gen]
      playGifProc.running = true
    } else {
      stopVideoProc.command = ["omarchy-shell", "ruixen.wallpaper", "stop", gen]
      stopVideoProc.running = true
      setProc.command = ["omarchy-theme-bg-set", e.real]
      setProc.running = true
    }
  }

  function refresh() {
    if (!listProc.running) listProc.running = true
    if (!currentProc.running) currentProc.running = true
  }

  onActiveChanged: {
    if (root.active) {
      root.selectedIndex = 0
      root.actionsMenuOpen = false
      root.hoverArmed = false
      root.hoverArmBaseline = Qt.point(-1, -1)
      root.refresh()
      Qt.callLater(function() { shuffleResultsList.positionViewAtBeginning() })
    }
  }

  // Direct ask: "make this left panel list live so current is ontop,
  // when it rotates it goes to the buttom... like a live que". The
  // order file itself already live-reloads (orderFile's own
  // watchChanges: true), so the rotated sequence shows up on its own
  // -- but currentBackground (what actually draws the checkmark icon)
  // only ever came from a single refresh() on open, so a rotation
  // that happens while this extension is already sitting open never
  // moved the checkmark until it was closed and reopened. Same 1000ms
  // poll every other wallpaper state file in this plugin family
  // already uses (WallpaperRotationState.qml/WallpaperAppearanceState
  // .qml/WallpaperAppearancePanel.qml), not a new pattern.
  Timer { interval: 1000; running: root.active; repeat: true; onTriggered: root.refresh() }

  onRowsChanged: {
    if (root.selectedIndex >= root.rows.length) root.selectedIndex = Math.max(0, root.rows.length - 1)
  }

  Process {
    id: listProc
    command: [root.helperDir + "/list-wallpapers.sh"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n").filter(function(line) { return line.length > 0 })
        root.mediaEntries = lines.map(function(line) {
          var parts = line.split("\u001f")
          return { kind: parts[0], display: parts[1], real: parts[2], identity: parts[3] !== undefined ? parts[3] : parts[1], source: parts[4] !== undefined ? parts[4] : "omarchy" }
        })
      }
    }
  }

  Process {
    id: currentProc
    command: ["bash", "-c", "readlink -f \"$HOME/.local/state/omarchy/current/background\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.currentBackground = String(text || "").trim()
    }
  }

  Process { id: setProc; stdout: StdioCollector { waitForEnd: true } }
  Process { id: stopVideoProc; stdout: StdioCollector { waitForEnd: true } }
  Process { id: playVideoProc; stdout: StdioCollector { waitForEnd: true } }
  Process { id: playGifProc; stdout: StdioCollector { waitForEnd: true } }

  FileView {
    id: orderFile
    path: Quickshell.env("HOME") + "/.local/state/ruixen/wallpaper-order.json"
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.loadOrder(text())
    onLoadFailed: root.storedOrder = []
    onFileChanged: reload()
  }

  function loadOrder(raw) {
    try {
      var parsed = JSON.parse(String(raw || "").trim() || "{}")
      var order = parsed && parsed.order
      root.storedOrder = Array.isArray(order) ? order.filter(function(n) { return typeof n === "string" }) : []
    } catch (e) {
      root.storedOrder = []
    }
  }

  FileView {
    id: ignoredFile
    path: Quickshell.env("HOME") + "/.local/state/ruixen/wallpaper-ignored.json"
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onLoaded: root.loadIgnored(text())
    onLoadFailed: root.ignoredNames = []
    onFileChanged: reload()
  }

  function loadIgnored(raw) {
    try {
      var parsed = JSON.parse(String(raw || "").trim() || "{}")
      var ignored = parsed && parsed.ignored
      root.ignoredNames = Array.isArray(ignored) ? ignored.filter(function(n) { return typeof n === "string" }) : []
    } catch (e) {
      root.ignoredNames = []
    }
  }

  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/ruixen"]
  }

  Component.onCompleted: {
    ensureDirProc.running = true
    Qt.callLater(function() { orderFile.reload(); ignoredFile.reload() })
  }

  ExtensionTwoPanel {
    id: panel
    anchors.fill: parent
    detailRatio: 0.6
  }

  ResultsList {
    id: shuffleResultsList
    parent: panel.leftPane
    anchors.fill: parent
    model: root.rows
    fontFamily: root.fontFamily
    mutedColor: root.muted
    textColor: root.textColor
    accentColor: root.accent
    filesMode: true
    selectedIndex: root.selectedIndex
    rowHeightPx: 44
    onRowHovered: (idx) => { if (root.hoverArmed) root.selectedIndex = idx }
    onRowActivated: (idx) => { root.selectedIndex = idx; root.applySelected() }
    onRowActionsRequested: (idx) => { root.selectedIndex = idx; root.openActionsMenu() }

    // Arms hoverArmed on the first REAL pointer movement -- a passive
    // input handler, not a MouseArea, so it observes pointer events
    // over the whole list without stealing anything from each row's
    // own MouseArea beneath it. The first onPointChanged after any
    // reset is captured as a baseline instead of treated as movement,
    // so a content-shift-under-a-still-cursor (this list scrolling
    // itself under the keyboard above) is never mistaken for the
    // user's hand actually moving. Same pattern ClipboardContent.qml's
    // own HoverHandler already uses.
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

  ResultActionsMenu {
    parent: root
    x: root.actionsMenuX
    y: root.actionsMenuY
    visible: root.actionsMenuOpen
    actions: root.shuffleActions
    selectedIndex: root.actionsSelectedIndex
    textColor: root.textColor
    accentColor: root.accent
    glassTint: root.glassTint
    glassBorder: root.glassBorder
    fontFamily: root.fontFamily
    menuWidth: shuffleResultsList.width - 12
    onActionHovered: (idx) => root.actionsSelectedIndex = idx
    onActionActivated: (id) => root.runAction(id)
  }

  WallpaperQueueDetailsPanel {
    parent: panel.rightPane
    anchors.fill: parent
    row: root.selectedRow
    currentBackground: root.currentBackground
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
  }
}
