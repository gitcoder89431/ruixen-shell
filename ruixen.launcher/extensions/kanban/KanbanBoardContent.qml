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
// Direct follow-up once that shipped ("whats a way to set priority or
// description" without a second input row -- "i dont like adding rows
// cause it makes it jumpy"): a trailing !h/!m/!l word sets priority
// (medium if omitted, same default as before), and "--" splits off
// everything after it as the description -- see parseCardInput below.
// Editing goes through Tab's actions menu instead -- Advance/Regress,
// Cycle Priority, Rename and Edit/Add Description (each opens ONE
// inline field in the details panel, not a form, same narrow shape
// AboutPage.qml's own uninstallConfirmField already uses), Delete. Set
// Label/Set Due Date are still deliberately NOT exposed here -- still
// reachable via the notch's own in-panel editor or raw
// `omarchy-shell ruixen.notch kanbanSetX`, kept out rather than
// stacking two more inline-input flows on top of Rename/Description.
//
// Description gets its own expanded block under the title (direct
// follow-up: "a more expanded detail mode... can this show up under
// the task title?") rather than living in the generic metadata zebra
// list with everything else -- word-wrapped there since this panel has
// the room, unlike the notch's own compact card (KanbanContent.qml
// keeps it a single always-elided line on purpose, "a card here is a
// glance surface").
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
  readonly property bool rightFocused: root.actionsMenuOpen || root.renaming || root.editingDescription

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

  // Same red/yellow/muted the notch's own Kanban panel already uses for
  // its priority dot (KanbanContent.qml's dangerColor/warningColor/
  // muted) -- reused here verbatim rather than inventing a second
  // mapping for the same three priorities.
  readonly property var priorityColor: ({
    "high": "#e05252",
    "medium": "#e8c34a",
    "low": root.muted
  })

  // Column/Priority filter chips -- direct ask ("filter by To do Done
  // etc"), same plain cycle-on-click-through-"All" shape ThemeBrowserContent
  // .qml's own Collection/Style chips already established (right-click
  // resets straight to "All"). Deliberately no separate sort chip:
  // cardsInColumn() already sorts by explicit order, then priority,
  // then age -- that ordering IS the point of the agent-reorganize
  // feature (docs/AGENT.md), so a second manual sort toggle here would
  // just compete with it over which one wins.
  property string columnFilter: ""
  function cycleColumnFilter() {
    var ids = [""].concat(KanbanModel.COLUMN_IDS)
    var idx = ids.indexOf(root.columnFilter)
    root.columnFilter = ids[(idx + 1) % ids.length]
  }
  function resetColumnFilter() { root.columnFilter = "" }
  readonly property string columnFilterLabel: root.columnFilter === "" ? "All" : (root.columnLabels[root.columnFilter] || root.columnFilter)

  property string priorityFilter: ""
  function cyclePriorityFilter() {
    var ids = [""].concat(KanbanModel.PRIORITIES)
    var idx = ids.indexOf(root.priorityFilter)
    root.priorityFilter = ids[(idx + 1) % ids.length]
  }
  function resetPriorityFilter() { root.priorityFilter = "" }
  readonly property string priorityFilterLabel: root.priorityFilter === "" ? "All" : (root.priorityFilter.charAt(0).toUpperCase() + root.priorityFilter.slice(1))

  // One section per column, in fixed Todo/In Progress/Done order
  // (skipping any column columnFilter has narrowed out entirely), each
  // column's own cardsInColumn() order (priority then age, or a real
  // manual order once reorderColumn has touched it -- see
  // KanbanModel.cardsInColumn's own comment).
  readonly property var allRows: {
    var out = []
    for (var i = 0; i < KanbanModel.COLUMN_IDS.length; i++) {
      var columnId = KanbanModel.COLUMN_IDS[i]
      if (root.columnFilter !== "" && columnId !== root.columnFilter) continue
      var cards = KanbanModel.cardsInColumn(root.rawCards, columnId)
      if (root.priorityFilter !== "") cards = cards.filter(function(c) { return c.priority === root.priorityFilter })
      for (var j = 0; j < cards.length; j++) {
        var card = cards[j]
        var bits = [card.priority.charAt(0).toUpperCase() + card.priority.slice(1)]
        if (card.label !== "") bits.push(card.label)
        if (card.dueAt > 0) bits.push((KanbanModel.isOverdue(card, Date.now()) ? "Overdue " : "Due ") + root.formatShortDate(card.dueAt))
        // Solid dot tinted by priority, swapped for a checkmark once a
        // card reaches Done -- same shape the notch's own priority dot
        // already uses (KanbanContent.qml: a colored dot, replaced by
        // "✓" in the done column, "the dots with the check on done").
        out.push({
          id: "kanban:" + card.id,
          providerId: "kanban-board",
          icon: columnId === "done" ? "" : "",
          iconColor: columnId === "done" ? root.accent : root.priorityColor[card.priority],
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
    root.editingDescription = false
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

  // "--" (if present) splits off everything after it as the
  // description, verbatim. Priority is read from the LAST word of
  // whatever's left before that -- "!h"/"!m"/"!l" only, case-
  // insensitive, trailing on purpose so it reads as a tag stuck on the
  // end of a normal title rather than a word that could appear mid-
  // sentence. Anything else in that position is left alone as part of
  // the real title; unrecognized or absent, priority is "medium" (the
  // same default as before this existed).
  function parseCardInput(raw) {
    var text = String(raw || "").trim()
    var description = ""
    var dashIndex = text.indexOf("--")
    if (dashIndex !== -1) {
      description = text.slice(dashIndex + 2).trim()
      text = text.slice(0, dashIndex).trim()
    }
    var priority = "medium"
    var tagWords = { "!h": "high", "!m": "medium", "!l": "low" }
    var lastSpace = text.lastIndexOf(" ")
    var lastWord = (lastSpace === -1 ? text : text.slice(lastSpace + 1)).toLowerCase()
    if (tagWords[lastWord] !== undefined) {
      priority = tagWords[lastWord]
      text = (lastSpace === -1 ? "" : text.slice(0, lastSpace)).trim()
    }
    return { title: text, priority: priority, description: description }
  }

  readonly property var parsedSearchInput: root.parseCardInput(root.searchText)

  // The description can't ride along in the same addProc call --
  // kanbanAddCard's own IPC signature has no description param, same
  // as the notch panel's own in-panel add row (KanbanContent.qml),
  // which also fires a separate kanbanSetDescription after addCard
  // returns the new id. addProc's own StdioCollector below plays that
  // same id back out so this can do the same second call.
  property string pendingDescription: ""

  function createCardFromSearch() {
    var parsed = root.parseCardInput(root.searchText)
    if (parsed.title === "") return
    root.pendingDescription = parsed.description
    addProc.exec(["omarchy-shell", "ruixen.notch", "kanbanAddCard", parsed.title, "todo", parsed.priority])
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

  property bool editingDescription: false
  property string descriptionText: ""

  function beginEditDescriptionSelected() {
    if (!root.selectedCard) return
    root.descriptionText = root.selectedCard.description
    root.editingDescription = true
    Qt.callLater(function() { detailsPanel.descriptionField.forceActiveFocus() })
  }

  // Unlike commitRename, an empty result is NOT treated as "cancelled"
  // -- "" is the real, documented way to clear a description
  // (docs/CONTROL.md: 'kanbanSetDescription <id> ""   # clears it'), so
  // this always calls through, even on an empty string.
  function commitDescription(text) {
    var description = String(text || "").trim()
    root.editingDescription = false
    root.returnFocusRequested()
    if (!root.selectedCard) return
    descriptionProc.exec(["omarchy-shell", "ruixen.notch", "kanbanSetDescription", root.selectedCard.id, description])
  }

  function cancelDescription() {
    root.editingDescription = false
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
    out.push({ id: "description", label: root.selectedCard.description !== "" ? "Edit Description" : "Add Description" })
    out.push({ id: "delete", label: root.deleteArmed ? "Confirm Delete" : "Delete" })
    return out
  })() : []

  function runBoardAction(id) {
    if (id === "advance") root.advanceSelected()
    else if (id === "regress") root.regressSelected()
    else if (id === "priority") root.cyclePrioritySelected()
    else if (id === "rename") { root.beginRenameSelected(); root.closeActionsMenu(); return }
    else if (id === "description") { root.beginEditDescriptionSelected(); root.closeActionsMenu(); return }
    else if (id === "delete") root.deleteSelected()
    if (!(id === "delete" && root.deleteArmed)) root.closeActionsMenu()
  }

  function focusRightPanel() {
    if (root.actionsMenuOpen) { root.closeActionsMenu(); return }
    root.openActionsMenu()
  }

  function blurToLeftPanel() {
    if (root.renaming) { root.cancelRename(); return }
    if (root.editingDescription) { root.cancelDescription(); return }
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
    // filterChipsRow.height, not a bare 8 -- same clamp shape
    // ClipboardContent.qml's own positionActionsMenuNearSelection
    // already uses for its own chip row, kept as a stale bare 8 here
    // from before the chips existed. Never actually reachable with
    // today's row/section heights (every real row sits well below 32px
    // regardless), but matches the established pattern and guards
    // against it mattering if that ever changes.
    root.actionsMenuY = Math.max(filterChipsRow.height + 8, Math.min(localPos.y + 4, root.height - menuHeight - 8))
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

  Process {
    id: addProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var cardId = text.trim()
        if (cardId !== "" && root.pendingDescription !== "")
          descriptionProc.exec(["omarchy-shell", "ruixen.notch", "kanbanSetDescription", cardId, root.pendingDescription])
        root.pendingDescription = ""
      }
    }
  }
  Process { id: advanceProc }
  Process { id: regressProc }
  Process { id: priorityProc }
  Process { id: renameProc }
  Process { id: descriptionProc }
  Process { id: deleteProc }

  // Visually matches ThemeBrowserContent.qml's own filterChipsRow (same
  // 24px pill buttons, same spacing/radius/tint) -- see that file's own
  // header comment for why this is built fresh per extension rather
  // than shared: each one's filter set is genuinely its own shape.
  Item {
    id: filterChipsRow
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 32

    Row {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6

      Rectangle {
        id: columnChip
        width: Math.max(96, columnChipLabel.implicitWidth + 20)
        height: 24
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Text {
          id: columnChipLabel
          anchors.centerIn: parent
          text: "Column: " + root.columnFilterLabel
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 11
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) root.resetColumnFilter()
            else root.cycleColumnFilter()
          }
        }
      }

      Rectangle {
        id: priorityChip
        width: Math.max(88, priorityChipLabel.implicitWidth + 20)
        height: 24
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Text {
          id: priorityChipLabel
          anchors.centerIn: parent
          text: "Priority: " + root.priorityFilterLabel
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 11
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) root.resetPriorityFilter()
            else root.cyclePriorityFilter()
          }
        }
      }
    }
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
    // !root.rightFocused -- confirmed live: opening the actions menu
    // via Tab leaves the real mouse cursor wherever it already was, so
    // the very next mouse movement toward the menu itself necessarily
    // sweeps across other list rows first. Each one's own hover used to
    // reselect (onSelectedIndexChanged closes the menu on any selection
    // change), so the menu would close itself mid-transit, before the
    // click ever reached it -- "I can't click Edit, the tab action
    // doesn't register." Same gap exists in every sibling extension
    // (Clipboard/Cliamp/Theme Browser/Wallpaper Shuffle all share this
    // exact onRowHovered shape with no actionsMenuOpen guard), not
    // something only this extension does -- fixed here first since
    // this is what surfaced it.
    onRowHovered: (idx) => { if (root.hoverArmed && !root.rightFocused) root.selectedIndex = idx }
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
      ? (root.parsedSearchInput.title !== ""
          ? "Press Enter to add “" + root.parsedSearchInput.title + "” to Todo"
            + (root.parsedSearchInput.priority !== "medium" ? " (" + root.parsedSearchInput.priority + ")" : "")
            + (root.parsedSearchInput.description !== "" ? " + description" : "")
          : "Type a title, then press Enter")
      : "No tasks yet -- type a title and press Enter\n(end with !h/!m/!l for priority, -- for a description)"
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
    editingDescription: root.editingDescription
    descriptionText: root.descriptionText
    onDescriptionTextChanged: root.descriptionText = descriptionText
    onDescriptionCommitted: (text) => root.commitDescription(text)
    onDescriptionCancelled: root.cancelDescription()
  }
}
