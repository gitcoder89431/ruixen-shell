import QtQuick
import QtQuick.Layouts
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
// Each theme folder in the upstream repo is already Omarchy's own
// native colors.toml schema byte-for-byte (confirmed directly, not
// guessed) -- browsing here never downloads more than the catalog
// listing (one API call) plus whichever single theme's colors.toml/
// preview.png is currently selected. The real background images and
// the actual install (writing into ~/.config/omarchy/themes/<name>/)
// are stage 2.
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

  // --- Catalog: the 100 base (dark) theme names, fetched once via a
  // single GitHub Contents API call (see ThemeCatalog.contentsApiUrl's
  // own comment for why this URL specifically, not git). "-day" light
  // variants share the exact same base names (confirmed directly) --
  // deriving them via ThemeCatalog.themeSlugFor means this never needs
  // a second listing call against the companion repo at all.
  property var themeNames: []
  property bool catalogLoading: false
  property bool catalogFailed: false

  readonly property var filteredThemeNames: ThemeCatalog.filterThemeNames(root.themeNames, root.searchText)
  readonly property var themeRows: ThemeCatalog.themeRows(root.filteredThemeNames)

  property int selectedIndex: 0
  readonly property string selectedThemeName: (root.selectedIndex >= 0 && root.selectedIndex < root.filteredThemeNames.length)
    ? root.filteredThemeNames[root.selectedIndex] : ""

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
  onFilteredThemeNamesChanged: {
    if (root.selectedIndex >= root.filteredThemeNames.length) root.selectedIndex = Math.max(0, root.filteredThemeNames.length - 1)
  }

  // --- Required core of the generic extension-content interface.
  function moveSelectionUp() {
    if (root.selectedIndex > 0) root.selectedIndex--
  }
  function moveSelectionDown() {
    if (root.selectedIndex < root.filteredThemeNames.length - 1) root.selectedIndex++
  }
  // Reserved for the install flow (stage 2) -- a no-op for now, same
  // "wire the shape first, the action later" sequencing Settings' own
  // layout-only first pass used (see SettingsContent.qml's own header
  // comment).
  function activateSelection() {}

  onActiveChanged: {
    if (root.active && root.themeNames.length === 0 && !root.catalogLoading) root.loadCatalog()
  }

  function loadCatalog() {
    root.catalogLoading = true
    root.catalogFailed = false
    catalogProc.command = ["curl", "-fsS", "--max-time", "10", ThemeCatalog.contentsApiUrl()]
    catalogProc.running = true
  }

  Process {
    id: catalogProc
    stdout: StdioCollector {
      id: catalogStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      root.catalogLoading = false
      if (exitCode !== 0) { root.catalogFailed = true; return }
      var names = ThemeCatalog.parseContentsListing(catalogStdout.text)
      if (names.length === 0) { root.catalogFailed = true; return }
      root.themeNames = names
    }
  }

  // --- Per-theme preview: colors.toml (the swatch, effectively
  // instant) plus preview.png (a progressive upgrade over the swatch,
  // fetched to a local cache file -- same "curl to disk, then Image
  // reads the real file" pattern this plugin's own avatar picker
  // already uses for a remote image, see SettingsContent.qml's own
  // ruixen-avatar-dicebear call site; QML's Image loading a bare
  // https:// source directly has no existing precedent in this repo to
  // trust).
  //
  // Debounced so rapid arrow-key scrolling through the list doesn't
  // fire a fetch per keystroke -- only the theme actually settled on
  // for a moment gets fetched. 150ms matches this plugin's own existing
  // feel for "fast enough to feel live, slow enough not to spam" (see
  // ruixen.weather's own geocodeDebounce for the same convention).
  property var previewColors: ({})
  property string previewImagePath: ""
  property bool previewImageLoading: false

  // Keyed "<name>:<variant>" -- avoids re-fetching colors.toml/
  // preview.png for a theme+variant pair already seen this session
  // (arrowing back and forth across the same few themes while browsing
  // is the common case). Session-only, never persisted -- nothing here
  // needs to survive a relaunch, and a stale cached preview is
  // harmless (it's read-only browsing, not state that could drift from
  // reality).
  property var previewCache: ({})
  function previewCacheKey(name, variant) { return name + ":" + variant }

  readonly property string cacheDir: Quickshell.env("HOME") + "/.cache/ruixen/theme-browser"

  Process {
    id: ensureCacheDirProc
    command: ["mkdir", "-p", root.cacheDir]
  }
  Component.onCompleted: ensureCacheDirProc.running = true

  Timer {
    id: previewDebounce
    interval: 150
    onTriggered: root.fetchPreview()
  }
  onSelectedThemeNameChanged: previewDebounce.restart()
  onPreviewVariantChanged: previewDebounce.restart()

  function fetchPreview() {
    var name = root.selectedThemeName
    if (name === "") {
      root.previewColors = {}
      root.previewImagePath = ""
      return
    }
    var key = root.previewCacheKey(name, root.previewVariant)
    var cached = root.previewCache[key]
    if (cached) {
      root.previewColors = cached.colors
      root.previewImagePath = cached.imagePath
      return
    }
    root.previewColors = {}
    root.previewImagePath = ""

    colorsProc.requestKey = key
    colorsProc.command = ["curl", "-fsS", "--max-time", "8", ThemeCatalog.themeFileUrl(name, root.previewVariant, "colors.toml")]
    colorsProc.running = true

    root.previewImageLoading = true
    var imageTarget = root.cacheDir + "/" + key.replace(":", "-") + "-preview.png"
    previewImageProc.requestKey = key
    previewImageProc.targetPath = imageTarget
    previewImageProc.command = ["curl", "-fsS", "--max-time", "10", "-o", imageTarget, ThemeCatalog.themeFileUrl(name, root.previewVariant, "preview.png")]
    previewImageProc.running = true
  }

  // Stores into previewCache under requestKey, not under whatever is
  // CURRENTLY selected -- a slow response arriving after the user has
  // already moved on to a different theme must still cache correctly
  // for if they arrow back to it, but must never overwrite what's
  // actively showing for the (different) theme now selected. Only
  // applies live to root.previewColors/previewImagePath when
  // requestKey still matches the live selection.
  Process {
    id: colorsProc
    property string requestKey: ""
    stdout: StdioCollector {
      id: colorsStdout
      waitForEnd: true
    }
    onExited: function(exitCode) {
      var colors = exitCode === 0 ? ThemeCatalog.parseColorsToml(colorsStdout.text) : {}
      var existing = root.previewCache[colorsProc.requestKey] || { colors: {}, imagePath: "" }
      existing.colors = colors
      var cache = root.previewCache
      cache[colorsProc.requestKey] = existing
      root.previewCache = cache
      if (colorsProc.requestKey === root.previewCacheKey(root.selectedThemeName, root.previewVariant))
        root.previewColors = colors
    }
  }

  Process {
    id: previewImageProc
    property string requestKey: ""
    property string targetPath: ""
    onExited: function(exitCode) {
      root.previewImageLoading = false
      var path = exitCode === 0 ? previewImageProc.targetPath : ""
      var existing = root.previewCache[previewImageProc.requestKey] || { colors: {}, imagePath: "" }
      existing.imagePath = path
      var cache = root.previewCache
      cache[previewImageProc.requestKey] = existing
      root.previewCache = cache
      if (previewImageProc.requestKey === root.previewCacheKey(root.selectedThemeName, root.previewVariant))
        root.previewImagePath = path
    }
  }

  ExtensionTwoPanel {
    id: panel
    anchors.fill: parent
  }

  ResultsList {
    parent: panel.leftPane
    anchors.fill: parent
    model: root.themeRows
    filesMode: true
    selectedIndex: root.selectedIndex
    textColor: root.textColor
    mutedColor: root.muted
    accentColor: root.accent
    fontFamily: root.fontFamily
    onRowHovered: (idx) => { root.selectedIndex = idx }
    onRowActivated: (idx) => { root.selectedIndex = idx }
  }

  Text {
    parent: panel.leftPane
    anchors.centerIn: parent
    width: parent.width - 16
    visible: !root.catalogLoading && !root.catalogFailed && root.themeNames.length > 0 && root.filteredThemeNames.length === 0
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

        Row {
          anchors.fill: parent
          visible: previewImage.status !== Image.Ready

          Repeater {
            model: [
              root.previewColors.background, root.previewColors.foreground, root.previewColors.accent,
              root.previewColors.red, root.previewColors.green, root.previewColors.yellow,
              root.previewColors.blue, root.previewColors.magenta, root.previewColors.cyan
            ]
            Rectangle {
              width: parent.width / 9
              height: parent.height
              color: modelData || "#00000000"
            }
          }
        }

        Text {
          anchors.centerIn: parent
          visible: root.previewImageLoading && previewImage.status !== Image.Ready
          text: "Loading preview…"
          font.family: root.fontFamily
          font.pixelSize: 11
          color: root.muted
        }

        Image {
          id: previewImage
          anchors.fill: parent
          fillMode: Image.PreserveAspectCrop
          source: root.previewImagePath !== "" ? "file://" + root.previewImagePath : ""
          asynchronous: true
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

      // --- Variant row (odd -- no tint). Same field-row shape, but the
      // value side is the actual Dark/Light toggle instead of plain
      // text -- mouse-only for stage 1 (no keyboard path to it yet, see
      // this file's own header comment on why rightFocused/
      // focusRightPanel aren't part of the interface here yet).
      Item {
        Layout.fillWidth: true
        height: 24

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

      // --- Palette row (even -- tinted again). Same single-line
      // field-row shape as Name/Variant above (label left, value right)
      // instead of its own label-on-top-of-a-grid layout -- direct
      // follow-up: small round swatches on the right, not a full-width
      // row of square blocks.
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
