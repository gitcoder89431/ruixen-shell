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

  // The single synthetic "Use ... with" fallback row -- not a real
  // provider result (there's no search() behind it, just a switch).
  // providerId "files-fallback" is special-cased in activateSelected()
  // below: activating it flips filesMode on instead of running
  // anything. This is meant to generalize the same way the other
  // "add a provider" extension points already do -- a future "Search
  // Files" for CONTENT (not just names) or a dictionary-style fallback
  // would each be one more entry in a fallbacks array here, not a
  // structural change -- deliberately not built yet, out of scope for
  // this pass.
  function filesFallbackRow(q) {
    return {
      id: "fallback:files",
      providerId: "files-fallback",
      icon: "",
      label: "Search Files",
      breadcrumb: "for \"" + q + "\"",
      kind: "",
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
  // A non-empty query collapses Applications/Commands/Folders into ONE
  // "Results" section, globally sorted by score -- confirmed directly
  // against Raycast's own actual behavior (checked live): typing a
  // query drops per-source headers and shows one flat, relevance-
  // ranked list. Plain Files are deliberately NOT mixed in here --
  // also confirmed directly against Raycast's own real behavior: it
  // doesn't inline file results either (too spammy once a query
  // matches hundreds of them), offering a "Use ... with" fallback row
  // instead. filesMode (flipped by activating that row) switches the
  // whole list over to file-only results for the same query.
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
    var fileHits = fileSearchProvider.search(q)
    if (root.filesMode) return tag(fileHits.sort(root.byScoreDesc), "Search Files")
    var cmds = omarchyActionsProvider.search(q)
    var apps = appSearchProvider.search(q)
    var folders = fileHits.filter(function(r) { return r.kind === "Folder" })
    var all = cmds.concat(apps).concat(folders).sort(root.byScoreDesc)
    return tag(all, "Results").concat([root.filesFallbackRow(q)])
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
      width: 640
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
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 8
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
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 16
          }

          // Label keeps only as much width as it needs (capped so a
          // long label can't push the subtitle off the row entirely) --
          // metaText then sits right after it with a small gap, as a
          // subtitle beside the name, rather than pinned to the row's
          // far right edge with a dead gap in between for short labels.
          Text {
            id: labelText
            anchors.left: parent.left
            anchors.leftMargin: 44
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, parent.width * 0.55 - 44)
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
          // the row's own edge, so the two never overlap.
          Text {
            id: metaText
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
          // subtitle's own length varies row to row.
          Text {
            id: kindText
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
    }
  }
}
