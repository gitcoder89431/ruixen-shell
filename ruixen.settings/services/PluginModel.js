// Pure logic behind the Plugins page, split out of PluginService.qml
// the same way ruixen.bar/BarModel.js already sits underneath Bar.qml
// -- no Process/Item/Quickshell dependency, so it is testable with a
// plain node run (see tests/js/PluginModel.test.js), not just a live
// Quickshell instance.

// ruixen.media is enabled service-only (its own oversized bar badge
// stays deliberately out of every layout -- see ruixen-bar-
// canonical.json's own comment) purely to back the notch's music
// control. The CLI itself reports canDisable: true for it (nothing
// else structurally depends on it staying enabled the way the bar
// does), but disabling it here would silently kill the notch's media
// widget with no toggle-back-on path visible anywhere in the bar -- it
// never had one to begin with. Locked the same way ruixen.settings
// locks itself, not via the CLI's own flag.
//
// Self-lockout for ruixen.settings is a guard the CLI itself does not
// provide -- ruixen.bar reports canDisable: false (Omarchy's own
// protection), but ruixen.settings reports canDisable: true even
// though disabling or removing the very plugin rendering this settings
// app would unload it immediately, mid-session, with no way back in
// short of a terminal.
function pluginIsProtected(row) {
  return !row || row.id === "ruixen.settings" || row.id === "ruixen.media" || !row.canDisable
}

// Parses `omarchy plugin list --json`, scoped to ruixen.* ids only,
// locked (protected) plugins sorted first then alphabetical within
// each group -- direct request ("the one that is locked like ruixen
// setting and ruixen bar, can you put them first of the list").
// pluginIsProtected above is the exact same real check the lock glyph
// itself is gated on (PluginsContent.qml), not a separate "core"
// concept invented just for sorting.
//
// ruixen.stayawake is dropped entirely: it is a plain bar-widget with
// no other kind, so "enabled" there is purely "present in bar.layout
// somewhere" (real registry semantics -- no separate disabled flag for
// a non-first-party widget), and ruixen.pluginpins' own pin/unpin
// dropdown already toggles that exact same state. Keeping both was a
// real, confusing duplicate control ("i have it disabled in settings
// but i can pin it and use it?").
function parsePluginList(raw) {
  var rows = []
  try {
    var data = JSON.parse(raw || "[]")
    for (var i = 0; i < data.length; i++) {
      var p = data[i]
      if (String(p.id || "").indexOf("ruixen.") !== 0) continue
      if (p.id === "ruixen.stayawake") continue
      rows.push(p)
    }
    rows.sort(function(a, b) {
      var aLocked = pluginIsProtected(a) ? 0 : 1
      var bLocked = pluginIsProtected(b) ? 0 : 1
      if (aLocked !== bLocked) return aLocked - bLocked
      return a.name.localeCompare(b.name)
    })
  } catch (e) {}
  return rows
}
