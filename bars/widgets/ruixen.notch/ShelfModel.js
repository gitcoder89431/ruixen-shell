// Pure helpers for the notch's own Shelf tab (5th dashboard tab,
// ShelfContent.qml) -- a drop pocket: drag files in, drag them back out
// into another app or terminal. Kept out of QML so the logic can be
// tested on its own, same pattern as KanbanModel.js.
//
// The shelf holds REFERENCES (absolute paths), never copies -- nothing
// is moved, duplicated or deleted on disk by adding or removing an
// item. A referenced file that later disappears just reads as missing.
//
// Agent-native, same as Kanban: every mutation is also reachable as an
// `omarchy-shell ruixen.notch shelf*` IPC function (see Overlay.qml), so
// an agent can read what you dropped (`shelfList`, then open the paths
// itself) and put files on the shelf for you to drag out (`shelfAdd`).
// Items added over IPC are tagged source "agent" so the panel can show
// who put them there. No MCP, no artifacts -- deliberately just paths.

var MAX_ITEMS = 200
var SOURCES = ["user", "agent"]
var IMAGE_EXTENSIONS = ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg", "avif"]

function isSource(value) {
  return SOURCES.indexOf(value) >= 0
}

// "file:///home/me/a%20b.txt" (or file://localhost/...) -> "/home/me/a b.txt".
// Anything that isn't a local file URL returns "".
function fileUrlToPath(url) {
  var s = String(url || "").trim()
  var m = /^file:\/\/(?:localhost)?(\/.*)$/i.exec(s)
  if (!m) return ""
  try {
    return decodeURIComponent(m[1])
  } catch (e) {
    return ""
  }
}

// Accepts an absolute path, a "~/" path (needs home), or a file URL.
// Returns a clean absolute path, or "" when it isn't acceptable: not
// absolute, the filesystem root, or containing characters that would
// break the one-path-per-line plumbing (NUL, newline, tab).
function normalizePath(raw, home) {
  var s = String(raw || "").trim()
  if (s === "") return ""
  if (/^file:/i.test(s)) s = fileUrlToPath(s)
  else if (s.indexOf("~/") === 0 && home) s = String(home).replace(/\/+$/, "") + s.slice(1)
  if (s.charAt(0) !== "/") return ""
  if (/[\0\n\r\t]/.test(s)) return ""
  s = s.replace(/\/{2,}/g, "/").replace(/\/+$/, "")
  return s === "" ? "" : s
}

function baseName(path) {
  var p = String(path || "")
  return p.slice(p.lastIndexOf("/") + 1) || p
}

function dirName(path) {
  var p = String(path || "")
  var idx = p.lastIndexOf("/")
  return idx <= 0 ? "/" : p.slice(0, idx)
}

function extension(path) {
  var name = baseName(path)
  var dot = name.lastIndexOf(".")
  return dot > 0 && dot < name.length - 1 ? name.slice(dot + 1).toLowerCase() : ""
}

function isImagePath(path) {
  return IMAGE_EXTENSIONS.indexOf(extension(path)) >= 0
}

// "file:///..." for one path, percent-encoding each segment (so spaces,
// #, ?, % etc. survive a text/uri-list round trip).
function uriFor(path) {
  return "file://" + String(path || "").split("/").map(encodeURIComponent).join("/")
}

// text/uri-list wants CRLF-separated URIs.
function uriList(paths) {
  return (paths || []).map(uriFor).join("\r\n")
}

// Unique-enough, sortable id; `taken` guards a same-millisecond burst
// (a multi-file drop) from colliding.
function makeId(now, taken) {
  var n = Math.floor(Number(now) || 0)
  var id = "s" + n.toString(36)
  var bump = 0
  while (taken[id]) {
    bump++
    id = "s" + n.toString(36) + "-" + bump
  }
  return id
}

