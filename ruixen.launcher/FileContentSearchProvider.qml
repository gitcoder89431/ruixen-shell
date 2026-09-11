import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Provider: matches INSIDE file contents (ripgrep), not filenames --
// the "search by context" follow-up to FileSearchProvider's own
// filename-only matching. A separate file, not folded into
// FileSearchProvider, because the underlying tool and result shape are
// both genuinely different (a path + line number + line text, not just
// a path) -- same "one new file, small isolated addition" convention
// every other provider here already follows.
//
// Results from this provider and FileSearchProvider's own are merged
// into ONE list by Launcher.qml (both tagged "Search Files"), not a
// separate mode/fallback -- direct design call: score band below (see
// contentMatchScore) keeps every content match ranked below every
// filename match, so a query with real filename hits reads exactly as
// before, and a query with NONE falls through to content matches
// instead of "No Results" -- reducing that dead end without ever
// skipping a real content search to get there (accuracy stays whole;
// this is a ranking decision, not a "only search content when
// filename hits are sparse" shortcut, which would have meant this
// provider sometimes just not running at all).
//
// homeDir/extraRoots are NOT independently discovered here -- Launcher.qml
// binds both straight from FileSearchProvider's own already-discovered
// values (same refreshRoots() call, same mounted-drive list), so there's
// one source of truth for "what counts as a search root," not two
// mount-discovery implementations that could disagree.
Item {
  id: root

  readonly property string providerName: "File Contents"
  readonly property bool ready: true

  property string query: ""
  property string sourceFilter: ""
  property string homeDir: ""
  // Issue #48: this provider's own extraRoots is a plain externally-
  // bound property (Launcher.qml wires it straight from
  // FileSearchProvider's own discovered value), but reassigning it
  // never re-triggered a search here -- confirmed real: a query typed
  // before mount discovery resolves would search only Home forever,
  // never picking up a newly-discovered drive the way FileSearchProvider
  // itself already does via its own onExtraRootsChanged. rootGeneration
  // (bumped in the same handler) also feeds searchIdentity() below, the
  // same composite-identity pattern FileSearchProvider uses for #46.
  property var extraRoots: []
  property int rootGeneration: 0
  onExtraRootsChanged: {
    root.rootGeneration++
    if (root.query.trim()) debounceTimer.restart()
  }

  property string pendingQuery: ""
  property string pendingSearchIdentity: ""
  property var lastResults: []
  // Real match rows collected incrementally as rg's own stdout streams
  // in -- see candidateBudget's own comment below for why this exists
  // instead of buffering everything then slicing.
  property var pendingMatches: []

  // Confirmed live (this exact query -- rg's own glob semantics differ
  // from fd's): a bare directory name ("go") excludes it at ANY depth,
  // gitignore-style, but a multi-segment pattern ("go/pkg/mod" or
  // "go/pkg/mod/**", fd's own excludeDirs entry) silently matches
  // NOTHING for rg -- confirmed both forms leaked real go/pkg/mod
  // results through before landing on this. Excluding the whole go/
  // tree here (not just pkg/mod) is deliberately broader than
  // FileSearchProvider's own list -- vendored Go module source is
  // exactly the kind of noisy, non-personal content nobody wants
  // surfacing in a content search, more so than in a filename search.
  readonly property var excludeDirs: ["node_modules", "vendor", "target", "go"]

  // Debounced separately from (and longer than) FileSearchProvider's
  // own 150ms -- measured directly, not guessed: ripgrep content-
  // searching this machine's real ~24GB/134k-file $HOME runs ~100-150ms
  // warm-cache for a realistic specific query, up to ~1.8s cold-cache
  // for the single most common word imaginable ("the"). Firing that on
  // every keystroke the way fd's own near-instant search can afford to
  // would be wasteful; 400ms means content results "stream in" a beat
  // after the already-fast filename results, not block them.
  onQueryChanged: {
    var q = root.query.trim()
    if (!q) {
      debounceTimer.stop()
      root.lastResults = []
      // Issue #49: stop in-flight work outright, not just its eventual
      // effect on lastResults -- see FileSearchProvider's own
      // onQueryChanged for the full reasoning (safe no-op when idle).
      searchProc.running = false
      return
    }
    debounceTimer.restart()
  }
  onSourceFilterChanged: if (root.query.trim()) debounceTimer.restart()

  function search(query) {
    return root.query.trim() ? root.lastResults : []
  }

  Timer {
    id: debounceTimer
    interval: 400
    repeat: false
    onTriggered: root.runSearch(root.query.trim())
  }

  readonly property int displayLimit: 15

  // Issue #51: `--max-count 1` below bounds matches PER FILE, not
  // total -- a broad query (e.g. "the", "config") can still match
  // thousands of files, and rg emits a full JSON object (match, plus
  // begin/end/summary framing) for every one of them. The previous
  // StdioCollector buffered ALL of that into one giant string before
  // ever slicing it down to displayLimit, so the transient output/
  // memory a broad query could generate was effectively unbounded even
  // though the UI only ever shows a handful of rows. candidateBudget
  // caps how many REAL match objects get collected (see searchProc's
  // own SplitParser below) before the process is stopped outright --
  // a small multiple of displayLimit, generous enough that ranking
  // still has more than the bare minimum to work with, small enough
  // that the bound is meaningful.
  //
  // What's actually guaranteed, confirmed with a standalone harness:
  // pendingMatches itself never grows past candidateBudget regardless of
  // how much more rg has already written by the time the budget is hit
  // (onRead's own early-return makes every line past it a cheap no-op,
  // not a discarded-but-still-allocated object) -- that JS-side bound is
  // unconditional. Actually stopping rg itself (running = false once the
  // budget is reached) is a real, additional saving for the normal case
  // (a real filesystem walk is throttled by disk I/O, not a tight loop),
  // but isn't a hard guarantee against a producer so fast that its own
  // output is already fully written/exited before the kill lands --
  // same "not absolute, but fixes the realistic case" caveat as the
  // existing rg `timeout` already carries.
  readonly property int candidateBudget: 60

  // Flat, deliberately below FileSearchProvider's own scoreFile() floor
  // (its weakest real match -- a long filename matching nowhere near
  // the start -- still lands well above this) so a content match NEVER
  // outranks a filename match, only fills in around/after them.
  readonly property int contentMatchScore: 1500

  // Issue #46 -- same composite-identity pattern as FileSearchProvider's
  // own searchIdentity(): query text alone misses a sourceFilter switch
  // or a root-set change with no query edit involved.
  function searchIdentity() {
    return root.query.trim() + "" + root.sourceFilter + "" + root.rootGeneration
  }

  function runSearch(query) {
    if (!root.homeDir) return
    root.pendingQuery = query
    root.pendingSearchIdentity = root.searchIdentity()
    root.pendingMatches = []
    // -F/--fixed-strings -- issue #47: rg treats the pattern as a regex
    // by default (same mismatch as fd's own default in
    // FileSearchProvider -- see its own comment), so an ordinary query
    // like "(notes)" or "*.json" would either match nothing or throw an
    // invalid-pattern error instead of searching for that literal text.
    var args = ["rg", "--json", "-i", "-F", "--max-count", "1", "--max-filesize", "5M"]
    for (var i = 0; i < root.excludeDirs.length; i++) args.push("-g", "!" + root.excludeDirs[i])
    args.push("--", query)
    if (root.sourceFilter) {
      args.push(root.sourceFilter)
    } else {
      args.push(root.homeDir)
      for (var i = 0; i < root.extraRoots.length; i++) args.push(root.extraRoots[i])
    }
    // Same real-world failure this shares extraRoots with
    // FileSearchProvider to avoid duplicating (see its own runSearch()
    // comment for the full reasoning): a network mount (rclone) among
    // extraRoots that's still establishing its remote connection right
    // after boot can stall rg's traversal of EVERY root in this one
    // combined invocation, not just that mount's own. rg does more I/O
    // per file than fd's own stat/listing (it reads content), so a
    // slightly longer bound than fd's 3s here.
    // .exec() (not command=...;running=true) -- issue #46, same fix as
    // FileSearchProvider's own runSearch(): reassigning command while
    // running is already true is a silent no-op in QML, which could
    // leave a query typed while a slow rg run is still in flight never
    // actually starting its own search. Confirmed directly that .exec()
    // kills whatever's running first and starts the new command
    // immediately either way.
    searchProc.exec(["timeout", "4"].concat(args))
  }

  function resultFor(path, lineNumber, lineText) {
    var slash = path.lastIndexOf("/")
    var name = slash === -1 ? path : path.substring(slash + 1)
    // Collapse the matched line to one clean, trimmed line -- rg's own
    // lines.text carries a trailing newline (and occasionally embedded
    // ones for odd files), neither of which belongs in a single-line
    // row breadcrumb.
    var snippet = lineText.replace(/\s+/g, " ").trim()
    if (snippet.length > 80) snippet = snippet.substring(0, 80) + "…"
    return {
      id: "content:" + path + ":" + lineNumber,
      providerId: "file-content-search",
      // fa-file (U+F15B) -- content matches are always files, rg
      // never matches inside a directory, so no folder-vs-file branch
      // is needed the way FileSearchProvider's own resultFor() has one.
      icon: "",
      label: name,
      // The matched line itself, not a parent-folder path -- this IS
      // the "search by context" feature made visible: why this row
      // matched, not just where the file lives (still available via
      // the details panel's own "Where" field once selected).
      breadcrumb: "Line " + lineNumber + ": " + snippet,
      kind: "File",
      providerName: root.providerName,
      score: root.contentMatchScore,
      action: { type: "open", path: path }
    }
  }

  Process {
    id: searchProc
    // Issue #51: SplitParser (line-by-line, as rg's own stdout streams
    // in) instead of StdioCollector (buffers the ENTIRE output as one
    // string, only usable once the stream closes) -- see
    // candidateBudget's own comment for why buffering everything first
    // is exactly the unbounded-output problem being fixed here. Each
    // real match is pushed onto pendingMatches as it arrives; once
    // candidateBudget is reached the process is stopped outright
    // (running = false, confirmed elsewhere in this codebase to kill
    // cleanly and still let whatever already ran finish normally) --
    // rg does no more work and produces no more output past that point.
    stdout: SplitParser {
      onRead: function(line) {
        if (root.pendingSearchIdentity !== root.searchIdentity()) return
        if (root.pendingMatches.length >= root.candidateBudget) return
        var obj
        try { obj = JSON.parse(line) } catch (e) { return }
        if (!obj || obj.type !== "match") return
        root.pendingMatches.push(root.resultFor(obj.data.path.text, obj.data.line_number, obj.data.lines.text))
        if (root.pendingMatches.length >= root.candidateBudget) searchProc.running = false
      }
    }
    // The single place that actually publishes to lastResults -- fires
    // whether rg exited on its own (query too specific to hit the
    // budget) or was stopped above once the budget was reached, so
    // there's only one finalization path to keep in sync rather than
    // duplicating it in onRead too.
    onExited: {
      if (root.pendingSearchIdentity === root.searchIdentity())
        root.lastResults = root.pendingMatches.slice(0, root.displayLimit)
      root.pendingMatches = []
    }
  }

  // Same as FileSearchProvider's own activate() -- xdg-open already
  // does the right thing for a file's default app; this doesn't (yet)
  // try to open an editor at the specific matched line, a genuinely
  // separate feature (needs a real per-app "open at line" convention)
  // rather than something to bolt on here speculatively.
  function activate(result) {
    Util.execArgv(["xdg-open", result.action.path])
  }
}
