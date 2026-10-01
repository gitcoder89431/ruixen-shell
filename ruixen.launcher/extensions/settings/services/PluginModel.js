// Pure logic behind the Plugins category, ported verbatim from
// ruixen.settings/services/PluginModel.js -- no Process/Item/Quickshell
// dependency, testable with a plain node run.

// ruixen.media is enabled service-only (its own bar badge stays
// deliberately out of every layout) purely to back the notch's music
// control -- disabling it here would silently kill that widget with no
// toggle-back-on path visible anywhere in the bar.
//
// Self-lockout here is for ruixen.launcher, not ruixen.settings -- the
// one deliberate change from the ported original. This Plugins category
// is rendered BY ruixen.launcher itself (this very plugin), so disabling
// or removing IT is what would unload this settings extension mid-
// session with no way back short of a terminal, the same self-rendering
// risk ruixen.settings' own copy of this file guards against for
// itself. ruixen.settings is just another row here, gated only by its
// own real canDisable flag from the CLI -- toggling it from inside
// ruixen.launcher's own Settings extension is perfectly safe.
function pluginIsProtected(row) {
  return !row || row.id === "ruixen.launcher" || row.id === "ruixen.media" || !row.canDisable
}

// Parses `omarchy plugin list --json`, scoped to ruixen.* ids only,
// locked (protected) plugins sorted first then alphabetical within each
// group -- same convention ruixen.settings' own list uses.
//
// ruixen.stayawake is dropped entirely: it is a plain bar-widget with no
// other kind, so "enabled" there is purely "present in bar.layout
// somewhere" -- ruixen.pluginpins' own pin/unpin dropdown already
// toggles that exact same state.
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
