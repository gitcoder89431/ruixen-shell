function summarizeText(text) {
  var s = String(text || "").replace(/\s+/g, " ").trim()
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

function looksLikeLink(text) {
  var s = String(text || "").trim()
  return /^https?:\/\/[^\s"'<>]+$/i.test(s)
    || /^[A-Za-z0-9][A-Za-z0-9.-]+\.[A-Za-z]{2,}(\/[^\s]*)?$/i.test(s)
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
      kind: isLink ? "Link" : "Text"
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
      kind: "Image"
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
  return String(entry.title || "").toLowerCase().indexOf(q) !== -1
    || String(entry.subtitle || "").toLowerCase().indexOf(q) !== -1
    || String(entry.mime || "").toLowerCase().indexOf(q) !== -1
    || String(entry.path || "").toLowerCase().indexOf(q) !== -1
    || String(entry.text || "").toLowerCase().indexOf(q) !== -1
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
