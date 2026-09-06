import QtQuick
import Quickshell
import Quickshell.Io
import "KanbanModel.js" as KanbanModel

// Backing store for the notch's own Kanban tab (4th dashboard tab,
// KanbanContent.qml) -- same FileView/debounced-save shape as
// NotificationService.qml's own persistence, see its header comment
// for the pattern this copies.
//
// Every mutation here is also a real IpcHandler function on
// Overlay.qml's own "ruixen.notch" target (addCard/moveCard/
// removeCard/renameColumn/listCards), so the board can be driven
// entirely from the CLI -- `omarchy-shell ruixen.notch kanbanAddCard
// "Fix bug" todo` -- the same mechanism already proven for
// setDoNotDisturb/debugOpenDashboard elsewhere in this plugin. Direct
// request: "i feel like its easier if you just set it up agent
// native... id tell you to manage and update it" -- this is the
// primary intended way to use the board, not a bonus feature bolted
// onto a mouse-driven one.
Item {
  id: service

  readonly property string home: Quickshell.env("HOME")
  // Flat under ~/.local/state/ruixen/, matching every other piece of
  // state this plugin already keeps there.
  readonly property string storePath: home + "/.local/state/ruixen/kanban-store.json"

  property var columns: KanbanModel.defaultColumns()
  property var cards: []
  property bool storeLoaded: false

  function cardsInColumn(columnId) {
    return KanbanModel.cardsInColumn(service.cards, columnId)
  }

  function cardFor(cardId) {
    var k = String(cardId || "")
    for (var i = 0; i < service.cards.length; i++)
      if (service.cards[i].id === k) return service.cards[i]
    return null
  }

  // Returns the new card's id (empty string on a blank title) --
  // useful for a caller that wants to immediately move/remove the
  // card it just created without a separate lookup. priority defaults
  // to "medium" when omitted/invalid (see KanbanModel.normalizePriority).
  function addCard(title, columnId, priority) {
    var entry = KanbanModel.entryFromInput(title, columnId, priority, Date.now())
    if (!entry) return ""
    service.cards = KanbanModel.addCard(service.cards, entry)
    scheduleSave()
    return entry.id
  }

  function setPriority(cardId, priority) {
    service.cards = KanbanModel.setPriority(service.cards, cardId, priority)
    scheduleSave()
  }

  function moveCard(cardId, columnId) {
    service.cards = KanbanModel.moveCard(service.cards, cardId, columnId)
    scheduleSave()
  }

  // The manual per-card arrow -- advances/regresses one column,
  // clamped at either end (see KanbanModel's own nextColumnId/
  // prevColumnId comment).
  function advanceCard(cardId) {
    var entry = service.cardFor(cardId)
    if (entry) service.moveCard(cardId, KanbanModel.nextColumnId(entry.column))
  }

  function regressCard(cardId) {
    var entry = service.cardFor(cardId)
    if (entry) service.moveCard(cardId, KanbanModel.prevColumnId(entry.column))
  }

  function removeCard(cardId) {
    service.cards = KanbanModel.removeCard(service.cards, cardId)
    scheduleSave()
  }

  function renameColumn(columnId, label) {
    service.columns = KanbanModel.renameColumn(service.columns, columnId, label)
    scheduleSave()
  }

  // Agent/CLI introspection -- `omarchy-shell ruixen.notch
  // kanbanListCards` returns this directly, so the board can be read
  // back without any QML access at all.
  function listCards() {
    return JSON.stringify({ columns: service.columns, cards: service.cards })
  }

  // ------------------------------------------------------------- persistence

  Timer {
    id: saveTimer
    interval: 400
    repeat: false
    onTriggered: service.flushStore()
  }

  function scheduleSave() {
    if (service.storeLoaded) saveTimer.restart()
  }

  FileView {
    id: storeFile
    path: service.storePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadStore(text())
    // First run: the file does not exist yet. Without this branch the
    // store never counts as loaded, every save stays a no-op.
    onLoadFailed: service.loadStore("")
  }

  function loadStore(raw) {
    if (service.storeLoaded) return
    try {
      var parsed = JSON.parse(String(raw || "").trim() || "{}")
      service.columns = KanbanModel.normalizeColumns(parsed.columns)
      service.cards = KanbanModel.normalizeCards(parsed.cards)
    } catch (e) {
      console.warn("ruixen.notch: kanban store parse failed:", e)
      service.columns = KanbanModel.defaultColumns()
      service.cards = []
    }
    service.storeLoaded = true
  }

  function flushStore() {
    storeFile.setText(JSON.stringify({
      version: 1,
      columns: service.columns,
      cards: service.cards
    }) + "\n")
  }

  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", service.home + "/.local/state/ruixen"]
    running: false
  }

  Component.onCompleted: {
    ensureDirProc.running = true
    // Give mkdir a tick before the read; FileView reports a missing
    // file through onLoadFailed, which loadStore already handles.
    Qt.callLater(function() { storeFile.reload() })
  }
}
