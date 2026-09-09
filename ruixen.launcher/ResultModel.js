// Cross-provider merge/rank/cap -- provider-agnostic on purpose. Every
// provider already scores/sorts its own results internally (0-10000
// scale, see OmarchyMenuParser.js's scoreEntry / AppSearch.js's
// fuzzyScore); this just flattens everything into one list, sorts by
// that shared score, and caps it. Adding a future provider never needs
// a change here -- it just needs to return results on the same scale.

// results: array of Result objects, each already carrying its own
// providerId/score (see Launcher.qml's own Result shape comment).
function mergeResults(results, maxTotal) {
  var out = results.slice()
  out.sort(function(a, b) {
    return (b.score || 0) - (a.score || 0)
  })
  var limit = (typeof maxTotal === "number" && maxTotal > 0) ? maxTotal : 9
  return out.slice(0, limit)
}
