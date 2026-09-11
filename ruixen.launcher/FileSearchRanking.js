// Issue #52: pure ranking/path-parsing logic pulled out of
// FileSearchProvider.qml so it's actually unit-testable -- a .qml file
// can't be loaded by this repo's own plain-JS test harness (it isn't
// valid standalone JS: `import QtQuick`, `Item { ... }` object syntax),
// the same reason OmarchyMenuParser.js/AppSearch.js already exist as
// separate modules instead of living inline in their own owning .qml
// files. FileSearchProvider.qml imports this module and calls straight
// through -- no behavior change, just relocated.

// Exact filename match > prefix > substring elsewhere in the name --
// same 0-10000 scale every other provider uses. dirBonus is passed in
// (not hardcoded here) since FileSearchProvider.qml's own dirBonus is a
// tunable property with its own real history documented there.
function scoreFile(name, query, isDir, dirBonus) {
  var q = String(query || "").toLowerCase()
  var n = String(name || "").toLowerCase()
  var base
  if (n === q) base = 10000
  else {
    var idx = n.indexOf(q)
    if (idx === 0) base = 9000 - n.length
    else if (idx > 0) base = 7000 - idx * 10 - n.length
    else base = 5000 - n.length
  }
  return isDir ? base + (dirBonus || 0) : base
}

// Issue #60: extension -> category table for the Search Files type
// filter -- deliberately extension-based, not a per-candidate stat/MIME
// subprocess (issue's own guidance: "do not stat/MIME-probe hundreds of
// candidates merely to decide category"). Grouped to match
// FileSearchProvider.qml's own extKindMap (the details-panel "Type"
// field) so the same file always reads as the same kind of thing in
// both places -- e.g. anything extKindMap calls an "Image" lands in
// the Images category here too.
var FILE_CATEGORIES = {
  Documents: ["md", "markdown", "txt", "pdf", "doc", "docx", "xls", "xlsx", "ppt", "pptx"],
  Images: ["png", "jpg", "jpeg", "gif", "svg", "webp", "bmp"],
  Video: ["mp4", "mkv", "webm", "mov", "avi"],
  Audio: ["mp3", "wav", "flac", "ogg"],
  Archives: ["zip", "tar", "gz", "xz", "7z", "rar"],
  "Code/Text": [
    "json", "jsonc", "yaml", "yml", "toml", "ini", "conf", "cfg",
    "js", "mjs", "cjs", "ts", "jsx", "tsx", "py", "go", "rs", "java", "rb", "php",
    "c", "h", "cpp", "cc", "hpp", "sh", "bash", "zsh", "fish", "qml", "lua", "sql",
    "html", "htm", "css", "scss", "less", "xml", "log", "csv"
  ]
}

// The ordered list of real, selectable categories -- "All" isn't in
// here (it's the absence of a filter, handled by matchesCategory
// below), and "Other" (an extensionless file, or an extension none of
// the tables above recognize) is a real possible classification but
// deliberately not offered as its own filter option, per the issue's
// own suggested category list.
var FILE_CATEGORY_NAMES = ["Folders", "Documents", "Images", "Video", "Audio", "Archives", "Code/Text"]

// A directory is always "Folders" regardless of name -- everything
// else is classified by extension, falling back to "Other" for an
// extensionless file or an extension none of the tables above lists.
function categoryForPath(name, isDir) {
  if (isDir) return "Folders"
  var dot = String(name || "").lastIndexOf(".")
  if (dot <= 0) return "Other"
  var ext = name.substring(dot + 1).toLowerCase()
  for (var cat in FILE_CATEGORIES) {
    if (FILE_CATEGORIES[cat].indexOf(ext) !== -1) return cat
  }
  return "Other"
}

// "All" (the default, no filter) always matches; any other filter
// value requires an exact category match.
function matchesCategory(category, filterCategory) {
  return !filterCategory || filterCategory === "All" || category === filterCategory
}

// Issue #63: a real accessor function for FILE_CATEGORY_NAMES -- a
// plain top-level `var` isn't reliably exposed through QML's own JS
// import semantics the same way a function declaration is, so
// LauncherQueryOperators.js's own resolveCategoryOperator (called from
// Launcher.qml) goes through this instead of reading the var directly.
function fileCategoryNames() {
  return FILE_CATEGORY_NAMES
}

// Issue #59: splits a query into literal terms for multi-component
// matching -- plain whitespace tokenization (no shell-style quoting).
// Every term stays a literal, fixed-string fragment; this function only
// ever produces MORE, narrower literal strings from the original query
// text, never a regex or a reinterpretation of it.
function tokenizeQuery(query) {
  return String(query || "").trim().split(/\s+/).filter(function(t) { return t.length > 0 })
}

