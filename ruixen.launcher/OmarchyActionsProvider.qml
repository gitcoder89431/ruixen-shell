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
  // so rootLabelFor() can look up a top-level root's own label).
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
      domain: "Ruixen",
      kind: "Command",
      aliases: ["settings", "preferences"],
      action: "omarchy-shell shell toggle ruixen.settings"
    }
  })

  // A handful of real, always-visible entries picked as the launcher's
  // empty-query "Suggestions" -- deliberately small and hand-picked
  // rather than "most frequently used" (no usage tracking exists), so
  // the palette isn't blank the instant it opens. synthetic entries are
  // referenced by their syntheticEntries key, real ones by their real
  // omarchy-menu.jsonc id.
  readonly property var suggestedIds: [
    "ruixen.settings",
    "trigger.capture.screenshot",
    "system.lock",
    "style.theme",
    "style.background"
  ]

  // domain/kind are the launcher's per-row right-side tag (e.g. "Omarchy
  // · Install", "Ruixen · Command") -- domain defaults to "Omarchy" for
  // every real menu entry (syntheticEntries override it, e.g. "Ruixen"),
  // kind is the entry's own top-level root label via rootLabelFor()
  // unless the entry supplies its own (again, syntheticEntries only --
  // "Command" has no real omarchy-menu.jsonc root of its own).
  function resultFor(id, entry, score) {
    return {
      id: "omarchy:" + id,
      providerId: "omarchy-actions",
      icon: entry.icon || "",
      label: entry.label || id,
      domain: entry.domain || "Omarchy",
      kind: entry.kind || OmarchyMenuParser.rootLabelFor(root.allEntries, id),
      providerName: root.providerName,
      score: score,
      action: { type: "shell", command: entry.action }
    }
  }

  function search(query) {
    var q = String(query || "").trim()
    if (!q) return []
    var out = []
    for (var id in root.actionable) {
      var entry = root.actionable[id]
      if (!OmarchyMenuParser.isVisible(id, entry, root.guardResults)) continue
      var score = OmarchyMenuParser.scoreEntry(entry, q)
      if (score < 0) continue
      out.push(root.resultFor(id, entry, score))
    }
    for (var sid in root.syntheticEntries) {
      var sentry = root.syntheticEntries[sid]
      var sscore = OmarchyMenuParser.scoreEntry(sentry, q)
      if (sscore < 0) continue
      out.push(root.resultFor(sid, sentry, sscore))
    }
    return out
  }

  function suggestions() {
    var out = []
    for (var i = 0; i < root.suggestedIds.length; i++) {
      var id = root.suggestedIds[i]
      var entry = root.syntheticEntries[id] || root.actionable[id]
      if (!entry) continue
      if (!OmarchyMenuParser.isVisible(id, entry, root.guardResults)) continue
      out.push(root.resultFor(id, entry, 0))
    }
    return out
  }

  // The rest of the empty-query tray, below Suggestions -- every other
  // actionable entry (real ones only, no synthetic rows), alphabetical
  // by label since there's no query to score against. excludeIds keeps
  // whatever's already shown in Suggestions from appearing twice;
  // limit keeps this to whatever room is left in the fixed-height tray
  // (see Launcher.qml's own sections property).
  function browse(excludeIds, limit) {
    var exclude = {}
    for (var i = 0; i < excludeIds.length; i++) exclude[excludeIds[i]] = true
    var out = []
    for (var id in root.actionable) {
      if (exclude[id]) continue
      var entry = root.actionable[id]
      if (!OmarchyMenuParser.isVisible(id, entry, root.guardResults)) continue
      out.push(root.resultFor(id, entry, 0))
    }
    out.sort(function(a, b) { return a.label.localeCompare(b.label) })
    return typeof limit === "number" ? out.slice(0, limit) : out
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
