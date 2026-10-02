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
  var prefix = entry.qr ? "QR Image" : "Image"
  return dims ? (prefix + " (" + dims + ")") : prefix
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

function openableUrl(text) {
  var s = String(text || "").trim()
  if (/^https?:\/\//i.test(s) && looksLikeLink(s)) return s
  if (/^www\./i.test(s) && looksLikeLink(s)) return "https://" + s
  return looksLikeLink(s) ? "https://" + s : ""
}

function hex2(n) {
  var h = Math.round(n).toString(16)
  return h.length < 2 ? "0" + h : h
}

function hslFromRgb(r, g, b) {
  r /= 255; g /= 255; b /= 255
  var max = Math.max(r, g, b), min = Math.min(r, g, b)
  var l = (max + min) / 2, h = 0, sat = 0
  if (max !== min) {
    var d = max - min
    sat = l > 0.5 ? d / (2 - max - min) : d / (max + min)
    if (max === r) h = (g - b) / d + (g < b ? 6 : 0)
    else if (max === g) h = (b - r) / d + 2
    else h = (r - g) / d + 4
    h *= 60
  }
  return "hsl(" + Math.round(h) + ", " + Math.round(sat * 100) + "%, " + Math.round(l * 100) + "%)"
}

// "#rgb" / "#rgba" / "#rrggbb" / "#rrggbbaa", rgb()/rgba(), hsl() ->
// {r,g,b,a} (0-255 / 0-1) or null.
function parseColor(text) {
  var s = String(text || "").trim()
  if (s.length > 64) return null
  var m = /^#([0-9a-f]{3,4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.exec(s)
  if (m) {
    var h = m[1]
    if (h.length <= 4) h = h.split("").map(function(c) { return c + c }).join("")
    return {
      r: parseInt(h.slice(0, 2), 16), g: parseInt(h.slice(2, 4), 16), b: parseInt(h.slice(4, 6), 16),
      a: h.length === 8 ? parseInt(h.slice(6, 8), 16) / 255 : 1
    }
  }
  m = /^rgba?\(\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*[, ]\s*(\d{1,3})\s*(?:[,/]\s*(\d*\.?\d+%?)\s*)?\)$/i.exec(s)
  if (m) {
    var r = +m[1], g = +m[2], b = +m[3]
    if (r > 255 || g > 255 || b > 255) return null
    var a = 1
    if (m[4] !== undefined) a = m[4].slice(-1) === "%" ? parseFloat(m[4]) / 100 : parseFloat(m[4])
    return { r: r, g: g, b: b, a: Math.max(0, Math.min(1, a)) }
  }
  m = /^hsla?\(\s*(\d{1,3})(?:deg)?\s*[, ]\s*(\d{1,3})%\s*[, ]\s*(\d{1,3})%\s*(?:[,/]\s*(\d*\.?\d+%?)\s*)?\)$/i.exec(s)
  if (m) {
    var hh = (+m[1] % 360) / 360, ss = Math.min(+m[2], 100) / 100, ll = Math.min(+m[3], 100) / 100
    var q = ll < 0.5 ? ll * (1 + ss) : ll + ss - ll * ss, p = 2 * ll - q
    var f = function(t) {
      if (t < 0) t += 1
      if (t > 1) t -= 1
      if (t < 1 / 6) return p + (q - p) * 6 * t
      if (t < 1 / 2) return q
      if (t < 2 / 3) return p + (q - p) * (2 / 3 - t) * 6
      return p
    }
    var alpha = 1
    if (m[4] !== undefined) alpha = m[4].slice(-1) === "%" ? parseFloat(m[4]) / 100 : parseFloat(m[4])
    return { r: f(hh + 1 / 3) * 255, g: f(hh) * 255, b: f(hh - 1 / 3) * 255, a: Math.max(0, Math.min(1, alpha)) }
  }
  return null
}

var EMAIL_RE = /^[^\s@<>()\[\]\\,;:"]+@[A-Za-z0-9-]+(?:\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}$/

function looksLikeEmail(text) {
  var s = String(text || "")
  return s.length <= 254 && EMAIL_RE.test(s.trim())
}

function looksLikePath(text) {
  var s = String(text || "")
  if (s.length > 4096 || s.length < 2) return false
  s = s.trim()
  if (/[\n\r\0]/.test(s) || /^\/\//.test(s)) return false
  return /^(~\/|\/)[^\s].*$/.test(s) && s !== "/"
}

function expandHome(path, home) {
  var p = String(path || "").trim()
  return p.indexOf("~/") === 0 ? String(home || "") + p.slice(1) : p
}

// Parses small-enough JSON objects/arrays only; returns {structure,
// pretty} or null.
function parseJsonSummary(text) {
  var s = String(text || "")
  if (s.length > 200000) return null
  s = s.trim()
  var c = s.charAt(0)
  if (c !== "{" && c !== "[") return null
  try {
    var v = JSON.parse(s)
    var structure = Array.isArray(v)
      ? "Array, " + v.length + (v.length === 1 ? " item" : " items")
      : "Object, " + Object.keys(v).length + (Object.keys(v).length === 1 ? " key" : " keys")
    return { structure: structure, pretty: JSON.stringify(v, null, 2) }
  } catch (e) {
    return null
  }
}

function shannonEntropy(s) {
  var counts = {}
  for (var i = 0; i < s.length; i++) counts[s[i]] = (counts[s[i]] || 0) + 1
  var h = 0
  for (var k in counts) {
    var p = counts[k] / s.length
    h -= p * Math.log(p) / Math.LN2
  }
  return h
}

// Heuristic only -- known credential shapes, or a long single "word"
// of mixed-case alphanumerics with high entropy. Used to mask the
// preview, never to block anything.
function looksLikeSecret(text) {
  var s = String(text || "")
  if (s.length < 16 || s.length > 4096) return false
  var t = s.trim()
  if (/^-----BEGIN [A-Z ]*PRIVATE KEY-----/.test(t)) return true
  if (/\s/.test(t) || t.indexOf("/") !== -1 && t.indexOf("://") !== -1) return false
  if (/^(sk-[A-Za-z0-9_-]{16,}|gh[pousr]_[A-Za-z0-9]{20,}|github_pat_[A-Za-z0-9_]{20,}|xox[abprs]-[A-Za-z0-9-]{10,}|AKIA[0-9A-Z]{16}|AIza[0-9A-Za-z_-]{30,}|npm_[A-Za-z0-9]{30,})$/.test(t)) return true
  if (/^eyJ[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+\.[A-Za-z0-9_-]*$/.test(t)) return true
  if (t.length < 24 || t.length > 256) return false
  if (/^[0-9a-f]+$/i.test(t) || t.indexOf("@") !== -1 || t.indexOf("/") !== -1 || t.indexOf(".") !== -1) return false
  return /[a-z]/.test(t) && /[A-Z]/.test(t) && /[0-9]/.test(t) && shannonEntropy(t) >= 4
}

function linkFacts(text) {
  var s = String(text || "").trim()
  var m = /^(?:([a-z][a-z0-9+.-]*):\/\/)?([^\/?#\s]+)([^?#\s]*)(?:\?([^#\s]*))?/i.exec(s)
  if (!m) return []
  var facts = [{ label: "Host", value: m[2] }]
  if (m[1]) facts.push({ label: "Scheme", value: m[1].toLowerCase() })
  if (m[4]) facts.push({ label: "Parameters", value: String(m[4].split("&").filter(Boolean).length) })
  return facts
}

// Classifies a text clipboard entry. Returns the display fields; the
// entry's own `type` ("text"/"link") still decides how it is pasted.
function classifyText(text) {
  var plain = {
    subtype: "plain", type: "text", kind: "Text", icon: "\uf0f6", swatch: "",
    secret: false, facts: [], preview: ""
  }
  if (looksLikeSecret(text)) {
    return {
      subtype: "secret", type: "text", kind: "Secret", icon: "\uf023", swatch: "", secret: true,
      facts: [{ label: "Length", value: String(String(text).trim().length) }], preview: ""
    }
  }
  var color = parseColor(text)
  if (color) {
    var hex = "#" + hex2(color.r) + hex2(color.g) + hex2(color.b) + (color.a < 1 ? hex2(color.a * 255) : "")
    var facts = [
      { label: "Hex", value: hex.toUpperCase() },
      { label: "RGB", value: "rgb(" + Math.round(color.r) + ", " + Math.round(color.g) + ", " + Math.round(color.b) + ")" },
      { label: "HSL", value: hslFromRgb(color.r, color.g, color.b) }
    ]
    if (color.a < 1) facts.push({ label: "Alpha", value: Math.round(color.a * 100) + "%" })
    return {
      subtype: "color", type: "text", kind: "Color", icon: "\uf53f",
      swatch: "#" + hex2(color.a * 255) + hex2(color.r) + hex2(color.g) + hex2(color.b),
      secret: false, facts: facts, preview: ""
    }
  }
  if (looksLikeEmail(text)) {
    var addr = String(text).trim()
    var at = addr.lastIndexOf("@")
    return {
      subtype: "email", type: "text", kind: "Email", icon: "\uf0e0", swatch: "", secret: false,
      facts: [{ label: "Domain", value: addr.slice(at + 1).toLowerCase() }], preview: ""
    }
  }
  if (looksLikeLink(text)) {
    return {
      subtype: "link", type: "link", kind: "Link", icon: "\uf0c1", swatch: "", secret: false,
      facts: linkFacts(text), preview: ""
    }
  }
  var json = parseJsonSummary(text)
  if (json) {
    return {
      subtype: "json", type: "text", kind: "JSON", icon: "\uf121", swatch: "", secret: false,
      facts: [{ label: "Structure", value: json.structure }], preview: json.pretty
    }
  }
  if (looksLikePath(text)) {
    var p = String(text).trim()
    var base = p.replace(/\/+$/, "")
    var name = base.slice(base.lastIndexOf("/") + 1)
    var dot = name.lastIndexOf(".")
    var pf = [{ label: "Name", value: name || p }]
    if (dot > 0 && dot < name.length - 1) pf.push({ label: "Extension", value: name.slice(dot + 1).toLowerCase() })
    return {
      subtype: "path", type: "text", kind: "Path", icon: "\uf07b", swatch: "", secret: false,
      facts: pf, preview: ""
    }
  }
  var lines = String(text).slice(0, 200000).split("\n").length
  plain.facts = lines > 1 ? [{ label: "Lines", value: String(lines) }] : []
  return plain
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

function normalizeEntry(entry, index, qrByPath) {
  if (!entry || typeof entry !== "object") return null
  if (entry.type === "text" && typeof entry.text === "string") {
    var c = classifyText(entry.text)
    return {
      sourceIndex: index,
      type: c.type,
      subtype: c.subtype,
      text: entry.text,
      path: "",
      mime: "text/plain",
      capturedAt: entry.capturedAt || "",
      title: c.secret ? "Possible secret (" + String(entry.text).trim().length + " chars)" : summarizeText(entry.text),
      subtitle: entry.capturedAt || c.kind,
      icon: c.icon,
      kind: c.kind,
      swatch: c.swatch,
      secret: c.secret,
      facts: c.facts,
      preview: c.preview,
      // A masked secret must not be findable by searching its own text.
      searchBlob: ((c.secret ? "" : entry.text.slice(0, SEARCH_TEXT_LIMIT)) + "\n" + (entry.capturedAt || "") + "\n" + c.kind).toLowerCase()
    }
  }
  if (entry.type === "image" && typeof entry.path === "string") {
    var qr = String(entry.qr || (qrByPath && qrByPath[entry.path]) || "")
    return {
      sourceIndex: index,
      type: "image",
      text: "",
      path: entry.path,
      qr: qr,
      qrUrl: openableUrl(qr),
      mime: entry.mime || "image/png",
      capturedAt: entry.capturedAt || "",
      title: basename(entry.path) || "Image",
      subtitle: qr ? ("QR: " + summarizeText(qr)) : (entry.capturedAt || entry.mime || "Image"),
      icon: "\uf1c5",
      kind: "Image",
      subtype: "image",
      swatch: "",
      secret: false,
      facts: [],
      preview: "",
      searchBlob: (entry.path + "\n" + (entry.mime || "image/png") + "\n" + (entry.capturedAt || "") + "\nimage\n" + qr).toLowerCase()
    }
  }
  return null
}

function parseHistory(raw, qrByPath) {
  var parsed = []
  try {
    var data = JSON.parse(String(raw || "[]"))
    if (!Array.isArray(data)) return []
    for (var i = 0; i < data.length; i++) {
      var entry = normalizeEntry(data[i], i, qrByPath || {})
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

function qrPathsToProbe(entries, known, limit) {
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

function mergeQr(cache, fresh, maxEntries) {
  var out = {}
  var keys = Object.keys(cache || {})
  var freshKeys = Object.keys(fresh || {})
  var drop = Math.max(0, keys.length + freshKeys.length - maxEntries)
  for (var i = drop; i < keys.length; i++) out[keys[i]] = cache[keys[i]]
  for (var j = 0; j < freshKeys.length; j++) out[freshKeys[j]] = String(fresh[freshKeys[j]] || "")
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

var KIND_ORDER = ["Text", "Link", "Image", "Color", "Path", "Email", "JSON", "Secret"]

// Kinds actually present in the history, in a stable display order --
// the Type chip cycles through exactly these.
function kindsPresent(entries) {
  var seen = {}
  for (var i = 0; i < entries.length; i++) seen[entries[i].kind] = true
  return KIND_ORDER.filter(function(k) { return seen[k] })
}

// view: { kind: "" | one of KIND_ORDER, sort: "recent" | "type",
//         direction: "asc" | "desc" } -- "recent" asc is history order
// (newest first, as Omarchy stores it); desc reverses it. "type" groups
// by kind (in KIND_ORDER) and keeps history order within a group.
function visibleEntries(entries, query, view) {
  var kind = view && view.kind ? view.kind : ""
  var sort = view && view.sort ? view.sort : "recent"
  var desc = !!view && view.direction === "desc"
  var out = []
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (kind !== "" && e.kind !== kind) continue
    if (!matches(e, query)) continue
    out.push(e)
  }
  if (sort === "type") {
    out = out.map(function(e, n) { return { e: e, n: n } })
    out.sort(function(a, b) {
      var d = KIND_ORDER.indexOf(a.e.kind) - KIND_ORDER.indexOf(b.e.kind)
      if (d !== 0) return desc ? -d : d
      return a.n - b.n
    })
    out = out.map(function(x) { return x.e })
  } else if (desc) {
    out.reverse()
  }
  return out
}

function rows(entries, query, accent, dimensionsByPath, view) {
  var out = []
  var visible = visibleEntries(entries, query, view)
  var grouped = !!view && view.sort === "type"
  for (var i = 0; i < visible.length; i++) {
    var entry = visible[i]
    var label = entry.type === "image" ? imageLabel(entry, dimensionsByPath) : entry.title
    out.push({
      id: "clipboard:" + entry.sourceIndex,
      providerId: "clipboard-history",
      icon: entry.icon,
      iconColor: entry.swatch ? entry.swatch : (entry.type === "image" ? accent : undefined),
      label: label,
      breadcrumb: entry.subtitle,
      kind: entry.kind,
      providerName: "",
      sectionLabel: grouped ? entry.kind : "Clipboard",
      score: 0,
      clipboardEntry: entry
    })
  }
  return out
}
