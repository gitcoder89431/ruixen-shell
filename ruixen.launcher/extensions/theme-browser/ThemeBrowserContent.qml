import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import "../.."
import "ThemeCatalog.js" as ThemeCatalog

// Stage 1 (browse-only, no install yet -- see the project's own staged
// plan): browse bjarneo/100-themes (100 community Omarchy themes) and
// its light companion bjarneo/100-themes-day (same hues, "-day"
// suffix), without ever downloading the ~180MB full repo. Direct
// design decision after walking through the upstream repo together:
// "this isnt a theme picker grid, its more of a installer or browser"
// -- shaped as a left list + right detail pane (ExtensionTwoPanel,
// same component Settings already uses), not a Wallpapers-style grid,
// specifically so only ONE theme's preview image is ever being fetched
// at a time (whichever is currently selected), regardless of how many
// themes are in the list.
//
// Each repo publishes its own assets/themes.js -- a single static file
// covering every theme's real display name, slug, motif, and full
// colors (already Omarchy's own native theme schema, confirmed
// directly, no TOML parsing needed) in one fetch. Browsing here never
// downloads more than that one file per variant (two fetches, total,
// for the whole 100-theme catalog) plus whichever single theme's
// preview.png is currently selected -- see ThemeCatalog.parseThemesJs's
// own comment for the full "why". The real background images and the
// actual install (writing into ~/.config/omarchy/themes/<name>/) are
// stage 2.
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
  // focusRightPanel trio -- there is no sub-focus concept yet (stage 2,
  // once Install/the variant toggle become real keyboard-reachable
  // controls, may add them).
  readonly property string searchPlaceholder: "Search Themes"

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

  // Direct follow-up ("how would we order this... sort and filter by
  // style") -- reuses the exact same top-right dropdown Wallpapers' own
  // "All Types" button already opens (Launcher.qml's dropdownOptions/
  // confirmDropdownSelection, branched a third way there by
  // activeExtensionId), rather than a new control invented for this
  // extension alone. "" is "All Styles", same sentinel Search Files'
  // own source dropdown already uses for "All Sources" -- styleFilter
  // just IS the real motif slug once a style is picked, so Launcher.qml
  // never needs a second mapping the way wallpapersContent.kindFilter's
  // "all"/"" pair does. Deliberately NOT reset when this tab is
  // re-entered -- same session-persistence convention kindFilter/
  // categoryFilter already use elsewhere in this plugin.
  property string styleFilter: ""
  readonly property var styleFilterOptions: ThemeCatalog.styleOptions(root.darkThemes)

  // Alphabetical by real display name, not whatever curated index order
  // the upstream catalog happens to ship in (Synthwave=1, Neon Wave=2,
  // ...) -- see ThemeCatalog.sortByName's own comment. Style filter
  // narrows first, then the (possibly already-narrowed) set is sorted,
  // so "Style: Sunset Grid" always reads alphabetically too, not in
  // whatever order those particular entries happened to appear upstream.
  readonly property var filteredThemes: ThemeCatalog.sortByName(
    ThemeCatalog.filterByStyle(ThemeCatalog.filterThemes(root.darkThemes, root.searchText), root.styleFilter))
  // {slug: true} set of every theme folder actually present under
  // ~/.config/omarchy/themes right now -- refreshed each time this
  // extension is (re)opened (see refreshInstalledThemes below), so it
  // reflects reality even if something was installed/removed by other
  // means (the stock Settings page, omarchy theme install, a previous
  // stage-2 install here) since the last time this tab was open.
  property var installedSlugs: ({})
  readonly property var themeRows: ThemeCatalog.themeRows(root.filteredThemes, root.installedSlugs, root.previewVariant, root.muted)

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
  // Reserved for the install flow (stage 2) -- a no-op for now, same
  // "wire the shape first, the action later" sequencing Settings' own
  // layout-only first pass used (see SettingsContent.qml's own header
  // comment).
  function activateSelection() {}

  onActiveChanged: {
    if (root.active && root.darkThemes.length === 0 && !root.catalogLoading) root.loadCatalog()
    if (root.active) {
      root.refreshInstalledThemes()
      // Same re-arm-on-(re)open as Launcher.qml's own hoverArmed/
      // WallpapersContent's own copy of the same thing.
      root.hoverArmed = false
      root.hoverArmBaseline = Qt.point(-1, -1)
    }
  }

  // Plain `ls` of the real themes directory -- cheap, local, no reason
  // to cache/skip this the way loadCatalog() above skips a re-fetch
  // once already loaded, since this needs to reflect CURRENT disk
  // state every time the tab is (re)opened, not just the first time.
  function refreshInstalledThemes() {
    installedThemesProc.command = ["ls", "-1", Quickshell.env("HOME") + "/.config/omarchy/themes"]
    installedThemesProc.running = true
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
      var themes = ThemeCatalog.parseThemesJs(darkCatalogStdout.text)
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
      var themes = ThemeCatalog.parseThemesJs(lightCatalogStdout.text)
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

  ExtensionTwoPanel {
    id: panel
    anchors.fill: parent
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
        // state instead of a strobing color placeholder.
        Text {
          anchors.centerIn: parent
          visible: root.previewImageLoading && previewImage.status !== Image.Ready
          text: "Loading preview…"
          font.family: root.fontFamily
          font.pixelSize: 11
          color: root.muted
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

      // --- Variant row (even -- tinted). Same field-row shape, but the
      // value side is the actual Dark/Light toggle instead of plain
      // text -- mouse-only for stage 1 (no keyboard path to it yet, see
      // this file's own header comment on why rightFocused/
      // focusRightPanel aren't part of the interface here yet).
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
          text: "Variant"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 11
          font.capitalization: Font.AllUppercase
        }

        Row {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          spacing: 4

          Rectangle {
            width: darkLabel.implicitWidth + 16
            height: 24
            radius: 6
            color: root.previewVariant === "dark" ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: root.previewVariant === "dark" ? root.accent : Qt.rgba(1, 1, 1, 0.12)

            Text {
              id: darkLabel
              anchors.centerIn: parent
              text: "Dark"
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.previewVariant === "dark" ? root.textColor : root.muted
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.previewVariant !== "dark") root.toggleVariant()
            }
          }

          Rectangle {
            width: lightLabel.implicitWidth + 16
            height: 24
            radius: 6
            color: root.previewVariant === "light" ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.25) : Qt.rgba(1, 1, 1, 0.06)
            border.width: 1
            border.color: root.previewVariant === "light" ? root.accent : Qt.rgba(1, 1, 1, 0.12)

            Text {
              id: lightLabel
              anchors.centerIn: parent
              text: "Light"
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.previewVariant === "light" ? root.textColor : root.muted
            }
            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.previewVariant !== "light") root.toggleVariant()
            }
          }
        }
      }

      // --- Palette row (odd -- no tint, now that Style sits between
      // Name and Variant above). Same single-line field-row shape as
      // Name/Variant (label left, value right) instead of its own
      // label-on-top-of-a-grid layout -- direct follow-up: small round
      // swatches on the right, not a full-width row of square blocks.
      Item {
        Layout.fillWidth: true
        height: 24

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
