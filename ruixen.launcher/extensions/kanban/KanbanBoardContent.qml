import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "KanbanModel.js" as KanbanModel

// Kanban board as a launcher extension -- direct ask: "maybe the
// launcher can have an extension page to show all task similar to
// bjaneo collection and then we can tab to move task around etc."
// Same two-panel shape ThemeBrowserContent.qml/ClipboardContent.qml
// already use: left list (sectioned by column, same ResultsList
// section.property grouping every other extension's own sections
// use), right pane read-only detail (KanbanBoardDetailsPanel.qml).
//
// Reads a local copy of the board (FileView on the SAME
// kanban-store.json the notch's own KanbanService.qml writes,
// KanbanModel.js duplicated byte-for-byte -- see that file's own
// header) purely for instant, live-updating display. Every actual
// mutation goes through the real `omarchy-shell ruixen.notch kanban*`
// IPC calls into the notch's live instance instead -- see
// KanbanModel.js's own header for why a second independent writer
// here would risk a clobber (KanbanService.qml's own FileView has
// watchChanges off). State lags up to the notch's own ~400ms debounced
// save after any write here, same documented lag docs/AGENT.md's own
// gotcha 5 already covers for every other kanban* caller.
//
// Add/edit, combined: direct follow-up ("not sure how i would combine
// add/edit task here... two panel then on tab edit the right panel
// changes to input style or edit style?") -- deliberately NOT a
// right-panel edit mode (no precedent for that anywhere in this
// plugin). Typing in the launcher's own search box IS the add form:
// Enter with nothing matching creates a card in Todo with that title.
// Editing goes through Tab's actions menu instead -- Advance/Regress,
// Cycle Priority, Rename (opens ONE inline field in the details panel,
// not a form, same narrow shape AboutPage.qml's own uninstallConfirmField
// already uses), Delete. Set Label/Set Due Date/Set Description are
// deliberately NOT exposed here yet -- still reachable via the notch's
// own in-panel editor or raw `omarchy-shell ruixen.notch kanbanSetX`,
// kept out of this first pass rather than stacking three more inline-
// input flows on top of Rename.
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

  readonly property string searchPlaceholder: "Search or type a new task title"
  readonly property bool showsEnterHint: true
  readonly property bool interceptsArrowKeys: true
  readonly property bool rightFocused: root.actionsMenuOpen || root.renaming

  // Launcher.qml clears its own query on this -- see onQueryClearRequested
  // at the instantiation site. Needed because searchText here is a
  // one-way binding FROM root.query (same convention every other
  // extension uses), so this extension has no direct way to blank the
  // box itself once a typed title has actually been turned into a card.
  signal queryClearRequested()

  // Same mechanism SettingsContent.qml's own returnFocusRequested
  // already established (see that file's signal and AboutPage.qml's
  // uninstallConfirmField, which hands real Qt focus to itself the
  // same way beginRenameSelected() below does) -- a sub-component that
  // takes real keyboard focus has to hand it back explicitly once it's
  // done, or nothing else in the launcher's own Keys handlers (Tab
  // included) ever fires again, since they live on searchHeader's own
  // input, not on this one. Confirmed live: without this, Tab stopped
  // responding entirely after a rename ended.
  signal returnFocusRequested()

  readonly property string storePath: Quickshell.env("HOME") + "/.local/state/ruixen/kanban-store.json"
  property var rawColumns: KanbanModel.defaultColumns()
  property var rawCards: []

  readonly property var columnLabels: {
    var out = {}
    for (var i = 0; i < root.rawColumns.length; i++) out[root.rawColumns[i].id] = root.rawColumns[i].label
    return out
  }

  readonly property var priorityColor: ({
    "high": "#e05252",
    "medium": root.textColor,
    "low": root.muted
  })

  // One section per column, in fixed Todo/In Progress/Done order,
  // each column's own cardsInColumn() order (priority then age, or a
  // real manual order once reorderColumn has touched it -- see
  // KanbanModel.cardsInColumn's own comment).
  readonly property var allRows: {
    var out = []
    for (var i = 0; i < KanbanModel.COLUMN_IDS.length; i++) {
      var columnId = KanbanModel.COLUMN_IDS[i]
      var cards = KanbanModel.cardsInColumn(root.rawCards, columnId)
      for (var j = 0; j < cards.length; j++) {
        var card = cards[j]
        var bits = [card.priority.charAt(0).toUpperCase() + card.priority.slice(1)]
        if (card.label !== "") bits.push(card.label)
        if (card.dueAt > 0) bits.push((KanbanModel.isOverdue(card, Date.now()) ? "Overdue " : "Due ") + root.formatShortDate(card.dueAt))
        out.push({
          id: "kanban:" + card.id,
          providerId: "kanban-board",
          icon: "",
          iconColor: root.priorityColor[card.priority],
          label: card.title,
          breadcrumb: bits.join(" · "),
          kind: "",
          providerName: "",
          sectionLabel: root.columnLabels[columnId] || columnId,
          score: 0,
          card: card
        })
      }
    }
    return out
  }

  function formatShortDate(epochMs) {
    var d = new Date(epochMs)
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return months[d.getMonth()] + " " + d.getDate()
  }

  readonly property var rows: {
    var q = root.searchText.trim().toLowerCase()
    if (q === "") return root.allRows
    return root.allRows.filter(function(r) { return r.label.toLowerCase().indexOf(q) !== -1 })
  }

  property int selectedIndex: 0
  readonly property var selectedRow: root.rows[root.selectedIndex] || null
  readonly property var selectedCard: root.selectedRow ? root.selectedRow.card : null
  readonly property int scrollOff: 2

  // Same scroll-follow snapback guard every other list in this plugin
  // already needs -- see CliampContent.qml's own header comment for
  // the full "why" (a content shift under a still cursor during
  // keyboard nav otherwise reads as a real hover).
  property bool hoverArmed: false
  property point hoverArmBaseline: Qt.point(-1, -1)

  onSelectedIndexChanged: {
    root.hoverArmed = false
    root.hoverArmBaseline = Qt.point(-1, -1)
    root.actionsMenuOpen = false
    root.renaming = false
    var lastIndex = root.rows.length - 1
    boardResultsList.positionViewAtIndex(Math.min(root.selectedIndex + root.scrollOff, lastIndex), ListView.Contain)
    boardResultsList.positionViewAtIndex(Math.max(root.selectedIndex - root.scrollOff, 0), ListView.Contain)
    boardResultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  onRowsChanged: {
    if (root.selectedIndex >= root.rows.length) root.selectedIndex = Math.max(0, root.rows.length - 1)
  }

  onActiveChanged: {
    if (root.active) {
      root.selectedIndex = 0
      root.hoverArmed = false
      root.hoverArmBaseline = Qt.point(-1, -1)
      Qt.callLater(function() { boardResultsList.positionViewAtBeginning() })
    }
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
      if (root.actionsSelectedIndex < root.boardActions.length - 1) root.actionsSelectedIndex++
      return
    }
    if (root.selectedIndex < root.rows.length - 1) root.selectedIndex++
  }

  // Enter on an existing row advances it -- same meaning the notch
  // panel's own left-click-to-advance already has, not a new gesture
  // invented for this surface. Enter with nothing matching the typed
  // text creates a new card instead (see createCardFromSearch below).
  function activateSelection() {
    if (root.actionsMenuOpen) {
      var action = root.boardActions[root.actionsSelectedIndex]
      if (action) root.runBoardAction(action.id)
      return
    }
    if (root.rows.length === 0 && root.searchText.trim() !== "") {
      root.createCardFromSearch()
      return
    }
    root.advanceSelected()
  }

  function createCardFromSearch() {
    var title = root.searchText.trim()
    if (title === "") return
    addProc.exec(["omarchy-shell", "ruixen.notch", "kanbanAddCard", title, "todo", "medium"])
    root.queryClearRequested()
  }

  function advanceSelected() {
    if (!root.selectedCard) return
    advanceProc.exec(["omarchy-shell", "ruixen.notch", "kanbanAdvanceCard", root.selectedCard.id])
  }

  function regressSelected() {
    if (!root.selectedCard) return
    regressProc.exec(["omarchy-shell", "ruixen.notch", "kanbanRegressCard", root.selectedCard.id])
  }

  // high -> medium -> low -> high, same rank order PRIORITIES itself
  // already defines (highest first).
  function cyclePrioritySelected() {
    if (!root.selectedCard) return
    var idx = KanbanModel.PRIORITIES.indexOf(root.selectedCard.priority)
    var next = KanbanModel.PRIORITIES[(idx + 1) % KanbanModel.PRIORITIES.length]
    priorityProc.exec(["omarchy-shell", "ruixen.notch", "kanbanSetPriority", root.selectedCard.id, next])
  }

  property bool renaming: false
  property string renameText: ""

  function beginRenameSelected() {
    if (!root.selectedCard) return
    root.renameText = root.selectedCard.title
    root.renaming = true
    Qt.callLater(function() { detailsPanel.renameField.forceActiveFocus() })
  }

  function commitRename(text) {
    var title = String(text || "").trim()
    root.renaming = false
    root.returnFocusRequested()
    if (!root.selectedCard || title === "") return
    renameProc.exec(["omarchy-shell", "ruixen.notch", "kanbanRenameCard", root.selectedCard.id, title])
  }

  function cancelRename() {
    root.renaming = false
    root.returnFocusRequested()
  }

  // Two-step: first press arms it (the details panel label below would
  // relabel to "Confirm" the same way Clipboard's own delete already
  // does), second press on that SAME card removes it. Moving the
  // selection disarms -- see onSelectedIndexChanged above.
  property string deleteArmedId: ""
  readonly property bool deleteArmed: root.selectedCard !== null && root.deleteArmedId === root.selectedCard.id

  function deleteSelected() {
    if (!root.selectedCard) return
    if (root.deleteArmedId !== root.selectedCard.id) {
      root.deleteArmedId = root.selectedCard.id
      return
    }
    root.deleteArmedId = ""
    deleteProc.exec(["omarchy-shell", "ruixen.notch", "kanbanRemoveCard", root.selectedCard.id])
  }

  property bool actionsMenuOpen: false
  property int actionsSelectedIndex: 0
  property real actionsMenuX: 0
  property real actionsMenuY: 0

  readonly property var boardActions: root.selectedCard ? (function() {
    var out = []
    if (root.selectedCard.column !== "done") out.push({ id: "advance", label: "Advance" })
    if (root.selectedCard.column !== "todo") out.push({ id: "regress", label: "Regress" })
    var idx = KanbanModel.PRIORITIES.indexOf(root.selectedCard.priority)
    var next = KanbanModel.PRIORITIES[(idx + 1) % KanbanModel.PRIORITIES.length]
    out.push({ id: "priority", label: "Priority -> " + (next.charAt(0).toUpperCase() + next.slice(1)) })
    out.push({ id: "rename", label: "Rename" })
    out.push({ id: "delete", label: root.deleteArmed ? "Confirm Delete" : "Delete" })
    return out
  })() : []

  function runBoardAction(id) {
    if (id === "advance") root.advanceSelected()
    else if (id === "regress") root.regressSelected()
    else if (id === "priority") root.cyclePrioritySelected()
    else if (id === "rename") { root.beginRenameSelected(); root.closeActionsMenu(); return }
    else if (id === "delete") root.deleteSelected()
    if (!(id === "delete" && root.deleteArmed)) root.closeActionsMenu()
  }

  function focusRightPanel() {
    if (root.actionsMenuOpen) { root.closeActionsMenu(); return }
    root.openActionsMenu()
  }

  function blurToLeftPanel() {
    if (root.renaming) { root.cancelRename(); return }
    root.closeActionsMenu()
  }

  function openActionsMenu() {
    if (root.boardActions.length === 0) return
    root.actionsSelectedIndex = 0
    root.actionsMenuOpen = true
    root.positionActionsMenuNearSelection()
  }

  function closeActionsMenu() {
    root.actionsMenuOpen = false
  }

  function positionActionsMenuNearSelection() {
    var item = boardResultsList.itemAtIndex(root.selectedIndex)
    if (!item) return
    var scenePos = item.mapToItem(null, 0, item.height)
    var localPos = root.mapFromItem(null, scenePos.x, scenePos.y)
    var menuHeight = root.boardActions.length * 34 + 8
    root.actionsMenuX = Math.max(8, Math.min(localPos.x + 6, root.width - boardResultsList.width - 8))
    root.actionsMenuY = Math.max(8, Math.min(localPos.y + 4, root.height - menuHeight - 8))
  }

  function loadStore(raw) {
    var keepId = root.active && root.selectedCard ? root.selectedCard.id : ""
    try {
      var parsed = JSON.parse(String(raw || "").trim() || "{}")
      root.rawColumns = KanbanModel.normalizeColumns(parsed.columns)
      root.rawCards = KanbanModel.normalizeCards(parsed.cards)
    } catch (e) {
      root.rawColumns = KanbanModel.defaultColumns()
      root.rawCards = []
    }
    if (keepId !== "") {
      for (var i = 0; i < root.rows.length; i++) {
        if (root.rows[i].card.id === keepId) { root.selectedIndex = i; break }
      }
    }
  }

  FileView {
    id: storeFile
    path: root.storePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadStore(text())
    onLoadFailed: root.loadStore("")
  }

  Process { id: addProc }
  Process { id: advanceProc }
  Process { id: regressProc }
  Process { id: priorityProc }
  Process { id: renameProc }
  Process { id: deleteProc }

  Item {
    id: filterChipsRow
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 0
  }

  ExtensionTwoPanel {
    id: panel
    anchors.top: filterChipsRow.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
    detailRatio: 0.6
  }

  ResultsList {
    id: boardResultsList
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
    onRowHovered: (idx) => { if (root.hoverArmed) root.selectedIndex = idx }
    onRowActivated: (idx) => { root.selectedIndex = idx; root.advanceSelected() }
    onRowActionsRequested: (idx) => {
      root.selectedIndex = idx
      root.openActionsMenu()
    }

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
    width: parent.width - 16
    visible: root.rows.length === 0
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    text: root.searchText.trim() !== ""
      ? "No match -- press Enter to add “" + root.searchText.trim() + "” to Todo"
      : "No tasks yet -- type a title and press Enter"
    font.family: root.fontFamily
    font.pixelSize: 11
    color: root.muted
  }

  ResultActionsMenu {
    parent: root
    x: root.actionsMenuX
    y: root.actionsMenuY
    visible: root.actionsMenuOpen
    actions: root.boardActions
    selectedIndex: root.actionsSelectedIndex
    textColor: root.textColor
    accentColor: root.accent
    glassTint: root.glassTint
    glassBorder: root.glassBorder
    fontFamily: root.fontFamily
    menuWidth: boardResultsList.width - 12
    onActionHovered: (idx) => root.actionsSelectedIndex = idx
    onActionActivated: (id) => root.runBoardAction(id)
  }

  KanbanBoardDetailsPanel {
    id: detailsPanel
    parent: panel.rightPane
    anchors.fill: parent
    row: root.selectedRow
    columnLabel: root.selectedCard ? (root.columnLabels[root.selectedCard.column] || root.selectedCard.column) : ""
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    renaming: root.renaming
    renameText: root.renameText
    onRenameTextChanged: root.renameText = renameText
    onRenameCommitted: (text) => root.commitRename(text)
    onRenameCancelled: root.cancelRename()
  }
}
