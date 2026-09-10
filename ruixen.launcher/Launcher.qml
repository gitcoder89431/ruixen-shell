import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland
import qs.Commons

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

  // Hardcoded OLED black, matching ruixen.settings/ruixen.notch/
  // ruixen.bar's own established convention -- not a theme-driven
  // token (see Bar.qml's GroupPill comment for the original reasoning).
  readonly property color panelBackground: "#000000"
  readonly property color scrim: Color.menu.scrim

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

  function open(payloadJson) {
    root.opened = true
    Qt.callLater(function() { searchInput.forceActiveFocus() })
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
      searchInput.text = ""
      root.query = ""
      root.filesMode = false
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
  onFilesModeChanged: {
    root.selectedIndex = 0
    Qt.callLater(function() { resultsList.positionViewAtBeginning() })
  }
  onQueryChanged: {
    root.selectedIndex = 0
    if (root.query.trim() === "") root.filesMode = false
    // Qt.callLater so this runs after selectedIndex's own change
    // already scrolled toward index 0 -- positionViewAtBeginning
    // additionally clears the top section header into view, which
    // ListView.Contain alone (from the selectedIndex handler below)
    // doesn't guarantee.
    Qt.callLater(function() { resultsList.positionViewAtBeginning() })
  }
  onSelectedIndexChanged: resultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)

  AppLibrary { id: appLibrary }
  OmarchyActionsProvider { id: omarchyActionsProvider }
  // maxResults is a sanity cap on matches, not a display limit -- the
  // results list scrolls now, so this no longer needs to track the
  // fixed card's own visibleRowCount.
  AppSearchProvider { id: appSearchProvider; appLibrary: appLibrary }
  FileSearchProvider { id: fileSearchProvider; query: root.query }

  readonly property var providers: [
    { id: "omarchy-actions", item: omarchyActionsProvider },
    { id: "app-search", item: appSearchProvider },
    { id: "file-search", item: fileSearchProvider }
  ]

  function byScoreDesc(a, b) { return (b.score || 0) - (a.score || 0) }

  // Search Files rows dropped their own path subtitle (see labelText's
  // own comment), so two folders/files that happen to share a bare
  // name (e.g. a "projects-plans" under both "dog" and "cats") would
  // otherwise render as identical, unlabeled rows with no way to tell
  // them apart. Prefixes the immediate PARENT folder's own name (not
  // the whole path -- that's what the details panel's own "Where"
  // field is for) only onto labels that actually collide within the
  // current result set, e.g. "dog/projects-plans" and
  // "cats/projects-plans" -- a name with no duplicate stays untouched.
  function disambiguateLabels(rows) {
    var counts = {}
    for (var i = 0; i < rows.length; i++) counts[rows[i].label] = (counts[rows[i].label] || 0) + 1
    for (var j = 0; j < rows.length; j++) {
      if (counts[rows[j].label] > 1) {
        var dir = String(rows[j].breadcrumb || "")
        var parent = dir.substring(dir.lastIndexOf("/") + 1) || dir
        if (parent) rows[j].label = parent + "/" + rows[j].label
      }
    }
    return rows
  }

  function formatSize(bytes) {
    var n = Number(bytes) || 0
    if (n < 1024) return n + " B"
    var units = ["KB", "MB", "GB", "TB"]
    var v = n / 1024
    for (var i = 0; i < units.length; i++) {
      if (v < 1024 || i === units.length - 1) return v.toFixed(1) + " " + units[i]
      v /= 1024
    }
  }

  function formatDate(epochSeconds) {
    if (!epochSeconds) return ""
    return Qt.formatDateTime(new Date(epochSeconds * 1000), "MMM d, yyyy  h:mm AP")
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
      icon: "",
      label: "Search Files",
      breadcrumb: "File Search",
      kind: "Command",
      providerName: "",
      score: 0,
      sectionLabel: "Use \"" + q + "\" with"
    }
  }

  // A single flat list, each row tagged with its own sectionLabel --
  // fed straight into the results ListView's section.property below,
  // which draws the group headers and keeps the list virtualized (real
  // perf concern once Commands lists every actionable entry, not just
  // a handful).
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
    // FileSearchProvider is asynchronous (a real fd subprocess, not a
    // synchronous scan) -- its own query property is bound directly to
    // root.query (see its instantiation above), and it kicks off a
    // debounced re-search from its own onQueryChanged, not from
    // search() itself (a property WRITE as a side effect of THIS
    // binding's own evaluation caused a real "Binding loop detected"
    // warning, confirmed live). search(q) here is a pure read of
    // whatever its last completed search found; reading lastResults
    // (indirectly, through search()) still makes this binding depend
    // on it, so results updates automatically once fd's output lands.
    if (root.filesMode) {
      var fileRows = root.disambiguateLabels(fileSearchProvider.search(q).sort(root.byScoreDesc))
      return tag(fileRows, "Search Files")
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

    // Backdrop -- click anywhere outside the card to dismiss.
    Rectangle {
      anchors.fill: parent
      color: root.scrim
      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
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
      // still a constant, so the card never grows/shrinks per state.
      // Extra content (more rows than fit, or more than 2 headers)
      // scrolls inside resultsList below rather than needing to fit.
      height: 64 + root.visibleRowCount * root.rowHeight + 2 * root.headerHeight + 8
      radius: 16
      color: root.panelBackground
      clip: true

      layer.enabled: true
      layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: "#000000"
        shadowOpacity: 0.7
        shadowBlur: 0.4
        shadowHorizontalOffset: 0
        shadowVerticalOffset: 6
      }

      // Swallows a click on the card itself so it doesn't fall through
      // to the scrim's own dismiss MouseArea behind it.
      MouseArea { anchors.fill: parent }

      Rectangle {
        id: searchBox
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 8
        height: 48
        radius: 12
        color: Qt.rgba(1, 1, 1, 0.06)

        TextInput {
          id: searchInput
          anchors.fill: parent
          anchors.leftMargin: 16
          anchors.rightMargin: 16
          verticalAlignment: TextInput.AlignVCenter
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 16
          clip: true
          onTextChanged: root.query = text

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.filesMode ? "Search files..." : "Search actions and apps..."
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 16
            visible: searchInput.text.length === 0
          }

          // Same Escape/Up/Down/Enter shape LauncherContent.qml's own
          // launcherSearchInput already proves out -- Escape now drills
          // up one level (out of Search Files, back to the main
          // Results view) before it dismisses the whole palette,
          // rather than always dismissing outright.
          Keys.onPressed: function(event) {
            var count = root.results.length
            if (event.key === Qt.Key_Escape) {
              if (root.filesMode) root.filesMode = false
              else root.dismiss()
              event.accepted = true
            } else if (event.key === Qt.Key_Up) {
              if (root.selectedIndex > 0) root.selectedIndex--
              event.accepted = true
            } else if (event.key === Qt.Key_Down) {
              if (root.selectedIndex < count - 1) root.selectedIndex++
              event.accepted = true
            } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
              root.activateSelected()
              event.accepted = true
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
      // selection math in sync with -- this delegate's own `index` is
      // already the same flat index as root.selectedIndex.
      ListView {
        id: resultsList
        anchors.top: searchBox.bottom
        anchors.topMargin: 8
        anchors.left: parent.left
        anchors.leftMargin: 8
        // Search Files mode splits the card: this list keeps the left
        // side, detailsPanel (below) takes the right -- Raycast's own
        // real Search Files layout, list left / metadata right.
        anchors.right: root.filesMode ? detailsPanel.left : parent.right
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        clip: true
        spacing: 0
        // Same fix as ruixen.settings' own detail panel Flickable /
        // DashboardContent.qml's notification ListView -- no overscroll
        // bounce.
        boundsBehavior: Flickable.StopAtBounds
        model: root.results

        section.property: "sectionLabel"
        section.criteria: ViewSection.FullString
        section.delegate: Item {
          width: resultsList.width
          height: root.headerHeight

          Text {
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            text: section
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
            font.capitalization: Font.AllUppercase
            font.bold: true
          }
        }

        delegate: Rectangle {
          id: row
          required property var modelData
          required property int index
          width: resultsList.width
          height: root.rowHeight
          radius: 10
          color: row.index === root.selectedIndex ? Qt.rgba(1, 1, 1, 0.12) : "transparent"

          // Omarchy Actions: a Nerd Font glyph. Applications: a real
          // icon via the shared AppLibrary instance -- same branch-on-
          // provider split LauncherContent.qml's own tilesAreApps
          // already uses for the identical reason (two different icon
          // sources, one Image + one fallback Text).
          Image {
            id: appIcon
            visible: row.modelData.providerId === "app-search" && status === Image.Ready
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            height: 22
            sourceSize: Qt.size(22, 22)
            asynchronous: true
            source: row.modelData.providerId === "app-search" ? appLibrary.iconSource(row.modelData.icon) : ""
          }

          Text {
            visible: row.modelData.providerId !== "app-search"
            anchors.left: parent.left
            anchors.leftMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            width: 22
            horizontalAlignment: Text.AlignHCenter
            text: row.modelData.icon
            // Folders (Search Files only -- Commands/Applications never
            // have kind "Folder") pick up the active theme's own accent
            // color, same as every other accent-colored element in this
            // repo's own theme convention -- files stay the plain
            // textColor every other icon uses.
            color: row.modelData.kind === "Folder" ? root.accent : root.textColor
            font.family: root.fontFamily
            font.pixelSize: 16
          }

          // Shrinks to the label's own content again, but WITHOUT
          // measuring rendered text at all this time -- both earlier
          // attempts did that and both broke: implicitWidth off a Text
          // that also elides is a real, documented Qt Quick "Binding
          // loop detected for property width" gotcha, and a sibling
          // TextMetrics (the usual fix for that gotcha) hit a worse
          // bug -- ListView recycles delegates, and TextMetrics.width
          // lagged a stale measurement from whatever row PREVIOUSLY
          // occupied this recycled delegate, truncating every label
          // regardless of its own actual length. Since the font here
          // is monospace (JetBrainsMono Nerd Font), label.length times
          // a fixed per-character advance is a good enough estimate of
          // the real rendered width -- pure arithmetic on a string, no
          // layout-engine measurement involved, so neither bug can
          // recur. elide still absorbs any small over/under-estimate.
          // In Search Files mode there's no subtitle/kind at all (see
          // metaText/kindText below), so the label just takes the
          // whole row regardless.
          readonly property real charWidth: 8
          Text {
            id: labelText
            anchors.left: parent.left
            anchors.leftMargin: 44
            anchors.verticalCenter: parent.verticalCenter
            width: root.filesMode
              ? (parent.width - 44 - 12)
              : Math.min(row.modelData.label.length * row.charWidth + 4, parent.width * 0.55 - 44)
            elide: Text.ElideRight
            text: row.modelData.label
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 13
          }

          // Subtitle beside the name -- Applications: AppSearchProvider's
          // own category (the app's genericName, e.g. "Web Browser",
          // falling back to a bare "Application"). Omarchy Actions / any
          // future native Ruixen provider: the full breadcrumb (e.g.
          // "Remove › Development", "Ruixen" for the synthetic Ruixen
          // Settings row). Bounded on the right by kindText below, not
          // the row's own edge, so the two never overlap. Hidden in
          // Search Files mode -- the details panel's own "Where" field
          // already shows the path, so repeating it here (and the
          // Folder/File kind tag below, already obvious from the row's
          // own icon) would just be noise; the row is just an icon +
          // name there, on purpose, so the details panel is the
          // featured part of that view, not a third column squeezed
          // beside it.
          Text {
            id: metaText
            visible: !root.filesMode
            anchors.left: labelText.right
            anchors.leftMargin: 8
            anchors.right: kindText.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: row.modelData.providerId === "app-search" ? row.modelData.category : row.modelData.breadcrumb
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
          }

          // Kind tag -- "Command" for every Omarchy Actions/native
          // Ruixen row, "Application" for App Search -- pinned to the
          // row's own right edge, kept separate from the breadcrumb/
          // category subtitle above rather than folded into one string,
          // so it stays in a stable, scannable column even as the
          // subtitle's own length varies row to row. Hidden in Search
          // Files mode -- see metaText's own comment above.
          Text {
            id: kindText
            visible: !root.filesMode
            anchors.right: parent.right
            anchors.rightMargin: 12
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            width: 72
            text: row.modelData.providerId === "app-search" ? "Application" : row.modelData.kind
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
          }

          MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: root.selectedIndex = row.index
            onClicked: {
              root.selectedIndex = row.index
              root.activateSelected()
            }
          }
        }
      }

      // Search Files' own metadata sidebar -- Raycast's real Search
      // Files splits the same way, list left / details right. Only
      // ever shows the CURRENTLY SELECTED file's info (fetched via
      // FileSearchProvider.loadDetails(), a real `stat` call -- fd
      // itself doesn't return size/type/modified time), not anything
      // for the whole list, so it's cheap regardless of result count.
      Rectangle {
        id: detailsPanel
        visible: root.filesMode && !root.showNoResults
        anchors.top: searchBox.bottom
        anchors.topMargin: 8
        anchors.right: parent.right
        anchors.rightMargin: 8
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 8
        // A real 1:3 split (0.75) turned out too extreme in practice --
        // this panel started swallowing the whole card and the list
        // got uncomfortably thin. 0.6 still gives this panel the
        // larger, featured share without starving the list. parent.width
        // - 24 is the usable space once the card's own left/right
        // margins (8 each) and the gap between the two panes (8,
        // resultsList's own rightMargin) are subtracted.
        width: (parent.width - 24) * 0.6
        radius: 12
        color: Qt.rgba(1, 1, 1, 0.04)
        clip: true

        readonly property var result: root.selectedResult
        readonly property var details: fileSearchProvider.selectedDetails
        // Still-image formats get a real thumbnail instead of the
        // generic file glyph -- reuses FileSearchProvider's own
        // extension-derived "Kind" string (e.g. "PNG Image") rather
        // than re-deriving the extension here a second time.
        // Plain truthiness, not `!== null` -- selectedResult/selectedDetails
        // can transiently be `undefined` rather than `null` between
        // selections, which `!== null` doesn't catch and which tripped a
        // real "Value is undefined and could not be converted to an
        // object" warning from the Image source binding below.
        readonly property bool isImagePreview: !!detailsPanel.details && !!detailsPanel.result &&
          ["PNG Image", "JPEG Image", "GIF Image", "WebP Image", "Bitmap Image", "SVG Image"].indexOf(detailsPanel.details.type) !== -1

        Column {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.margins: 24
          spacing: 18
          visible: detailsPanel.result !== null

          // A real preview pane, not just an icon -- tall enough to give
          // a still-image thumbnail room to breathe (Raycast's own
          // Search Files detail view reserves similar space up top).
          // The name used to live in its own Text below this pane; it's
          // now the first metadata field instead (see Repeater below),
          // so this pane gets that space too -- non-image results (most
          // prominently folders, which never get a thumbnail) just show
          // the same glyph the list row already uses, bigger still.
          Item {
            width: parent.width
            height: 210

            // clip + radius on the container, not the Image itself --
            // QML Image has no radius of its own. PreserveAspectCrop
            // (rather than the Fit used elsewhere) so the image always
            // fills this rect edge-to-edge -- with Fit's letterboxing,
            // rounding the container's corners would round empty
            // transparent space instead of the image.
            Rectangle {
              anchors.fill: parent
              visible: detailsPanel.isImagePreview
              radius: 12
              clip: true
              color: "transparent"

              Image {
                anchors.fill: parent
                source: detailsPanel.isImagePreview && detailsPanel.result ? "file://" + detailsPanel.result.action.path : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
              }
            }

            Text {
              anchors.centerIn: parent
              visible: !detailsPanel.isImagePreview
              text: detailsPanel.result ? detailsPanel.result.icon : ""
              // Same folder-only accent as the list row's own icon.
              color: detailsPanel.result && detailsPanel.result.kind === "Folder" ? root.accent : root.textColor
              font.family: root.fontFamily
              font.pixelSize: 88
            }
          }

          Rectangle { width: parent.width; height: 1; color: Qt.rgba(1, 1, 1, 0.08) }

          Repeater {
            model: detailsPanel.details ? [
              { label: "Name", value: detailsPanel.result ? detailsPanel.result.label : "" },
              { label: "Type", value: detailsPanel.details.type },
              { label: "Size", value: root.formatSize(detailsPanel.details.size) },
              { label: "Where", value: detailsPanel.result ? detailsPanel.result.breadcrumb : "" },
              { label: "Modified", value: root.formatDate(detailsPanel.details.mtime) },
              { label: "Permissions", value: detailsPanel.details.permissions }
            ] : []

            // One row per field -- label left, value right, elided
            // rather than wrapped (a "Where" path can be long; a second
            // wrapped line would break the fixed row height). The value
            // Text's width comes from anchors between the two siblings
            // here, not its own implicitWidth, so this doesn't reintroduce
            // the implicitWidth+elide binding-loop gotcha documented on
            // the results list's own labelText above.
            Item {
              id: field
              required property var modelData
              width: parent.width
              height: 20

              Text {
                id: fieldLabel
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: field.modelData.label
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: 11
                font.capitalization: Font.AllUppercase
              }
              Text {
                anchors.left: fieldLabel.right
                anchors.leftMargin: 12
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideMiddle
                text: field.modelData.value
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 13
              }
            }
          }

          Text {
            visible: !detailsPanel.details
            width: parent.width
            horizontalAlignment: Text.AlignHCenter
            text: "Loading…"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 11
          }
        }
      }

      // Empty state -- centered in the whole content area below the
      // search box (spans the full card width, not just the list
      // column, so it reads the same whether or not detailsPanel would
      // otherwise be showing beside it). Same magnifying-glass glyph
      // (fa-search, U+F002) as the Search Files fallback row's own
      // icon, just large -- a found-nothing state reading as "the
      // search itself" rather than needing a distinct icon of its own.
      Item {
        visible: root.showNoResults
        anchors.top: searchBox.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right

        Column {
          anchors.centerIn: parent
          spacing: 10

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: ""
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 40
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: "No Results"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 14
          }
        }
      }
    }
  }
}
