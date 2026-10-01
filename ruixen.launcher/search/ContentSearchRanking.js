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

// Issue #55: rg's own exit code convention is DIFFERENT from fd's
// (confirmed live, see FileSearchRanking.js's own classifyFdExitCode)
// -- 0 means at least one match, 1 means it ran fine but found ZERO
// matches (not an error), anything else is a real failure. `timeout <n>
// rg ...` passes rg's own real exit code through when it completes in
// time, and returns 124 itself only when IT had to kill rg.
function classifyRgExitCode(exitCode) {
  if (exitCode === 0 || exitCode === 1) return "success"
  if (exitCode === 124) return "timeout"
  return "error"
}
