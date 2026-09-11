import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "LauncherHelpers.js" as LauncherHelpers
import "FileSearchRanking.js" as FileSearchRanking
import "LauncherQueryOperators.js" as LauncherQueryOperators

// Raycast/Spotlight-style command palette. Root contract copied from
// ruixen.settings/Settings.qml (confirmed by reading it directly --
// property shell/manifest injected by the host, open()/close()/
// dismiss()/toggle(), a PanelWindow whose visible follows root.opened)
// -- NOT from ruixen.notch/Overlay.qml/LauncherContent.qml, which are
// notch-embedded and animate their own size. That combination
// (WlrKeyboardFocus.Exclusive + a resizing/masked silhouette) caused a
// real, non-deterministic MultiEffect masking bug there before -- this
// card is a plain rounded rectangle (shadow only, no silhouette mask).
// Card height is a fixed viewport (see visibleRowCount below) rather
// than driven by the result count, so that risk doesn't apply here
// anyway -- content beyond the viewport scrolls (a real ListView, not
// a plain Column+clip like the very first cut of this file), so the
// full command list is reachable, not just whatever fits on screen.
//
// Providers (OmarchyActionsProvider, AppSearchProvider,
// FileSearchProvider) are the only three built so far, on purpose --
// direct instruction not to build every provider at once. Each is a
// small QML Item exposing providerName/ready/search(query)/
// activate(result); Launcher.qml never inspects a result to decide how
// to run it, always provider.activate(result) looked up by
// result.providerId. Adding a future provider (Kanban capture,
// calculator, ...) is one new file + one entry in root.providers below
// -- nothing else here changes.
//
// Issue #57: this file used to also own every visual detail of the
// search bar, result rows, the Search Files details/preview panel, and
// the empty/degraded states inline -- split into SearchHeader.qml,
// ResultsList.qml/ResultRow.qml, FileDetailsPanel.qml/FilePreview.qml,
// and EmptyState.qml, each a focused presentational component. This
// file stays the coordinator: shell lifecycle, query/mode/source
// state, provider wiring, the merged/ranked results list, selection,
// and the derived preview/metadata values those components render --
// no visual/behavior change from the pre-split version, verified live
// (see this issue's own closing comment for the exact checklist).
Item {
  id: root
  property var shell: null
  property var manifest: null

  property bool opened: false

  // Same theme-aware-with-safety-net treatment as ruixen.settings/
  // ruixen.notch/ruixen.bar (see Settings.qml's own themeForeground
  // comment for the full reasoning).
  readonly property color themeForeground: Color.bar.text
  readonly property real themeForegroundLuminance: 0.299 * themeForeground.r + 0.587 * themeForeground.g + 0.114 * themeForeground.b
  readonly property color safeForeground: "#e8e8e8"
  readonly property color textColor: themeForegroundLuminance > 0.45 ? themeForeground : safeForeground
  readonly property color muted: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5)
  readonly property color accent: Color.accent

  // The card's own frosted-glass background -- translucent so Hyprland's
  // real compositor blur (a `layer_rule` keyed to this window's own
  // WlrLayershell.namespace, see hyprland/looknfeel.ruixen.lua) has
  // something to actually show through, at 0.4 alpha the panel's own
  // `ignore_alpha` layer-rule threshold would skip blurring it entirely.
  //
  // Black tinted with the active theme's own accent (Qt.tint blends
  // tintColor over baseColor weighted by the tint's own alpha). 0.12
  // read as barely-there once actually live -- direct follow-up ("not
  // seeing that much tint... maybe more") -- bumped to 0.25, still
  // black-dominant (translucency + the dark base under it keep this
  // from becoming a lighter theme-colored surface) but the accent hue
  // itself should now actually read. Black stays the foundation on
  // purpose: a full theme background token (what the maajix/omarchy-
  // spotlight reference this was ported from actually uses) was
  // already tried and explicitly rejected earlier as too theme-token-
  // influenced/light; this is theme identity on top of that same
  // hardcoded-black foundation, not a reversal of it.
  readonly property color glassTint: Qt.tint("#000000", Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.25))
  readonly property color glassBackground: Qt.rgba(glassTint.r, glassTint.g, glassTint.b, 0.68)
  readonly property color glassBorder: Qt.rgba(1, 1, 1, 0.08)

  readonly property string fontFamily: "JetBrainsMono Nerd Font"

  // Fixed-size "tray" card -- always sized for this many visible rows
  // regardless of how many results actually match, so the panel doesn't
  // grow/shrink/jump as the query changes (Raycast keeps its own window
  // size fixed the same way). This is a viewport size, not a result
  // cap -- extra results scroll instead of being cut off, so the full
  // command list is always reachable.
  readonly property int visibleRowCount: 10
  readonly property int rowHeight: 44
  readonly property int headerHeight: 26
  // "Scrolloff" -- direct request: keyboard nav used to scroll the bare
  // minimum to keep the selected row in view (Qt's own ListView.Contain
  // mode), so it could ride flush against the very top/bottom edge with
  // zero look-ahead until the NEXT press finally triggered a scroll.
  // This many rows of context stay visible ahead of/behind the
  // selection instead, the same "scrolloff" idea vim's own scrolloff
  // setting names -- see onSelectedIndexChanged below for how it's
  // applied with plain positionViewAtIndex calls (no custom Flickable
  // math needed).
  readonly property int scrollOff: 2
  // Shared by SearchHeader's own sourceFilterButton (the closed
  // control) and sourceFilterList below (the opened menu) -- same
  // width on both so they read as one dropdown widget rather than a
  // button with a mismatched panel underneath.
  readonly property int sourceFilterWidth: 150

  function open(payloadJson) {
    root.opened = true
    // Issue #50: this plugin is keepLoaded, so the shell can stay alive
    // for a long session while real system state (an installed package,
    // a user's own menu/keybind edit, a `when` guard's truth value)
    // changes underneath it -- without this, the action catalog/
    // visibility/keybind hints could only ever reflect whatever was true
    // at the LAST full shell restart. Cheap: a few local file reads plus
    // one short bash guard-eval script, not run per keystroke.
    omarchyActionsProvider.refresh()
    Qt.callLater(function() { searchHeader.focusInput() })
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "ruixen.launcher")
  }

  function toggle(payloadJson) {
    if (root.opened) root.dismiss()
    else root.open(payloadJson)
  }

  onOpenedChanged: {
    if (!root.opened) {
      searchHeader.text = ""
      root.query = ""
      root.filesMode = false
      root.actionsMenuOpen = false
      root.hasScopeHistory = false
    }
  }

  property string query: ""
  property int selectedIndex: 0
  // Raycast's own real behavior, checked live: plain files don't mix
  // into the main result list at all (too spammy once a query matches
  // hundreds of them) -- instead there's a permanent "Use ... with"
  // fallback row (Search Files, Search Google, Define word, ...) that
  // switches the whole view into that provider's own dedicated search.
  // filesMode is that switch here -- Applications/Commands/Folders
  // stay in the main "Results" list always (folders are relatively
  // rare/meaningful, not the spammy part), plain Files only appear
  // once this fallback row is actually activated.
  property bool filesMode: false
  // "" means every known root (the source-filter dropdown's own "All Sources"
  // entry); a specific path restricts Search Files to just that drive.
  // Reset to "" on every fresh entry into Search Files -- "defaults to
  // All" should mean that literally each time, not just the first time.
  property string selectedSourcePath: ""
  // Issue #62: "Search inside this folder" scopes selectedSourcePath to
  // an arbitrary folder for the rest of the session -- these two track
  // the ONE previous value so Escape can restore it (rather than
  // immediately drilling out of Search Files entirely), per the scope
  // this feature was folded in under. A plain string alone can't
  // distinguish "no history" from "history was All Sources" (also "",
  // the same sentinel selectedSourcePath itself uses), hence the
  // separate bool.
  property string scopeHistoryPrevious: ""
  property bool hasScopeHistory: false
  // Issue #60: type/scope/hidden Search Files filters -- deliberately
  // NOT reset on entering/leaving Search Files (unlike selectedSourcePath
  // above) or on close/reopen. Session persistence is fine per this
  // issue's own acceptance criteria; durable cross-session preferences
  // are a separate, later feature (#61).
  property string categoryFilter: "All"
  // "both" | "names" | "contents" -- gates which provider's own query
  // binding is even live, below, reusing the exact mechanism filesMode
  // already uses to stop a provider running at all (an empty query
  // already means "stop debouncing, clear results, stop any in-flight
  // process" in both providers).
  property string searchScope: "both"
  property bool hiddenFilesEnabled: false

  // Issue #63: keyboard-first operators (type:/kind:, in:/source:,
  // name:/content:, hidden:) parsed straight out of the live query
  // text -- only meaningful in Search Files mode; outside it the raw
  // text passes through completely untouched (an Applications/Commands
  // query like "in the loop" should search for exactly that literal
  // text, never be reinterpreted).
  readonly property var parsedFilesQuery: root.filesMode ? LauncherQueryOperators.parseQuery(root.query) : { text: root.query }

  // Precedence per this issue's own acceptance criteria: a recognized
  // operator overrides the corresponding SESSION filter (the visible
  // SearchFiltersBar/source-dropdown controls) only for as long as it's
  // present in the query text -- there is no separate persisted
  // "override" state to fall out of sync with those controls, this is
  // recomputed fresh from the current query every time, so removing the
  // operator (editing it back out) automatically reverts to whatever
  // the session filter already was. An operator whose value doesn't
  // resolve to anything real (resolveCategoryOperator/
  // resolveSourceOperator returning null) falls back to the session
  // filter too, same as if the operator hadn't been recognized at all
  // -- never a silent "filter to nothing".
  //
  // Deliberately does NOT update the visible filter control labels
  // (SearchFiltersBar's own Type/Scope/Hidden buttons, the source
  // dropdown) -- only the actual search behavior. Issue #63's own
  // acceptance criteria treats that as a "where practical" nice-to-
  // have, not a hard requirement, and wiring live label feedback
  // through would mean threading a second, transient value into every
  // one of those controls alongside the real session state they
  // already show -- a real complexity/value tradeoff, not free.
  readonly property string effectiveCategoryFilter: {
    if (root.parsedFilesQuery.type !== undefined) {
      var resolved = LauncherQueryOperators.resolveCategoryOperator(root.parsedFilesQuery.type, FileSearchRanking.fileCategoryNames())
      if (resolved) return resolved
    }
    return root.categoryFilter
  }
  readonly property string effectiveSearchScope: root.parsedFilesQuery.scope !== undefined ? root.parsedFilesQuery.scope : root.searchScope
  readonly property bool effectiveHiddenFilesEnabled: root.parsedFilesQuery.hidden !== undefined ? root.parsedFilesQuery.hidden : root.hiddenFilesEnabled
  readonly property string effectiveSelectedSourcePath: {
    if (root.parsedFilesQuery.source !== undefined) {
      var resolved = LauncherQueryOperators.resolveSourceOperator(root.parsedFilesQuery.source, fileSearchProvider.sources)
      if (resolved !== null) return resolved
    }
    return root.selectedSourcePath
  }

  onFilesModeChanged: {
    // Re-discovers mounted secondary drives (see FileSearchProvider's
    // own refreshRoots()) each time Search Files is entered, rather
    // than once at startup or on a timer -- a drive plugged in mid-
    // session (a USB stick, say) becomes searchable the next time this
    // view opens, without needing a full shell restart.
    if (root.filesMode) fileSearchProvider.refreshRoots()
    root.selectedSourcePath = ""
    root.hasScopeHistory = false
    root.actionsMenuOpen = false
    searchHeader.dropdownOpen = false
    root.selectedIndex = 0
    Qt.callLater(function() { resultsList.positionViewAtBeginning() })
  }
  onQueryChanged: {
    root.selectedIndex = 0
    root.actionsMenuOpen = false
    if (root.query.trim() === "") root.filesMode = false
    // Qt.callLater so this runs after selectedIndex's own change
    // already scrolled toward index 0 -- positionViewAtBeginning
    // additionally clears the top section header into view, which
    // ListView.Contain alone (from the selectedIndex handler below)
    // doesn't guarantee.
    Qt.callLater(function() { resultsList.positionViewAtBeginning() })
  }
  // Contain-ing a point scrollOff rows AHEAD of (and behind) the actual
  // selection first means the list scrolls a beat early, revealing that
  // many rows of what's coming before the selection itself would ever
  // reach the edge -- Contain only ever scrolls the minimum distance
  // needed, so this can't overshoot, and clamping both probes to the
  // real result range means the true start/end of the list still comes
  // flush against the edge with no artificial padding beyond it. The
  // plain selectedIndex call last is then always a no-op (already
  // contained by the wider of the other two), kept only so the very
  // first selection on a fresh query is still handled the same way.
  onSelectedIndexChanged: {
    // The selection moving out from under an open actions menu (mouse
    // hover, a fresh query/filesMode reset -- see their own handlers
    // above) would otherwise leave the menu open against a DIFFERENT
    // result than the one it was opened for. Actions-menu-only
    // navigation (see openActionsMenu()'s own up/down redirect) moves
    // actionsSelectedIndex instead, never this property, so it can
    // never trigger this itself.
    root.actionsMenuOpen = false
    var lastIndex = root.results.length - 1
    resultsList.positionViewAtIndex(Math.min(root.selectedIndex + root.scrollOff, lastIndex), ListView.Contain)
    resultsList.positionViewAtIndex(Math.max(root.selectedIndex - root.scrollOff, 0), ListView.Contain)
    resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  AppLibrary { id: appLibrary }
  OmarchyActionsProvider { id: omarchyActionsProvider }
  // maxResults is a sanity cap on matches, not a display limit -- the
  // results list scrolls now, so this no longer needs to track the
  // fixed card's own visibleRowCount.
  AppSearchProvider { id: appSearchProvider; appLibrary: appLibrary }
  // Issue #49: query bound to "" outside Search Files mode -- both file
  // providers otherwise ran a real fd/rg subprocess (across every
  // discovered root, rclone/FUSE mounts included) on every ordinary
  // Applications/Commands keystroke even though file results are never
  // shown outside filesMode. onQueryChanged in each provider already
  // treats an empty query as "stop debouncing, clear results, stop any
  // in-flight process" (see FileSearchProvider's own handler), so
  // flipping filesMode off both cancels in-flight work and prevents new
  // work from starting, with no separate cancellation path needed here.
  FileSearchProvider {
    id: fileSearchProvider
    // Issue #60: "Names"/"Both" run this provider; "Contents" gates it
    // off entirely the same way leaving Search Files already does.
    // Issue #63: the EFFECTIVE scope/text/source/category (session
    // filter, unless a query operator overrides it) -- see
    // effectiveSearchScope's own comment above.
    query: (root.filesMode && root.effectiveSearchScope !== "contents") ? root.parsedFilesQuery.text : ""
    sourceFilter: root.effectiveSelectedSourcePath
    categoryFilter: root.effectiveCategoryFilter
    hiddenEnabled: root.effectiveHiddenFilesEnabled
  }
  // homeDir/extraRoots bound straight from fileSearchProvider's own
  // already-discovered values (see this file's own header comment) --
  // one mount-discovery pass shared by both providers, not two that
  // could disagree.
  FileContentSearchProvider {
    id: fileContentSearchProvider
    // Issue #60: "Contents"/"Both" run this provider; "Names" gates it
    // off, same mechanism. A "Folders" category filter ALSO gates it
    // off outright -- rg never matches a directory, so running it at
    // all when only folders are wanted could only ever waste a real
    // filesystem walk for zero possible results. Issue #63: effective
    // values, same as FileSearchProvider's own instantiation above.
    query: (root.filesMode && root.effectiveSearchScope !== "names" && root.effectiveCategoryFilter !== "Folders") ? root.parsedFilesQuery.text : ""
    sourceFilter: root.effectiveSelectedSourcePath
    categoryFilter: root.effectiveCategoryFilter
    hiddenEnabled: root.effectiveHiddenFilesEnabled
    homeDir: fileSearchProvider.homeDir
    // Issue #61: the EFFECTIVE (config-filtered) extra roots, not
    // FileSearchProvider's own raw auto-discovered list -- one place
    // (FileSearchProvider's own effectiveExtraRoots) decides what the
    // user's config actually means, this provider just inherits it.
    extraRoots: fileSearchProvider.effectiveExtraRoots
    includeHome: fileSearchProvider.searchConfig.includeHome
  }

  readonly property var providers: [
    { id: "omarchy-actions", item: omarchyActionsProvider },
    { id: "app-search", item: appSearchProvider },
    { id: "file-search", item: fileSearchProvider },
    { id: "file-content-search", item: fileContentSearchProvider }
  ]

  function byScoreDesc(a, b) { return (b.score || 0) - (a.score || 0) }

  // Search Files rows dropped their own path subtitle (see ResultRow's
  // own labelText comment), so two folders/files that happen to share a
  // bare name (e.g. a "projects-plans" under both "dog" and "cats")
  // would otherwise render as identical, unlabeled rows with no way to
  // tell them apart. Prefixes the immediate PARENT folder's own name
  // (not the whole path -- that's what the details panel's own "Where"
  // field is for) only onto labels that actually collide within the
  // current result set, e.g. "dog/projects-plans" and
  // "cats/projects-plans" -- a name with no duplicate stays untouched.
  function disambiguateLabels(rows) {
    return LauncherHelpers.disambiguateLabels(rows)
  }

  function formatSize(bytes) {
    return LauncherHelpers.formatSize(bytes)
  }

  function formatDate(epochSeconds) {
    if (!epochSeconds) return ""
    return Qt.formatDateTime(new Date(epochSeconds * 1000), "MMM d, yyyy  h:mm AP")
  }

  // Derives "Where" straight from the real path, generically for any
  // provider's result -- not a per-provider breadcrumb convention.
  // Needed once FileContentSearchProvider's own results existed: its
  // breadcrumb is deliberately the matched LINE snippet (the whole
  // point of "search by context" -- see its own resultFor() comment),
  // so reusing that same field for "Where" would show a line of file
  // content where a folder location belongs.
  function parentDirOf(path) {
    return LauncherHelpers.parentDirOf(path, fileSearchProvider.homeDir)
  }

  // The single synthetic "Use ... with" fallback row -- not a real
  // provider result (there's no search() behind it, just a switch).
  // providerId "files-fallback" is special-cased in activateSelected()
  // below: activating it flips filesMode on instead of running
  // anything.
  //
  // "File Search" as the subtitle (not "for '<query>'") and "Command"
  // as the kind are deliberate: a future content-search fallback
  // ("Search File Contents", discussed but not built) is meant to read
  // as a SECOND command from that same "File Search" extension, the
  // way Raycast shows one extension's name as the shared subtitle
  // across each of its own commands -- not a third unrelated provider.
  // Adding it later is one more object here (same subtitle, different
  // label/id), not a structural change.
  function filesFallbackRow(q) {
    return {
      id: "fallback:files",
      providerId: "files-fallback",
      // fa-folder_open (U+F07C), written as a \u escape (not a pasted
      // glyph -- this repo's own convention for PUA glyphs, see
      // ruixen.pluginpins/BarWidget.qml's own comment) so the tool
      // that wrote this file can't silently drop the raw bytes.
      // Deliberately NOT fa-search/U+F002 -- direct follow-up ("give
      // it one but not the magnifying glass by itself cause thats for
      // launcher/search thing already"): that glyph already means
      // "search" everywhere else in this file (SearchHeader's own
      // icon, EmptyState's "No Results" icon), so reusing it here
      // would read as a duplicate of the search box itself rather
      // than a distinct row. Plain fa-folder (real folder results'
      // own icon, see FileSearchProvider.qml) was the other candidate,
      // but read too much like "this row IS a folder" -- folder_open
      // reads as "browse/open your files" instead, matching what
      // activating this row actually does.
      icon: "",
      label: "Search Files",
      breadcrumb: "File Search",
      kind: "Command",
      providerName: "",
      score: 0,
      sectionLabel: "Use \"" + q + "\" with"
    }
  }

  // A single flat list, each row tagged with its own sectionLabel --
  // fed straight into ResultsList's own model, which draws the group
  // headers and keeps the list virtualized (real perf concern once
  // Commands lists every actionable entry, not just a handful).
  //
  // Empty query keeps real, separate "Suggestions"/"Commands" groups --
  // curated defaults plus the full command list below them, distinct
  // groups because there's no query to rank them against each other by.
  //
  // A non-empty query collapses Applications/Commands into ONE
  // "Results" section, globally sorted by score -- confirmed directly
  // against Raycast's own actual behavior (checked live): typing a
  // query drops per-source headers and shows one flat, relevance-
  // ranked list. Files AND Folders both stay out of this list entirely
  // (folders used to be the one exception, merged in here -- moved
  // into Search Files alongside files instead, so growing the Commands
  // list later, e.g. a Kanban "Create Task"/"Update Task Status", never
  // has to compete against filesystem noise for space here) -- also
  // confirmed directly against Raycast's own real behavior: it doesn't
  // inline file results either (too spammy once a query matches
  // hundreds of them), offering a "Use ... with" fallback row instead.
  // filesMode (flipped by activating that row) switches the whole list
  // over to file+folder results for the same query, folders ranked
  // above files there (FileSearchProvider's own dirBonus) -- that
  // priority only has to make sense against other filesystem results
  // now, not against Applications/Commands too.
  readonly property var results: {
    var q = root.query.trim()
    function tag(rows, label) {
      for (var i = 0; i < rows.length; i++) rows[i].sectionLabel = label
      return rows
    }
    if (q === "") {
      var sug = tag(omarchyActionsProvider.suggestions(), "Suggestions")
      var browse = tag(omarchyActionsProvider.browse(omarchyActionsProvider.suggestedIds), "Commands")
      return sug.concat(browse)
    }
    // FileSearchProvider/FileContentSearchProvider are both asynchronous
    // (real fd/ripgrep subprocesses, not a synchronous scan) -- each
    // one's own query property is bound directly to root.query (see
    // their instantiation above), and each kicks off its OWN debounced
    // re-search from its own onQueryChanged, not from search() itself
    // (a property WRITE as a side effect of THIS binding's own
    // evaluation caused a real "Binding loop detected" warning,
    // confirmed live, back when there was only one such provider).
    // search(q) on each is a pure read of whatever its last completed
    // search found; reading lastResults (indirectly, through search())
    // still makes this binding depend on both, so results updates
    // automatically once either one's output lands -- independently,
    // not gated on the other. Concatenated BEFORE the shared sort, not
    // as two separate sections: content matches carry a flat score well
    // below any real filename match (see FileContentSearchProvider's
    // own contentMatchScore), so they only ever rank after genuine
    // filename hits, filling in around them rather than needing a
    // separate mode -- and turn a query with zero filename matches into
    // real content-match results instead of "No Results", without ever
    // skipping the content search itself to get there.
    if (root.filesMode) {
      var fileRows = fileSearchProvider.search(q).concat(fileContentSearchProvider.search(q))
      return tag(root.disambiguateLabels(fileRows.sort(root.byScoreDesc)), "Search Files")
    }
    var cmds = omarchyActionsProvider.search(q)
    var apps = appSearchProvider.search(q)
    var all = cmds.concat(apps).sort(root.byScoreDesc)
    return tag(all, "Results").concat([root.filesFallbackRow(q)])
  }

  // Empty state -- Search Files ONLY, deliberately. It has no fallback
  // row of its own to fall back on, so zero matches there is a
  // genuinely bare list with nothing else to do. The main Results view
  // always has the "Use ... with" fallback row appended (see
  // filesFallbackRow above) even when Applications/Commands find
  // nothing -- showing a big "No Results" glyph there on top of that
  // fallback made it read as a dead end when it isn't one; confirmed
  // directly, the fallback row was still right there underneath it.
  readonly property bool showNoResults: root.filesMode && root.query.trim() !== "" && root.results.length === 0

  // Issue #55: a genuinely empty result and a search that never
  // actually finished (a timed-out or failed root) used to render
  // identically -- both just an empty results list -- which made real
  // field reports hard to diagnose (this project's own "No Results for
  // ruixen-doctor" investigation turned out to be a stale checkout, not
  // a real bug, but a degraded indicator would have ruled that out in
  // seconds). Deliberately minimal: one combined boolean, not a full
  // per-root breakdown surfaced in the UI, per direct product guidance
  // ("a small note, not an elaborate status system").
  readonly property bool filesSearchDegraded: root.filesMode && root.query.trim() !== ""
    && (fileSearchProvider.hasDegradedRoot || fileContentSearchProvider.hasDegradedRoot)

  // Drives the Search Files details panel -- whichever row is
  // currently selected, or null between/at the edges of the list.
  // FileSearchProvider.qml doesn't know about selection at all; this
  // just tells it which path to stat() whenever that changes.
  readonly property var selectedResult: root.results[root.selectedIndex] || null
  // No `!root.filesMode` early return -- leaving Search Files mode used
  // to skip this entirely, leaving fileSearchProvider.selectedDetails
  // (and its thumbnail/type data) stale on whatever the previously-
  // selected file was. detailsPanel's own bindings then applied that
  // stale, truthy `details` to whatever non-file result got selected
  // next (an Omarchy Action's `action.command`, or the Search Files
  // fallback row's missing `action` entirely) -- confirmed live via a
  // real "Cannot open: file://undefined" / "Value is undefined" pair of
  // warnings. Only file-search results ever have `action.path`, so this
  // handler already no-ops correctly for every other result on its own;
  // the guard was redundant AND the source of the staleness bug.
  onSelectedResultChanged: {
    var path = (root.selectedResult && root.selectedResult.action) ? root.selectedResult.action.path : ""
    if (path && path !== fileSearchProvider.pendingDetailsPath) fileSearchProvider.loadDetails(path)
    else if (!path) fileSearchProvider.selectedDetails = null
  }

  // Issue #62: the contextual action list for whichever Search Files
  // result is currently selected -- empty (no menu) for anything that
  // isn't a real file/folder result (Applications/Commands, the Search
  // Files fallback row itself, or no selection at all), since none of
  // these actions mean anything for those. "Search Inside This Folder"
  // only applies to folders; every other action applies to both.
  readonly property var resultActions: {
    var r = root.selectedResult
    if (!root.filesMode || !r || !r.action || !r.action.path) return []
    var isFolder = r.kind === "Folder"
    var actions = [{ id: "open", label: isFolder ? "Open Folder" : "Open" }]
    if (isFolder) actions.push({ id: "search-inside", label: "Search Inside This Folder" })
    actions.push({ id: "open-containing", label: "Open Containing Folder" })
    actions.push({ id: "copy-path", label: "Copy Path" })
    actions.push({ id: "copy-name", label: "Copy Name" })
    actions.push({ id: "copy-parent", label: "Copy Parent Directory Path" })
    return actions
  }
  property bool actionsMenuOpen: false
  property int actionsSelectedIndex: 0
  // Issue #62 follow-up: positioned next to whichever row the menu was
  // opened for (see positionActionsMenuNearSelection below) rather than
  // a fixed card corner -- set once when the menu opens, not re-tracked
  // afterward (Up/Down while the menu is open navigates ITS OWN list,
  // never the results list underneath, so the selection this was
  // computed for can't move out from under it while it's showing).
  property real actionsMenuX: 0
  property real actionsMenuY: 0

  function openActionsMenu() {
    if (root.resultActions.length === 0) return
    root.actionsSelectedIndex = 0
    root.actionsMenuOpen = true
    searchHeader.dropdownOpen = false
    root.positionActionsMenuNearSelection()
  }

  // itemAtIndex() only returns a delegate ListView has actually
  // instantiated (it virtualizes offscreen rows) -- the existing
  // scrolloff/positionViewAtIndex navigation already keeps the selected
  // row's own delegate live in every normal case, so this should always
  // resolve; if it somehow doesn't (a query that just changed and
  // hasn't settled yet), the menu simply keeps whatever position it
  // already had rather than guessing at one.
  function positionActionsMenuNearSelection() {
    var item = resultsList.itemAtIndex(root.selectedIndex)
    if (!item) return
    // localPos.x is the row's own LEFT edge in card-local coordinates
    // (mapping (0, height), not (width, height)) -- direct request:
    // the popup should match the row's own full width and align with
    // it exactly, not just sit somewhere near it.
    var scenePos = item.mapToItem(null, 0, item.height)
    var localPos = card.mapFromItem(null, scenePos.x, scenePos.y)
    // Clamped so the popup never renders partly outside the card,
    // whichever edge the selected row happens to be near. 34/8 mirror
    // ResultActionsMenu.qml's own rowHeight/padding height formula --
    // duplicated here (not read back from the component itself) only
    // because the menu's real height needs to be known BEFORE
    // positioning it, not after.
    var menuHeight = root.resultActions.length * 34 + 8
    root.actionsMenuX = Math.max(8, Math.min(localPos.x, card.width - resultsList.width - 8))
    root.actionsMenuY = Math.max(8, Math.min(localPos.y + 4, card.height - menuHeight - 8))
  }

  function closeActionsMenu() {
    root.actionsMenuOpen = false
  }

  // Issue #62: dispatches one contextual action against the LIVE
  // selectedResult, not any cached copy -- read fresh here rather than
  // captured when the menu opened, same staleness discipline
  // onSelectedResultChanged already applies to the details panel.
  // Safe argv execution throughout (Util.execArgv already runs via
  // bash's own "$@" expansion, never string interpolation -- see
  // qs.Commons/Util.qml) -- a path/name with spaces, quotes, Unicode,
  // or a leading dash is never treated as command syntax.
  function runResultAction(id) {
    var result = root.selectedResult
    if (!result || !result.action || !result.action.path) return
    var path = result.action.path
    if (id === "open") {
      root.actionsMenuOpen = false
      root.activateSelected()
      return
    }
    if (id === "open-containing") {
      // The REAL parent path, not root.parentDirOf()'s own ~-abbreviated
      // display form -- xdg-open has no shell to expand "~" for it, and
      // a literal "~/notes" path simply wouldn't exist.
      Util.execArgv(["xdg-open", LauncherHelpers.parentDirOf(path, "")])
      root.actionsMenuOpen = false
      root.dismiss()
      return
    }
    if (id === "search-inside") {
      // Session-only scoping, per this issue's own follow-up note --
      // remembers the ONE prior source so Escape can restore it (see
      // onEscapePressed below) instead of immediately drilling all the
      // way out of Search Files. Query text is deliberately left as-is,
      // same as switching the source-filter dropdown already does.
      root.scopeHistoryPrevious = root.selectedSourcePath
      root.hasScopeHistory = true
      root.selectedSourcePath = path
      root.actionsMenuOpen = false
      return
    }
    if (id === "copy-path") {
      Util.execArgv(["wl-copy", "--", path])
      root.actionsMenuOpen = false
      return
    }
    if (id === "copy-name") {
      Util.execArgv(["wl-copy", "--", LauncherHelpers.baseName(path)])
      root.actionsMenuOpen = false
      return
    }
    if (id === "copy-parent") {
      // The REAL parent path, never the ~-abbreviated display form --
      // copy actions must copy the exact real path (direct requirement,
      // not just the "Where" field's own shorthand).
      Util.execArgv(["wl-copy", "--", LauncherHelpers.parentDirOf(path, "")])
      root.actionsMenuOpen = false
      return
    }
  }

  // Issue #57: the Search Files preview/metadata values FileDetailsPanel/
  // FilePreview now just render, moved up here from what used to be
  // detailsPanel's own inline computed properties -- Launcher.qml keeps
  // owning "what IS the current preview state", the components just
  // display whatever they're handed. No behavior change: same
  // conditions, same fallback chain, just named at the coordinator
  // level instead of on a child Rectangle's own id.
  //
  // Still-image formats get a real thumbnail instead of the generic
  // file glyph -- reuses FileSearchProvider's own extension-derived
  // "Kind" string (e.g. "PNG Image") rather than re-deriving the
  // extension here a second time. Plain truthiness, not `!== null` --
  // selectedResult/selectedDetails can transiently be `undefined`
  // rather than `null` between selections, which `!== null` doesn't
  // catch and which tripped a real "Value is undefined and could not be
  // converted to an object" warning from the Image source binding.
  readonly property bool isImagePreview: !!fileSearchProvider.selectedDetails && !!root.selectedResult &&
    ["PNG Image", "JPEG Image", "GIF Image", "WebP Image", "Bitmap Image", "SVG Image"].indexOf(fileSearchProvider.selectedDetails.type) !== -1

  // Video gets a real extracted-frame poster instead of the generic
  // glyph, same as an image gets its own file directly -- see
  // FileSearchProvider's own loadDetails/posterProc (the exact ffmpeg
  // -vframes 1 technique ruixen.notch's wallpaper picker already uses
  // for its own .mp4 tiles, sharing that same disk cache). Poster
  // generation is async and can still be running (or have failed -- a
  // corrupt video) when this is first checked, so it's gated on
  // videoPosterPath actually being populated, not just "this is a
  // video file".
  readonly property bool isVideoPreview: !!fileSearchProvider.selectedDetails && fileSearchProvider.selectedDetails.type === "Video" && fileSearchProvider.videoPosterPath !== ""
  readonly property bool hasThumbnail: root.isImagePreview || root.isVideoPreview
  readonly property string thumbnailSource: root.isImagePreview && root.selectedResult ? ("file://" + root.selectedResult.action.path)
    : root.isVideoPreview ? ("file://" + fileSearchProvider.videoPosterPath)
    : ""

  // Text preview -- same fixed preview footprint an image/video
  // thumbnail uses, but with the file's own leading content instead.
  // Gated on textPreviewContent actually having arrived (same pattern
  // as isVideoPreview above gating on videoPosterPath), not just "this
  // looks like a text extension" -- the read can still be in flight, or
  // (though unlikely for an explicit extension allowlist) come back
  // empty.
  readonly property bool isTextPreview: !root.hasThumbnail && fileSearchProvider.textPreviewContent !== ""

  // Issue #56: reads FileSearchProvider's own `file`-based lookup
  // instead of the preview Image's own sourceSize -- once that Image
  // has its own sourceSize bound to the small preview box, reading
  // sourceSize back would report the BOUNDED decode size, not the
  // source's real dimensions.
  readonly property string previewImageDimensions: root.isImagePreview ? fileSearchProvider.imageDimensions : ""

  // Dimensions/Duration/Created only appear when actually available --
  // an IIFE rather than a flat literal, since "insert this field only
  // if truthy" isn't expressible as a single ternary once there are
  // three independent optional fields instead of one.
  readonly property var detailsFields: fileSearchProvider.selectedDetails ? (function() {
    var d = fileSearchProvider.selectedDetails
    var out = [
      { label: "Name", value: root.selectedResult ? root.selectedResult.label : "" },
      { label: "Type", value: d.type }
    ]
    // Mutually exclusive in practice (isImagePreview's own type list
    // and videoExtensions never overlap), but checked independently
    // rather than else-if -- neither depends on the other being absent.
    if (root.previewImageDimensions) out.push({ label: "Dimensions", value: root.previewImageDimensions })
    if (fileSearchProvider.videoDuration) out.push({ label: "Duration", value: fileSearchProvider.videoDuration })
    out.push({ label: "Size", value: root.formatSize(d.size) })
    out.push({ label: "Where", value: (root.selectedResult && root.selectedResult.action && root.selectedResult.action.path) ? root.parentDirOf(root.selectedResult.action.path) : "" })
    // Search Files rows hide their own subtitle text entirely (see
    // ResultRow's own metaText visible: !filesMode), so a content
    // match's own breadcrumb -- the matched LINE itself, the whole
    // "search by context" feature -- had nowhere else to surface once
    // "Where" above got fixed to show the real folder instead of
    // reusing that same field. This is that field, shown only for
    // content matches (identified by providerId, not by re-deriving
    // "does this look like a snippet" from the text itself).
    if (root.selectedResult && root.selectedResult.providerId === "file-content-search")
      out.push({ label: "Match", value: root.selectedResult.breadcrumb })
    // 0 means this filesystem doesn't track birth time (see
    // FileSearchProvider's own loadDetails comment) -- omit rather than
    // show a bogus 1970 date.
    if (d.created) out.push({ label: "Created", value: root.formatDate(d.created) })
    out.push({ label: "Modified", value: root.formatDate(d.mtime) })
    out.push({ label: "Permissions", value: d.permissions })
    return out
  })() : []

  function providerFor(id) {
    for (var i = 0; i < root.providers.length; i++)
      if (root.providers[i].id === id) return root.providers[i].item
    return null
  }

  function activateSelected() {
    var result = root.results[root.selectedIndex]
    if (!result) return
    // Not a real provider result -- switches the view into file
    // search instead of running anything, and deliberately doesn't
    // dismiss (same as picking a folder to browse further would feel,
    // not like running a command).
    if (result.providerId === "files-fallback") {
      root.filesMode = true
      return
    }
    var provider = root.providerFor(result.providerId)
    if (provider) provider.activate(result)
    root.dismiss()
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "ruixen-launcher"
    // Overlay, not Top -- avoids the click-stacking contention with
    // ruixen.bar's own top-layer surface (see ruixen.notch/Overlay.qml's
    // own comment for the original finding).
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Backdrop -- click anywhere outside the card to dismiss. No dim
    // wash of its own (transparent, not root.scrim) -- direct request
    // ("we dont need the black drop... thing, just the pop up
    // spotlight"): with the card's own frosted glass, the blurred
    // desktop itself already reads as the backdrop; a separate
    // darkening layer over the whole screen fought with that rather
    // than complementing it.
    Rectangle {
      anchors.fill: parent
      color: "transparent"
      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    // Contact shadow -- a second, tighter shadow layered behind the
    // card's own softer, wider one below (a common "soft ambient +
    // tight contact" pairing real elevated glass surfaces use for more
    // perceived depth than either shadow alone gives). Needs its own
    // proxy Item, not a second shadow on `card` itself -- QML only
    // allows one layer.effect per Item. Same live-texture-source
    // pattern already proven in this file (the Search Files thumbnail
    // mask): an invisible same-shape Rectangle, layer.enabled so its
    // rendered texture is still captured despite visible:false, feeding
    // a MultiEffect. shadowOpacity 0.35 stays under the layer_rule's
    // own ignore_alpha threshold (0.4, see hyprland/looknfeel.ruixen.lua)
    // same as card's own shadow -- otherwise Hyprland's blur would hit
    // this one too.
    Rectangle {
      anchors.fill: card
      radius: card.radius
      color: "#000000"
      visible: false
      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.35
        shadowBlur: 0.15
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 2
      }
    }

    Rectangle {
      id: card
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      anchors.topMargin: parent.height * 0.22
      // Wider in Search Files mode only -- a details panel sits beside
      // the result list there (Raycast's own real Search Files does
      // the same split). Still not resizing per result COUNT (the
      // "fixed tray" property that matters), just per deliberate mode.
      width: root.filesMode ? 920 : 640
      Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
      // A fixed viewport height, not a function of the result count --
      // still a constant, so the card never grows/shrinks per state
      // (Search Files mode is the one deliberate exception, same as
      // width above -- issue #60's own filtersBar adds a fixed amount
      // matching its own topMargin+height, so resultsList keeps its
      // full visibleRowCount viewport rather than losing a row's worth
      // of space to the new filter controls). Extra content (more rows
      // than fit, or more than 2 headers) scrolls inside resultsList
      // below rather than needing to fit.
      height: 64 + root.visibleRowCount * root.rowHeight + 2 * root.headerHeight + 8 + (root.filesMode ? 36 : 0)
      Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutQuad } }
      radius: 16
      color: root.glassBackground
      border.width: 1
      border.color: root.glassBorder
      clip: true

      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#000000"
        // 0.7 (its original value, from before the frosted-glass
        // layer_rule existed) peaks above both glassBackground's own
        // alpha (0.68) and the layer_rule's ignore_alpha threshold
        // (0.4, see hyprland/looknfeel.ruixen.lua) right at the card's
        // edge -- Hyprland's own compositor blur doesn't know "this is
        // a rendered shadow, don't touch it," it just blurs every
        // pixel whose alpha clears that threshold, so the already-soft
        // shadow was getting blurred a second time. Direct report
        // ("the drop shadow looks a bit blurry or faded") confirmed
        // live. 0.3 keeps its peak comfortably under ignore_alpha, so
        // Hyprland leaves it alone -- crisp again, just a touch lighter.
        shadowOpacity: 0.3
        shadowBlur: 0.4
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 6
      }

      // Swallows a click on the card itself so it doesn't fall through
      // to the scrim's own dismiss MouseArea behind it.
      MouseArea { anchors.fill: parent }

      // Top inner highlight -- a common glass/vibrancy trick (macOS,
      // Raycast v2): the top edge reads a touch brighter than the
      // sides/bottom, faking a light source from above rather than a
      // uniformly-lit border on all four sides. Inset by radius so it
      // only spans the flat top edge, not the rounded corners -- its
      // own corners are square, and running it full-width would poke
      // past the card's own curve there.
      //
      // A horizontal gradient (fading to fully transparent at both
      // ends), not a flat color -- a solid-color bar with hard-cut
      // ends read as a drawn line/rule (direct report: "too thick...
      // looks like a line on the top edge"), not a soft glint. Peak
      // alpha also dropped 0.2 -> 0.14 at the same time.
      Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: card.radius
        anchors.rightMargin: card.radius
        anchors.topMargin: 1
        height: 1
        gradient: Gradient {
          orientation: Gradient.Horizontal
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
          GradientStop { position: 0.5; color: Qt.rgba(1, 1, 1, 0.14) }
          GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }
      }

      SearchHeader {
        id: searchHeader
        filesMode: root.filesMode
        resultCount: root.results.length
        selectedSourcePath: root.selectedSourcePath
        sources: fileSearchProvider.sources
        sourceFilterWidth: root.sourceFilterWidth
        textColor: root.textColor
        mutedColor: root.muted
        fontFamily: root.fontFamily
        onTextChanged: root.query = text
        // Issue #62: while the actions menu is open, Up/Down/Enter
        // navigate/run ITS list instead of the results list -- the menu
        // always operates on whichever result was selected when it was
        // opened, so there's no reason for these to touch selectedIndex
        // (and onSelectedIndexChanged would just close the menu right
        // back out from under itself if they did).
        onUpPressed: {
          if (root.actionsMenuOpen) { if (root.actionsSelectedIndex > 0) root.actionsSelectedIndex-- }
          else if (root.selectedIndex > 0) root.selectedIndex--
        }
        onDownPressed: {
          if (root.actionsMenuOpen) { if (root.actionsSelectedIndex < root.resultActions.length - 1) root.actionsSelectedIndex++ }
          else if (root.selectedIndex < root.results.length - 1) root.selectedIndex++
        }
        onEnterPressed: {
          if (root.actionsMenuOpen) root.runResultAction(root.resultActions[root.actionsSelectedIndex].id)
          else root.activateSelected()
        }
        onEscapePressed: {
          // Priority order: close an open actions menu, then restore a
          // "Search Inside This Folder" scope (issue #62's own follow-up
          // note -- Escape should drill back OUT of that scope, not
          // straight past it to exiting Search Files entirely), then the
          // original two steps.
          if (root.actionsMenuOpen) {
            root.closeActionsMenu()
          } else if (root.hasScopeHistory) {
            root.selectedSourcePath = root.scopeHistoryPrevious
            root.hasScopeHistory = false
          } else if (root.filesMode) {
            root.filesMode = false
          } else {
            root.dismiss()
          }
        }
        onBackClicked: root.filesMode = false
        onTabPressed: {
          if (root.actionsMenuOpen) root.closeActionsMenu()
          else root.openActionsMenu()
        }
      }

      // Issue #60: collapses to zero height (not just hidden) outside
      // Search Files -- resultsList/detailsPanel/EmptyState below all
      // anchor off its bottom edge unconditionally, so the normal
      // Applications/Commands view's own layout is completely
      // unaffected when this row isn't showing.
      SearchFiltersBar {
        id: filtersBar
        anchors.top: searchHeader.bottom
        anchors.topMargin: root.filesMode ? 4 : 0
        active: root.filesMode
        categoryFilter: root.categoryFilter
        searchScope: root.searchScope
        hiddenEnabled: root.hiddenFilesEnabled
        textColor: root.textColor
        mutedColor: root.muted
        accentColor: root.accent
        fontFamily: root.fontFamily
        onCategorySelected: (category) => root.categoryFilter = category
        onScopeSelected: (scope) => root.searchScope = scope
        onHiddenToggled: root.hiddenFilesEnabled = !root.hiddenFilesEnabled
      }

      // Closes the dropdown on any click elsewhere on the card (rows,
      // the details panel, ...) -- only present while the list is open,
      // and z-ordered between searchHeader (default z:0) and the list
      // itself (z:100) so it can't intercept normal clicks the rest of
      // the time. The outside click is consumed here rather than also
      // passed through to whatever's underneath -- a common, expected
      // dropdown convention (the first click away just dismisses). See
      // SearchHeader.qml's own header comment for why this stays here
      // rather than nested inside that component.
      MouseArea {
        anchors.fill: parent
        visible: searchHeader.dropdownOpen
        z: 50
        onClicked: searchHeader.dropdownOpen = false
      }

      // Issue #62: same outside-click-to-close convention as the
      // source-filter dropdown above, for the result-actions menu.
      MouseArea {
        anchors.fill: parent
        visible: root.actionsMenuOpen
        z: 50
        onClicked: root.closeActionsMenu()
      }

      Rectangle {
        id: sourceFilterList
        visible: searchHeader.dropdownOpen
        anchors.top: searchHeader.bottom
        anchors.topMargin: 6
        anchors.right: searchHeader.right
        // Matches sourceFilterButton's own rightMargin (12) exactly, not
        // an independent value -- its right edge lines up with the
        // button's right edge, same as this width matches its width.
        anchors.rightMargin: 12
        width: root.sourceFilterWidth
        // "All Sources" plus one row per discovered source (Home + every
        // extraRoot) -- height follows that count directly rather than
        // scrolling, since this is at most a small handful of drives.
        // 28 matches sourceRow's own height below.
        height: (fileSearchProvider.sources.length + 1) * 28 + 8
        radius: 10
        // Genuinely near-opaque, not glassBackground's own translucency
        // -- direct follow-up after real use: unlike the card (whose
        // backdrop is the blurred desktop, predictable), this dropdown
        // floats OVER the card's own content -- most awkwardly, the
        // details panel's own image thumbnail -- and translucent text
        // over an arbitrary bright thumbnail is unreadable. Still uses
        // glassTint (the same theme-accent-tinted black) for hue
        // consistency with the rest of the card, just far less see-
        // through.
        color: Qt.rgba(root.glassTint.r, root.glassTint.g, root.glassTint.b, 0.95)
        border.width: 1
        border.color: root.glassBorder
        z: 100

        layer.enabled: true
        layer.effect: MultiEffect {
          shadowEnabled: true
          shadowColor: "#000000"
          // Same fix as the card's own shadow above, same reason -- this
          // shadow's own semi-transparent falloff crossed the layer_rule's
          // ignore_alpha threshold (0.4) and got blurred a second time,
          // on top of its own already-soft edge.
          shadowOpacity: 0.3
          shadowBlur: 0.4
          shadowVerticalOffset: 3
        }

        Column {
          anchors.fill: parent
          anchors.margins: 4

          Repeater {
            // "All Sources" (path "") first, then every real source -- same
            // shape sourceFilterButton.currentLabel above already
            // expects (an empty path means All).
            model: [{ id: "", label: "All Sources", path: "" }].concat(fileSearchProvider.sources)

            delegate: Rectangle {
              id: sourceRow
              required property var modelData
              width: sourceFilterList.width - 8
              height: 28
              radius: 5
              // No hover/selected highlight box -- direct follow-up
              // ("still bigger and overlapping each other, just no
              // focus hover"): with zero spacing between rows in the
              // Column above, adjacent rows' own rounded-rect
              // highlights sat flush against each other with no gap,
              // reading as one overlapping blob rather than two
              // distinct rows. Plain text + click is simpler and
              // doesn't have that problem at all.
              color: "transparent"

              Text {
                anchors.left: parent.left
                anchors.leftMargin: 10
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                elide: Text.ElideRight
                text: sourceRow.modelData.label
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 12
              }

              MouseArea {
                anchors.fill: parent
                onClicked: {
                  root.selectedSourcePath = sourceRow.modelData.path
                  searchHeader.dropdownOpen = false
                }
              }
            }
          }
        }
      }

      // A real ListView, not a Column+Repeater -- once Commands lists
      // every actionable entry (not just a handful), the row count can
      // run into the hundreds, so this needs actual virtualization
      // (only visible delegates exist) and real scrolling, not a
      // clip:true Column that silently truncated. section.property
      // groups by each row's own sectionLabel (set in root.results)
      // and draws its own header, so there's no manual nesting to keep
      // selection math in sync with -- ResultsList's own delegate index
      // is already the same flat index as root.selectedIndex.
      ResultsList {
        id: resultsList
        anchors.top: filtersBar.bottom
        // 8 -> 4 -- direct report: felt like too much empty space now
        // that the search box's own bottom border separator is gone
        // (nothing "explains" the gap visually anymore, so it read as
        // bigger than the same 8px did before).
        anchors.topMargin: 4
        anchors.left: parent.left
        anchors.leftMargin: 8
        // Search Files mode splits the card: this list keeps the left
        // side, detailsPanel (below) takes the right -- Raycast's own
        // real Search Files layout, list left / metadata right.
        anchors.right: root.filesMode ? detailsPanel.left : parent.right
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        model: root.results
        fontFamily: root.fontFamily
        mutedColor: root.muted
        textColor: root.textColor
        accentColor: root.accent
        filesMode: root.filesMode
        selectedIndex: root.selectedIndex
        rowHeightPx: root.rowHeight
        sectionHeaderHeight: root.headerHeight
        appLibrary: appLibrary
        onRowHovered: (idx) => root.selectedIndex = idx
        onRowActivated: (idx) => { root.selectedIndex = idx; root.activateSelected() }
        onRowActionsRequested: (idx) => { root.selectedIndex = idx; root.openActionsMenu() }
      }

      // Marks the list/details boundary now that detailsPanel has no
      // surface of its own to do that job -- centered in the 8px gutter
      // between resultsList's own right edge and detailsPanel's left
      // (resultsList.right already accounts for its own rightMargin,
      // so anchoring off it directly here needs no extra math).
      Rectangle {
        visible: root.filesMode && !root.showNoResults
        anchors.top: resultsList.top
        anchors.bottom: resultsList.bottom
        anchors.left: resultsList.right
        anchors.leftMargin: 4
        width: 1
        // Vertical gradient, transparent at both ends -- direct
        // follow-up ("maybe a bit much? yea smaller tips"): the first
        // pass faded across the line's ENTIRE length (peaking only at
        // the exact midpoint), so it never really looked solid
        // anywhere. Four stops instead of three -- short fade-in/out
        // tips (0-15% and 85-100%) bookending a solid run at full
        // glassBorder alpha through the middle 70%, rather than one
        // continuous taper.
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
          GradientStop { position: 0.3; color: root.glassBorder }
          GradientStop { position: 0.7; color: root.glassBorder }
          GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
        }
      }

      // Search Files' own metadata sidebar -- Raycast's real Search
      // Files splits the same way, list left / details right. Only
      // ever shows the CURRENTLY SELECTED file's info (fetched via
      // FileSearchProvider.loadDetails(), a real `stat` call -- fd
      // itself doesn't return size/type/modified time), not anything
      // for the whole list, so it's cheap regardless of result count.
      FileDetailsPanel {
        id: detailsPanel
        visible: root.filesMode && !root.showNoResults
        anchors.top: filtersBar.bottom
        // Matches resultsList's own topMargin (see its comment) --
        // both panels need the exact same offset from filtersBar for
        // the alignment fix on the inner Column below to actually work.
        anchors.topMargin: 4
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        result: root.selectedResult
        hasThumbnail: root.hasThumbnail
        thumbnailSource: root.thumbnailSource
        isTextPreview: root.isTextPreview
        textPreviewContent: fileSearchProvider.textPreviewContent
        fields: root.detailsFields
        detailsPresent: fileSearchProvider.selectedDetails !== null
        textColor: root.textColor
        mutedColor: root.muted
        accentColor: root.accent
        fontFamily: root.fontFamily
      }

      EmptyState {
        anchors.top: filtersBar.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        showNoResults: root.showNoResults
        degraded: root.filesSearchDegraded
        sourceSelected: root.selectedSourcePath !== ""
        mutedColor: root.muted
        fontFamily: root.fontFamily
      }

      // Issue #62: same top-right popup treatment as sourceFilterList
      // (openActionsMenu() closes that dropdown first, so the two never
      // show at once) -- a transient overlay over whatever's underneath
      // while open, same as any dropdown/context menu.
      ResultActionsMenu {
        // Issue #62 follow-up: positioned next to the row it was
        // opened for (root.positionActionsMenuNearSelection) instead of
        // a fixed card corner -- plain x/y, not anchors, since the
        // target position is an arbitrary computed point, not a fixed
        // relationship to another element.
        x: root.actionsMenuX
        y: root.actionsMenuY
        // Direct request: matches the row it's for, same width every
        // ResultRow already renders at.
        menuWidth: resultsList.width
        actions: root.actionsMenuOpen ? root.resultActions : []
        selectedIndex: root.actionsSelectedIndex
        textColor: root.textColor
        accentColor: root.accent
        glassTint: root.glassTint
        glassBorder: root.glassBorder
        fontFamily: root.fontFamily
        onActionHovered: (idx) => root.actionsSelectedIndex = idx
        onActionActivated: (id) => root.runResultAction(id)
      }
    }
  }
}