// The single term handed to fd as its own bounded --full-path
// --fixed-strings candidate filter (issue #59's own recommended
// strategy) -- keeps candidate generation to exactly one fd process per
// root regardless of how many terms the query has, rather than a
// separate fd invocation per term or (far worse) `fd .` over the whole
// tree with everything fuzzy-filtered in JS. The LONGEST term is the
// cheapest available proxy for "most selective" without doing real
// frequency analysis against the filesystem. Ties keep the FIRST
// (leftmost) of the equally-long terms, for determinism. Empty input
// returns "" rather than throwing -- callers only ever reach this with
// a non-empty query, but it's a plain string op either way.
function primaryCandidateTerm(terms) {
  if (!terms || terms.length === 0) return ""
  var best = terms[0]
  for (var i = 1; i < terms.length; i++) {
    if (terms[i].length > best.length) best = terms[i]
  }
  return best
}

// Issue #59: does every term appear SOMEWHERE in the full path
// (case-insensitively)? fd's own --full-path candidate generation
// already guarantees this for the single PRIMARY term (see
// primaryCandidateTerm above) -- this is what catches the OTHER terms,
// which fd never checked at all. Plain string checks against paths fd
// already returned, not a second filesystem walk -- called once per
// candidate, not once per directory entry.
function pathSatisfiesAllTerms(fullPath, terms) {
  var lower = String(fullPath || "").toLowerCase()
  for (var i = 0; i < terms.length; i++) {
    if (lower.indexOf(terms[i].toLowerCase()) === -1) return false
  }
  return true
}

// rawPath may carry fd's own trailing "/" marking a directory match --
// stripped before use as the real name/breadcrumb/action path. Returns
// the plain path split into its parts; homeDir abbreviation (the `~`
// substitution) is applied separately by abbreviateHome() below, since
// it needs the caller's own homeDir value.
function parseRawPath(rawPath) {
  var isDir = rawPath.length > 0 && rawPath.charAt(rawPath.length - 1) === "/"
  var path = isDir ? rawPath.substring(0, rawPath.length - 1) : rawPath
  var slash = path.lastIndexOf("/")
  var name = slash === -1 ? path : path.substring(slash + 1)
  var dir = slash === -1 ? "" : path.substring(0, slash)
  return { isDir: isDir, path: path, name: name, dir: dir }
}

// Same convention FileSearchProvider.qml's own breadcrumb/Where field
// already used before this extraction -- "/home/dev/notes" under
// homeDir "/home/dev" reads as "~/notes".
function abbreviateHome(dir, homeDir) {
  if (homeDir && dir.indexOf(homeDir) === 0) return "~" + dir.substring(homeDir.length)
  return dir
}

// Issue #56: extracts real pixel dimensions from `file`'s own plain-text
// output -- a header parse, not a decode (confirmed live: instant even
// on an 8000x6000 test JPEG), used instead of reading them off the
// displayed preview Image's own sourceSize once that gets bounded to
// the small preview box for the actual fix this issue is about.
//
// Takes the LAST "NxN"-shaped match, not the first -- caught live
// against a real JPEG sample: file(1)'s own JPEG output is "..., density
// 1x1, ..., precision 8, 8000x6000, components 3" -- the density field
// (usually a placeholder like "1x1") reliably comes BEFORE the real
// pixel dimensions in that format's own output, so a first-match regex
// grabbed "1 × 1" instead of "8000 × 6000". PNG/GIF/WebP/BMP each only
// ever produce one such match regardless (BMP's own trailing bit-depth
// number, e.g. "800 x 600 x 24", isn't itself of the "N x N" shape once
// the first pair is consumed), so taking the last match is a no-op
// difference for those and the fix that matters for JPEG.
function parseFileDimensions(fileOutput) {
  var re = /(\d+)\s*x\s*(\d+)/gi
  var m
  var last = null
  while ((m = re.exec(String(fileOutput || ""))) !== null) last = m
  return last ? (last[1] + " × " + last[2]) : ""
}

// Issue #53: findmnt's own fstype classifies a discovered root as local
// (safe to content-scan automatically) or remote/network-backed (opened
// per-file, over a network, only when a search deliberately walks its
// content -- a much riskier default than a filename listing, and the
// exact shape of the real rclone report that motivated the earlier
// timeout work). A conservative ALLOWLIST, not a denylist -- an
// unrecognized/exotic fstype defaults to "remote" (excluded from
// automatic content search) rather than risking treating something
// unknown as safe, per this issue's own "prefer a conservative policy"
// guidance.
//
// "fuseblk" (not bare "fuse") specifically denotes a FUSE filesystem
// backed by a real local block device -- ntfs-3g, exfat-fuse, hfsplus
// support -- the one FUSE shape that's genuinely local. Every OTHER
// fuse.* (fuse.rclone, fuse.sshfs, fuse.gvfsd-fuse, ...) stays excluded
// by default: it's typically network/remote-backed and there's no
// reliable way to tell from the fstype string alone, exactly the
// ambiguity this issue warns about.
var LOCAL_FSTYPES = [
  "ext2", "ext3", "ext4", "btrfs", "xfs", "f2fs", "reiserfs", "jfs", "zfs",
  "vfat", "exfat", "ntfs", "ntfs3", "fuseblk", "iso9660", "udf"
]

