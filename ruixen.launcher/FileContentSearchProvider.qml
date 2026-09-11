import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "ContentSearchRanking.js" as ContentSearchRanking
// Issue #53: reuses FileSearchProvider's own local/remote fstype
// classification (isLocalFstype) rather than duplicating a second copy
// of that policy here -- ONE authoritative classification shared by
// both providers, not string checks spread across each.
import "FileSearchRanking.js" as FileSearchRanking
// Issue #58: same pure worker-pool/reuse-safety logic FileSearchProvider
// uses -- see WorkerPool.js's own header for the full "why".
import "WorkerPool.js" as WorkerPool

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
  //
  // Issue #61: Launcher.qml now binds this straight from
  // FileSearchProvider's own EFFECTIVE extra roots (already filtered by
  // the user's own config -- disabled auto-roots, excluded subtrees),
  // not its raw auto-discovered list -- this provider doesn't need its
  // own copy of that config-filtering logic, it just inherits whatever
  // FileSearchProvider already decided the real root set is.
  property var extraRoots: []
  property int rootGeneration: 0
  onExtraRootsChanged: {
    root.rootGeneration++
    if (root.query.trim()) debounceTimer.restart()
  }
  // Issue #61: whether Home is searched at all -- bound from
  // FileSearchProvider's own searchConfig.includeHome, same single
  // source of truth as extraRoots above.
  property bool includeHome: true
  onIncludeHomeChanged: {
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

  // Issue #55: { [rootPath]: "success"|"timeout"|"error" } -- see
  // FileSearchProvider's own rootStatuses for the full "why" (tells a
  // genuinely empty result apart from a search that never finished).
  // hasDegradedRoot is a plain property explicitly assigned by
  // updateDegradedStatus() below, NOT a declarative binding over
  // rootStatuses -- confirmed live (a standalone QML harness) that
  // mutating an object referenced by a property doesn't trigger that
  // property's own change notification, so a binding would silently
  // never re-evaluate after handleRootSearchDone()'s own in-place
  // update.
  property var rootStatuses: ({})
  property bool hasDegradedRoot: false

  function updateDegradedStatus() {
    var degraded = false
    for (var path in root.rootStatuses) {
      if (root.rootStatuses[path] !== "success") { degraded = true; break }
    }
    root.hasDegradedRoot = degraded
  }

  function classifyExitCode(exitCode) {
    return ContentSearchRanking.classifyRgExitCode(exitCode)
  }

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
      root.stopAllRootSearches()
      return
    }
    debounceTimer.restart()
  }
  onSourceFilterChanged: if (root.query.trim()) debounceTimer.restart()

  // Issue #60: same category/hidden-file filters as FileSearchProvider's
  // own, reusing its FileSearchRanking.js classification directly --
  // one shared table so a file always classifies the same way in both
  // providers. Content matches are always files (rg never matches a
  // directory), so "Folders" as a category naturally excludes every
  // real content match rather than needing a special case.
  property string categoryFilter: "All"
  onCategoryFilterChanged: if (root.query.trim()) debounceTimer.restart()
  property bool hiddenEnabled: false
  onHiddenEnabledChanged: if (root.query.trim()) debounceTimer.restart()

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
  // caps how many REAL match objects get collected (see each rootWorker's
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
      + "" + root.categoryFilter + "" + root.hiddenEnabled
  }

  // Issue #54: one rg process per effective root instead of one process
  // walking every root together, same reasoning and same confirmed-live
  // mechanism as FileSearchProvider's own runSearch() (see its header
  // comment) -- a slow/unresponsive root can no longer stall every other
  // root's own results in this one combined invocation. Same small
  // fixed worker pool, same reason (avoid unbounded process fan-out on a
  // machine with many mounts).
  //
  // Unlike FileSearchProvider's own per-root rootResults map, this
  // provider keeps ONE shared pendingMatches array across every worker
  // -- candidateBudget (issue #51) is a GLOBAL bound on total matches
  // collected, not a per-root one, so every worker's own onRead checks
  // and appends to the SAME array. JS's single-threaded event loop means
  // there's no real race between workers touching it concurrently, each
  // onRead callback runs to completion before another can start.
  readonly property var rootWorkers: [contentWorker0, contentWorker1, contentWorker2, contentWorker3]
  // Issue #58: which root each worker slot is actually processing, and
  // whether it's safely reusable -- WorkerPool.js's own pure, unit-
  // tested state machine (tests/js/WorkerPool.test.js), not an ad hoc
  // per-worker `currentRoot` property. See its own header for the full
  // "why" (an async kill's own onExited firing after this same slot has
  // already been reassigned, misattributing a killed invocation's exit
  // code to whatever it was reassigned to).
  property var pool: WorkerPool.createPool(4)
  property var rootSearchQueue: []

  // requestStop() marks the slot but does NOT free it -- see
  // WorkerPool.js's own header and FileSearchProvider's identical
  // stopWorker() for the full reasoning (same bug, same fix, both
  // providers).
  function stopWorker(i) {
    if (WorkerPool.isBusy(root.pool, i)) {
      root.rootWorkers[i].running = false
      WorkerPool.requestStop(root.pool, i)
    }
  }

  function stopAllRootSearches() {
    root.rootSearchQueue = []
    root.pendingMatches = []
    root.rootStatuses = ({})
    root.hasDegradedRoot = false
    for (var i = 0; i < root.rootWorkers.length; i++) root.stopWorker(i)
  }

  // -F/--fixed-strings -- issue #47: rg treats the pattern as a regex by
  // default (same mismatch as fd's own default in FileSearchProvider --
  // see its own comment), so an ordinary query like "(notes)" or
  // "*.json" would either match nothing or throw an invalid-pattern
  // error instead of searching for that literal text.
  function buildRgArgs(query, rootPath) {
    var args = ["rg", "--json", "-i", "-F", "--max-count", "1", "--max-filesize", "5M"]
    // Issue #60: rg skips hidden files/dirs by default -- --hidden opts
    // back in. Confirmed live (rg --help): "-./--hidden will include
    // files and folders like .git regardless of --no-ignore-vcs", so
    // ".git" is excluded unconditionally alongside it -- harmless when
    // hidden files are off (rg wouldn't walk into it anyway), required
    // once they're on.
    if (root.hiddenEnabled) args.push("--hidden")
    for (var i = 0; i < root.excludeDirs.length; i++) args.push("-g", "!" + root.excludeDirs[i])
    args.push("-g", "!.git")
    args.push("--", query, rootPath)
    return args
  }

  function scheduleRootSearches() {
    for (var i = 0; i < root.rootWorkers.length && root.rootSearchQueue.length > 0; i++) {
      if (WorkerPool.isBusy(root.pool, i)) continue
      // The global budget may already be satisfied by roots that
      // finished earlier -- no point starting a whole new rg process
      // for a root whose matches would just be discarded by every
      // worker's own onRead guard anyway.
      if (root.pendingMatches.length >= root.candidateBudget) {
        root.rootSearchQueue = []
        break
      }
      var nextRoot = root.rootSearchQueue.shift()
      WorkerPool.assign(root.pool, i, nextRoot)
      var w = root.rootWorkers[i]
      // Same real-world failure this shares extraRoots with
      // FileSearchProvider to avoid duplicating (see its own runSearch()
      // comment for the full reasoning): a slow/unresponsive root can
      // stall a search -- bounded per root now via `timeout`, same as
      // before this issue's own per-root split. rg does more I/O per
      // file than fd's own stat/listing (it reads content), so a
      // slightly longer bound than fd's 3s here.
      //
      // .exec() (not command=...;running=true) -- issue #46: reassigning
      // command while running is already true is a silent no-op in QML.
      // Confirmed directly that .exec() kills whatever's running first
      // and starts the new command immediately either way.
      w.exec(["timeout", "4"].concat(root.buildRgArgs(root.pendingQuery, nextRoot)))
    }
  }

  // Issue #58: once the shared candidateBudget is reached, every
  // additional match any OTHER still-running worker might find would
  // just be discarded anyway (pendingMatches is already full) --
  // letting them keep walking their own root only burns CPU/IO for a
  // result nobody will ever see. Stop every other active worker for
  // this same search generation outright and drop anything still
  // queued, rather than letting them run to their own natural
  // completion or 4s timeout. Their own eventual (now early) onExited
  // still goes through handleRootSearchDone() like any other
  // completion -- the existing pendingMatches>=candidateBudget check
  // there already marks a budget-driven stop as "success", not
  // degraded, regardless of which worker's own stop triggered it.
  function stopOtherWorkersForBudget(selfIndex) {
    root.rootSearchQueue = []
    for (var i = 0; i < root.rootWorkers.length; i++) {
      if (i !== selfIndex) root.stopWorker(i)
    }
  }

  // The single place that actually publishes to lastResults -- called
  // after every individual root's own completion (not just once at the
  // very end), so a fast root's matches can appear before a slower
  // one's own rg process finishes.
  function publishPendingMatches() {
    root.lastResults = ContentSearchRanking.dedupeByPath(root.pendingMatches).slice(0, root.displayLimit)
  }

  // Shared completion handler for every rootWorker -- see
  // FileSearchProvider's own handleRootSearchDone for why its own fixed
  // `index` into rootWorkers is named explicitly by each one's own
  // onExited below rather than this being one shared Process.
  // WorkerPool.retire() guarantees rootPath is exactly the root THIS
  // invocation was assigned, never a value a later reassignment might
  // have overwritten it with (issue #58).
  function handleRootSearchDone(index, exitCode) {
    var rootPath = WorkerPool.retire(root.pool, index)
    if (rootPath === null) { root.scheduleRootSearches(); return }
    // A stale response for a search identity the UI has already moved
    // on from -- drop it entirely (including not scheduling more queued
    // roots for an abandoned search) rather than publishing against
    // newer state. See searchIdentity()'s own comment.
    if (root.pendingSearchIdentity !== root.searchIdentity()) {
      root.pendingMatches = []
      return
    }
    // Hitting the global candidateBudget deliberately self-stops a
    // worker early (see onRead's own running=false below) -- that's a
    // form of SUCCESS (already found more than enough matches), not a
    // failure, even though the resulting exit code looks identical to
    // any other killed process.
    root.rootStatuses[rootPath] = (root.pendingMatches.length >= root.candidateBudget)
      ? "success"
      : root.classifyExitCode(exitCode)
    root.updateDegradedStatus()
    root.publishPendingMatches()
    root.scheduleRootSearches()
  }

  function runSearch(query) {
    if (!root.homeDir) return
    root.pendingQuery = query
    root.pendingSearchIdentity = root.searchIdentity()
    root.pendingMatches = []
    root.rootStatuses = ({})
    root.hasDegradedRoot = false
    // Stop whatever the previous search's workers were still doing --
    // their own eventual completion would be discarded anyway (the
    // staleness check above), but there's no reason to let them keep
    // running for an abandoned search. Safe when already idle. Issue
    // #58: stopWorker() deliberately does not free the pool slot -- see
    // stopAllRootSearches()'s own comment above.
    for (var i = 0; i < root.rootWorkers.length; i++) root.stopWorker(i)
    if (root.sourceFilter) {
      // Issue #53: an explicitly selected source is a deliberate choice
      // -- content-search it regardless of local/remote, existing
      // timeout/candidateBudget still apply exactly as for any other
      // source.
      root.rootSearchQueue = [root.sourceFilter]
    } else {
      // Issue #61: Home is now conditional on includeHome rather than
      // always the first root.
      var roots = root.includeHome ? [root.homeDir] : []
      // "All Sources" excludes remote/network-backed roots from
      // automatic content scanning by default -- recursively opening
      // FILE CONTENTS (not just listing names) over a network mount is
      // meaningfully riskier than a filename walk (latency amplified
      // per file, auth/network wakeups, rate limits), and this is
      // exactly the shape of the real rclone report that motivated the
      // earlier timeout work. Filename search (FileSearchProvider's own
      // runSearch) still walks every effective root regardless -- only
      // automatic content search is scoped down here. extraRoots here
      // is already the config-filtered EFFECTIVE set (issue #61,
      // disabled auto-roots/excluded subtrees already removed) -- this
      // loop only adds the remaining local-vs-remote policy on top.
      for (var j = 0; j < root.extraRoots.length; j++) {
        var r = root.extraRoots[j]
        if (FileSearchRanking.isLocalFstype(r.fstype)) roots.push(r.path)
      }
      root.rootSearchQueue = roots
    }
    // Issue #61: see FileSearchProvider's own identical comment -- an
    // empty effective root set means no worker starts, so
    // publishPendingMatches() (normally only reached via a real
    // worker's own completion) would never run, leaving lastResults
    // stuck on a previous, differently-configured search.
    if (root.rootSearchQueue.length === 0) root.publishPendingMatches()
    root.scheduleRootSearches()
  }

  // Issue #60: returns null for a match whose own file doesn't pass the
  // active category filter -- pure extension-based classification,
  // shared with FileSearchProvider via FileSearchRanking.js so a file
  // always classifies the same way in both providers. A content match
  // is always a real file (rg never matches a directory), so
  // categoryForPath's own isDir argument is always false here.
  function resultFor(path, lineNumber, lineText) {
    var name = ContentSearchRanking.baseName(path)
    if (!FileSearchRanking.matchesCategory(FileSearchRanking.categoryForPath(name, false), root.categoryFilter)) return null
    // Collapse the matched line to one clean, trimmed line -- rg's own
    // lines.text carries a trailing newline (and occasionally embedded
    // ones for odd files), neither of which belongs in a single-line
    // row breadcrumb.
    var snippet = ContentSearchRanking.collapseSnippet(lineText, 80)
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
      // Issue #62: the matched line number preserved as structured
      // action metadata (not just embedded in the breadcrumb string
      // above) -- Enter's own default behavior stays a plain
      // `xdg-open path` for now, but a future "open at line" action
      // (needs a real per-app editor convention this launcher doesn't
      // have yet) has the data it needs without re-parsing breadcrumb's
      // own "Line N: <snippet>" text back apart.
      action: { type: "open", path: path, line: lineNumber }
    }
  }


  // Issue #54: four workers, a small fixed pool per root (see
  // rootWorkers' own comment above) -- same reasoning and same static-
  // pool-over-dynamic-objects tradeoff as FileSearchProvider's own
  // rootWorker0-3. SplitParser (issue #51, line-by-line as rg's own
  // stdout streams in) instead of StdioCollector on each -- every real
  // match is pushed onto the SHARED pendingMatches as it arrives; once
  // the GLOBAL candidateBudget is reached, THIS worker stops itself
  // outright (confirmed elsewhere in this codebase: running = false
  // kills cleanly and still lets whatever already ran finish normally).
  Process {
    id: contentWorker0
    stdout: SplitParser {
      onRead: function(line) {
        if (root.pendingSearchIdentity !== root.searchIdentity()) return
        if (root.pendingMatches.length >= root.candidateBudget) return
        var obj
        try { obj = JSON.parse(line) } catch (e) { return }
        if (!obj || obj.type !== "match") return
        var r = root.resultFor(obj.data.path.text, obj.data.line_number, obj.data.lines.text)
        if (r) root.pendingMatches.push(r)
        if (root.pendingMatches.length >= root.candidateBudget) {
          contentWorker0.running = false
          root.stopOtherWorkersForBudget(0)
        }
      }
    }
    onExited: (exitCode, exitStatus) => root.handleRootSearchDone(0, exitCode)
  }
  Process {
    id: contentWorker1
    stdout: SplitParser {
      onRead: function(line) {
        if (root.pendingSearchIdentity !== root.searchIdentity()) return
        if (root.pendingMatches.length >= root.candidateBudget) return
        var obj
        try { obj = JSON.parse(line) } catch (e) { return }
        if (!obj || obj.type !== "match") return
        var r = root.resultFor(obj.data.path.text, obj.data.line_number, obj.data.lines.text)
        if (r) root.pendingMatches.push(r)
        if (root.pendingMatches.length >= root.candidateBudget) {
          contentWorker1.running = false
          root.stopOtherWorkersForBudget(1)
        }
      }
    }
    onExited: (exitCode, exitStatus) => root.handleRootSearchDone(1, exitCode)
  }
  Process {
    id: contentWorker2
    stdout: SplitParser {
      onRead: function(line) {
        if (root.pendingSearchIdentity !== root.searchIdentity()) return
        if (root.pendingMatches.length >= root.candidateBudget) return
        var obj
        try { obj = JSON.parse(line) } catch (e) { return }
        if (!obj || obj.type !== "match") return
        var r = root.resultFor(obj.data.path.text, obj.data.line_number, obj.data.lines.text)
        if (r) root.pendingMatches.push(r)
        if (root.pendingMatches.length >= root.candidateBudget) {
          contentWorker2.running = false
          root.stopOtherWorkersForBudget(2)
        }
      }
    }
    onExited: (exitCode, exitStatus) => root.handleRootSearchDone(2, exitCode)
  }
  Process {
    id: contentWorker3
    stdout: SplitParser {
      onRead: function(line) {
        if (root.pendingSearchIdentity !== root.searchIdentity()) return
        if (root.pendingMatches.length >= root.candidateBudget) return
        var obj
        try { obj = JSON.parse(line) } catch (e) { return }
        if (!obj || obj.type !== "match") return
        var r = root.resultFor(obj.data.path.text, obj.data.line_number, obj.data.lines.text)
        if (r) root.pendingMatches.push(r)
        if (root.pendingMatches.length >= root.candidateBudget) {
          contentWorker3.running = false
          root.stopOtherWorkersForBudget(3)
        }
      }
    }
    onExited: (exitCode, exitStatus) => root.handleRootSearchDone(3, exitCode)
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
