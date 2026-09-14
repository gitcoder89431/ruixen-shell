import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "AppSearch.js" as AppSearch

// ruixen-shell issue #44/#38: Omarchy v4.0.3 only populates
// shell.appLibrary for a plugin declaring manifest kind "menu", which
// nothing in this repo does -- and per the issue's own research,
// shell.appLibrary is independently broken by a caching bug even for
// plugins that DO declare that kind (omacom/omarchy#10871, #10876), so
// adding a fake "menu" kind here was never going to be a real fix
// either way.
//
// Quickshell.DesktopEntries is a real, core Quickshell type,
// independent of Omarchy and unaffected by either problem (confirmed
// present: "Quickshell/DesktopEntries 0.0" in this machine's own
// quickshell-core.qmltypes). This is a thin, from-scratch wrapper
// around it -- NOT a copy of Omarchy's own AppLibrary.qml file, just an
// independent implementation reusing the same public Quickshell API it
// itself is built on. AppSearch.js alongside this file (ranking
// algorithm only, no host object involved) IS ported verbatim from
// Omarchy's own real source (MIT), see its own header.
//
// Deliberately narrower than Omarchy's own AppLibrary.qml, since
// neither ruixen.notch/LauncherContent.qml nor
// ruixen.pinnedapps/BarWidget.qml (the two call sites this replaces)
// ever called the parts left out:
// - No custom icon-index scan (a background `find` across XDG icon
//   dirs, used there as a fallback for an app installed after the
//   shell process started but before its own icon-theme cache
//   refreshed). Quickshell.iconPath()'s own themed lookup alone covers
//   every real icon under normal operation; this is a real, disclosed
//   scope trim for that one edge case, not a silent one -- see
//   ruixen-shell issue #44's own closing comment.
// - No launch-feedback OSD (the "Launching X..." toast that appears
//   when an app takes a couple seconds to open) -- neither call site
//   read launchOsdOpen/launchOsdMessage, so there was nothing for
//   losing shell.appLibrary to actually break here.
// - No remove()/hidden-entry EDITING -- neither call site ever called
//   appLibrary.remove(); hidden-entry READING (below) is kept, since
//   both call sites' own result lists need to agree with what the real
//   launcher already hides.
//
// One instance lives on ruixen.notch/Overlay.qml's own root (see
// notificationHistory/kanbanService for the same "one instance per
// session" pattern) and ruixen.pinnedapps/BarWidget.qml's own root --
// plugin folders can't share a file across install locations, so this
// file (and AppSearch.js) is kept byte-identical between the two
// copies by convention. DesktopEntries itself is a Quickshell
// singleton regardless of how many places import it, so this doesn't
// duplicate any desktop-entry parsing between the two instances --
// only the small amount of state below (hidden-entry ids) is per-copy.
Item {
  id: root

  readonly property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  property var configuredHiddenEntryIds: ({})
  property var desktopHiddenEntryIds: ({})

  function entryName(entry) {
    return AppSearch.entryName(entry)
  }

  function isHiddenEntry(entry) {
    var id = String((entry && entry.id) || "")
    return root.configuredHiddenEntryIds[id] === true || root.desktopHiddenEntryIds[id] === true
  }

  function sortedEntries(query) {
    var values = DesktopEntries.applications.values || []
    return AppSearch.sortedEntries(values, query, function(entry) { return root.isHiddenEntry(entry) })
  }

  function iconSource(icon) {
    var value = String(icon || "")
    if (value.length === 0) return Quickshell.iconPath("application-x-executable", true)
    if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0) return value
    if (value.charAt(0) === "/") return Util.fileUrl(value)
    var themed = Quickshell.iconPath(value, true)
    if (themed.length > 0) return themed
    return Quickshell.iconPath("application-x-executable", true)
  }

  // Same launch mechanism Omarchy's own AppLibrary.qml uses (confirmed
  // by reading it directly, not guessed) rather than DesktopEntry's own
  // native execute() -- gtk-launch inside a uwsm-app scope keeps a
  // launched app out of wayland-wm@.service the same way the real
  // launcher already does; execute() alone would run it as a plain
  // child of this shell process instead, a real (if minor) isolation
  // regression the acceptance bar ("launch... identically to today")
  // doesn't call for.
  function launch(desktopId, name) {
    var id = String(desktopId || "")
    if (!id) return
    Util.execDetached("uwsm-app -- gtk-launch " + Util.shellQuote(id + ".desktop"))
  }

  function normalizeDesktopId(id) {
    var value = String(id || "").trim()
    if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
    return value
  }

  function loadConfiguredHides(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = root.normalizeDesktopId(lines[i])
      if (id.length > 0) next[id] = true
    }
    root.configuredHiddenEntryIds = next
  }

  function loadDesktopHiddenEntries(rawText) {
    var next = ({})
    var lines = String(rawText || "").split(/\n/)
    for (var i = 0; i < lines.length; i++) {
      var id = root.normalizeDesktopId(lines[i])
      if (id.length > 0) next[id] = true
    }
    root.desktopHiddenEntryIds = next
  }

  function hiddenEntryScanCommand() {
    var desktop = [Quickshell.env("XDG_CURRENT_DESKTOP"), Quickshell.env("XDG_SESSION_DESKTOP"), Quickshell.env("DESKTOP_SESSION")].filter(function(v) { return String(v || "").length > 0 }).join(":")
    var script = root.omarchyPath + "/shell/services/hidden-entries.sh"
    return Util.shellQuote(script) + " " + Util.shellQuote(desktop)
  }

  QtObject {
    id: hiddenEntryOutput
    property string text: ""
  }

  Process {
    id: hiddenEntryScan
    command: ["bash", "-c", root.hiddenEntryScanCommand()]
    stdout: SplitParser { onRead: function(line) { hiddenEntryOutput.text += line + "\n" } }
    onStarted: hiddenEntryOutput.text = ""
    onExited: root.loadDesktopHiddenEntries(hiddenEntryOutput.text)
  }

  FileView {
    path: root.omarchyPath + "/default/omarchy/launcher.hides"
    watchChanges: true
    printErrors: false
    onLoaded: root.loadConfiguredHides(text())
    onFileChanged: root.loadConfiguredHides(text())
    onLoadFailed: root.loadConfiguredHides("")
  }

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { hiddenEntryScan.running = true }
  }

  Component.onCompleted: hiddenEntryScan.running = true
}
