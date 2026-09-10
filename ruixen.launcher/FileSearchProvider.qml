import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Provider: files by name under $HOME, via `fd` (confirmed on this
// machine per CLAUDE.md's own tool table -- a full $HOME search here
// takes ~8ms). fd's default match scope is the filename only, not the
// full path, which is exactly what a "search files by name" provider
// wants -- no extra filtering needed on our side beyond ranking what
// fd already returns.
//
// Unlike the other two providers, this one is ASYNCHRONOUS -- fd is a
// real subprocess, not a synchronous JS scan. search(query) is a PURE
// read of lastResults (whatever the last completed search found) --
// it does NOT trigger a new search itself. Query-change detection and
// the debounced re-search live in query/onQueryChanged instead: query
// is bound externally (Launcher.qml sets `query: root.query`, a plain
// declarative binding), and onQueryChanged -- a real signal handler,
// run after that binding settles -- is where the side effect
// (restarting the debounce timer) belongs. Doing that inside search()
// itself instead (a property WRITE as a side effect of evaluating
// Launcher.qml's own `results` binding) tripped a real "Binding loop
// detected for property results" warning, confirmed live -- QML
// doesn't like a binding's evaluation mutating state out from under
// itself. lastResults changing still makes `results` recompute
// automatically once fd's output lands, same as before -- that part
// was never the problem, only where the trigger-a-new-search side
// effect lived.
Item {
  id: root

  readonly property string providerName: "Files"
  readonly property bool ready: true

  // Set externally: Launcher.qml binds `fileSearchProvider.query: root.query`.
  property string query: ""
  // The query the currently-running (or most recently started) fd
  // process was launched for -- checked in onStreamFinished so a slow
  // response to an abandoned query can't clobber a newer one's results
  // (the debounce below makes this rare, not impossible).
  property string pendingQuery: ""
  property var lastResults: []

  readonly property string homeDir: Quickshell.env("HOME") || ""
  // Heavy, rarely-what-you-want directories worth skipping even though
  // they're not dotfiles -- fd already skips hidden dirs (.cache,
  // .git, .config, ...) by default, no flag needed for those.
  readonly property var excludeDirs: ["node_modules", "vendor", "target", "go/pkg/mod"]

  // Extra fd search roots for mounted secondary drives (an internal
  // HDD, a plugged-in USB stick, ...) -- auto-discovered rather than
  // hardcoded, since a mountpoint varies per machine and per drive.
  // Refreshed on demand (see refreshRoots() below), not on a timer --
  // Launcher.qml calls it once each time Search Files mode is entered,
  // which is a natural, low-frequency checkpoint for "did the set of
  // mounted drives change" without re-running findmnt on every keystroke.
  //
  // onExtraRootsChanged re-triggers a search the same way sourceFilter's
  // own handler below does, and for the same reason: refreshRoots() is
  // async (a real findmnt subprocess), so it commonly resolves AFTER a
  // query already finished being typed and searched -- confirmed live,
  // searching a query that only matches a file on a just-discovered USB
  // drive returned "No Results" because THIS handler didn't exist yet:
  // the search that ran used the still-empty extraRoots from before
  // refreshRoots() had a chance to respond, and nothing ever re-ran it
  // once the real roots came in.
  property var extraRoots: []
  onExtraRootsChanged: if (root.query.trim()) debounceTimer.restart()

  // Set externally (Launcher.qml's own source-filter dropdown): "" means
  // search every known root (Home + every extraRoot), same as before this
  // existed; a specific path restricts fd to just that one root. Changing
  // this needs to re-trigger a search the same way a query edit does --
  // see onSourceFilterChanged below -- since the query text itself may
  // not have changed at all when someone just switches the drive filter.
  property string sourceFilter: ""
  onSourceFilterChanged: if (root.query.trim()) debounceTimer.restart()

  // Populates the source-filter dropdown -- Home plus one entry per
  // discovered extraRoot, labelled by its own last path segment (a
  // mount's own volume-label folder name, e.g. "OMARCHY_202607") rather
  // than the full path, matching how a file manager's own sidebar
  // already labels a mounted drive.
  readonly property var sources: {
    var out = [{ id: root.homeDir, label: "Home", path: root.homeDir }]
    for (var i = 0; i < root.extraRoots.length; i++) {
      var p = root.extraRoots[i]
      var slash = p.lastIndexOf("/")
      out.push({ id: p, label: slash === -1 ? p : p.substring(slash + 1), path: p })
    }
    return out
  }

  function refreshRoots() {
    mountProc.running = true
  }

  Process {
    id: mountProc
    command: ["findmnt", "-P", "-o", "TARGET,FSTYPE"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // -P (key="value" pairs) rather than the plain columnar output
        // used elsewhere in this file -- a mount TARGET can contain
        // spaces (a USB drive labeled "My Files", say), which the
        // plain format has no safe way to split back apart.
        var re = /TARGET="([^"]*)" FSTYPE="([^"]*)"/
        var lines = text.split("\n")
        var roots = []
        for (var i = 0; i < lines.length; i++) {
          var m = re.exec(lines[i])
          if (!m) continue
          var target = m[1]
          // Convention every major desktop file manager already relies
          // on (Nautilus/udisks2 auto-mounts to /run/media/$USER/<label>,
          // manual mounts commonly go to /mnt or /media) -- real system
          // mounts (/, /boot, /var/*, tmpfs, proc, ...) never live under
          // any of these three prefixes, so this alone is enough to
          // exclude them without also needing an fstype allowlist.
          if (target.indexOf("/mnt/") === 0 || target.indexOf("/media/") === 0 || target.indexOf("/run/media/") === 0)
            roots.push(target)
        }
        root.extraRoots = roots
      }
    }
  }

  onQueryChanged: {
    var q = root.query.trim()
    if (!q) {
      debounceTimer.stop()
      root.lastResults = []
      return
    }
    debounceTimer.restart()
  }

  // Pure -- just reads lastResults, no side effects. The `query`
  // argument is accepted (matching every other provider's own
  // search(query) signature) but ignored in favor of root.query, which
  // is what actually drives onQueryChanged above; the two are the same
  // value by the time Launcher.qml's results binding calls this.
  function search(query) {
    return root.query.trim() ? root.lastResults : []
  }

  Timer {
    id: debounceTimer
    interval: 150
    repeat: false
    onTriggered: root.runSearch(root.query.trim())
  }

  // Final displayed cap, applied AFTER our own relevance sort in
  // onStreamFinished below -- see runSearch()'s own comment for why
  // that's a different number from fd's own --max-results.
  readonly property int displayLimit: 30

  function runSearch(query) {
    if (!root.homeDir) return
    root.pendingQuery = query
    // -t f -t d: files AND directories -- fd ORs multiple --type flags
    // together (confirmed live). fd prints a trailing "/" on directory
    // matches, which resultFor() below uses to tell them apart without
    // a separate stat() per result.
    //
    // fd's own --max-results is a raw CANDIDATE cap, not a relevance
    // cap -- fd fills it in directory-traversal order, with no idea
    // which matches score best. A tight cap here can silently drop a
    // highly relevant match before scoreFile() ever sees it: confirmed
    // live, searching "shell" with a 50-candidate cap never even
    // considered the real folder `dhh-shell` because 50 less-relevant
    // "shell"-matching files elsewhere filled the quota first. 500 is
    // a generous safety valve against a truly pathological one-
    // character query on a huge tree (a full unthrottled $HOME search
    // already takes ~8ms here), not a meaningful relevance filter --
    // the real cap is displayLimit, applied after sorting.
    var args = ["fd", "--type", "f", "--type", "d", "--ignore-case", "--max-results", "500"]
    for (var i = 0; i < root.excludeDirs.length; i++) args.push("--exclude", root.excludeDirs[i])
    // fd accepts multiple trailing path roots in one invocation --
    // confirmed via `fd --help` ([path]...) -- so every known root (or,
    // with sourceFilter set, just the one the dropdown picked) rides
    // along as positional args in the same call, not separate fd
    // processes to merge results from.
    args.push("--", query)
    if (root.sourceFilter) {
      args.push(root.sourceFilter)
    } else {
      args.push(root.homeDir)
      for (var i = 0; i < root.extraRoots.length; i++) args.push(root.extraRoots[i])
    }
    searchProc.command = args
    searchProc.running = true
  }

  // Exact filename match > prefix > substring elsewhere in the name --
  // same 0-10000 scale every other provider uses.
  //
  // dirBonus's history: a large bonus (5000) reliably surfaced a
  // substring match like `dhh-shell` above prefix-matching files for
  // "shell", but broke short queries badly -- back when Files/Folders
  // were merged into the same globally-sorted list as Applications/
  // Commands, searching "di" buried the real app "Discord" (scored
  // 9993 by AppSearch.js's own formula) under every folder that
  // trivially prefix-matches two characters. That risk is gone now
  // that Folders/Files only ever compete against EACH OTHER, inside
  // Search Files mode -- Applications/Commands live in a separate list
  // entirely (Launcher.qml's own "Results", never mixed with
  // filesystem matches at all). 2100 is calibrated to close the real
  // prefix-vs-substring gap this provider's own scoreFile() produces
  // (~2000-2050 between a short substring match and a short prefix
  // match), so a real directory hit like `dhh-shell` reliably outranks
  // prefix-matching files for "shell" again, without needing to worry
  // about Application/Command relevance at all in this view.
  readonly property int dirBonus: 2100

  function scoreFile(name, query, isDir) {
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
    return isDir ? base + root.dirBonus : base
  }

  // rawPath may carry fd's own trailing "/" marking a directory match --
  // stripped before use as the real name/breadcrumb/action path.
  function resultFor(rawPath, query) {
    var isDir = rawPath.length > 0 && rawPath.charAt(rawPath.length - 1) === "/"
    var path = isDir ? rawPath.substring(0, rawPath.length - 1) : rawPath
    var slash = path.lastIndexOf("/")
    var name = slash === -1 ? path : path.substring(slash + 1)
    var dir = slash === -1 ? "" : path.substring(0, slash)
    if (root.homeDir && dir.indexOf(root.homeDir) === 0) dir = "~" + dir.substring(root.homeDir.length)
    return {
      id: "file:" + path,
      providerId: "file-search",
      icon: isDir ? "" : "",
      label: name,
      breadcrumb: dir,
      kind: isDir ? "Folder" : "File",
      providerName: root.providerName,
      score: root.scoreFile(name, query, isDir),
      action: { type: "open", path: path }
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // A stale response for a query the user has already moved on
        // from -- drop it rather than overwriting newer (still
        // pending) results with old ones.
        if (root.pendingQuery !== root.query.trim()) return
        var q = root.pendingQuery
        var lines = text.split("\n").filter(function(l) { return l.length > 0 })
        var out = []
        for (var i = 0; i < lines.length; i++) out.push(root.resultFor(lines[i], q))
        // Sort by score BEFORE capping -- the whole point of raising
        // fd's own --max-results above is that truncation has to
        // happen after ranking, not before it (see runSearch()'s own
        // comment).
        out.sort(function(a, b) { return b.score - a.score })
        root.lastResults = out.slice(0, root.displayLimit)
      }
    }
  }

  // xdg-open already does the right thing for either path type -- the
  // default file manager for a directory (opens it in Nautilus/Files
  // here), the default app for a file -- so this doesn't need to
  // branch on kind. Opening a terminal cd'd into the folder instead
  // would need a real secondary-action mechanism this launcher doesn't
  // have yet (a modifier+Enter, a per-result action menu, ...) -- a
  // reasonable follow-up if wanted, not folded into the default Enter/
  // click behavior here.
  function activate(result) {
    Util.execArgv(["xdg-open", result.action.path])
  }

  // Details for the currently-selected row in Search Files mode --
  // fetched on demand for ONE path at a time (whichever is selected),
  // not for every result, since fd itself only ever returns paths, not
  // size/type/modified time. Launcher.qml calls this whenever its own
  // selectedResult changes while filesMode is on.
  property string pendingDetailsPath: ""
  property var selectedDetails: null

  // stat's own %F only distinguishes Unix-level kinds (regular file vs
  // directory vs symlink), never file FORMAT -- every plain file reports
  // as "regular file" regardless of whether it's Markdown or a JPEG.
  // fileKindFor() below derives the human-readable kind shown in the
  // details panel from the extension instead, same vocabulary a Finder-
  // style "Kind" column uses. Not exhaustive -- unknown extensions fall
  // back to "<EXT> File", and extensionless files to "Document".
  readonly property var extKindMap: ({
    md: "Markdown", markdown: "Markdown",
    json: "JSON", jsonc: "JSON",
    yaml: "YAML", yml: "YAML",
    toml: "TOML", ini: "INI Config", conf: "Config", cfg: "Config",
    js: "JavaScript", mjs: "JavaScript", cjs: "JavaScript",
    ts: "TypeScript", jsx: "JavaScript (JSX)", tsx: "TypeScript (JSX)",
    py: "Python", go: "Go", rs: "Rust", java: "Java", rb: "Ruby", php: "PHP",
    c: "C Source", h: "C Header", cpp: "C++ Source", cc: "C++ Source", hpp: "C++ Header",
    sh: "Shell Script", bash: "Shell Script", zsh: "Shell Script", fish: "Fish Script",
    qml: "QML", lua: "Lua", sql: "SQL",
    html: "HTML", htm: "HTML", css: "CSS", scss: "SCSS", less: "LESS", xml: "XML",
    txt: "Plain Text", log: "Log File", csv: "CSV",
    pdf: "PDF Document", doc: "Word Document", docx: "Word Document",
    xls: "Excel Spreadsheet", xlsx: "Excel Spreadsheet", ppt: "PowerPoint", pptx: "PowerPoint",
    png: "PNG Image", jpg: "JPEG Image", jpeg: "JPEG Image", gif: "GIF Image",
    svg: "SVG Image", webp: "WebP Image", bmp: "Bitmap Image",
    mp3: "Audio", wav: "Audio", flac: "Audio", ogg: "Audio",
    mp4: "Video", mkv: "Video", webm: "Video", mov: "Video", avi: "Video",
    zip: "Archive", tar: "Archive", gz: "Archive", xz: "Archive", "7z": "Archive", rar: "Archive"
  })

  function fileKindFor(path, statType) {
    // Non-regular-file kinds (directory, symbolic link, socket, ...)
    // pass through as-is -- only "regular file" is ambiguous enough to
    // need the extension lookup. "Folder" matches the rest of the UI's
    // own kind vocabulary (resultFor() above already says "Folder", not
    // "directory") rather than echoing stat's raw wording.
    if (statType === "directory") return "Folder"
    if (statType !== "regular file") return statType.charAt(0).toUpperCase() + statType.slice(1)
    var name = path.substring(path.lastIndexOf("/") + 1)
    var dot = name.lastIndexOf(".")
    if (dot <= 0) return "Document"
    var ext = name.substring(dot + 1).toLowerCase()
    return root.extKindMap[ext] || (ext.toUpperCase() + " File")
  }

  // Video formats get a duration lookup alongside the stat() call below
  // (see ffprobeProc) -- ffprobe confirmed present on this machine as a
  // dependency of core Omarchy-adjacent packages (mpv, gpu-screen-
  // recorder, obs-studio, qt6-multimedia-ffmpeg), not something
  // specific to this dev setup. Checked by extension directly rather
  // than waiting on stat's own fileKindFor() result, so both run in
  // parallel instead of one gating the other.
  readonly property var videoExtensions: ["mp4", "mkv", "webm", "mov", "avi"]
  function isVideoPath(path) {
    var dot = path.lastIndexOf(".")
    if (dot <= 0) return false
    return root.videoExtensions.indexOf(path.substring(dot + 1).toLowerCase()) !== -1
  }

  property string pendingVideoPath: ""
  property string videoDuration: ""

  function loadDetails(path) {
    root.pendingDetailsPath = path
    root.selectedDetails = null
    root.pendingVideoPath = ""
    root.videoDuration = ""
    if (!path) return
    // %W added for a "Created" field -- confirmed live this returns a
    // real, non-zero birth time on this machine's own btrfs root, not
    // just the "0 = unsupported" fallback GNU stat's own docs warn
    // about for filesystems that don't track it. Field order shifted
    // (%W now sits between %Y and %F), so onStreamFinished's own
    // parts.slice() index for reassembling a pathological "|"-
    // containing filename moves from 4 to 5 accordingly.
    statProc.command = ["stat", "--format=%s|%Y|%W|%F|%A|%n", "--", path]
    statProc.running = true
    if (root.isVideoPath(path)) {
      root.pendingVideoPath = path
      ffprobeProc.command = ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", "--", path]
      ffprobeProc.running = true
    }
  }

  Process {
    id: statProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = text.trim().split("|")
        if (parts.length < 6) return
        // %n (the path) is last and may itself contain "|" in a
        // pathological filename -- rejoin everything after the first
        // 5 fields rather than assuming exactly 6 parts.
        var path = parts.slice(5).join("|")
        // A slower stat() for a path the user has already navigated
        // away from -- drop it rather than showing stale details for
        // the wrong row (same staleness guard runSearch() already
        // uses for search results).
        if (path !== root.pendingDetailsPath) return
        root.selectedDetails = {
          size: parseInt(parts[0], 10) || 0,
          mtime: parseInt(parts[1], 10) || 0,
          // 0 means this filesystem doesn't track birth time at all --
          // Launcher.qml's own Repeater model only shows "Created" when
          // this is truthy, rather than showing a bogus 1970 date.
          created: parseInt(parts[2], 10) || 0,
          type: root.fileKindFor(path, parts[3]),
          permissions: parts[4]
        }
      }
    }
  }

  // Duration for video files -- see isVideoPath() above for why this is
  // a separate, parallel lookup rather than gated behind statProc's own
  // result.
  Process {
    id: ffprobeProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.pendingVideoPath === "" || root.pendingVideoPath !== root.pendingDetailsPath) return
        var seconds = parseFloat(text.trim())
        if (isNaN(seconds) || seconds <= 0) return
        var total = Math.round(seconds)
        var h = Math.floor(total / 3600)
        var m = Math.floor((total % 3600) / 60)
        var s = total % 60
        var pad = function(n) { return n < 10 ? "0" + n : "" + n }
        root.videoDuration = h > 0 ? (h + ":" + pad(m) + ":" + pad(s)) : (m + ":" + pad(s))
      }
    }
  }
}
