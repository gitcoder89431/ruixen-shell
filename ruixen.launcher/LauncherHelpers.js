// Issue #52: pure helpers pulled out of Launcher.qml for the same
// reason FileSearchRanking.js/ContentSearchRanking.js exist (see
// FileSearchRanking.js's own header) -- not everything in Launcher.qml
// qualifies (formatDate uses Qt.formatDateTime, a real Qt global that
// doesn't exist outside a QML engine, so it stays there), but these two
// have no such dependency. No behavior change, just relocated.

// Search Files rows dropped their own path subtitle, so two folders/
// files that happen to share a bare name (e.g. a "projects-plans" under
// both "dog" and "cats") would otherwise render as identical, unlabeled
// rows with no way to tell them apart. Prefixes the immediate PARENT
// folder's own name (not the whole path) only onto labels that actually
// collide within the current result set. Derives the disambiguating
// parent from the row's own real path (action.path), not breadcrumb --
// breadcrumb IS the parent directory for a plain filename match, but a
// content-search row's own breadcrumb is "Line N: <snippet>" instead
// (see FileContentSearchProvider.qml's own resultFor()), so deriving
// from breadcrumb could split a snippet of file CONTENT on "/" and
// label a row with fragments of unrelated code. action.path is real and
// present on every Search Files row from either provider.
function disambiguateLabels(rows) {
  var counts = {}
  for (var i = 0; i < rows.length; i++) counts[rows[i].label] = (counts[rows[i].label] || 0) + 1
  for (var j = 0; j < rows.length; j++) {
    if (counts[rows[j].label] > 1) {
      var path = String((rows[j].action && rows[j].action.path) || "")
      var dir = path.substring(0, path.lastIndexOf("/"))
      var parent = dir.substring(dir.lastIndexOf("/") + 1)
      if (parent) rows[j].label = parent + "/" + rows[j].label
    }
  }
  return rows
}

function formatSize(bytes) {
  var n = Number(bytes) || 0
  if (n < 1024) return n + " B"
  var units = ["KB", "MB", "GB", "TB"]
  var v = n / 1024
  for (var i = 0; i < units.length; i++) {
    if (v < 1024 || i === units.length - 1) return v.toFixed(1) + " " + units[i]
    v /= 1024
  }
}

// Derives "Where" straight from the real path, generically for any
// provider's result -- not a per-provider breadcrumb convention. Needed
// once FileContentSearchProvider's own results existed: its breadcrumb
// is deliberately the matched LINE snippet (the whole point of "search
// by context"), so reusing that same field for "Where" would show a
// line of file content where a folder location belongs. Same ~
// abbreviation FileSearchRanking.js's own abbreviateHome() uses.
function parentDirOf(path, homeDir) {
  var slash = path.lastIndexOf("/")
  var dir = slash === -1 ? "" : path.substring(0, slash)
  if (homeDir && dir.indexOf(homeDir) === 0) dir = "~" + dir.substring(homeDir.length)
  return dir
}
