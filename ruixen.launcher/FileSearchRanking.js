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
