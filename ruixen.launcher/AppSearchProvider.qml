import QtQuick
import Quickshell
import Quickshell.Io
import "OmarchyMenuParser.js" as OmarchyMenuParser

// Provider: installed applications, via a local AppLibrary instance
// (see AppLibrary.qml's own header -- wraps Quickshell.DesktopEntries
// directly, not the broken/gated shell.appLibrary). No new search
// logic here at all -- AppLibrary.sortedEntries()/entryName()/
// iconSource()/launch() already do the real work.
Item {
  id: root

  readonly property string providerName: "Applications"
  property var appLibrary: null
  // A sanity cap, not a display limit -- Launcher.qml's results list
  // scrolls, so this just guards against sortedEntries() ever handing
  // back an unreasonably long tail.
  property int maxResults: 40
  readonly property bool ready: root.appLibrary !== null

  // Omarchy's own default app-launch keybinds (Docker, Spotify via its
  // own "Music" label, ...) -- real request: "these were set by
  // omarchy... can we make them show up for applications?" See
  // OmarchyMenuParser.js's own "Application keybind hints" header for
  // why this is matched by Exec= substring rather than by label the way
  // Omarchy Actions rows are. Loaded once at provider startup (a small
  // local config file), never re-parsed per keystroke. Only the
  // packaged default file is read -- none of this dev machine's own 3
  // real personal bindings.lua overrides target an app this way (see
  // OmarchyActionsProvider's own parsePersonalBindings usage), so
  // there's nothing to merge yet; revisit if that ever changes.
  property var appBindingEntries: []

  function keybindFor(entry) {
    return OmarchyMenuParser.appKeybindFor(entry.execString || "", root.appBindingEntries)
  }

  FileView {
    id: applicationBindingsFile
    path: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/default/hypr/bindings/applications.lua"
    watchChanges: false
    printErrors: false
    onLoaded: root.appBindingEntries = OmarchyMenuParser.parseApplicationBindings(text())
  }

  Component.onCompleted: applicationBindingsFile.reload()

  // The real .desktop file's own "Comment=" (a one-line description,
  // e.g. OBS Studio's "Free and Open Source Streaming/Recording
  // Software") over "GenericName=" (a short category, e.g. "Streaming/
  // Recording Software") -- surveyed directly against every installed
  // app's own .desktop file: Comment is populated on meaningfully more
  // of them (47 vs 33 here) and usually reads as a fuller, more useful
  // subtitle. Falls back to genericName when comment is missing or
  // degenerate (a few apps just repeat their own name as the comment,
  // e.g. Obsidian's "Comment=Obsidian" -- not worth showing), then to a
  // bare "Application" when neither exists. Both fields are real
  // Quickshell.DesktopEntry properties (confirmed against Quickshell's
  // own qmltypes), not something AppLibrary.qml computes.
  function subtitleFor(entry, name) {
    var comment = String(entry.comment || "").trim()
    if (comment && comment.toLowerCase() !== String(name || "").trim().toLowerCase()) return comment
    return entry.genericName || "Application"
  }

  function search(query) {
    if (!root.appLibrary) return []
    var q = String(query || "").trim()
    if (!q) return []
    var rows = root.appLibrary.sortedEntries(q)
    var out = []
    for (var i = 0; i < rows.length && out.length < root.maxResults; i++) {
      var entry = rows[i].entry
      var name = root.appLibrary.entryName(entry)
      out.push({
        id: "app:" + entry.id,
        providerId: "app-search",
        icon: entry.icon || "",
        label: name,
        category: root.subtitleFor(entry, name),
        providerName: root.providerName,
        score: rows[i].score,
        keybind: root.keybindFor(entry),
        action: { type: "launchApp", desktopId: entry.id, name: name }
      })
    }
    return out
  }

  function activate(result) {
    if (!root.appLibrary) return
    root.appLibrary.launch(result.action.desktopId, result.action.name)
  }
}
