// Issue #63: keyboard-first query operators layered over Search Files'
// existing filter state (#59's multi-term search, #60's type/scope/
// hidden filters, #61's configurable sources). Pure SYNTAX-level
// parsing only -- this module knows the operator KEYS and how to
// extract their raw string values, nothing about what a real category
// or source name actually IS. Resolving "image" against the real
// FILE_CATEGORY_NAMES list, or "Home"/"Work Drive" against the real
// discovered sources, is a separate step the caller (Launcher.qml,
// which has that runtime context) does afterward with its own
// case-insensitive matching and its own graceful-fallback rules. This
// keeps the parser itself fully pure and testable without any of that
// context, matching this issue's own worked example exactly:
//
//   parseQuery("type:image in:Home sunset")
//   => { text: "sunset", type: "image", source: "Home" }
//
// Never evaluated as shell code, never concatenated into a command --
// this produces plain structured data only, consumed by the SAME safe
// argv-building/provider paths the visual filter controls already use
// (SearchFiltersBar.qml's own category cycling, the source-filter
// dropdown, ...).

var OPERATOR_ALIASES = {
  type: "type", kind: "type",
  in: "source", source: "source",
  name: "scope-name", content: "scope-content",
  hidden: "hidden"
}

function isSpace(ch) {
  return ch === " " || ch === "\t" || ch === "\n" || ch === "\r"
}

// Splits a query into structured operator fields plus the remaining
// literal search text. An operator is recognized only as a WHOLE token
// (`key:value` or `key:"quoted value with spaces"`) bounded by
// whitespace or the string's own start/end -- never mid-word, so an
// ordinary search term that happens to contain a colon is never
// misread as one. Quoted values allow spaces
// (`in:"Google Drive" report`); an unterminated quote, an unrecognized
// key, or a recognized key with a value that fails its own shape check
// (e.g. `hidden:maybe`) all degrade the SAME way -- the whole token is
// treated as ordinary literal text instead, never a partial/silent
// misapplication of the operator.
function parseQuery(query) {
  var raw = String(query || "")
  var textParts = []
  var type, source, scope, hidden
  var i = 0
  var n = raw.length

  while (i < n) {
    while (i < n && isSpace(raw.charAt(i))) i++
    if (i >= n) break
    var start = i
    var keyMatch = /^([A-Za-z]+):/.exec(raw.slice(i))
    var consumed = false

    if (keyMatch) {
      var canonical = OPERATOR_ALIASES[keyMatch[1].toLowerCase()]
      if (canonical) {
        var afterColon = i + keyMatch[0].length
        var value, end
        if (raw.charAt(afterColon) === "\"") {
          var closeIdx = raw.indexOf("\"", afterColon + 1)
          if (closeIdx !== -1) {
            value = raw.slice(afterColon + 1, closeIdx)
            end = closeIdx + 1
          }
        } else {
          var m = /^\S*/.exec(raw.slice(afterColon))
          value = m[0]
          end = afterColon + value.length
        }

        if (value !== undefined) {
          if (canonical === "type" && value) { type = value; consumed = true }
          else if (canonical === "source" && value) { source = value; consumed = true }
          else if (canonical === "hidden") {
            var lower = value.toLowerCase()
            if (lower === "true" || lower === "false") { hidden = (lower === "true"); consumed = true }
          } else if (canonical === "scope-name") {
            scope = "names"
            if (value) textParts.push(value)
            consumed = true
          } else if (canonical === "scope-content") {
            scope = "contents"
            if (value) textParts.push(value)
            consumed = true
          }
          if (consumed) i = end
        }
      }
    }

    if (!consumed) {
      var tok = /^\S+/.exec(raw.slice(start))[0]
      textParts.push(tok)
      i = start + tok.length
    }
  }

  // Built in this fixed order (never the order operators happened to
  // appear in the input) so equivalent queries always produce
  // structurally identical, directly comparable results.
  var result = { text: textParts.filter(function(t) { return t.length > 0 }).join(" ") }
  if (type !== undefined) result.type = type
  if (source !== undefined) result.source = source
  if (scope !== undefined) result.scope = scope
  if (hidden !== undefined) result.hidden = hidden
  return result
}

// Issue #63's own resolution step: matches a raw `type:`/`kind:` value
// against the real category list case-insensitively, returning the
// correctly-cased category name FileSearchRanking.js's own
// categoryForPath()/matchesCategory() expect, or null if it doesn't
// match anything real -- the caller's job to then decide "fall back to
// literal text" per this issue's own graceful-degradation requirement
// (this function only resolves, it doesn't rewrite the query).
function resolveCategoryOperator(rawValue, categoryNames) {
  var lower = String(rawValue || "").toLowerCase()
  for (var i = 0; i < categoryNames.length; i++) {
    if (categoryNames[i].toLowerCase() === lower) return categoryNames[i]
  }
  // A couple of natural singular/plural aliases worth accepting beyond
  // an exact category-name match -- "image"/"images" should both find
  // the real "Images" category rather than only the plural form typed
  // exactly.
  if (lower + "s" !== lower) {
    for (var j = 0; j < categoryNames.length; j++) {
      if (categoryNames[j].toLowerCase() === lower + "s") return categoryNames[j]
    }
  }
  return null
}

// Same idea for `in:`/`source:` -- matches a raw value against the
// real discovered sources list ({id, label, path}[], the exact shape
// FileSearchProvider.qml's own `sources` property already produces),
// case-insensitively against either the label ("Home", "Work Drive")
// or the bare path, returning the real source path
// (selectedSourcePath's own value shape) or null if nothing matches.
function resolveSourceOperator(rawValue, sources) {
  var lower = String(rawValue || "").toLowerCase()
  for (var i = 0; i < sources.length; i++) {
    if (sources[i].label.toLowerCase() === lower) return sources[i].path
  }
  for (var j = 0; j < sources.length; j++) {
    if (sources[j].path.toLowerCase() === lower) return sources[j].path
  }
  return null
}
