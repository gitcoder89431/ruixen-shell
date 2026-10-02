import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import "../.."
import "ThemeCatalog.js" as ThemeCatalog

// Browse bjarneo/100-themes (100 community Omarchy themes) and its
// light companion bjarneo/100-themes-day (same hues, "-day" suffix),
// without ever downloading the ~180MB full repo. Direct design decision
// after walking through the upstream repo together: "this isnt a theme
// picker grid, its more of a installer or browser" -- shaped as a left
// list + right detail pane (ExtensionTwoPanel, same component Settings
// already uses), not a Wallpapers-style grid, specifically so only ONE
// theme's preview image is ever being fetched at a time (whichever is
// currently selected), regardless of how many themes are in the list.
//
// Each repo publishes its own assets/themes.js -- a single static file
// covering every theme's real display name, slug, motif, and full
// colors (already Omarchy's own native theme schema, confirmed
// directly, no TOML parsing needed) in one fetch. Browsing never
// downloads more than that one file per variant (two fetches, total,
// for the whole 100-theme catalog) plus whichever single theme's
// preview.png is currently selected -- see ThemeCatalog.parseThemesJs's
// own comment for the full "why".
//
// Install (direct follow-up: "when i press enter it installs it right
// and then switches to it too, if already installed it works as a
// theme switcher?") only ever runs on Enter, for the one theme actually
// selected -- see activateSelection()/installTheme()/switchToTheme()
// below, and ThemeCatalog.js's own "Stage 2: install" header comment
// for the full file-by-file design and the security reasoning behind
// isSafeThemeSlug.
Item {
  id: root

  // --- Standard extension-content contract -- same four properties
  // every extension content file in this plugin takes (WallpapersContent.qml/
  // SettingsContent.qml both declare the identical set).
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  // Only fetches the catalog once, the first time this extension is
  // actually shown -- same "no reason to run while some other tab is
  // showing" reasoning WallpapersContent.qml's own active property
  // already documents.
  property bool active: false
  property string searchText: ""

  // --- Generic extension-content interface -- see Launcher.qml's own
  // activeExtensionContent comment for the full contract this is part
  // of. A 2-panel list+detail extension like Settings, but deliberately
  // NOT prefersCompactWindow -- direct follow-up after seeing it next
  // to Settings' own compact panel: the preview image/swatch grid here
  // wants the same wide/tall room Wallpapers' own grid gets, not the
  // narrower default. Settings' own comment at that width/height
  // binding (Launcher.qml) already documents this exact revert as a
  // one-line, no-other-change toggle -- this is that toggle, just
  // never turned on in the first place rather than turned back off.
  // nothing here needs moveSelectionLeft/Right or the rightFocused/
  // focusRightPanel trio -- there is no sub-focus concept yet (the
  // variant toggle is still mouse-only).
  readonly property string searchPlaceholder: "Search Themes"
  // Enter now installs/switches (see activateSelection below) --
  // same "↵" chip Settings' own category-open already shows.
  readonly property bool showsEnterHint: true

  // --- Catalog: all 100 themes (real display name/slug/motif/colors/
  // ansi), fetched once via each repo's own assets/themes.js -- see
  // ThemeCatalog.parseThemesJs's own comment for why this single file
  // replaces what would otherwise be a GitHub API catalog call plus a
  // colors.toml fetch per theme. darkThemes is this extension's own
  // canonical list/order; light colors are looked up by slug (dark
  // slug + "-day", confirmed directly: every light entry's own slug is
  // exactly that) only when actually needed for display -- a failed/
  // empty light fetch is not fatal to browsing overall, dark still
  // works either way.
  property var darkThemes: []
  property var lightThemesBySlug: ({})
  property bool catalogLoading: false
  property bool catalogFailed: false

  // Direct follow-up ("the types... moved to the stuff below it like
  // how file search has these chips thing") -- a cycling chip
  // (filterChipsRow below), not a dropdown, same "click to cycle, no
  // popup" shape Search Files' own SearchFiltersBar Type button already
  // uses (see its own header comment for why: avoids a z-stacking trap
  // a real popup would reintroduce). "" is "All Styles" -- styleFilter
  // just IS the real motif slug once a style is picked. Deliberately
  // NOT reset when this tab is re-entered -- same session-persistence
  // convention kindFilter/categoryFilter already use elsewhere in this
  // plugin.
  property string styleFilter: ""
  readonly property var styleFilterOptions: ThemeCatalog.styleOptions(root.darkThemes)
  function cycleStyleFilter() {
    var slugs = [""].concat(root.styleFilterOptions.map(function(o) { return o.path }))
    var idx = slugs.indexOf(root.styleFilter)
    root.styleFilter = slugs[(idx + 1) % slugs.length]
  }
  // Direct follow-up ("right click on styles chip to go back to all...
  // once i start clicking cause like its a long list") -- 15 motifs
  // means up to 14 left-clicks to cycle all the way back around to
  // "All" from wherever you land. Right-click jumps straight there
  // instead, same second-button-does-something-else shape ResultRow's
  // own right-click-for-actions-menu already uses in this plugin.
  function resetStyleFilter() { root.styleFilter = "" }
  readonly property string styleFilterLabel: root.styleFilter === "" ? "All" : ThemeCatalog.motifLabel(root.styleFilter)

  // Direct follow-up ("im thinking about making that between All and
  // Installed") -- what the top-right dropdown now controls (see
  // Launcher.qml's own installedFilterOptions comment) instead of
  // style. A real browse/manage distinction, not session-persisted on
  // purpose: re-entering this tab should default back to browsing
  // everything, not silently stay narrowed to Installed from a
  // previous visit.
  property bool installedOnlyFilter: false

  // Direct follow-up ("click name chip to order it from z-a and then
  // Style so it orders it by subtitles instead") -- "name" | "style",
  // "asc" | "desc". See filterChipsRow's own Name/By Style chips for
  // how these toggle, and ThemeCatalog.sortThemes's own comment for the
  // actual compare.
  //
  // Defaults to "style", not "name" -- direct follow-up ("instead of
  // names a-z order for default lets do the style a-z order default,
  // its easier to pick when looking at them by styles"): grouping by
  // motif first reads as "here are all the Sunset Grid ones, here are
  // all the Aurora ones" at a glance, which is the actual way most
  // people pick a theme to try, rather than an alphabetical name list
  // that scatters same-style themes throughout it.
  property string sortKey: "style"
  property string sortDirection: "asc"
  function toggleSortByName() {
    if (root.sortKey === "name") root.sortDirection = root.sortDirection === "asc" ? "desc" : "asc"
    else { root.sortKey = "name"; root.sortDirection = "asc" }
  }
  function toggleSortByStyle() {
    if (root.sortKey === "style") root.sortDirection = root.sortDirection === "asc" ? "desc" : "asc"
    else { root.sortKey = "style"; root.sortDirection = "asc" }
  }

  // {slug: true} set of every theme folder actually present under
  // ~/.config/omarchy/themes right now -- refreshed each time this
  // extension is (re)opened (see refreshInstalledThemes below), so it
  // reflects reality even if something was installed/removed by other
  // means (the stock Settings page, omarchy theme install, a previous
  // stage-2 install here) since the last time this tab was open.
  property var installedSlugs: ({})

  // Filter order: text search, then style, then installed-only -- each
  // one only ever narrows, so the order between them doesn't change the
  // result, just how early a cheap check can skip a theme. Sorted last,
  // over whatever subset survives, so "Style: Sunset Grid" or
  // "Installed" both still read alphabetically (or by-style) rather
  // than in upstream's own curated order.
  readonly property var filteredThemes: ThemeCatalog.sortThemes(
    ThemeCatalog.filterByInstalled(
      ThemeCatalog.filterByStyle(ThemeCatalog.filterThemes(root.darkThemes, root.searchText), root.styleFilter),
      root.installedSlugs, root.installedOnlyFilter),
    root.sortKey, root.sortDirection)
  // The REAL active theme's own name, read from
  // ~/.local/state/omarchy/current/theme.name (see
  // refreshCurrentTheme below) -- direct follow-up ("icons color isnt
  // enough to tell" installed apart from current; see
  // ThemeCatalog.themeRows's own comment for the distinct-glyph fix).
  property string currentThemeSlug: ""
  readonly property var themeRows: ThemeCatalog.themeRows(root.filteredThemes, root.installedSlugs, root.previewVariant, root.muted, root.currentThemeSlug)

  property int selectedIndex: 0
  readonly property var selectedDarkTheme: (root.selectedIndex >= 0 && root.selectedIndex < root.filteredThemes.length)
    ? root.filteredThemes[root.selectedIndex] : null
  readonly property string selectedThemeName: root.selectedDarkTheme ? root.selectedDarkTheme.name : ""
  readonly property string selectedThemeSlug: root.selectedDarkTheme ? root.selectedDarkTheme.slug : ""
  // Real, human label (e.g. "Sunset Grid") -- same regardless of which
  // variant is previewed, the motif itself never differs between dark
  // and light (confirmed directly).
  readonly property string selectedThemeStyle: root.selectedDarkTheme ? ThemeCatalog.motifLabel(root.selectedDarkTheme.motif) : ""

  // Live-preview-on-highlight, like Search Files' own selectedResult ->
  // FileDetailsPanel (direct reference point: "like file search
  // preview") -- no separate "open" step the way Settings' own
  // left list needs one (Enter there opens a category; here Enter is
  // reserved for Install in stage 2, so just moving the cursor already
  // drives what the right panel shows).
  //
  // Not reset per-selection on purpose: toggling to Light then arrowing
  // through more themes keeps previewing each one's own Light variant,
  // same as a persisted view-mode choice rather than a per-row setting
  // that forgets itself the moment you move.
  property string previewVariant: "dark"
  function toggleVariant() {
    root.previewVariant = root.previewVariant === "light" ? "dark" : "light"
  }

  // Clamp back into range whenever the filtered set shrinks (typing a
  // query that matches fewer themes than the previous selectedIndex) --
  // same convention Launcher.qml's own onQueryChanged already uses for
  // its own selectedIndex.
  onFilteredThemesChanged: {
    if (root.selectedIndex >= root.filteredThemes.length) root.selectedIndex = Math.max(0, root.filteredThemes.length - 1)
  }

  // Direct follow-up ("check the left panel scroll, it needs smart
  // scroll that follows on kbd") -- ResultsList.qml is a plain ListView
  // with no scroll-follow of its own (see its own header comment: every
  // consumer wires that externally), and this extension's own
  // moveSelectionUp/Down just mutate selectedIndex with nothing
  // positioning the viewport, so arrowing past the visible rows left
  // the highlight scrolling off-screen while the list itself sat still.
  // Same Contain-based technique Launcher.qml's own main results list
  // already uses, same scrollOff=2 margin (so the list scrolls a beat
  // before the selection would actually reach the edge; Contain never
  // overscrolls past the minimum needed either way).
  readonly property int scrollOff: 2

  // First live test of the scroll-follow above reproduced the exact
  // snapback this plugin has already hit (and fixed) twice before, in
  // two different shapes -- Launcher.qml's own main results list
  // (hoverArmed/hoverArmBaseline) and WallpapersContent's own grid
  // (its header comment documents a SECOND, worse version of the same
  // bug: a naive one-way "armed forever" latch silently broke keyboard
  // nav too, since a content shift under a physically still cursor
  // looks IDENTICAL to a real hover to a plain MouseArea.onEntered).
  // ResultsList/ResultRow is a plain ListView + per-row MouseArea,
  // structurally the same shape the MAIN list already uses (not the
  // grid's bespoke indexAt-driven design, which only existed because a
  // GridView's 2D navigation needed hover to drive currentIndex
  // directly) -- so this reuses that simpler, already-proven mechanism
  // rather than the heavier one: hoverArmed stays false (onRowHovered
  // below is a no-op) until the HoverHandler below observes the
  // pointer at a DIFFERENT position than wherever it last rested.
  // Resetting BOTH to false/(-1,-1) on every onSelectedIndexChanged --
  // not just once at open -- means the very next pointer-position
  // reading after a keyboard-driven scroll is treated as establishing
  // a fresh baseline, not as the user having moved anything, even if
  // the compositor's content-shift-under-a-still-cursor sends an
  // event. Only a SECOND, genuinely different reading re-arms it.
  property bool hoverArmed: false
  property point hoverArmBaseline: Qt.point(-1, -1)

  onSelectedIndexChanged: {
    root.hoverArmed = false
    root.hoverArmBaseline = Qt.point(-1, -1)
    // Moving to a different row disarms a pending Remove confirm --
    // see requestRemove's own comment for why this matters (a stale
    // "Confirm?" shouldn't carry over to whatever's now selected).
    root.removeArmed = false
    var lastIndex = root.filteredThemes.length - 1
    themeResultsList.positionViewAtIndex(Math.min(root.selectedIndex + root.scrollOff, lastIndex), ListView.Contain)
    themeResultsList.positionViewAtIndex(Math.max(root.selectedIndex - root.scrollOff, 0), ListView.Contain)
    themeResultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  // --- Required core of the generic extension-content interface.
  function moveSelectionUp() {
    if (root.selectedIndex > 0) root.selectedIndex--
  }
  function moveSelectionDown() {
    if (root.selectedIndex < root.filteredThemes.length - 1) root.selectedIndex++
  }

  // Direct follow-up ("when i press enter it installs it right and then
  // switches to it too, if already installed it works as a theme
  // switcher?") -- exactly that branch: an already-installed variant
  // (installedSlugs already keys off the SAME installedSlugFor(theme,
  // previewVariant) themeRows uses for the green/muted icon, so this
  // reads as "install" right up until the icon is already green) just
  // runs omarchy-theme-set directly; everything else goes through the
  // real fetch pipeline first. Ignored entirely while one is already
  // running, rather than queuing a second -- Enter held down/mashed
  // should not spawn overlapping installs of two different themes.
  function activateSelection() {
    if (!root.selectedDarkTheme) return
    if (root.installState !== "idle") return
    var slug = ThemeCatalog.installedSlugFor(root.selectedDarkTheme, root.previewVariant)
    if (root.installedSlugs[slug]) {
      root.switchToTheme(slug, root.selectedThemeName)
    } else {
      root.installTheme(root.selectedDarkTheme, root.previewVariant, slug)
    }
  }

  onActiveChanged: {
    if (root.active && root.darkThemes.length === 0 && !root.catalogLoading) root.loadCatalog()
    if (root.active) {
      root.refreshInstalledThemes()
      root.refreshCurrentTheme()
      // Same re-arm-on-(re)open as Launcher.qml's own hoverArmed/
      // WallpapersContent's own copy of the same thing.
      root.hoverArmed = false
      root.hoverArmBaseline = Qt.point(-1, -1)
      // Direct follow-up ("when i come back to theme, can i start at
      // the top of the list, when i back out its like putting the
      // active somewhere down below") -- selectedIndex and the list's
      // own scroll position both persist for the rest of the session
      // (same convention styleFilter/installedOnlyFilter already use),
      // so backing out right after installing/switching to something
      // alphabetically far down and coming back landed right back on
      // that same row whenever it was, not a clean view. Same
      // Qt.callLater(positionViewAtBeginning()) convention Launcher.qml's
      // own onQueryChanged/onFilesModeChanged already use for the exact
      // same "fresh view, start from the top" reset -- selectedIndex's
      // own change (when it was something other than 0 already) fires
      // the usual Contain-based scroll-follow too, this just guarantees
      // the exact flush-at-the-top position regardless.
      root.selectedIndex = 0
      Qt.callLater(function() { themeResultsList.positionViewAtBeginning() })
    }
  }

  readonly property string themesDir: Quickshell.env("HOME") + "/.config/omarchy/themes"

  // Plain `ls` of the real themes directory -- cheap, local, no reason
  // to cache/skip this the way loadCatalog() above skips a re-fetch
  // once already loaded, since this needs to reflect CURRENT disk
  // state every time the tab is (re)opened, not just the first time.
  function refreshInstalledThemes() {
    installedThemesProc.command = ["ls", "-1", root.themesDir]
    installedThemesProc.running = true
  }

  // Plain `cat` of omarchy's own current-theme marker -- the same file
  // omarchy-theme-current itself reads, so this always agrees with
  // whatever Omarchy considers active, including a switch made from
  // outside this extension entirely (the stock Settings page, a
  // keybind, omarchy theme set run directly).
  function refreshCurrentTheme() {
    currentThemeProc.command = ["cat", Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"]
    currentThemeProc.running = true
  }

  Process {
    id: currentThemeProc
    stdout: StdioCollector {
      id: currentThemeStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      // No marker file at all (a genuinely fresh install, say) just
      // means nothing reads as "current" -- fails closed, same
      // convention installedThemesProc's own onExited already uses.
      root.currentThemeSlug = exitCode === 0 ? String(currentThemeStdout.text || "").trim() : ""
    }
  }

  Process {
    id: installedThemesProc
    stdout: StdioCollector {
      id: installedThemesStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var set = {}
      if (exitCode === 0) {
        var lines = String(installedThemesStdout.text || "").trim().split("\n")
        for (var i = 0; i < lines.length; i++) {
          var name = lines[i].trim()
          if (name !== "") set[name] = true
        }
      }
      // A failed/empty `ls` (no themes directory yet, say, on a
      // genuinely fresh install) just means nothing shows as
      // installed -- fails closed to "nothing installed", never
      // throws or leaves the previous (possibly stale) set showing.
      root.installedSlugs = set
    }
  }

  // --- Install/switch pipeline -----------------------------------------
  //
  // "idle" the rest of the time; "installing"/"switching" while a real
  // omarchy-theme-set (or the fetch that precedes it) is in flight;
  // "error" briefly after a failed install (see installErrorTimer).
  // installingName is the display name of whichever theme this is
  // CURRENTLY running for -- captured at kickoff rather than read live
  // off selectedDarkTheme, since arrow-key navigation during a slow
  // network fetch must not relabel an in-flight install after a
  // different row the user has since moved to.
  property string installState: "idle"
  property string installingName: ""
  property string installErrorMessage: ""

  Timer {
    id: installErrorTimer
    interval: 2500
    onTriggered: { root.installState = "idle"; root.installErrorMessage = "" }
  }

  function switchToTheme(slug, displayName) {
    root.installState = "switching"
    root.installingName = displayName
    themeSetProc.command = ["omarchy-theme-set", slug]
    themeSetProc.running = true
  }

  // --- Remove -------------------------------------------------------
  //
  // Direct follow-up ("how would remove work?... i dont think we need
  // a warning if it doesn't fail" -- confirmed directly: omarchy-theme-
  // remove never refuses the currently active theme, it just deletes
  // the folder; the active theme keeps working exactly as installed
  // until the next real switch, which would then need a fresh install
  // to come back). No special-casing for "this is the current theme"
  // here as a result -- removeButton's own visibility is purely "is
  // THIS variant installed", same installedSlugs check the row's own
  // icon already uses.
  //
  // Click-to-arm, click-again-to-confirm instead of firing on the
  // first click -- Install/Switch (Enter) are both easily undone
  // (switch back, or reinstall over the network), but a removal
  // actually deletes local files, so this gets a little more friction
  // than a plain click-through. removeArmedSlug (not just a bare bool)
  // means navigating to a DIFFERENT theme while one is armed can't
  // leave a stale "Confirm?" that then deletes whatever you've since
  // selected -- see onSelectedIndexChanged's own disarm below.
  property bool removeArmed: false
  property string removeArmedSlug: ""

  Timer {
    id: removeArmTimer
    interval: 3000
    onTriggered: root.removeArmed = false
  }

  function requestRemove(slug) {
    if (root.installState !== "idle") return
    if (root.removeArmed && root.removeArmedSlug === slug) {
      root.removeArmed = false
      if (ThemeCatalog.isSafeThemeSlug(slug)) {
        removeThemeProc.command = ["omarchy-theme-remove", slug]
        removeThemeProc.running = true
      }
    } else {
      root.removeArmed = true
      root.removeArmedSlug = slug
      removeArmTimer.restart()
    }
  }

  Process {
    id: removeThemeProc
    onExited: function(exitCode) { root.refreshInstalledThemes() }
  }

  // Four fixed, parallel units of work once the theme's own directory
  // exists: colors.toml (the one load-bearing fetch -- everything else
  // is best-effort), icons.theme, preview.png, and the backgrounds/
  // folder (its own listing call, then a short sequential download
  // chain -- see downloadNextBackground). installPendingCount starts at
  // this fixed 4 rather than growing dynamically with how many
  // backgrounds a theme turns out to have, since the backgrounds UNIT
  // as a whole only reports done once, after its own chain finishes.
  property int installPendingCount: 0
  property bool installColorsOk: false
  property string installThemeDir: ""
  property string installSlug: ""
  property var installBackgroundsQueue: []

  function installTheme(theme, variant, slug) {
    if (!ThemeCatalog.isSafeThemeSlug(slug)) {
      root.installState = "error"
      root.installErrorMessage = "Could not install this theme"
      installErrorTimer.restart()
      return
    }
    root.installState = "installing"
    root.installingName = theme.name
    root.installSlug = slug
    root.installThemeDir = root.themesDir + "/" + slug
    root.installColorsOk = false
    root.installPendingCount = 4
    installMkdirProc.variant = variant
    installMkdirProc.command = ["mkdir", "-p", root.installThemeDir, root.installThemeDir + "/backgrounds"]
    installMkdirProc.running = true
  }

  Process {
    id: installMkdirProc
    property string variant: "dark"
    onExited: function(exitCode) {
      if (exitCode !== 0) { root.failInstall(); return }
      var slug = root.installSlug
      var variant = installMkdirProc.variant
      installColorsProc.command = ["curl", "-fsS", "--max-time", "10", "-o", root.installThemeDir + "/colors.toml", ThemeCatalog.themeFileUrl(slug, variant, "colors.toml")]
      installColorsProc.running = true
      installIconsProc.command = ["curl", "-fsS", "--max-time", "10", "-o", root.installThemeDir + "/icons.theme", ThemeCatalog.themeFileUrl(slug, variant, "icons.theme")]
      installIconsProc.running = true
      installPreviewProc.command = ["curl", "-fsS", "--max-time", "10", "-o", root.installThemeDir + "/preview.png", ThemeCatalog.themeFileUrl(slug, variant, "preview.png")]
      installPreviewProc.running = true
      installBackgroundsListProc.command = ["curl", "-fsS", "--max-time", "10", ThemeCatalog.backgroundsApiUrl(slug, variant)]
      installBackgroundsListProc.running = true
    }
  }

  Process {
    id: installColorsProc
    onExited: function(exitCode) {
      root.installColorsOk = exitCode === 0
      root.installStepDone()
    }
  }

  // Best-effort -- a missing icon theme name degrades to whatever icon
  // theme was already active, never blocks the install.
  Process {
    id: installIconsProc
    onExited: function(exitCode) { root.installStepDone() }
  }

  // Best-effort -- Omarchy's own theme pickers fall back fine without
  // one; this plugin's own browse/preview path never depends on it.
  Process {
    id: installPreviewProc
    onExited: function(exitCode) { root.installStepDone() }
  }

  Process {
    id: installBackgroundsListProc
    stdout: StdioCollector {
      id: installBackgroundsListStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      // A 404 (no backgrounds/ folder for this theme) and a real
      // network failure both just mean nothing to download -- see
      // omarchy-theme-set's own choose_theme_background, which already
      // tolerates a theme with no backgrounds at all.
      root.installBackgroundsQueue = exitCode === 0 ? ThemeCatalog.parseBackgroundsListing(installBackgroundsListStdout.text) : []
      root.downloadNextBackground()
    }
  }

  // Sequential, not parallel -- a theme has at most a small handful of
  // backgrounds (every one checked directly so far has exactly 2), so
  // there is no real latency win worth a second Process/queue-slot
  // bookkeeping for.
  function downloadNextBackground() {
    if (root.installBackgroundsQueue.length === 0) { root.installStepDone(); return }
    var job = root.installBackgroundsQueue.shift()
    installBackgroundDownloadProc.command = ["curl", "-fsS", "--max-time", "15", "-o", root.installThemeDir + "/backgrounds/" + job.name, job.url]
    installBackgroundDownloadProc.running = true
  }

  Process {
    id: installBackgroundDownloadProc
    onExited: function(exitCode) { root.downloadNextBackground() }
  }

  function installStepDone() {
    root.installPendingCount--
    if (root.installPendingCount > 0) return
    if (!root.installColorsOk) { root.failInstall(); return }
    themeSetProc.command = ["omarchy-theme-set", root.installSlug]
    themeSetProc.running = true
  }

  // Leaves nothing half-written behind for a colors.toml that never
  // arrived -- a retry (selecting the same row and pressing Enter
  // again) should start clean, not find a theme folder that `ls`
  // already considers "installed" with no real palette inside it.
  function failInstall() {
    installCleanupProc.command = ["rm", "-rf", root.installThemeDir]
    installCleanupProc.running = true
    root.installState = "error"
    root.installErrorMessage = "Could not install this theme"
    installErrorTimer.restart()
  }

  Process { id: installCleanupProc }

  Process {
    id: themeSetProc
    onExited: function(exitCode) {
      root.refreshInstalledThemes()
      root.refreshCurrentTheme()
      if (exitCode === 0) {
        root.installState = "idle"
        root.installErrorMessage = ""
      } else {
        root.installState = "error"
        root.installErrorMessage = "Could not switch to this theme"
        installErrorTimer.restart()
      }
    }
  }

  function loadCatalog() {
    root.catalogLoading = true
    root.catalogFailed = false
    darkCatalogProc.command = ["curl", "-fsS", "--max-time", "10", ThemeCatalog.themesDataUrl("dark")]
    darkCatalogProc.running = true
    // Fired alongside, not gating catalogLoading -- light is a
    // secondary enhancement (the Light toggle just shows nothing yet
    // if this is still in flight or fails), not something worth
    // blocking the whole browsable list on.
    lightCatalogProc.command = ["curl", "-fsS", "--max-time", "10", ThemeCatalog.themesDataUrl("light")]
    lightCatalogProc.running = true
  }

  Process {
    id: darkCatalogProc
    stdout: StdioCollector {
      id: darkCatalogStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.catalogLoading = false
      if (exitCode !== 0) { root.catalogFailed = true; return }
      var themes = ThemeCatalog.parseThemesJs(darkCatalogStdout.text, "dark")
      if (themes.length === 0) { root.catalogFailed = true; return }
      root.darkThemes = themes
    }
  }

  Process {
    id: lightCatalogProc
    stdout: StdioCollector {
      id: lightCatalogStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) return
      var themes = ThemeCatalog.parseThemesJs(lightCatalogStdout.text, "day")
      var bySlug = {}
      for (var i = 0; i < themes.length; i++) bySlug[themes[i].slug] = themes[i]
      root.lightThemesBySlug = bySlug
    }
  }

  // Colors are synchronous now -- already in memory from the catalog
  // fetch above, no per-theme network round trip needed at all (unlike
  // the old colors.toml-per-selection design this replaced).
  readonly property var previewColors: {
    if (!root.selectedDarkTheme) return {}
    if (root.previewVariant === "dark") return root.selectedDarkTheme.colors || {}
    var light = root.lightThemesBySlug[root.selectedDarkTheme.slug + "-day"]
    return light ? (light.colors || {}) : {}
  }

  // --- Preview image: the one thing that still needs a real per-
  // selection network fetch -- curled to a local cache file, then
  // Image reads the real file (same pattern this plugin's own avatar
  // picker already uses for a remote image, see SettingsContent.qml's
  // own ruixen-avatar-dicebear call site; QML's Image loading a bare
  // https:// source directly has no existing precedent in this repo to
  // trust).
  //
  // Debounced so rapid arrow-key scrolling through the list doesn't
  // fire a fetch per keystroke -- only the theme actually settled on
  // for a moment gets fetched. 150ms matches this plugin's own existing
  // feel for "fast enough to feel live, slow enough not to spam" (see
  // ruixen.weather's own geocodeDebounce for the same convention).
  property string previewImagePath: ""
  property bool previewImageLoading: false

  // Keyed "<slug>:<variant>" -> local path (or "" for a failed fetch,
  // itself cached so a known-dead theme/variant pair doesn't retry on
  // every revisit this session). Session-only, never persisted --
  // nothing here needs to survive a relaunch.
  property var previewImageCache: ({})
  function previewImageCacheKey(slug, variant) { return slug + ":" + variant }

  // The real slug for whichever variant is currently selected --
  // "-day" only ever applies to the light companion repo's own copy,
  // confirmed directly against its own catalog data rather than
  // derived blindly.
  function variantSlug() {
    if (!root.selectedDarkTheme) return ""
    return root.previewVariant === "light" ? root.selectedDarkTheme.slug + "-day" : root.selectedDarkTheme.slug
  }

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/ruixen/theme-browser"

  Process {
    id: ensureCacheDirProc
    command: ["mkdir", "-p", root.cacheDir]
  }
  Component.onCompleted: ensureCacheDirProc.running = true

  Timer {
    id: previewImageDebounce
    interval: 150
    onTriggered: root.fetchPreviewImage()
  }
  onSelectedThemeSlugChanged: previewImageDebounce.restart()
  onPreviewVariantChanged: previewImageDebounce.restart()

  function fetchPreviewImage() {
    var slug = root.variantSlug()
    if (slug === "") { root.previewImagePath = ""; return }
    var key = root.previewImageCacheKey(slug, root.previewVariant)
    var cached = root.previewImageCache[key]
    if (cached !== undefined) { root.previewImagePath = cached; return }

    root.previewImagePath = ""
    root.previewImageLoading = true
    var imageTarget = root.cacheDir + "/" + key.replace(":", "-") + "-preview.png"
    previewImageProc.requestKey = key
    previewImageProc.targetPath = imageTarget
    previewImageProc.command = ["curl", "-fsS", "--max-time", "10", "-o", imageTarget, ThemeCatalog.themeFileUrl(slug, root.previewVariant, "preview.png")]
    previewImageProc.running = true
  }

  // Stores into previewImageCache under requestKey, not under whatever
  // is CURRENTLY selected -- a slow response arriving after the user
  // has already moved on to a different theme must still cache
  // correctly for if they arrow back to it, but must never overwrite
  // what's actively showing for the (different) theme now selected.
  // Only applies live to root.previewImagePath when requestKey still
  // matches the live selection.
  Process {
    id: previewImageProc
    property string requestKey: ""
    property string targetPath: ""
    onExited: function(exitCode) {
      root.previewImageLoading = false
      var path = exitCode === 0 ? previewImageProc.targetPath : ""
      var cache = root.previewImageCache
      cache[previewImageProc.requestKey] = path
      root.previewImageCache = cache
      if (previewImageProc.requestKey === root.previewImageCacheKey(root.variantSlug(), root.previewVariant))
        root.previewImagePath = path
    }
  }

  // Direct follow-up ("the types... moved to the stuff below it like
  // how file search has these chips thing... click name chip to order
  // it from z-a and then Style so it orders it by subtitles instead")
  // -- visually matches SearchFiltersBar.qml's own chip row (same 24px
  // pill buttons, same spacing/radius/tint), but built fresh rather
  // than reused: that component's own props (categoryFilter/
  // searchScope/hiddenEnabled, its three signals) are Search-Files-
  // specific, and ExtensionTwoPanel's own header comment already
  // settles this exact question for Wallpapers' grid -- a genuinely
  // different shape "isn't forced through" a shared component that
  // doesn't fit it, it just matches the same look.
  Item {
    id: filterChipsRow
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 32

    Row {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6

      // Style filter -- cycles on click through every motif present in
      // the loaded catalog, "All" wrapping back around, same plain
      // cycle-on-click shape (and lack of active/inactive tint -- this
      // is always exactly one of its own options showing, never a
      // multi-choice row) SearchFiltersBar's own Type button uses.
      Rectangle {
        id: styleChip
        width: Math.max(76, styleChipLabel.implicitWidth + 20)
        height: 24
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Text {
          id: styleChipLabel
          anchors.centerIn: parent
          text: "Style: " + root.styleFilterLabel
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 11
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) root.resetStyleFilter()
            else root.cycleStyleFilter()
          }
        }
      }

      // Dark/Light -- direct follow-up ("make one of these chips
      // toggle between light and dark... it controls left panel stuff
      // right then metadata"): previewVariant was living as a pair of
      // buttons down in the metadata panel, but it actually drives the
      // LEFT panel too (themeRows' own installed/current icon reads
      // whichever variant this is currently set to, same as the
      // preview on the right) -- a view-mode control like Style, that
      // happened to be parked next to Name/the palette instead of up
      // here with the other ones. One cycling chip (Dark <-> Light),
      // same plain two-state-cycle shape Style's own chip uses, not the
      // metadata panel's old two-separate-buttons layout -- there's
      // only ever two states here, a single click-to-flip reads just as
      // clearly and matches this row's own rhythm better. The metadata
      // panel's own Variant row is gone now that this is its one home,
      // not duplicated in both places.
      Rectangle {
        id: variantChip
        width: variantChipLabel.implicitWidth + 20
        height: 24
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        Text {
          id: variantChipLabel
          anchors.centerIn: parent
          text: root.previewVariant === "light" ? "Light" : "Dark"
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 11
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleVariant()
        }
      }

      // By Style/Name -- exactly one is ever the active sort key, same
      // accent-tinted "exactly one of these is selected" shape
      // SearchFiltersBar's own scope row (Both/Names/Contents) uses.
      // Clicking the ALREADY-active one flips direction instead of
      // doing nothing -- direct request ("click name chip to order it
      // from z-a"). By Style first, Name last -- matches sortKey's own
      // default (direct follow-up: "swap places so By Style and then
      // Names is last chip", after making Style the default sort).
      Rectangle {
        id: styleSortChip
        readonly property bool isActive: root.sortKey === "style"
        width: styleSortLabel.implicitWidth + 16
        height: 24
        radius: 6
        color: styleSortChip.isActive ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: styleSortChip.isActive ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) : Qt.rgba(1, 1, 1, 0.12)

        Text {
          id: styleSortLabel
          anchors.centerIn: parent
          text: "By Style" + (styleSortChip.isActive ? (root.sortDirection === "asc" ? " ↑" : " ↓") : "")
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 11
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleSortByStyle()
        }
      }

      Rectangle {
        id: nameSortChip
        readonly property bool isActive: root.sortKey === "name"
        width: nameSortLabel.implicitWidth + 16
        height: 24
        radius: 6
        color: nameSortChip.isActive ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: nameSortChip.isActive ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) : Qt.rgba(1, 1, 1, 0.12)

        Text {
          id: nameSortLabel
          anchors.centerIn: parent
          text: "Name" + (nameSortChip.isActive ? (root.sortDirection === "asc" ? " ↑" : " ↓") : "")
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 11
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.toggleSortByName()
        }
      }
    }
  }

  ExtensionTwoPanel {
    id: panel
    anchors.top: filterChipsRow.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
  }

  // Direct follow-up: a small motif/style subtitle beside each theme's
  // name, same treatment the landing list's own rows get ("similar to
  // ruixen launcher home"). ResultRow.qml only renders that subtitle
  // (and the real kind tag, this file's own kind always stays "" so
  // that column renders nothing) outside filesMode -- Settings/
  // Wallpapers use filesMode specifically to suppress it (Search
  // Files' details panel already repeats that information elsewhere),
  // but this extension's whole point is surfacing it right here in the
  // list, so it deliberately opts out of that mode instead.
  ResultsList {
    id: themeResultsList
    parent: panel.leftPane
    anchors.fill: parent
    model: root.themeRows
    selectedIndex: root.selectedIndex
    textColor: root.textColor
    mutedColor: root.muted
    accentColor: root.accent
    fontFamily: root.fontFamily
    onRowHovered: (idx) => { if (root.hoverArmed) root.selectedIndex = idx }
    onRowActivated: (idx) => { root.selectedIndex = idx }

    // Arms hoverArmed (see its own property comment) on the first REAL
    // pointer movement -- a passive input handler, not a MouseArea, so
    // it observes pointer events over the whole list without stealing
    // anything from each row's own MouseArea beneath it. Matches
    // Launcher.qml's own card-level HoverHandler exactly: the first
    // onPointChanged after any reset is captured as a baseline instead
    // of treated as movement, so a content-shift-under-a-still-cursor
    // (this list scrolling itself under the keyboard above) is never
    // mistaken for the user's hand actually moving.
    HoverHandler {
      onPointChanged: {
        if (root.hoverArmed) return
        if (root.hoverArmBaseline.x < 0) {
          root.hoverArmBaseline = point.position
          return
        }
        if (Math.abs(point.position.x - root.hoverArmBaseline.x) > 0.5
            || Math.abs(point.position.y - root.hoverArmBaseline.y) > 0.5)
          root.hoverArmed = true
      }
    }
  }

  Text {
    parent: panel.leftPane
    anchors.centerIn: parent
    width: parent.width - 16
    visible: !root.catalogLoading && !root.catalogFailed && root.darkThemes.length > 0 && root.filteredThemes.length === 0
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    text: "No matches"
    font.family: root.fontFamily
    font.pixelSize: 11
    color: root.muted
  }

  Column {
    parent: panel.leftPane
    anchors.centerIn: parent
    spacing: 6
    visible: root.catalogLoading || root.catalogFailed

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.catalogFailed ? "" : ""
      font.family: root.fontFamily
      font.pixelSize: 22
      color: root.muted
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: root.catalogFailed ? "Could not load the theme list" : "Loading themes…"
      font.family: root.fontFamily
      font.pixelSize: 12
      color: root.muted
    }
    Text {
      visible: root.catalogFailed
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Check your connection, then reopen this tab"
      font.family: root.fontFamily
      font.pixelSize: 10
      color: root.muted
      opacity: 0.8
    }
  }

  // --- Right pane: swatch (instant, from previewColors) + preview
  // image (progressive upgrade once previewImagePath lands) + a plain
  // Dark/Light toggle. Install itself is stage 2 -- this pane is
  // read-only browsing for now.
  Item {
    parent: panel.rightPane
    anchors.fill: parent
    visible: root.selectedThemeName !== ""

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 16
      spacing: 12

      // Preview image once it lands; the swatch grid underneath stays
      // visible the whole time as a loading placeholder/fallback (a
      // failed or slow image fetch still leaves a real color preview on
      // screen, never a blank pane). Direct follow-up on the overall
      // layout: preview first, then the Dark/Light toggle, then name +
      // palette grouped together as one metadata field below -- the
      // image is the actual preview, name/palette are plain facts
      // about the theme rather than something that belongs above it.
      Rectangle {
        id: previewBox
        Layout.fillWidth: true
        // Neither a short wide strip nor a square was right -- both
        // cropped real content (the first cut off top/bottom, the
        // second cut off the sides). Checked the real files directly
        // this time instead of guessing again: every preview.png
        // across the whole catalog is exactly 1920x1200 (confirmed
        // against several themes, not just one), so this box is just
        // that same real ratio -- PreserveAspectCrop below then has
        // nothing to crop at all, the full composite always shows.
        readonly property real sourceAspectRatio: 1200 / 1920
        Layout.preferredHeight: width * previewBox.sourceAspectRatio
        radius: 10
        clip: true
        color: Qt.rgba(0, 0, 0, 0.25)

        // Direct follow-up: the per-theme color swatch that used to
        // fill this box while the image loaded was flashing a new set
        // of colors on every arrow-key move (a real visual effect, not
        // a bug -- previewColors itself updates instantly now that
        // it's synchronous, see this file's own header comment). A
        // plain "Loading…" text reads as a calmer, more normal loading
        // state instead of a strobing color placeholder. Hidden while
        // an install/switch is in flight -- that status (below) takes
        // over this same spot instead of the two overlapping.
        Text {
          anchors.centerIn: parent
          visible: root.installState === "idle" && root.previewImageLoading && previewImage.status !== Image.Ready
          text: "Loading preview…"
          font.family: root.fontFamily
          font.pixelSize: 11
          color: root.muted
        }

        // Install/switch status -- direct follow-up ("when i press
        // enter it installs it right and then switches to it too, if
        // already installed it works as a theme switcher?"). A dimmed
        // backing fill keeps the message legible over whatever preview
        // image/colors happen to be showing underneath (the actual
        // palette, not a fixed color, so a plain text shadow can't be
        // trusted to contrast against all 100 of them).
        Rectangle {
          anchors.fill: parent
          radius: previewBox.radius
          color: Qt.rgba(0, 0, 0, 0.55)
          visible: root.installState !== "idle"
        }
        Text {
          anchors.centerIn: parent
          visible: root.installState !== "idle"
          text: root.installState === "installing" ? "Installing " + root.installingName + "…"
            : root.installState === "switching" ? "Switching to " + root.installingName + "…"
            : root.installErrorMessage
          font.family: root.fontFamily
          font.pixelSize: 12
          color: root.installState === "error" ? "#ff6b6b" : root.textColor
        }

        // clip on a Rectangle only clips to its plain bounding box --
        // radius never participates in child clipping (confirmed
        // directly, same gotcha FilePreview.qml's own comment already
        // documents for the exact same reason: without this, a loaded
        // preview image still rendered with square corners, hiding
        // previewBox's own rounded ones underneath it). Same MultiEffect
        // mask technique that file already uses, copied verbatim: a
        // hidden source Image, a hidden rounded mask Rectangle, and a
        // MultiEffect that composites the two.
        Image {
          id: previewImage
          anchors.fill: parent
          fillMode: Image.PreserveAspectCrop
          source: root.previewImagePath !== "" ? "file://" + root.previewImagePath : ""
          asynchronous: true
          visible: false
        }

        Rectangle {
          id: previewMask
          anchors.fill: parent
          radius: previewBox.radius
          color: "#ffffff"
          visible: false
          layer.enabled: true
        }

        MultiEffect {
          anchors.fill: parent
          source: previewImage
          maskEnabled: true
          maskSource: previewMask
          maskThresholdMin: 0.5
          maskThresholdMax: 1.0
        }
      }

      // Metadata -- same section-header/zebra-striped-row convention
      // Search Files' own FileDetailsPanel.qml uses (ghost, no bordered
      // card of its own; muted/uppercase/bold 10px header; each row
      // label left, value right, alternating row tint), not a separate
      // look invented for this extension. Direct follow-up: Name,
      // Variant (the Dark/Light toggle folded in as a row here instead
      // of sitting on its own between the preview and this section),
      // and Palette.
      Text {
        text: "Metadata"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 10
        font.capitalization: Font.AllUppercase
        font.bold: true
      }

      // --- Name row (even -- tinted, same zebra parity FileDetailsPanel
      // itself uses: index % 2 === 0).
      Item {
        Layout.fillWidth: true
        height: 19

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: -10
          anchors.rightMargin: -10
          anchors.topMargin: -4
          anchors.bottomMargin: -4
          radius: 4
          color: Qt.rgba(0, 0, 0, 0.18)
        }

        Text {
          id: nameFieldLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Name"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 11
          font.capitalization: Font.AllUppercase
        }
        Text {
          anchors.left: nameFieldLabel.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideMiddle
          text: root.selectedThemeName
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 13
        }
      }

      // --- Style row (odd -- no tint). The theme's real motif label
      // (e.g. "Sunset Grid" for Synthwave) -- same from the upstream
      // gallery's own grouping, confirmed directly against its own
      // MOTIFS table rather than derived mechanically from the slug
      // (several genuinely differ, see ThemeCatalog.motifLabel's own
      // comment). Same regardless of the Dark/Light toggle below --
      // the motif itself never changes between variants.
      Item {
        Layout.fillWidth: true
        height: 19

        Text {
          id: styleFieldLabel
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Style"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 11
          font.capitalization: Font.AllUppercase
        }
        Text {
          anchors.left: styleFieldLabel.right
          anchors.leftMargin: 12
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          horizontalAlignment: Text.AlignRight
          elide: Text.ElideMiddle
          text: root.selectedThemeStyle
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 13
        }
      }

      // --- Palette row (even -- tinted, now that Variant moved up into
      // filterChipsRow and left this the third/last row instead of the
      // fourth -- direct follow-up: "it controls left panel stuff...
      // then metadata", moving the Dark/Light toggle off this panel
      // entirely rather than leaving it duplicated in both places; see
      // filterChipsRow's own variantChip for where it lives now). Same
      // single-line field-row shape as Name/Style (label left, value
      // right) instead of its own label-on-top-of-a-grid layout --
      // direct follow-up: small round swatches on the right, not a
      // full-width row of square blocks.
      Item {
        Layout.fillWidth: true
        height: 24

        Rectangle {
          anchors.fill: parent
          anchors.leftMargin: -10
          anchors.rightMargin: -10
          anchors.topMargin: -4
          anchors.bottomMargin: -4
          radius: 4
          color: Qt.rgba(0, 0, 0, 0.18)
        }

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Palette"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 11
          font.capitalization: Font.AllUppercase
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 5

          Repeater {
            model: ["red", "orange", "yellow", "green", "cyan", "blue", "magenta", "brown"]
            Rectangle {
              width: 16
              height: 16
              radius: 8
              color: root.previewColors[modelData] || Qt.rgba(1, 1, 1, 0.06)
              border.width: 1
              border.color: Qt.rgba(1, 1, 1, 0.15)
            }
          }
        }
      }

      // --- Remove row (odd -- no tint). Only shows once there's
      // actually something to remove -- same installedSlugs check the
      // row's own icon color already uses, keyed to whichever variant
      // is currently being previewed/toggled (the Dark/Light chip),
      // same as Install/Switch (Enter) itself operates on. Hidden
      // (not just disabled) when not installed, rather than a greyed-
      // out button with nothing real behind it.
      Item {
        Layout.fillWidth: true
        height: 24
        visible: !!(root.selectedDarkTheme && root.installedSlugs[ThemeCatalog.installedSlugFor(root.selectedDarkTheme, root.previewVariant)])

        Text {
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "Manage"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 11
          font.capitalization: Font.AllUppercase
        }

        Rectangle {
          id: removeButton
          readonly property string targetSlug: root.selectedDarkTheme ? ThemeCatalog.installedSlugFor(root.selectedDarkTheme, root.previewVariant) : ""
          readonly property bool armed: root.removeArmed && root.removeArmedSlug === removeButton.targetSlug
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: removeLabel.implicitWidth + 16
          height: 24
          radius: 6
          color: removeButton.armed ? Qt.rgba(1, 0.33, 0.33, 0.22) : Qt.rgba(1, 1, 1, 0.06)
          border.width: 1
          border.color: removeButton.armed ? "#ff6b6b" : Qt.rgba(1, 1, 1, 0.12)

          Text {
            id: removeLabel
            anchors.centerIn: parent
            text: removeButton.armed ? "Confirm?" : "Remove"
            font.family: root.fontFamily
            font.pixelSize: 11
            color: removeButton.armed ? "#ff6b6b" : root.textColor
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.requestRemove(removeButton.targetSlug)
          }
        }
      }

      Item { Layout.fillHeight: true }
    }
  }

  Column {
    parent: panel.rightPane
    anchors.centerIn: parent
    spacing: 6
    visible: root.selectedThemeName === "" && !root.catalogLoading && !root.catalogFailed

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: ""
      font.family: root.fontFamily
      font.pixelSize: 22
      color: root.muted
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Select a theme to preview it"
      font.family: root.fontFamily
      font.pixelSize: 12
      color: root.muted
    }
  }
}