function isLocalFstype(fstype) {
  return LOCAL_FSTYPES.indexOf(String(fstype || "").toLowerCase()) !== -1
}

// Issue #54: merges per-root result arrays (keyed by root path) into
// one ranked, deduped list -- called after every individual root's own
// completion (not just once at the very end), which is what actually
// lets a fast root's results appear before a slower one still in
// flight finishes, rather than the whole "All Sources" result set being
// coupled to whichever root is slowest. Dedupes by the result's own
// real path -- a nested/bind mount could in principle surface the same
// file under two different discovered roots. Sort happens BEFORE
// capping to displayLimit, same reasoning as fd's own generous
// --max-results per root: truncation has to happen after ranking, not
// before it.
function mergeRootResults(rootResultsByPath, displayLimit) {
  var merged = []
  var seen = ({})
  for (var rootPath in rootResultsByPath) {
    var items = rootResultsByPath[rootPath]
    for (var i = 0; i < items.length; i++) {
      var key = items[i].action.path
      if (seen[key]) continue
      seen[key] = true
      merged.push(items[i])
    }
  }
  merged.sort(function(a, b) { return b.score - a.score })
  return merged.slice(0, displayLimit)
}

// Issue #52: findmnt's own tree walked recursively into a flat list --
// children reflect mount hierarchy (a bind mount under another mount,
// etc.), not something this provider needs to preserve, just enumerate.
// Pulled out of FileSearchProvider.qml alongside discoverExtraRoots
// below for the same reason every other pure-logic extraction in this
// file exists: independently testable without a real Quickshell
// runtime.
function flattenMountTree(node, out) {
  if (node && typeof node.target === "string") out.push({ path: node.target, fstype: String(node.fstype || "") })
  if (node && Array.isArray(node.children)) {
    for (var i = 0; i < node.children.length; i++) flattenMountTree(node.children[i], out)
  }
}

// Convention every major desktop file manager already relies on
// (Nautilus/udisks2 auto-mounts to /run/media/$USER/<label>, manual
// mounts commonly go to /mnt or /media) -- real system mounts (/,
// /boot, /var/*, tmpfs, proc, ...) never live under any of these three
// prefixes, so a path check alone is enough to tell "a real extra root
// worth offering at all" from noise -- a SEPARATE question from
// local-vs-remote (issue #53), which isLocalFstype() above answers
// downstream from the fstype kept alongside each root.
function isMountCandidate(path) {
  return path.indexOf("/mnt/") === 0 || path.indexOf("/media/") === 0 || path.indexOf("/run/media/") === 0
}

// Issue #48/#52: the full findmnt --json -> extraRoots pipeline, pulled
// out of FileSearchProvider.qml's own onStreamFinished so it's testable
// without a real findmnt process or Quickshell runtime. --json
// sidesteps findmnt's own `-P` hex-escaping of unsafe characters
// entirely (findmnt(8): "All potentially unsafe value characters are
// hex-escaped (\xNN)") -- a real mount like "/mnt/Google Drive" used to
// come back from the old regex-based `-P` parser as
// "/mnt/Google\x20Drive" and get searched as a path that doesn't exist.
// JSON's own string escaping is unambiguous and QML/Node's JSON.parse
// already handles it correctly, so there's no hand-rolled escape format
// to keep in sync with findmnt's own. Malformed/empty JSON returns an
// empty list rather than throwing -- a transient findmnt failure should
// leave extraRoots as "nothing extra found," not crash the provider.
function discoverExtraRoots(findmntJsonText) {
  var targets = []
  try {
    var data = JSON.parse(findmntJsonText)
    var top = (data && Array.isArray(data.filesystems)) ? data.filesystems : []
    for (var i = 0; i < top.length; i++) flattenMountTree(top[i], targets)
  } catch (e) {
    return []
  }
  var seen = ({})
  var roots = []
  for (var j = 0; j < targets.length; j++) {
    var target = targets[j].path
    // Dedup -- a bind mount or a submount nested under an already-
    // discovered root would otherwise search the same files twice and
    // show duplicate rows for them.
    if (isMountCandidate(target) && !seen[target]) {
      seen[target] = true
      roots.push({ path: target, fstype: targets[j].fstype })
    }
  }
  return roots
}

// Issue #55: fd's own exit code convention (confirmed live): 0 whether
// or not anything matched -- zero matches is NOT an error for fd,
// unlike ripgrep's own different convention (see
// ContentSearchRanking.js's own classifyRgExitCode). `timeout <n> fd
// ...` passes fd's own real exit code through when it completes in
// time, and returns 124 itself only when IT had to kill fd -- confirmed
// live. Anything else non-zero is fd's own real failure for that
// specific root (a bad/vanished path, most commonly a root that
// unmounted mid-search).
function classifyFdExitCode(exitCode) {
  if (exitCode === 0) return "success"
  if (exitCode === 124) return "timeout"
  return "error"
}
