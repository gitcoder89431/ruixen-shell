// Ported verbatim from Omarchy's own real
// /usr/share/omarchy/shell/services/AppSearch.js (MIT license,
// github.com/omacom/omarchy) -- ruixen-shell issue #44/#38: Omarchy
// v4.0.3 only populates shell.appLibrary for a plugin declaring
// manifest kind "menu", which nothing in this repo does. This is the
// exact same ranking algorithm shell.appLibrary used (prefix match
// highest, then substring, then a bounded acronym fallback -- not
// fuzzy/subsequence matching), reused here against
// Quickshell.DesktopEntries directly (see AppLibrary.qml in this same
// directory) instead of the now-gated shell.appLibrary object.
function entryName(entry) {
  return String((entry && entry.name) || (entry && entry.id) || "")
}

function entrySubtext(entry) {
  return String((entry && entry.genericName) || "")
}

function entrySortKey(entry) {
  return entryName(entry).toLowerCase()
}

function keywordText(entry) {
  try {
    if (entry && entry.keywords && typeof entry.keywords.join === "function") return entry.keywords.join(" ")
  } catch (e) {
  }
  return ""
}

function entrySearchText(entry) {
  if (!entry) return ""
  return [entry.name, entry.genericName, entry.comment, keywordText(entry), entry.id].join(" ").toLowerCase()
}

function wordText(value) {
  return String(value || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[._:/\\-]+/g, " ")
    .toLowerCase()
}

function words(value) {
  var values = wordText(value).split(/[^a-z0-9]+/)
  var result = []
  for (var i = 0; i < values.length; i++) {
    if (values[i]) result.push(values[i])
  }
  return result
}

function entryAcronym(entry) {
  var values = words([entry && entry.name, entry && entry.genericName, keywordText(entry), entry && entry.id].join(" "))
  var result = ""
  for (var i = 0; i < values.length; i++) result += values[i].charAt(0)
  return result
}

function termMatches(entry, term) {
  if (!term) return true

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = entrySearchText(entry)

  if (name.indexOf(term) >= 0) return true
  if (id.indexOf(term) >= 0) return true
  if (haystack.indexOf(term) >= 0) return true

  return term.length <= 5 && entryAcronym(entry).indexOf(term) >= 0
}

function allTermsMatch(entry, query) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termMatches(entry, terms[i])) return false
  }
  return true
}

// frecencyBoostFor is optional -- a caller that doesn't pass it (every
// call site before frecency existed) gets the exact same score as
// before, unchanged. It's a plain function returning an already-
// resolved NUMBER (see LauncherFrecency.js's own frecencyBoost) -- this
// file has no notion of frecency itself, just "add this extra to the
// tier score", so the same pattern works for any provider's own
// scoring function, not just this one.
function fuzzyScore(entry, query, frecencyBoostFor) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return 0
  if (!allTermsMatch(entry, q)) return -1

  var name = entryName(entry).toLowerCase()
  var id = String((entry && entry.id) || "").toLowerCase()
  var haystack = entrySearchText(entry)
  var directName = name.indexOf(q)
  var directId = id.indexOf(q)
  var base
  if (directName === 0) base = 10000 - name.length
  else if (directId === 0) base = 9500 - id.length
  else if (directName > 0) base = 8000 - directName * 10 - name.length
  else if (directId > 0) base = 7600 - directId * 10 - id.length
  else {
    var hayIndex = haystack.indexOf(q)
    if (hayIndex >= 0) {
      base = 6000 - hayIndex
    } else {
      var acronym = entryAcronym(entry)
      var acronymIndex = acronym.indexOf(q)
      if (acronymIndex === 0) base = 5000 - acronym.length
      else if (acronymIndex > 0) base = 4600 - acronymIndex * 10 - acronym.length
      else base = 4000 - name.length
    }
  }

  return base + (frecencyBoostFor ? frecencyBoostFor(entry) : 0)
}

function sortedEntries(values, query, hiddenCallback, frecencyBoostFor) {
  var q = String(query || "").trim()
  var rows = []

  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    if (!entry || entry.noDisplay) continue
    if (hiddenCallback && hiddenCallback(entry)) continue
    var name = entryName(entry)
    if (!name) continue
    var score = fuzzyScore(entry, q, frecencyBoostFor)
    if (score < 0) continue
    rows.push({ entry: entry, score: score, key: entrySortKey(entry), name: name.toLowerCase() })
  }

  rows.sort(function(a, b) {
    if (q && a.score !== b.score) return b.score - a.score
    if (a.key < b.key) return -1
    if (a.key > b.key) return 1
    if (a.name < b.name) return -1
    if (a.name > b.name) return 1
    return 0
  })

  return rows
}
