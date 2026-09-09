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
    args.push("--", query, root.homeDir)
    searchProc.command = args
    searchProc.running = true
  }

  // Exact filename match > prefix > substring elsewhere in the name --
  // same 0-10000 scale every other provider uses, so Launcher.qml's
  // now-GLOBAL cross-provider sort ("Results", not separate per-source
  // sections -- confirmed against Raycast's own real behavior) stays
  // meaningful.
  //
  // dirBonus needs to be big enough to close the PREFIX-vs-SUBSTRING
  // gap within this scale, not just nudge a near-tie -- confirmed
  // live: searching "shell" with a small bonus (300) still buried the
  // real folder `dhh-shell` (a substring match, "shell" isn't at
  // index 0) under files like `shell.qml`/`shell.toml` (prefix
  // matches, ~8991-9000) even though the user wanted the folder
  // ranked above them. The prefix/substring tiers span roughly
  // 5000-9000 within this provider's own base score, so a bonus below
  // ~4000 can't reliably close that gap. 5000 guarantees any real
  // directory match outranks any file match at the same or a weaker
  // match tier, while still landing below a genuinely exact Command/
  // Application hit (10000) most of the time -- an exact-name folder
  // match (10000 + 5000) is the one case that outranks even those,
  // which is the intended behavior: if you typed the folder's actual
  // name, that folder is almost certainly what you meant.
  readonly property int dirBonus: 5000

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
}
