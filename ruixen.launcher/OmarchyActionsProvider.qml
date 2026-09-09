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
  // Real, documented, hot-reloading user customization point (confirmed
  // in Omarchy's own SKILL.md config-path table and the native
  // Menu.qml) -- entries added here merge on top of the packaged
  // defaults via OmarchyMenuParser.mergeUserOverrides, same as the
  // native menu's own mergeMenuSources. Missing entirely is the normal
  // case (most users never touch it), not an error.
  readonly property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"

  // Raw parsed maps from each source, before merging -- kept separate
  // so either file can finish loading (or fail) independently and
  // rebuildEntries() below just re-merges whatever's currently known.
  property var defaultEntries: ({})
  property var userEntries: ({})
  // Full flat {id: entry} map, defaults merged with user overrides --
  // needed so breadcrumbFor() can look up any ancestor's own label.
  property var allEntries: ({})
  // Subset of allEntries with a real "action" string -- what search()
  // actually offers as results.
  property var actionable: ({})
  // {id: {when, checked}} -- see OmarchyMenuParser.parseGuardOutput.
  property var guardResults: ({})

  // Both FileViews' own onLoaded can fire more than once during startup
  // (the implicit preload when `path` resolves, plus the explicit
  // .reload() call in Component.onCompleted -- same double-fire already
  // documented in ruixen.notch/NotificationService.qml's own
  // loadStore()) and each needs the OTHER to have at least settled
  // (loaded or failed) once before the first real merge+guard-evaluate
  // pass. defaultSettled/userSettled track that; rebuildEntries() is a
  // no-op until both are true, and safely re-runs (parsing is cheap,
  // idempotent) on any later change to either file.
  property bool defaultSettled: false
  property bool userSettled: false

  function rebuildEntries() {
    if (!root.defaultSettled || !root.userSettled) return
    root.allEntries = OmarchyMenuParser.mergeUserOverrides(root.defaultEntries, root.userEntries)
    root.actionable = OmarchyMenuParser.actionableEntries(root.allEntries)
    var script = OmarchyMenuParser.buildGuardScript(root.actionable)
    if (script.length === 0) {
      root.ready = true
      return
    }
    guardProc.command = ["bash", "-c", script]
    guardProc.running = true
  }

  // Ruixen Settings has no manifest kind "menu" entry of its own, and
  // Super+R no longer opens it directly once this plugin owns that key
  // -- one synthetic row here keeps it reachable from the palette too,
  // same real toggle command its own keybind already used. Not a third
  // provider, just one more entry alongside the real Omarchy ones.
  readonly property var syntheticEntries: ({
    "ruixen.settings": {
      // fa-gear (U+F013) -- matches ruixen.settingsbutton's own bar
      // icon and Settings.qml's own panel header, so the palette row
      // and what it opens read as the same thing.
      icon: "",
      label: "Ruixen Settings",
      // A short tagline, same spirit as a .desktop file's own
      // GenericName= (e.g. "Streaming/Recording Software") -- a
      // couple of words, not a feature list. Not a breadcrumb (there's
      // no omarchy-menu.jsonc chain to walk for a synthetic entry),
      // just plain text describing what this opens.
      breadcrumb: "Shell Control",
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

  // breadcrumb is the launcher's per-row subtitle (e.g. "Remove ›
  // Development", "Setup › Defaults › Editor") -- the entry's full
  // ancestor chain via breadcrumbFor(), root down to its immediate
  // parent. syntheticEntries override it outright (e.g. "Ruixen" --
  // not part of the real omarchy-menu.jsonc tree, so there's no chain
  // to walk). kind is a fixed "Command" for every row this provider
  // produces -- see Launcher.qml's own row delegate for how the two
  // combine ("Remove › Development  ·  Command").
  function resultFor(id, entry, score) {
    return {
      id: "omarchy:" + id,
      providerId: "omarchy-actions",
      icon: entry.icon || "",
      label: entry.label || id,
      breadcrumb: entry.breadcrumb || OmarchyMenuParser.breadcrumbFor(root.allEntries, id),
      kind: "Command",
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
      if (root.defaultSettled) return
      root.defaultSettled = true
      root.defaultEntries = OmarchyMenuParser.parseMenuEntries(text())
      root.rebuildEntries()
    }
    // The packaged default is expected to always exist -- a failure
    // here is real (Omarchy itself missing/broken), not the normal
    // "no user file" case userMenuFile's own onLoadFailed handles.
    onLoadFailed: {
      if (root.defaultSettled) return
      root.defaultSettled = true
      root.ready = true
    }
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: false
    printErrors: false
    onLoaded: {
      if (root.userSettled) return
      root.userSettled = true
      root.userEntries = OmarchyMenuParser.parseMenuEntries(text())
      root.rebuildEntries()
    }
    // No ~/.config/omarchy/extensions/omarchy-menu.jsonc at all is the
    // normal case (most users never touch it) -- not an error, just an
    // empty override map.
    onLoadFailed: {
      if (root.userSettled) return
      root.userSettled = true
      root.rebuildEntries()
    }
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

  Component.onCompleted: {
    menuFile.reload()
    userMenuFile.reload()
  }
}
