import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "FileSearchRanking.js" as FileSearchRanking
import "WorkerPool.js" as WorkerPool
import "LauncherSearchConfig.js" as LauncherSearchConfig

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
  // Issue #59: pendingQuery tokenized once per search (not once per
  // worker/candidate) -- the literal terms a multi-word query gets
  // split into. A single-term query is just a one-element array here;
  // buildFdArgs/resultFor treat that case identically to before this
  // issue, just routed through the same code path instead of a special
  // case.
  property var pendingTerms: []
  property var lastResults: []

  readonly property string homeDir: Quickshell.env("HOME") || ""

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

  // Issue #61: user-configurable search locations/exclusions --
  // ~/.local/state/ruixen/launcher-search-config.json, the same
  // convention every other Ruixen plugin's own persisted state already
  // uses (confirmed directly against ruixen.settings/ruixen.media/
  // ruixen.peripherals/ruixen.wallpaper/ruixen.notch's own Kanban
  // service before picking this path -- none of them use ~/.config/
  // ruixen, despite that being what this issue's own text guessed).
  // Read/written from ruixen.settings' own "Launcher" page -- watched
  // here with watchChanges so an edit there takes effect immediately,
  // no shell restart needed (this issue's own acceptance criterion).
  readonly property string searchConfigPath: (root.homeDir || "") + "/.local/state/ruixen/launcher-search-config.json"
  property var searchConfig: LauncherSearchConfig.defaultConfig()

  function loadSearchConfig(raw) {
    root.searchConfig = LauncherSearchConfig.parseSearchConfig(raw)
  }

  Process {
    id: ensureSearchConfigDirProc
    command: ["mkdir", "-p", (root.homeDir || "") + "/.local/state/ruixen"]
  }
  Component.onCompleted: ensureSearchConfigDirProc.running = true

  FileView {
    id: searchConfigFile
    path: root.searchConfigPath
    watchChanges: true
    printErrors: false
    onLoaded: root.loadSearchConfig(text())
    onLoadFailed: root.loadSearchConfig("")
    onFileChanged: reload()
  }

  // The real, config-filtered extra-root set every "All Sources" search
  // actually walks -- auto-discovered mounts (minus any individually
  // disabled, minus config.includeMountedRoots entirely) plus the
  // user's own custom roots, minus anything under an excluded subtree.
  // Recomputes automatically whenever EITHER extraRoots (a new mount
  // appeared) OR searchConfig (the user edited a setting) changes --
  // both assignments are always a genuinely NEW object (parseSearchConfig/
  // discoverExtraRoots both build a fresh return value, never mutate an
  // existing one in place), so this binding's own dependency tracking
  // fires correctly for both triggers.
  readonly property var effectiveExtraRoots: LauncherSearchConfig.computeEffectiveExtraRoots(root.searchConfig, root.extraRoots, root.homeDir)
  // Same reasoning as onExtraRootsChanged above -- effectiveExtraRoots
  // changing is one more way the CURRENT desired root set can change
  // without the query text itself changing (a config edit lands here
  // even when extraRoots itself didn't move at all).
  onEffectiveExtraRootsChanged: {
    root.rootGeneration++
    if (root.query.trim()) debounceTimer.restart()
  }
  // Issue #64: excludeNames/excludePaths feed directly into buildFdArgs
  // (constraining traversal WITHIN a root, not just which roots exist at
  // all) -- editing either in Ruixen Settings can change what an ACTIVE
  // search should return even when effectiveExtraRoots itself doesn't
  // move at all (e.g. adding "~/VMs" to excludePaths while Home stays
  // the same enabled root throughout). Without this, that edit would
  // only take effect on the NEXT query typed from scratch, not the
  // current in-flight/just-completed one -- the issue's own explicit
  // acceptance criterion is that it takes effect immediately.
  onSearchConfigChanged: {
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

  // Issue #60: "All" means every category (today's behavior, unchanged);
  // a specific category (see FileSearchRanking.js's own
  // FILE_CATEGORY_NAMES) excludes anything else. Same re-trigger
  // reasoning as sourceFilter above -- the query text itself doesn't
  // change when someone just switches the type filter.
  property string categoryFilter: "All"
  onCategoryFilterChanged: if (root.query.trim()) debounceTimer.restart()
  // fd skips dotfiles/dotdirs by default -- this opts back in. Confirmed
  // live (rg --help) that ripgrep's own --hidden explicitly pulls in
  // .git regardless of --no-ignore-vcs; fd's --exclude below always
  // includes ".git" too so enabling this can't flood results with
  // git's own internal object tree either.
  property bool hiddenEnabled: false
  onHiddenEnabledChanged: if (root.query.trim()) debounceTimer.restart()

  // Populates the source-filter dropdown -- Home (if config.includeHome
  // hasn't turned it off) plus one entry per effective extra root
  // (config-filtered, issue #61), labelled by its own last path segment
  // (a mount's own volume-label folder name, e.g. "OMARCHY_202607")
  // rather than the full path, matching how a file manager's own
  // sidebar already labels a mounted drive.
  readonly property var sources: {
    var out = []
    if (root.searchConfig.includeHome) out.push({ id: root.homeDir, label: "Home", path: root.homeDir })
    for (var i = 0; i < root.effectiveExtraRoots.length; i++) {
      var p = root.effectiveExtraRoots[i].path
      var slash = p.lastIndexOf("/")
      out.push({ id: p, label: slash === -1 ? p : p.substring(slash + 1), path: p })
    }
    return out
  }

  function refreshRoots() {
    mountProc.exec(["findmnt", "--json", "-o", "TARGET,FSTYPE"])
  }

  // Issue #52: the findmnt-output-to-extraRoots pipeline (tree
  // flattening, /mnt//media//run/media candidacy, dedup) lives in
  // FileSearchRanking.js's own discoverExtraRoots() now -- pure logic,
  // independently unit-tested (tests/js/FileSearchRanking.test.js)
  // without needing a real findmnt process or Quickshell runtime.
  Process {
    id: mountProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.extraRoots = FileSearchRanking.discoverExtraRoots(text)
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
      root.stopAllRootSearches()
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
  // completion time (handleRootSearchDone below, issue #54) is the same
  // frozen-snapshot-vs-live-recompute pattern this file already used for
  // pendingQuery, just extended to cover all three identity-defining
  // inputs instead of one.
  // Issue #60 extends this the same way: category/hidden-file
  // changes are one more way the CURRENT desired result set can change
  // without the query text itself changing.
  function searchIdentity() {
    return root.query.trim() + "" + root.sourceFilter + "" + root.rootGeneration
      + "" + root.categoryFilter + "" + root.hiddenEnabled
  }

  property string pendingSearchIdentity: ""

  // Issue #54: one fd process per EFFECTIVE root instead of one process
  // walking every root together -- a single combined invocation coupled
  // the whole "All Sources" result set to whichever root was slowest,
  // confirmed live (a standalone Quickshell harness) that this isn't
  // theoretical: two independent Process objects launched together
  // finish completely independently (a fast one reported in 0.02s while
  // a deliberately slow one was still running at 3s), so per-root
  // processes really do let Home's own fast results land immediately
  // regardless of another root's own health.
  //
  // A small fixed worker pool (rootWorkers below), not one process per
  // root unconditionally -- avoids unbounded process fan-out on a
  // machine with many mounts. Real-world root counts (0-3 extra roots
  // typically) rarely exceed the pool size anyway, so this is the
  // uncommon path, not the common one.
  readonly property var rootWorkers: [rootWorker0, rootWorker1, rootWorker2, rootWorker3]
  // Issue #58: which root (if any) each worker slot is actually
  // processing right now, and whether it's safely reusable -- moved
  // into WorkerPool.js as pure, unit-tested logic (tests/js/
  // WorkerPool.test.js) rather than the ad hoc per-worker
  // `currentRoot` property this used before. See that module's own
  // header for the full "why".
  property var pool: WorkerPool.createPool(4)
  property var rootSearchQueue: []
  // { [rootPath]: Array<result> } -- accumulates as each root's own
  // worker finishes; publishRootResults() below merges/ranks/dedupes
  // whatever's in here so far, called after every individual root
  // completes (not just once at the very end), which is what actually
  // lets Home's own results appear before a slow root's own eventually
  // do.
  property var rootResults: ({})
  // Issue #55: { [rootPath]: "success"|"timeout"|"error" }, populated
  // alongside rootResults so the UI can tell "this root genuinely has
  // zero matches" apart from "this root's own search never actually
  // completed" -- both used to look identical (an empty results list),
  // which made real field reports hard to diagnose (this project's own
  // "No Results for ruixen-doctor" investigation turned out to be
  // unrelated, but a degraded/error indicator would have ruled that out
  // in seconds instead of a live debugging session). hasDegradedRoot is
  // the simple aggregate Launcher.qml actually reads -- a full per-root
  // breakdown isn't surfaced in the UI, kept deliberately minimal per
  // direct product guidance ("a small note, not an elaborate status
  // system").
  property var rootStatuses: ({})
  // Plain property, explicitly assigned (see updateDegradedStatus()
  // below) rather than a declarative binding over rootStatuses --
  // confirmed live (a standalone QML harness) that mutating an object
  // referenced by a property, or even reassigning the SAME object
  // reference back to it, does NOT trigger that property's own change
  // notification, so a binding reading rootStatuses in place would
  // silently never re-evaluate after the in-place updates
  // handleRootSearchDone() below actually does.
  property bool hasDegradedRoot: false

  function updateDegradedStatus() {
    var degraded = false
    for (var path in root.rootStatuses) {
      if (root.rootStatuses[path] !== "success") { degraded = true; break }
    }
    root.hasDegradedRoot = degraded
  }

  function classifyExitCode(exitCode) {
    return FileSearchRanking.classifyFdExitCode(exitCode)
  }

  // Issue #58: requestStop() marks the pool slot but deliberately does
  // NOT free it -- running=false is an async kill (confirmed live: the
  // killed process's own onExited fires LATER, after this function has
  // already returned), so freeing the slot synchronously would let
  // scheduleRootSearches() immediately hand this same worker a NEW
  // root while the OLD process is still dying. That old process's own
  // eventual onExited would then retire() whatever root the slot had
  // been reassigned to in the meantime, misattributing its exit code/
  // output to it -- confirmed live with a standalone harness, and now
  // enforced by WorkerPool.js's own tested contract (a stopping slot
  // stays busy until its real completion retires it). handleRootSearchDone()
  // -- fired by the REAL onExited -- is the only thing that actually
  // frees a slot, and it does so in the same synchronous call that
  // hands it back to the scheduler, with no room for another event to
  // interleave.
  function stopWorker(i) {
    if (WorkerPool.isBusy(root.pool, i)) {
      root.rootWorkers[i].running = false
      WorkerPool.requestStop(root.pool, i)
    }
  }

  function stopAllRootSearches() {
    root.rootSearchQueue = []
    root.rootResults = ({})
    root.rootStatuses = ({})
    root.hasDegradedRoot = false
    for (var i = 0; i < root.rootWorkers.length; i++) root.stopWorker(i)
  }

  // -t f -t d: files AND directories -- fd ORs multiple --type flags
  // together (confirmed live). fd prints a trailing "/" on directory
  // matches, which resultFor() below uses to tell them apart without a
  // separate stat() per result. --fixed-strings -- issue #47: fd treats
  // the pattern as a regex by default, which disagrees with this
  // provider's own literal-substring ranking (scoreFile) and silently
  // mishandles ordinary filenames containing regex metacharacters.
  //
  // fd's own --max-results is a raw CANDIDATE cap per root, not a
  // relevance cap -- fd fills it in directory-traversal order, with no
  // idea which matches score best. A tight cap here can silently drop a
  // highly relevant match before scoreFile() ever sees it: confirmed
  // live, searching "shell" with a 50-candidate cap never even
  // considered the real folder `dhh-shell` because 50 less-relevant
  // "shell"-matching files elsewhere filled the quota first. 500 is a
  // generous safety valve against a truly pathological one-character
  // query on a huge tree (a full unthrottled $HOME search already takes
  // ~8ms here), not a meaningful relevance filter -- the real cap is
  // displayLimit, applied after sorting the MERGED results across every
  // root.
  //
  // Issue #59: --full-path matches the pattern against the WHOLE path,
  // not just the filename -- a strict superset of the old basename-only
  // matching (any basename match is trivially still a full-path match),
  // so this can only ever ADD candidates fd wouldn't have returned
  // before, never drop ones it already found. Only ONE term (the
  // caller's own chosen candidate term -- see FileSearchRanking.js's
  // own primaryCandidateTerm for a multi-word query) is ever handed to
  // fd itself; requiring every OTHER term is a cheap plain-string check
  // against paths fd already returned (resultFor() below), not a second
  // fd invocation or a full unbounded walk.
  function buildFdArgs(candidateTerm, rootPath) {
    var args = ["fd", "--type", "f", "--type", "d", "--ignore-case", "--fixed-strings", "--full-path", "--max-results", "500"]
    // Issue #60: fd skips dotfiles/dotdirs by default -- --hidden opts
    // back in when the user explicitly asks for it. ".git" is always
    // excluded regardless of hiddenEnabled -- harmless (never reached)
    // when hidden files are off, since fd wouldn't walk into it anyway,
    // but required once they're on: confirmed live (rg --help) that a
    // sibling flag on ripgrep's own --hidden explicitly pulls in .git
    // regardless of --no-ignore-vcs, and fd's own --hidden works the
    // same way -- without this, enabling hidden files would flood
    // results with git's own internal object tree.
    if (root.hiddenEnabled) args.push("--hidden")
    // Issue #64: config.excludeNames (Ruixen Settings' own Launcher page)
    // is now the single authoritative name-exclusion list for both this
    // provider and FileContentSearchProvider -- no more separate
    // hardcoded excludeDirs of its own. Escaped per name (see
    // LauncherSearchConfig.js's own escapeGlobLiteral) so a literal
    // directory name containing a glob metacharacter can't be misread as
    // glob syntax. ".git" stays forced on separately, unconditionally --
    // a user removing it from their own excludeNames must not reopen the
    // "hidden files flood results with git's own internal object tree"
    // bug this already protects against.
    var names = root.searchConfig.excludeNames
    for (var i = 0; i < names.length; i++) args.push("--exclude", LauncherSearchConfig.escapeGlobLiteral(names[i]))
    args.push("--exclude", ".git")
    // Issue #64: config.excludePaths used to only filter the ROOT LIST
    // (computeEffectiveExtraRoots, for a mount/custom root that IS or is
    // under an exclusion) -- it never actually constrained traversal
    // WITHIN a root that stays active, e.g. excluding "~/VMs" while Home
    // is still enabled. excludeInfoForRoot translates each configured
    // exclusion into what THIS specific root needs: nothing if the
    // exclusion lies outside this root entirely, or a root-relative,
    // leading-"/" anchored --exclude pattern for a genuine subtree under
    // it (confirmed live: fd anchors a leading-"/" --exclude to the
    // SEARCH ROOT argument itself, not the process's own cwd). The
    // "exclusion equals this whole root" case is handled earlier, in
    // runSearch()'s own rootExactlyExcluded filter -- a root that would
    // hit `skip: true` here never reaches buildFdArgs at all.
    var paths = root.searchConfig.excludePaths
    for (var j = 0; j < paths.length; j++) {
      var info = LauncherSearchConfig.excludeInfoForRoot(paths[j], rootPath, root.homeDir)
      if (info && !info.skip) args.push("--exclude", info.relative)
    }
    args.push("--", candidateTerm, rootPath)
    return args
  }

  // Pulls queued roots into any currently-idle worker -- called once
  // when a new search starts (queue freshly populated) and again every
  // time a worker finishes (queue may still have more roots waiting,
  // issue #54's own "small concurrency limit/queue" rather than an
  // unbounded process fan-out).
  function scheduleRootSearches() {
    for (var i = 0; i < root.rootWorkers.length && root.rootSearchQueue.length > 0; i++) {
      if (WorkerPool.isBusy(root.pool, i)) continue
      var nextRoot = root.rootSearchQueue.shift()
      WorkerPool.assign(root.pool, i, nextRoot)
      var w = root.rootWorkers[i]
      // Real report: search "stopped working" right after a reboot, for
      // someone with a network mount (rclone) among their own
      // extraRoots, and fixed itself after waiting -- exactly the shape
      // of a FUSE mount still establishing its remote connection right
      // after boot. `timeout` bounds that per root now, same as before
      // this issue's own per-root split: whatever fd already found
      // before a slow root's own timeout fires still reaches this
      // worker's own stdout (a killed process's already-written output
      // isn't lost). Not an absolute guarantee -- a syscall truly stuck
      // in D-state can't be killed by SIGTERM until it returns on its
      // own -- but that's a rarer failure shape than "needs a few more
      // seconds," which this does fix.
      //
      // .exec() (not command=...;running=true) -- issue #46: reassigning
      // `command` while `running` is already true is a silent no-op in
      // QML, which could leave a query typed while this worker's
      // previous root is still running never actually starting.
      // Confirmed directly: .exec() while running kills the old command
      // and starts the new one immediately, with the killed process's
      // own already-written stdout still delivered.
      w.exec(["timeout", "3"].concat(root.buildFdArgs(FileSearchRanking.primaryCandidateTerm(root.pendingTerms), nextRoot)))
    }
  }

  // Merges whatever roots have reported back so far (not necessarily
  // all of them -- see rootResults' own comment), ranks together, dedupes
  // by real path (a nested/bind mount could in principle surface the
  // same file under two different roots), and republishes. Called after
  // EVERY individual root's own completion so a fast root's results
  // appear without waiting on a slower one still in flight.
  function publishRootResults() {
    root.lastResults = FileSearchRanking.mergeRootResults(root.rootResults, root.displayLimit)
  }

  // Shared completion handler for every rootWorker -- `index` (this
  // worker's own fixed position in rootWorkers, issue #58) is passed in
  // explicitly by each one's own onExited below rather than this being
  // one shared Process (QML has no direct way for a signal handler to
  // identify which sender fired it, so each worker's own handler names
  // itself). retire() is the ONLY thing that reports which root this
  // slot was actually processing and frees it for reuse -- guaranteed
  // by WorkerPool.js's own contract to be the root this exact
  // invocation was assigned, never a value a later reassignment might
  // have overwritten it with, because assign() refuses to touch a slot
  // retire() hasn't freed yet.
  function handleRootSearchDone(index, exitCode) {
    var worker = root.rootWorkers[index]
    var output = worker.pendingOutput
    worker.pendingOutput = ""
    var rootPath = WorkerPool.retire(root.pool, index)
    if (rootPath === null) { root.scheduleRootSearches(); return }
    // A stale response for a search identity (query + sourceFilter +
    // root generation) the UI has already moved on from -- drop it
    // entirely (including not scheduling more queued work for an
    // abandoned search) rather than overwriting newer results. See
    // searchIdentity()'s own comment for why this checks more than just
    // the query string.
    if (root.pendingSearchIdentity !== root.searchIdentity()) return
    var lines = output.split("\n").filter(function(l) { return l.length > 0 })
    var out = []
    // Issue #59: resultFor() returns null for a candidate that matched
    // fd's own single bounded term but is missing one of the OTHER
    // query terms anywhere in its path -- fd itself only ever checked
    // the one term it was given (see buildFdArgs), so this is the only
    // place the rest are actually enforced.
    for (var i = 0; i < lines.length; i++) {
      var r = root.resultFor(lines[i], root.pendingTerms)
      if (r) out.push(r)
    }
    root.rootResults[rootPath] = out
    root.rootStatuses[rootPath] = root.classifyExitCode(exitCode)
    root.updateDegradedStatus()
    root.publishRootResults()
    root.scheduleRootSearches()
  }

  function runSearch(query) {
    if (!root.homeDir) return
    root.pendingQuery = query
    root.pendingTerms = FileSearchRanking.tokenizeQuery(query)
    root.pendingSearchIdentity = root.searchIdentity()
    root.rootResults = ({})
    root.rootStatuses = ({})
    root.hasDegradedRoot = false
    // Stop whatever the previous search's workers were still doing --
    // their own eventual completion would be discarded anyway (the
    // staleness check above), but there's no reason to let them keep
    // running for an abandoned search. Safe when already idle. Issue
    // #58: stopWorker() deliberately does NOT free the pool slot -- see
    // its own comment for why an early free would let
    // scheduleRootSearches() below reassign this same worker to a NEW
    // root before the old (still-dying) process's onExited fires,
    // corrupting that new root's own status/output.
    for (var i = 0; i < root.rootWorkers.length; i++) root.stopWorker(i)
    // fd accepts multiple trailing path roots in one invocation, but
    // issue #54 deliberately does NOT use that -- one root per process
    // instead, so a slow/unhealthy root can't hold back the others (see
    // this provider's own header comment above for the confirmed
    // measurement backing that). If sourceFilter picked exactly one
    // root, only that one is ever queued.
    if (root.sourceFilter) {
      root.rootSearchQueue = [root.sourceFilter]
    } else {
      // Issue #61: Home is now conditional on config.includeHome rather
      // than always the first root -- a user who's turned it off (and
      // has other roots configured) shouldn't have it silently
      // searched anyway.
      var roots = root.searchConfig.includeHome ? [root.homeDir] : []
      // Issue #53: filename/folder search walks EVERY effective root
      // regardless of local vs remote -- only automatic CONTENT search
      // (FileContentSearchProvider's own runSearch) excludes remote
      // roots by default, since a plain listing is comparatively
      // lightweight even over a network mount (unlike recursively
      // opening file contents). effectiveExtraRoots is already
      // config-filtered (issue #61) -- disabled auto-roots and excluded
      // subtrees never reach here at all.
      for (var j = 0; j < root.effectiveExtraRoots.length; j++) roots.push(root.effectiveExtraRoots[j].path)
      root.rootSearchQueue = roots
    }
    // Issue #64: a mount/custom root that IS (not merely under) an
    // exclusion already never reaches effectiveExtraRoots at all (see
    // computeEffectiveExtraRoots' own isUnderAnyExcludedPath check) --
    // this covers the one remaining case that filter can't: Home itself
    // exactly matching a configured excludePaths entry. "Where the
    // exclusion is equal to the worker root itself, skip that root
    // entirely instead of launching a process only to exclude everything
    // beneath it" -- applied uniformly here (covers the sourceFilter
    // branch above too) rather than duplicated per branch.
    root.rootSearchQueue = root.rootSearchQueue.filter(function(r) {
      return !LauncherSearchConfig.rootExactlyExcluded(r, root.searchConfig.excludePaths, root.homeDir)
    })
    // Issue #65: compact overlapping/nested roots (e.g. Home enabled
    // alongside a custom root that's really just one of Home's own
    // subdirectories) into the minimal covering set before scheduling
    // workers -- the covering root's own traversal already reaches
    // everything a nested one would, so searching both is pure wasted
    // filesystem work. One constant policyKey for every root here --
    // filename search doesn't distinguish local/remote at all (#53's own
    // policy split only applies to automatic CONTENT search), so nothing
    // stops any two roots here from compacting together regardless of
    // fstype. Applied AFTER the rootExactlyExcluded filter above, not
    // before -- see compactRoots' own comment for why the order matters.
    root.rootSearchQueue = LauncherSearchConfig.compactRoots(
      root.rootSearchQueue.map(function(p) { return { path: p, policyKey: "any" } }),
      { excludePaths: root.searchConfig.excludePaths, homeDir: root.homeDir }
    ).map(function(r) { return r.path })
    // Issue #61: an empty effective root set (Home off, nothing else
    // configured/enabled) means no worker will ever start, so
    // publishRootResults() -- normally only called from a real worker's
    // own completion -- would never run either, leaving lastResults
    // stuck on whatever a PREVIOUS, differently-configured search last
    // found. Publish the correctly-empty result immediately instead.
    if (root.rootSearchQueue.length === 0) root.publishRootResults()
    root.scheduleRootSearches()
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

  // Issue #59: scored against EVERY term, taking the best result -- not
  // just the one term fd used for candidate generation. A query like
  // "ruixen readme" against ~/Projects/ruixen-shell/README.md should
  // rank as a strong (exact-basename-level) match even though the
  // LONGER/candidate term ("ruixen") only appears in the parent path,
  // not the basename -- it's the OTHER term ("readme") that hits the
  // basename exactly, and the max here surfaces that rather than
  // scoring against an arbitrarily "primary" term alone.
  function scoreFile(name, terms, isDir) {
    var best = -Infinity
    for (var i = 0; i < terms.length; i++) {
      var s = FileSearchRanking.scoreFile(name, terms[i], isDir, root.dirBonus)
      if (s > best) best = s
    }
    return best
  }

  // rawPath may carry fd's own trailing "/" marking a directory match --
  // stripped before use as the real name/breadcrumb/action path.
  // Returns null for a multi-term query whose OTHER terms (beyond the
  // one fd itself already matched, see buildFdArgs) aren't found
  // anywhere in this candidate's own path -- fd only ever checked ONE
  // term, so anything less than a full pathSatisfiesAllTerms pass here
  // isn't actually a match for the query as a whole and must not be
  // shown, not just ranked low.
  function resultFor(rawPath, terms) {
    var parsed = FileSearchRanking.parseRawPath(rawPath)
    if (terms.length > 1 && !FileSearchRanking.pathSatisfiesAllTerms(parsed.path, terms)) return null
    // Issue #60: pure extension-based classification (no stat/MIME
    // subprocess per candidate) -- "All" always passes.
    if (!FileSearchRanking.matchesCategory(FileSearchRanking.categoryForPath(parsed.name, parsed.isDir), root.categoryFilter)) return null
    var dir = FileSearchRanking.abbreviateHome(parsed.dir, root.homeDir)
    return {
      id: "file:" + parsed.path,
      providerId: "file-search",
      icon: parsed.isDir ? "" : "",
      label: parsed.name,
      breadcrumb: dir,
      kind: parsed.isDir ? "Folder" : "File",
      providerName: root.providerName,
      score: root.scoreFile(parsed.name, terms, parsed.isDir),
      action: { type: "open", path: parsed.path }
    }
  }

  // Issue #54: four workers, a small fixed pool rather than one process
  // per discovered root unconditionally (see rootWorkers' own comment
  // above for why a bound matters) or dynamically-created Process
  // objects (a fixed static pool avoids the extra lifecycle complexity
  // of creating/destroying QML objects on every search). Each calls the
  // shared handleRootSearchDone() naming its OWN fixed index into
  // rootWorkers explicitly, since a QML signal handler has no built-in
  // way to identify its own sender -- issue #58: which root each
  // worker's own index is (or was) assigned lives in root.pool
  // (WorkerPool.js), not a per-worker property, so a stale completion
  // can never read a value some other, later invocation already
  // overwrote.
  //
  // Issue #55: completion moved from stdout's own onStreamFinished to
  // the Process's own onExited -- confirmed live (a standalone
  // Quickshell harness) that onStreamFinished always fires BEFORE
  // onExited, for both a normal exit and a `timeout`-killed one, so
  // stashing the collected text into pendingOutput there and finalizing
  // in onExited (which alone carries the real exit code) reliably
  // combines both pieces of information the status classification
  // needs -- text-only completion had no way to tell "genuinely zero
  // matches" apart from "this root's own search never finished".
  Process {
    id: rootWorker0
    property string pendingOutput: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: rootWorker0.pendingOutput = text }
    onExited: (exitCode, exitStatus) => root.handleRootSearchDone(0, exitCode)
  }
  Process {
    id: rootWorker1
    property string pendingOutput: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: rootWorker1.pendingOutput = text }
    onExited: (exitCode, exitStatus) => root.handleRootSearchDone(1, exitCode)
  }
  Process {
    id: rootWorker2
    property string pendingOutput: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: rootWorker2.pendingOutput = text }
    onExited: (exitCode, exitStatus) => root.handleRootSearchDone(2, exitCode)
  }
  Process {
    id: rootWorker3
    property string pendingOutput: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: rootWorker3.pendingOutput = text }
    onExited: (exitCode, exitStatus) => root.handleRootSearchDone(3, exitCode)
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

  // Issue #56: same extension-based check as isVideoPath/isTextPath
  // above -- kicked off in parallel with stat rather than waiting for
  // fileKindFor()'s own result (Launcher.qml's own isImagePreview
  // already recognizes exactly these Kind strings; this list is the
  // same set by extension instead, so the lookup below can start
  // immediately).
  readonly property var imageExtensions: ["png", "jpg", "jpeg", "gif", "webp", "bmp", "svg"]
  function isImagePath(path) {
    var dot = path.lastIndexOf(".")
    if (dot <= 0) return false
    return root.imageExtensions.indexOf(path.substring(dot + 1).toLowerCase()) !== -1
  }

  property string pendingVideoPath: ""
  property string videoDuration: ""

  // Issue #56: real pixel dimensions read via `file` (a header parse,
  // not a decode -- confirmed live: instant even on an 8000x6000 test
  // JPEG) rather than off the displayed thumbnail's own sourceSize.
  // That distinction matters once the preview Image below gets its own
  // sourceSize bound to the small preview box (the actual fix for this
  // issue's own memory concern) -- reading sourceSize back at that point
  // would report the BOUNDED decode size, not the source's real
  // dimensions, silently breaking the "Dimensions" metadata field.
  property string pendingImageDimensionsPath: ""
  property string imageDimensions: ""

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
    root.pendingImageDimensionsPath = ""
    root.imageDimensions = ""
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
    imageDimensionsProc.running = false
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
    if (root.isImagePath(path)) {
      root.pendingImageDimensionsPath = path
      imageDimensionsProc.exec(["file", "--", path])
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

  // `file` reads just the format header (JPEG's SOF marker, PNG's IHDR
  // chunk, ...), not the full pixel data -- confirmed live: instant even
  // on an 8000x6000 test JPEG, unlike a real decode. Output already
  // contains the real dimensions in plain text for every format issue
  // #56 cares about (confirmed against real JPEG/PNG/GIF/WebP/BMP
  // samples), just formatted slightly differently per format ("WxH" for
  // JPEG/GIF/WebP, "W x H" for PNG/BMP) -- one regex handles both.
  Process {
    id: imageDimensionsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.pendingImageDimensionsPath === "" || root.pendingImageDimensionsPath !== root.pendingDetailsPath) return
        root.imageDimensions = FileSearchRanking.parseFileDimensions(text)
      }
    }
  }
}
