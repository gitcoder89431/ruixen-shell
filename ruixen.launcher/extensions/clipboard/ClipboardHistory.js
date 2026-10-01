// Bounds: clipboard text can be megabytes. Titles, link detection and
// the details preview only ever look at a prefix.
var TITLE_SCAN_LIMIT = 400
var LINK_MAX_LENGTH = 2048
var PREVIEW_LIMIT = 6000
var SEARCH_TEXT_LIMIT = 20000

function summarizeText(text) {
  var s = String(text || "").slice(0, TITLE_SCAN_LIMIT).replace(/\s+/g, " ").trim()
  if (s.length === 0) return "Empty text"
  return s.length > 80 ? s.slice(0, 77) + "..." : s
}

function basename(path) {
  var p = String(path || "")
  var idx = p.lastIndexOf("/")
  return idx >= 0 ? p.slice(idx + 1) : p
}

function imageLabel(entry, dimensionsByPath) {
  var dims = dimensionsByPath && entry.path ? dimensionsByPath[entry.path] : ""
  return dims ? ("Image (" + dims + ")") : "Image"
}

// Bare "word.tld" is only a link when the TLD is a well-known one --
// otherwise filenames like main.py / install.sh / Node.js read as URLs.
var BARE_LINK_TLDS = {
  com: 1, org: 1, net: 1, io: 1, dev: 1, app: 1, co: 1, ai: 1, edu: 1,
  gov: 1, me: 1, info: 1, xyz: 1, uk: 1, de: 1, fr: 1, nl: 1, eu: 1,
  us: 1, ca: 1, au: 1, tv: 1, cc: 1
}

function looksLikeLink(text) {
  var s = String(text || "")
  if (s.length > LINK_MAX_LENGTH) return false
  s = s.trim()
  if (/^https?:\/\/[^\s"'<>]+$/i.test(s)) return true
  if (/^www\.[A-Za-z0-9.-]+\.[A-Za-z]{2,}(\/[^\s]*)?$/i.test(s)) return true
  var m = /^[A-Za-z0-9][A-Za-z0-9-]*(?:\.[A-Za-z0-9-]+)*\.([A-Za-z]{2,})(?:\/[^\s]*)?$/.exec(s)
  return !!m && BARE_LINK_TLDS[m[1].toLowerCase()] === 1
}

// Stable identity for an entry across history reloads (sourceIndex is
// only a position in the file and shifts when new items are copied).
function entryKey(entry) {
  if (!entry) return ""
  return entry.type + "|" + (entry.type === "image" ? entry.path : String(entry.text).slice(0, 200) + "|" + String(entry.text).length) + "|" + (entry.capturedAt || "")
}

function previewText(text, limit) {
  var s = String(text || "")
  var max = limit || PREVIEW_LIMIT
  return s.length > max ? s.slice(0, max) + "\n\u2026 (preview truncated)" : s
}

function normalizeEntry(entry, index) {
  if (!entry || typeof entry !== "object") return null
  if (entry.type === "text" && typeof entry.text === "string") {
    var isLink = looksLikeLink(entry.text)
    return {
      sourceIndex: index,
      type: isLink ? "link" : "text",
      text: entry.text,
      path: "",
      mime: "text/plain",
      capturedAt: entry.capturedAt || "",
      title: summarizeText(entry.text),
      subtitle: entry.capturedAt || (isLink ? "Link" : "Text"),
      icon: isLink ? "\uf0c1" : "\uf0f6",
      kind: isLink ? "Link" : "Text",
      searchBlob: (entry.text.slice(0, SEARCH_TEXT_LIMIT) + "\n" + (entry.capturedAt || "")).toLowerCase()
    }
  }
  if (entry.type === "image" && typeof entry.path === "string") {
    return {
      sourceIndex: index,
      type: "image",
      text: "",
      path: entry.path,
      mime: entry.mime || "image/png",
      capturedAt: entry.capturedAt || "",
      title: basename(entry.path) || "Image",
      subtitle: entry.capturedAt || entry.mime || "Image",
      icon: "\uf1c5",
      kind: "Image",
      searchBlob: (entry.path + "\n" + (entry.mime || "image/png") + "\n" + (entry.capturedAt || "") + "\nimage").toLowerCase()
    }
  }
  return null
}

function parseHistory(raw) {
  var parsed = []
  try {
    var data = JSON.parse(String(raw || "[]"))
    if (!Array.isArray(data)) return []
    for (var i = 0; i < data.length; i++) {
      var entry = normalizeEntry(data[i], i)
      if (entry) parsed.push(entry)
    }
  } catch (e) {
    return []
  }
  return parsed
}

function matches(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return true
  return String(entry.searchBlob || "").indexOf(q) !== -1
}

// First-seen-first image paths that still need a dimensions probe,
// capped so a long history never triggers an unbounded scan.
function pathsToProbe(entries, known, limit) {
  var out = []
  var seen = {}
  for (var i = 0; i < entries.length && out.length < limit; i++) {
    var e = entries[i]
    if (e.type !== "image" || !e.path || seen[e.path]) continue
    seen[e.path] = true
    if (known && known[e.path] !== undefined) continue
    out.push(e.path)
  }
  return out
}

// Bounded merge so the per-path cache can't grow without limit.
function mergeDimensions(cache, fresh, maxEntries) {
  var out = {}
  var keys = Object.keys(cache || {})
  var freshKeys = Object.keys(fresh || {})
  var drop = Math.max(0, keys.length + freshKeys.length - maxEntries)
  for (var i = drop; i < keys.length; i++) out[keys[i]] = cache[keys[i]]
  for (var j = 0; j < freshKeys.length; j++) out[freshKeys[j]] = fresh[freshKeys[j]]
  return out
}

function rows(entries, query, accent, dimensionsByPath) {
  var out = []
  for (var i = 0; i < entries.length; i++) {
    var entry = entries[i]
    if (!matches(entry, query)) continue
    var label = entry.type === "image" ? imageLabel(entry, dimensionsByPath) : entry.title
    out.push({
      id: "clipboard:" + entry.sourceIndex,
      providerId: "clipboard-history",
      icon: entry.icon,
      iconColor: entry.type === "image" ? accent : undefined,
      label: label,
      breadcrumb: entry.subtitle,
      kind: entry.kind,
      providerName: "",
      sectionLabel: "Clipboard",
      score: 0,
      clipboardEntry: entry
    })
  }
  return out
}
