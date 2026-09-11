// Issue #52: pure ranking/path-parsing logic pulled out of
// FileSearchProvider.qml so it's actually unit-testable -- a .qml file
// can't be loaded by this repo's own plain-JS test harness (it isn't
// valid standalone JS: `import QtQuick`, `Item { ... }` object syntax),
// the same reason OmarchyMenuParser.js/AppSearch.js already exist as
// separate modules instead of living inline in their own owning .qml
// files. FileSearchProvider.qml imports this module and calls straight
// through -- no behavior change, just relocated.

// Exact filename match > prefix > substring elsewhere in the name --
// same 0-10000 scale every other provider uses. dirBonus is passed in
// (not hardcoded here) since FileSearchProvider.qml's own dirBonus is a
// tunable property with its own real history documented there.
function scoreFile(name, query, isDir, dirBonus) {
  var q = String(query || "").toLowerCase()
  var n = String(name || "").toLowerCase()
  var base
  if (n === q) base = 10000
  else {
    var idx = n.indexOf(q)
    if (idx === 0) base = 9000 - n.length
    else if (idx > 0) base = 7000 - idx * 10 - n.length
    else base = 5000 - n.length
  }
  return isDir ? base + (dirBonus || 0) : base
}

// rawPath may carry fd's own trailing "/" marking a directory match --
// stripped before use as the real name/breadcrumb/action path. Returns
// the plain path split into its parts; homeDir abbreviation (the `~`
// substitution) is applied separately by abbreviateHome() below, since
// it needs the caller's own homeDir value.
function parseRawPath(rawPath) {
  var isDir = rawPath.length > 0 && rawPath.charAt(rawPath.length - 1) === "/"
  var path = isDir ? rawPath.substring(0, rawPath.length - 1) : rawPath
  var slash = path.lastIndexOf("/")
  var name = slash === -1 ? path : path.substring(slash + 1)
  var dir = slash === -1 ? "" : path.substring(0, slash)
  return { isDir: isDir, path: path, name: name, dir: dir }
}

// Same convention FileSearchProvider.qml's own breadcrumb/Where field
// already used before this extraction -- "/home/dev/notes" under
// homeDir "/home/dev" reads as "~/notes".
function abbreviateHome(dir, homeDir) {
  if (homeDir && dir.indexOf(homeDir) === 0) return "~" + dir.substring(homeDir.length)
  return dir
}
