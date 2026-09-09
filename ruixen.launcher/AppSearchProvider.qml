import QtQuick

// Provider: installed applications, via a local AppLibrary instance
// (see AppLibrary.qml's own header -- wraps Quickshell.DesktopEntries
// directly, not the broken/gated shell.appLibrary). No new search
// logic here at all -- AppLibrary.sortedEntries()/entryName()/
// iconSource()/launch() already do the real work.
Item {
  id: root

  readonly property string providerName: "Applications"
  property var appLibrary: null
  // Matches Launcher.qml's own visibleRowCount -- no point returning
  // more rows than the fixed-height card can ever show.
  property int maxResults: 10
  readonly property bool ready: root.appLibrary !== null

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
        category: entry.genericName || "Application",
        providerName: root.providerName,
        score: rows[i].score,
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
