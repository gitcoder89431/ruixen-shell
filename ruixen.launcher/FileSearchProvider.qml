import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "FileSearchRanking.js" as FileSearchRanking

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
  // Issue #48/#46: query text alone isn't a complete search identity --
  // switching sourceFilter or having extraRoots change underneath an
  // in-flight search are both real ways the CURRENT desired result set
  // can change without the query string itself changing at all.
  // rootGeneration bumps every time extraRoots is reassigned (below),
  // and feeds into searchIdentity()'s own composite key alongside query
  // and sourceFilter, so runSearch()'s staleness guard can catch every
  // one of these cases with the same single check instead of three
  // separate ad hoc ones.
  property int rootGeneration: 0
  onExtraRootsChanged: {
    root.rootGeneration++
    if (root.query.trim()) debounceTimer.restart()
  }

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
      var p = root.extraRoots[i].path
      var slash = p.lastIndexOf("/")
      out.push({ id: p, label: slash === -1 ? p : p.substring(slash + 1), path: p })
    }
    return out
  }

  function refreshRoots() {
    mountProc.exec(["findmnt", "--json", "-o", "TARGET,FSTYPE"])
  }

  // findmnt's own tree walked recursively into a flat list -- children
  // reflect mount hierarchy (a bind mount under another mount, etc.),
  // not something this provider needs to preserve, just enumerate.
  // Issue #53: fstype kept alongside each target now (previously
  // discarded down to a bare path) -- needed to classify a root as
  // local vs remote/network-backed, see FileSearchRanking.js's own
  // isLocalFstype().
  function flattenMounts(node, out) {
    if (node && typeof node.target === "string") out.push({ path: node.target, fstype: String(node.fstype || "") })
    if (node && Array.isArray(node.children)) {
      for (var i = 0; i < node.children.length; i++) root.flattenMounts(node.children[i], out)
    }
  }

  Process {
    id: mountProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // Issue #48: findmnt's own `-P` (key="value" pairs) format hex-
        // escapes unsafe characters (findmnt(8): "All potentially unsafe
        // value characters are hex-escaped (\xNN)"), and the previous
        // regex parser stored that escaped form verbatim -- a real mount
        // like "/mnt/Google Drive" would come back as "/mnt/Google\x20Drive"
        // and get searched as a path that doesn't exist. --json sidesteps
        // decoding entirely: JSON's own string escaping is unambiguous
        // and QML's JSON.parse already handles it correctly, so there's
        // no hand-rolled escape format to keep in sync with findmnt's own.
        var targets = []
        try {
          var data = JSON.parse(text)
          var top = (data && Array.isArray(data.filesystems)) ? data.filesystems : []
          for (var i = 0; i < top.length; i++) root.flattenMounts(top[i], targets)
        } catch (e) {
          return
        }
        var seen = ({})
        var roots = []
        for (var j = 0; j < targets.length; j++) {
          var target = targets[j].path
          // Convention every major desktop file manager already relies
          // on (Nautilus/udisks2 auto-mounts to /run/media/$USER/<label>,
          // manual mounts commonly go to /mnt or /media) -- real system
          // mounts (/, /boot, /var/*, tmpfs, proc, ...) never live under
          // any of these three prefixes, so a path check alone is enough
          // to tell "a real extra root worth offering at all" from noise
          // -- a SEPARATE question from local-vs-remote (issue #53),
          // which FileSearchRanking.js's own isLocalFstype() answers
          // downstream from the fstype kept alongside each root below.
          var isCandidate = target.indexOf("/mnt/") === 0 || target.indexOf("/media/") === 0 || target.indexOf("/run/media/") === 0
          // Dedup -- a bind mount or a submount nested under an already-
          // discovered root would otherwise search the same files twice
          // and show duplicate rows for them.
          if (isCandidate && !seen[target]) {
            seen[target] = true
            roots.push({ path: target, fstype: targets[j].fstype })
          }
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
      // Issue #49: actually stop in-flight work, not just stop caring
      // about its result -- a query cleared (or Search Files left, via
      // Launcher.qml gating this provider's own query to "") while fd is
      // still walking a slow/unready mount would otherwise keep running
      // for up to the full timeout for no reason. Safe even if nothing
      // is running (confirmed live: setting running=false on an idle
      // Process is a no-op, not an error).
      searchProc.running = false
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

  // Issue #46: a query string alone is not a complete search identity --
  // sourceFilter or the discovered root set can each change without the
  // query text itself changing (switching the source dropdown, a drive
  // mounting mid-search), and either one changing means an in-flight
  // search's eventual result no longer belongs to what the UI currently
  // wants. Snapshotting this into pendingSearchIdentity at launch and
  // re-deriving it fresh from the same three LIVE properties at
  // completion time (searchProc's own onStreamFinished) is the same
  // frozen-snapshot-vs-live-recompute pattern this file already used for
  // pendingQuery, just extended to cover all three identity-defining
  // inputs instead of one.
  function searchIdentity() {
    return root.query.trim() + "" + root.sourceFilter + "" + root.rootGeneration
  }

  property string pendingSearchIdentity: ""

  function runSearch(query) {
    if (!root.homeDir) return
    root.pendingQuery = query
    root.pendingSearchIdentity = root.searchIdentity()
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
    // --fixed-strings -- issue #47: fd treats the pattern as a regex by
    // default, which disagrees with this provider's own literal-
    // substring ranking (scoreFile below) and silently mishandles
    // ordinary filenames containing regex metacharacters (e.g.
    // "file[1]", "hello.world", "C++"). Forcing literal matching makes
    // fd's own interpretation of the query match what the UI already
    // promises.
    var args = ["fd", "--type", "f", "--type", "d", "--ignore-case", "--fixed-strings", "--max-results", "500"]
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
      // Issue #53: filename/folder search walks EVERY discovered root
      // regardless of local vs remote -- only automatic CONTENT search
      // (FileContentSearchProvider's own runSearch) excludes remote
      // roots by default, since a plain listing is comparatively
      // lightweight even over a network mount (unlike recursively
      // opening file contents).
      for (var i = 0; i < root.extraRoots.length; i++) args.push(root.extraRoots[i].path)
    }
    // Real report: search "stopped working" right after a reboot, for
    // someone with a network mount (rclone) among their own extraRoots,
    // and fixed itself after waiting -- exactly the shape of a FUSE
    // mount that's still establishing its remote connection (auth
    // refresh, first network round-trip) right after boot. fd walks
    // every root in ONE invocation (see this function's own comment
    // above), so a single slow/unready mount stalls results for every
    // OTHER root too, including plain local $HOME files that have
    // nothing to do with it. `timeout` bounds that: whatever fd already
    // found on the fast roots before the slow one stalled it still
    // reaches searchProc's own stdout (a killed process's already-
    // written output isn't lost), so a stuck network mount degrades a
    // search instead of hanging it outright. Not an absolute guarantee
    // -- a syscall truly stuck in D-state (uninterruptible sleep, e.g.
    // the kernel itself still waiting on FUSE) can't be killed by
    // SIGTERM until it returns on its own -- but that's a rarer failure
    // shape than "the mount just needs a few more seconds," which this
    // does fix.
    // Issue #46: .exec() (not command=...;running=true) -- reassigning
    // `command` while `running` is already true and then setting
    // `running` to the SAME value it already holds is a no-op in QML
    // (equal-value property writes don't re-trigger anything), so a
    // query typed faster than the previous fd run completes would
    // silently never actually start a new process, leaving the old
    // query's own run to finish on its own. Confirmed directly (a
    // standalone Quickshell harness): calling .exec() while a process is
    // already running kills it (SIGTERM) and starts the new command
    // immediately, and the killed process's own already-written stdout
    // still reaches its StdioCollector rather than being lost -- exactly
    // "last action wins" instead of "first action wins by accident."
    searchProc.exec(["timeout", "3"].concat(args))
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
    return FileSearchRanking.scoreFile(name, query, isDir, root.dirBonus)
  }

  // rawPath may carry fd's own trailing "/" marking a directory match --
  // stripped before use as the real name/breadcrumb/action path.
  function resultFor(rawPath, query) {
    var parsed = FileSearchRanking.parseRawPath(rawPath)
    var dir = FileSearchRanking.abbreviateHome(parsed.dir, root.homeDir)
    return {
      id: "file:" + parsed.path,
      providerId: "file-search",
      icon: parsed.isDir ? "" : "",
      label: parsed.name,
      breadcrumb: dir,
      kind: parsed.isDir ? "Folder" : "File",
      providerName: root.providerName,
      score: root.scoreFile(parsed.name, query, parsed.isDir),
      action: { type: "open", path: parsed.path }
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // A stale response for a search identity (query + sourceFilter +
        // root generation) the UI has already moved on from -- drop it
        // rather than overwriting newer (still pending) results with old
        // ones. See searchIdentity()'s own comment for why this checks
        // more than just the query string.
        if (root.pendingSearchIdentity !== root.searchIdentity()) return
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

  // Video poster (a real extracted still frame, not a generic icon) --
  // exact same technique ruixen.notch's own wallpaper picker already
  // uses for its .mp4 wallpaper tiles (list-wallpapers.sh / Service.qml,
  // both independently duplicate this same three-step recipe rather
  // than sharing it, "so both sides agree on the same cache file with
  // neither one telling the other its path" -- same reasoning applies
  // here, a third independent call site). Cached at the SAME path
  // ruixen.notch uses (keyed only by an md5 of the file path, not which
  // plugin asked for it), so a video already thumbnailed once in the
  // wallpaper picker loads here instantly with no re-encode, and vice
  // versa.
  readonly property string posterCacheDir: (root.homeDir || "") + "/.cache/ruixen/wallpaper-posters"
  property string pendingVideoPosterPath: ""
  property string videoPosterPath: ""

  // Text preview -- fills the same fixed preview footprint an image/
  // video thumbnail uses, but with the file's own leading content
  // instead. Explicit extension allowlist (not "anything that isn't
  // an image/video"), same reasoning as videoExtensions above -- a
  // wrongly-guessed binary file read as text would render as garbage,
  // not crash, but there's no reason to risk it when the real set of
  // "this is source/config/prose" extensions is easy to just list.
  // head -c (not the whole file) keeps this flat-cost regardless of
  // file size -- a multi-GB log matching by name costs the exact same
  // few KB read as a one-line README, since head stops as soon as it
  // has enough bytes rather than reading to EOF first.
  readonly property var textExtensions: [
    "md", "markdown", "json", "jsonc", "yaml", "yml", "toml", "ini", "conf", "cfg",
    "js", "mjs", "cjs", "ts", "jsx", "tsx", "py", "go", "rs", "java", "rb", "php",
    "c", "h", "cpp", "cc", "hpp", "sh", "bash", "zsh", "fish", "qml", "lua", "sql",
    "html", "htm", "css", "scss", "less", "xml", "txt", "log", "csv"
  ]
  function isTextPath(path) {
    var dot = path.lastIndexOf(".")
    if (dot <= 0) return false
    return root.textExtensions.indexOf(path.substring(dot + 1).toLowerCase()) !== -1
  }

  property string pendingTextPreviewPath: ""
  property string textPreviewContent: ""

  function loadDetails(path) {
    root.pendingDetailsPath = path
    root.selectedDetails = null
    root.pendingVideoPath = ""
    root.videoDuration = ""
    root.pendingVideoPosterPath = ""
    root.videoPosterPath = ""
    root.pendingTextPreviewPath = ""
    root.textPreviewContent = ""
    // Issue #46: stop whatever ffprobe/poster/text-preview work was
    // still running for the PREVIOUS selection outright, not just
    // disown its eventual result -- the pending-path resets above
    // already make a late completion harmless (it can't match the new
    // path), but there's no reason to let a video's ffmpeg poster
    // extraction keep burning CPU for a row that isn't even selected
    // anymore. Safe when already idle (confirmed directly: running=false
    // on an idle Process is a no-op).
    ffprobeProc.running = false
    posterProc.running = false
    textPreviewProc.running = false
    if (!path) return
    if (root.isTextPath(path)) {
      root.pendingTextPreviewPath = path
      // ~4000 bytes -- comfortably more than the fixed preview pane can
      // ever actually display (well past a screenful of wrapped lines
      // at the preview's own font size), so it never needs to be tuned
      // per-file; the pane's own clip does the rest, no scrolling.
      textPreviewProc.exec(["head", "-c", "4000", "--", path])
    }
    // %W added for a "Created" field -- confirmed live this returns a
    // real, non-zero birth time on this machine's own btrfs root, not
    // just the "0 = unsupported" fallback GNU stat's own docs warn
    // about for filesystems that don't track it. Field order shifted
    // (%W now sits between %Y and %F), so onStreamFinished's own
    // parts.slice() index for reassembling a pathological "|"-
    // containing filename moves from 4 to 5 accordingly.
    //
    // .exec() (not command=...;running=true) on every one of these four
    // Process elements -- issue #46: rapid row navigation is exactly
    // the "next request before the previous one finished" race that
    // makes an equal-value running=true write a silent no-op, which
    // would otherwise leave stat/ffprobe/poster/text-preview stuck
    // showing (or never updating past) an earlier selection.
    statProc.exec(["stat", "--format=%s|%Y|%W|%F|%A|%n", "--", path])
    if (root.isVideoPath(path)) {
      root.pendingVideoPath = path
      ffprobeProc.exec(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "default=noprint_wrappers=1:nokey=1", "--", path])

      root.pendingVideoPosterPath = path
      // Regenerate only if missing or the source is newer (-nt), same
      // staleness check as ruixen.notch's own copy -- replacing a video
      // at the same path invalidates the cache in place, nothing to
      // prune. Prints the poster path ONLY if it actually exists after
      // ffmpeg runs -- a corrupt/undecodable video just produces no
      // output at all (onStreamFinished below then leaves
      // videoPosterPath empty, same graceful "no thumbnail" fallback
      // this plugin already uses everywhere else), never a crash.
      posterProc.exec(["bash", "-c",
        'mkdir -p "$1" && hash=$(printf "%s" "$2" | md5sum | cut -d" " -f1) && poster="$1/$hash.jpg" && if [ ! -f "$poster" ] || [ "$2" -nt "$poster" ]; then ffmpeg -y -loglevel quiet -i "$2" -vframes 1 -q:v 3 "$poster" 2>/dev/null; fi && if [ -f "$poster" ]; then printf "%s" "$poster"; fi',
        "--", root.posterCacheDir, path])
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

  Process {
    id: posterProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.pendingVideoPosterPath === "" || root.pendingVideoPosterPath !== root.pendingDetailsPath) return
        var poster = text.trim()
        if (poster) root.videoPosterPath = poster
      }
    }
  }

  Process {
    id: textPreviewProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.pendingTextPreviewPath === "" || root.pendingTextPreviewPath !== root.pendingDetailsPath) return
        // No .trim() -- would strip real leading/trailing whitespace
        // (YAML/Python indentation on the first or last captured line)
        // that's part of the file's own actual content, not padding.
        root.textPreviewContent = text
      }
    }
  }
}