// Validates a persisted list: drops malformed entries and duplicate
// paths (first wins), keeps newest-first order, caps at MAX_ITEMS.
function normalizeItems(raw, home) {
  var out = []
  var seenPath = {}
  var seenId = {}
  var list = Array.isArray(raw) ? raw : []
  for (var i = 0; i < list.length && out.length < MAX_ITEMS; i++) {
    var e = list[i]
    if (!e || typeof e !== "object") continue
    var path = normalizePath(e.path, home)
    if (path === "" || seenPath[path]) continue
    var id = typeof e.id === "string" && e.id !== "" && !seenId[e.id] ? e.id : makeId(Number(e.addedAt) || 0, seenId)
    seenPath[path] = true
    seenId[id] = true
    out.push({
      id: id,
      path: path,
      name: baseName(path),
      source: isSource(e.source) ? e.source : "user",
      addedAt: Number(e.addedAt) || 0
    })
  }
  return out
}

// Adds paths to the front (newest first). A path that's already on the
// shelf moves to the front instead of duplicating. Returns the new list
// plus which ids were added/refreshed and how many inputs were rejected.
function addPaths(items, paths, source, now, home) {
  var list = Array.isArray(items) ? items.slice() : []
  var src = isSource(source) ? source : "user"
  var taken = {}
  var byPath = {}
  for (var i = 0; i < list.length; i++) {
    taken[list[i].id] = true
    byPath[list[i].path] = list[i]
  }
  var added = []
  var rejected = 0
  var incoming = []
  var seenInBatch = {}
  var input = Array.isArray(paths) ? paths : []
  for (var j = 0; j < input.length; j++) {
    var p = normalizePath(input[j], home)
    if (p === "") { rejected++; continue }
    if (seenInBatch[p]) continue
    seenInBatch[p] = true
    var existing = byPath[p]
    if (existing) {
      list = list.filter(function(it) { return it.id !== existing.id })
      incoming.push(existing)
      added.push(existing.id)
    } else {
      var id = makeId(now, taken)
      taken[id] = true
      incoming.push({ id: id, path: p, name: baseName(p), source: src, addedAt: Number(now) || 0 })
      added.push(id)
    }
  }
  // Keep the batch's own order (first dropped = first listed).
  var merged = incoming.concat(list).slice(0, MAX_ITEMS)
  return { items: merged, added: added, rejected: rejected }
}

// Removes by id or by path; unknown values change nothing.
function removeItem(items, idOrPath, home) {
  var key = String(idOrPath || "")
  var asPath = normalizePath(key, home)
  return (items || []).filter(function(it) {
    return it.id !== key && (asPath === "" || it.path !== asPath)
  })
}

function clearItems() {
  return []
}

// `stat -L --printf='%n\t%F\t%s\t%Y\n'` output -> { path: {kind, size, mtime} }.
// kind: "folder" | "file" | "other". Paths that stat couldn't read are
// simply absent (the caller treats absent-after-a-stat as missing).
function parseStatOutput(text) {
  var out = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var parts = lines[i].split("\t")
    if (parts.length !== 4 || parts[0].charAt(0) !== "/") continue
    var type = parts[1].toLowerCase()
    out[parts[0]] = {
      kind: type === "directory" ? "folder" : type.indexOf("regular") === 0 ? "file" : "other",
      size: parseInt(parts[2], 10) || 0,
      mtime: parseInt(parts[3], 10) || 0
    }
  }
  return out
}

// What `shelfList` returns to an agent: everything it needs to decide
// what to open, nothing it has to guess. `stats` is the service's
// per-path cache; `checked` is the set of paths a completed stat pass
// has covered, so "exists": null honestly means "not checked yet"
// rather than "gone".
function listEntries(items, stats, checked) {
  return (items || []).map(function(it) {
    var st = stats ? stats[it.path] : undefined
    var exists = st ? true : (checked && checked[it.path] ? false : null)
    return {
      id: it.id,
      path: it.path,
      name: it.name,
      source: it.source,
      addedAt: it.addedAt,
      exists: exists,
      kind: st ? st.kind : (exists === false ? "missing" : "unknown"),
      size: st ? st.size : null
    }
  })
}

// One-line "2 files" style summary for the panel header.
function countLabel(n) {
  return n === 1 ? "1 item" : n + " items"
}
