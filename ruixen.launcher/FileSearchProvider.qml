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

  function runSearch(query) {
    if (!root.homeDir) return
    root.pendingQuery = query
    var args = ["fd", "--type", "f", "--ignore-case", "--max-results", "50"]
    for (var i = 0; i < root.excludeDirs.length; i++) args.push("--exclude", root.excludeDirs[i])
    args.push("--", query, root.homeDir)
    searchProc.command = args
    searchProc.running = true
  }

  // Exact filename match > prefix > substring elsewhere in the name --
  // same 0-10000 scale every other provider uses, so Launcher.qml's
  // per-section byScoreDesc sort is meaningful here too.
  function scoreFile(name, query) {
    var q = String(query || "").toLowerCase()
    var n = String(name || "").toLowerCase()
    if (n === q) return 10000
    var idx = n.indexOf(q)
    if (idx === 0) return 9000 - n.length
    if (idx > 0) return 7000 - idx * 10 - n.length
    return 5000 - n.length
  }

  function resultFor(path, score) {
    var slash = path.lastIndexOf("/")
    var name = slash === -1 ? path : path.substring(slash + 1)
    var dir = slash === -1 ? "" : path.substring(0, slash)
    if (root.homeDir && dir.indexOf(root.homeDir) === 0) dir = "~" + dir.substring(root.homeDir.length)
    return {
      id: "file:" + path,
      providerId: "file-search",
      icon: "",
      label: name,
      breadcrumb: dir,
      kind: "File",
      providerName: root.providerName,
      score: score,
      action: { type: "openFile", path: path }
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
        for (var i = 0; i < lines.length; i++) {
          var path = lines[i]
          var slash = path.lastIndexOf("/")
          var name = slash === -1 ? path : path.substring(slash + 1)
          out.push(root.resultFor(path, root.scoreFile(name, q)))
        }
        root.lastResults = out
      }
    }
  }

  function activate(result) {
    Util.execArgv(["xdg-open", result.action.path])
  }
}
