import QtQuick
import Quickshell
import Quickshell.Io
import "ShelfModel.js" as ShelfModel

// Backing store for the Shelf window (ShelfContent.qml, hosted by
// Shelf.qml) -- same FileView/debounced-save shape as the notch's
// KanbanService.qml, see its header for the pattern this copies.
//
// This service is the ONLY writer of shelf.json: the panel's drops and
// buttons call these functions directly, and agents/scripts reach the
// same ones through the IpcHandler on Shelf.qml's "ruixen.shelf" target
// (`omarchy-shell ruixen.shelf add /abs/path`). ruixen.notch's
// quick-drop relays through that same IPC target too. One writer means
// no file-locking story and no lost updates between the GUI and the CLI.
//
// The shelf holds absolute-path references, never copies (see
// ShelfModel.js). Whether each path still exists comes from a bounded,
// async `stat` pass (never on the UI thread), cached per path.
Item {
  id: service

  readonly property string home: Quickshell.env("HOME")
  readonly property string storePath: home + "/.local/state/ruixen/shelf.json"

  property var items: []
  property bool storeLoaded: false

  // path -> { kind, size, mtime } for paths the last stat pass could
  // read; checked: path -> true for every path a completed pass covered
  // (so "checked but not in stats" means missing, "not checked" means
  // unknown). Bumped as a whole so QML bindings re-evaluate.
  property var stats: ({})
  property var checked: ({})

  // ---------------------------------------------------------------- mutations

  // paths: array of absolute paths / file URLs. source: "user" | "agent".
  // Returns { added: [ids], rejected: n } (rejected = not an acceptable
  // local absolute path).
  function addPaths(paths, source) {
    var result = ShelfModel.addPaths(service.items, paths, source, Date.now(), service.home)
    if (result.added.length > 0) {
      service.items = result.items
      scheduleSave()
      service.refreshStats()
    }
    return { added: result.added, rejected: result.rejected }
  }

  function removeItem(idOrPath) {
    var next = ShelfModel.removeItem(service.items, idOrPath, service.home)
    if (next.length === service.items.length) return false
    service.items = next
    scheduleSave()
    return true
  }

  function clear() {
    if (service.items.length === 0) return
    service.items = ShelfModel.clearItems()
    scheduleSave()
  }

  // Agent/CLI introspection -- `omarchy-shell ruixen.shelf list`
  // returns this directly, so what's on the shelf can be read back with
  // no QML access at all. Each entry carries path/name/source/kind/size
  // and `exists` (true/false, or null while a path hasn't been checked
  // yet).
  function listItems() {
    return JSON.stringify({
      items: ShelfModel.listEntries(service.items, service.stats, service.checked)
    })
  }

  // ------------------------------------------------------------ existence/stat

  // One worker at a time (AGENTS.md §5): a request that arrives while
  // it's running just marks it dirty, and a rerun starts only after the
  // real exit is observed. Results merge by path, so a late result can
  // never overwrite something newer, and paths no longer on the shelf
  // are ignored.
  property bool statDirty: false

  function refreshStats() {
    if (statProc.running) {
      service.statDirty = true
      return
    }
    var paths = service.items.map(function(it) { return it.path })
    if (paths.length === 0) return
    statProc.requestedPaths = paths
    statProc.exec(["stat", "-L", "--printf=%n\\t%F\\t%s\\t%Y\\n", "--"].concat(paths))
  }

  Process {
    id: statProc
    property var requestedPaths: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parsed = ShelfModel.parseStatOutput(text)
        var nextStats = {}
        var nextChecked = {}
        var onShelf = {}
        for (var i = 0; i < service.items.length; i++) onShelf[service.items[i].path] = true
        // Carry over still-relevant earlier results, then apply this pass.
        for (var p in service.stats) if (onShelf[p]) nextStats[p] = service.stats[p]
        for (var q in service.checked) if (onShelf[q]) nextChecked[q] = true
        for (var j = 0; j < statProc.requestedPaths.length; j++) {
          var path = statProc.requestedPaths[j]
          if (!onShelf[path]) continue
          nextChecked[path] = true
          if (parsed[path]) nextStats[path] = parsed[path]
          else delete nextStats[path]
        }
        service.stats = nextStats
        service.checked = nextChecked
      }
    }
    onRunningChanged: {
      if (!running && service.statDirty) {
        service.statDirty = false
        service.refreshStats()
      }
    }
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
      service.items = ShelfModel.normalizeItems(parsed.items, service.home)
    } catch (e) {
      console.warn("ruixen.notch: shelf store parse failed:", e)
      service.items = []
    }
    service.storeLoaded = true
    service.refreshStats()
  }

  function flushStore() {
    storeFile.setText(JSON.stringify({
      version: 1,
      items: service.items
    }) + "\n")
  }

  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", service.home + "/.local/state/ruixen"]
    running: false
  }

  Component.onCompleted: {
    ensureDirProc.running = true
    Qt.callLater(function() { storeFile.reload() })
  }
}
