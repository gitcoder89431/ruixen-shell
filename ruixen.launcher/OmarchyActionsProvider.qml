import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "OmarchyMenuParser.js" as OmarchyMenuParser

// Provider: every directly-executable Omarchy menu action, searchable
// by label/alias, filtered by its own real "when" visibility guard.
// Reads /usr/share/omarchy/default/omarchy/omarchy-menu.jsonc directly
// -- a real, stable, DOCUMENTED Omarchy config file, not an internal
// implementation detail (see OmarchyMenuParser.js's own header for why
// that distinction matters and what is deliberately NOT imported).
Item {
  id: root

  readonly property string providerName: "Omarchy Actions"
  property bool ready: false

  readonly property string menuPath: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/default/omarchy/omarchy-menu.jsonc"

  // Full flat {id: entry} map (every entry, actionable or not -- needed
  // so categoryFor() can look up a pure-category parent's own label).
  property var allEntries: ({})
  // Subset of allEntries with a real "action" string -- what search()
  // actually offers as results.
  property var actionable: ({})
  // {id: {when, checked}} -- see OmarchyMenuParser.parseGuardOutput.
  property var guardResults: ({})

  // FileView can fire onLoaded more than once during startup -- the
  // implicit preload when `path` resolves, plus the explicit
  // menuFile.reload() in Component.onCompleted, can both end up calling
  // here (same double-fire already documented in
  // ruixen.notch/NotificationService.qml's own loadStore()). Without
  // this guard the jsonc gets re-parsed and the guard script re-run
  // twice on every startup.
  property bool loaded: false

  // Ruixen Settings has no manifest kind "menu" entry of its own, and
  // Super+R no longer opens it directly once this plugin owns that key
  // -- one synthetic row here keeps it reachable from the palette too,
  // same real toggle command its own keybind already used. Not a third
  // provider, just one more entry alongside the real Omarchy ones.
  readonly property var syntheticEntries: ({
    "ruixen.settings": {
      icon: "",
      label: "Ruixen Settings",
      aliases: ["settings", "preferences"],
      action: "omarchy-shell shell toggle ruixen.settings"
    }
  })

  function search(query) {
    var q = String(query || "").trim()
    if (!q) return []
    var out = []
    for (var id in root.actionable) {
      var entry = root.actionable[id]
      if (!OmarchyMenuParser.isVisible(id, entry, root.guardResults)) continue
      var score = OmarchyMenuParser.scoreEntry(entry, q)
      if (score < 0) continue
      out.push({
        id: "omarchy:" + id,
        providerId: "omarchy-actions",
        icon: entry.icon || "",
        label: entry.label || id,
        category: OmarchyMenuParser.categoryFor(root.allEntries, id),
        providerName: root.providerName,
        score: score,
        action: { type: "shell", command: entry.action }
      })
    }
    for (var sid in root.syntheticEntries) {
      var sentry = root.syntheticEntries[sid]
      var sscore = OmarchyMenuParser.scoreEntry(sentry, q)
      if (sscore < 0) continue
      out.push({
        id: "omarchy:" + sid,
        providerId: "omarchy-actions",
        icon: sentry.icon,
        label: sentry.label,
        category: "Ruixen",
        providerName: root.providerName,
        score: sscore,
        action: { type: "shell", command: sentry.action }
      })
    }
    return out
  }

  function activate(result) {
    Util.execDetached(result.action.command)
  }

  FileView {
    id: menuFile
    path: root.menuPath
    watchChanges: false
    printErrors: false
    onLoaded: {
      if (root.loaded) return
      root.loaded = true
      root.allEntries = OmarchyMenuParser.parseMenuEntries(text())
      root.actionable = OmarchyMenuParser.actionableEntries(root.allEntries)
      var script = OmarchyMenuParser.buildGuardScript(root.actionable)
      if (script.length === 0) {
        root.ready = true
        return
      }
      guardProc.command = ["bash", "-c", script]
      guardProc.running = true
    }
    onLoadFailed: root.ready = true
  }

  Process {
    id: guardProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.guardResults = OmarchyMenuParser.parseGuardOutput(text)
        root.ready = true
      }
    }
  }

  Component.onCompleted: menuFile.reload()
}
