// Issue #52: pure snippet/path logic pulled out of
// FileContentSearchProvider.qml for the same reason
// FileSearchRanking.js exists (see its own header) -- a .qml file can't
// be loaded by this repo's plain-JS test harness. No behavior change,
// just relocated.

function baseName(path) {
  var slash = path.lastIndexOf("/")
  return slash === -1 ? path : path.substring(slash + 1)
}

// Collapse a matched line to one clean, trimmed line -- rg's own
// lines.text carries a trailing newline (and occasionally embedded ones
// for odd files), neither of which belongs in a single-line row
// breadcrumb. Long lines are truncated with an ellipsis rather than
// wrapping/overflowing the row.
function collapseSnippet(lineText, maxLen) {
  var snippet = String(lineText || "").replace(/\s+/g, " ").trim()
  var limit = typeof maxLen === "number" ? maxLen : 80
  if (snippet.length > limit) snippet = snippet.substring(0, limit) + "…"
  return snippet
}

// Issue #54: per-root content search could in principle surface the
// same real file twice (a nested/bind mount reachable through two
// different discovered roots) -- dedupes by the result's own real path,
// keeping the first-seen copy. Order-preserving, not a re-sort.
function dedupeByPath(items) {
  var out = []
  var seen = ({})
  for (var i = 0; i < items.length; i++) {
    var key = items[i].action.path
    if (seen[key]) continue
    seen[key] = true
    out.push(items[i])
  }
  return out
}
