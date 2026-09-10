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
  // Shared by sourceFilterButton (the closed control) and sourceFilterList
  // (the opened menu) -- same width on both so they read as one dropdown
  // widget rather than a button with a mismatched panel underneath.
  readonly property int sourceFilterWidth: 150

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
  // "" means every known root (the source-filter dropdown's own "All Sources"
  // entry); a specific path restricts Search Files to just that drive.
  // Reset to "" on every fresh entry into Search Files -- "defaults to
  // All" should mean that literally each time, not just the first time.
  property string selectedSourcePath: ""
  onFilesModeChanged: {
    // Re-discovers mounted secondary drives (see FileSearchProvider's
    // own refreshRoots()) each time Search Files is entered, rather
    // than once at startup or on a timer -- a drive plugged in mid-
    // session (a USB stick, say) becomes searchable the next time this
    // view opens, without needing a full shell restart.
    if (root.filesMode) fileSearchProvider.refreshRoots()
    root.selectedSourcePath = ""
    sourceFilterList.visible = false
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
  FileSearchProvider { id: fileSearchProvider; query: root.query; sourceFilter: root.selectedSourcePath }

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
      // still a constant, so the card never grows/shrinks per state.
      // Extra content (more rows than fit, or more than 2 headers)
      // scrolls inside resultsList below rather than needing to fit.
      height: 64 + root.visibleRowCount * root.rowHeight + 2 * root.headerHeight + 8
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

      Rectangle {
        id: searchBox
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 8
        height: 48
        // Ghost -- no pill surface of its own (direct request: "put it
        // on the glass so its ghost"), just the card's own frosted
        // background showing straight through. No bottom border either
        // now -- direct follow-up ("we dont need this separator
        // anymore") -- the search box just flows straight into the
        // results below.
        radius: 0
        color: "transparent"

        // fa-search (U+F002), same glyph as the Search Files fallback
        // row's own icon. Positioned with the exact same leftMargin/
        // width/centering as a result row's own icon Text below
        // (row.qml's own `appIcon`/icon Text) -- searchBox and
        // resultsList share the same leftMargin (8) off the card, and
        // a ListView delegate's own x is that view's x with no further
        // offset, so matching leftMargin+width here lines this glyph's
        // column up with every row's icon column exactly, not just
        // approximately.
        Text {
          id: searchIcon
          anchors.left: parent.left
          anchors.leftMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          width: 22
          horizontalAlignment: Text.AlignHCenter
          text: ""
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 16
        }

        // Search Files only -- filters fd's own search roots to just one
        // drive (see FileSearchProvider's own sources/sourceFilter).
        // Meaningless outside Search Files (Applications/Commands have
        // no "drive"), so hidden the rest of the time -- TextInput's own
        // rightMargin below only makes room for it while it's visible.
        // Ghost trigger, not a nested pill -- no background surface of
        // its own (a faint hover/open tint is the only visual affordance),
        // so it reads as part of the search input rather than a separate
        // control sitting on top of it. Sized to its own content
        // (filterRow.implicitWidth), not a fixed box, so the label sits
        // right up against the chevron instead of floating inside slack
        // space.
        // Fixed width shared with sourceFilterList below (sourceFilterWidth)
        // so the closed control and the opened menu share one width --
        // reads as a single dropdown widget rather than a button with a
        // mismatched panel. No hover tint -- the chevron itself flipping
        // to point up is the only "open" affordance needed.
        Item {
          id: sourceFilterButton
          visible: root.filesMode
          anchors.right: parent.right
          anchors.rightMargin: 12
          anchors.verticalCenter: parent.verticalCenter
          width: root.sourceFilterWidth
          height: 28

          readonly property string currentLabel: root.selectedSourcePath === "" ? "All Sources" : (function() {
            var srcs = fileSearchProvider.sources
            for (var i = 0; i < srcs.length; i++) if (srcs[i].path === root.selectedSourcePath) return srcs[i].label
            return "All Sources"
          })()

          Text {
            id: sourceFilterLabel
            anchors.left: parent.left
            anchors.leftMargin: 10
            anchors.right: sourceFilterChevron.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            elide: Text.ElideRight
            text: sourceFilterButton.currentLabel
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 12
          }

          // fa-chevron-down (U+F078) -- rotates to point up while the
          // menu is open, same convention as a native <select>.
          Text {
            id: sourceFilterChevron
            anchors.right: parent.right
            anchors.rightMargin: 10
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 9
            rotation: sourceFilterList.visible ? 180 : 0
            transformOrigin: Item.Center
            Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
          }

          MouseArea {
            anchors.fill: parent
            onClicked: sourceFilterList.visible = !sourceFilterList.visible
          }
        }

        TextInput {
          id: searchInput
          anchors.fill: parent
          // searchIcon's own leftMargin (12) + width (22) + a 10px gap.
          anchors.leftMargin: 44
          // sourceFilterWidth + sourceFilterButton's own rightMargin (12)
          // + a small gap, only while it's actually showing.
          anchors.rightMargin: root.filesMode ? (root.sourceFilterWidth + 12 + 10) : 16
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
              if (sourceFilterList.visible) sourceFilterList.visible = false
              else if (root.filesMode) root.filesMode = false
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

      // Closes the dropdown on any click elsewhere on the card (rows,
      // the details panel, ...) -- only present while the list is open,
      // and z-ordered between searchBox (default z:0) and the list
      // itself (z:100) so it can't intercept normal clicks the rest of
      // the time. The outside click is consumed here rather than also
      // passed through to whatever's underneath -- a common, expected
      // dropdown convention (the first click away just dismisses).
      MouseArea {
        anchors.fill: parent
        visible: sourceFilterList.visible
        z: 50
        onClicked: sourceFilterList.visible = false
      }

      Rectangle {
        id: sourceFilterList
        visible: false
        anchors.top: searchBox.bottom
        anchors.topMargin: 6
        anchors.right: searchBox.right
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
                  sourceFilterList.visible = false
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
      // selection math in sync with -- this delegate's own `index` is
      // already the same flat index as root.selectedIndex.
      ListView {
        id: resultsList
        anchors.top: searchBox.bottom
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
          // Row itself stays a plain transparent hit-box, full width
          // (icon/text below still anchor off ITS edges, unaffected) --
          // the actual highlight fill is the separate, inset Rectangle
          // below instead. Direct report: the highlight used to fill
          // row's own full width, right up against the list/details
          // separator (only the resultsList-to-separator 4px gap stood
          // between them, reading as "too close"). 6px on both sides
          // now, matching left/right for balance.
          color: "transparent"

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: 6
            anchors.rightMargin: 6
            radius: row.radius
            color: row.index === root.selectedIndex ? Qt.rgba(1, 1, 1, 0.12) : "transparent"
          }

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
      Rectangle {
        id: detailsPanel
        visible: root.filesMode && !root.showNoResults
        anchors.top: searchBox.bottom
        // Matches resultsList's own topMargin (see its comment) --
        // both panels need the exact same offset from searchBox for
        // the alignment fix on the inner Column below to actually work.
        anchors.topMargin: 4
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
        // Ghost -- no surface of its own (direct request: "ghost it on
        // the spotlight"), just the card's own frosted background
        // showing straight through, same treatment already given to
        // the search input. A line separator (see detailsSeparator
        // below) takes over marking the boundary with the results
        // list, instead of a filled panel doing that job.
        color: "transparent"
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

        // Read straight off the already-loaded thumbnail Image itself
        // (sourceSize reports the source file's own natural pixel
        // dimensions once decoded) -- no external tool needed at all,
        // unlike video duration below which has nothing already loaded
        // to read this from.
        readonly property string imageDimensions: (detailsPanel.isImagePreview && thumbnailImage.status === Image.Ready && thumbnailImage.sourceSize.width > 0)
          ? (thumbnailImage.sourceSize.width + " × " + thumbnailImage.sourceSize.height)
          : ""

        // No scrolling -- reverted direct follow-up: a Flickable here
        // gave real mouse-wheel scrolling, but with no keyboard path to
        // reach it at all (this launcher's own key handling never
        // touches detailsPanel), that read as a dead end rather than a
        // real fix ("doesnt seem worth it for durations and size").
        // Compacting the row height/spacing instead (both below) so
        // the list fits without needing to scroll in the first place.
        Column {
          id: detailsColumn
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          // Top margin separated out from the rest (was 24 on all
          // sides) -- direct report: "the panels are kinda unbalanced,
          // the preview fixed size is taking a bit too much space...
          // make sure the thumbnail height starts where the left panel
          // text search files is". 0 here, not a further inset on top
          // of detailsPanel's own topMargin above -- resultsList's own
          // header has no internal inset beyond ITS topMargin either,
          // so adding another one here (an earlier pass used 8, double-
          // counting against detailsPanel's own offset) put the preview
          // 8px lower than actually aligned. Left/right padding stays
          // 24 for the panel's own internal breathing room.
          anchors.topMargin: 0
          anchors.leftMargin: 24
          anchors.rightMargin: 24
          // 18 -> 10 -> 14 -> 12 -- first compacted to fit 8 rows
          // without scrolling, eased back up ("a bit too tight now...
          // we have alot more space now") once that turned out to
          // leave slack, but 14 (plus the restored Metadata header)
          // overflowed again -- confirmed live, an 8-row video's own
          // Permissions row was genuinely clipped off the bottom, not
          // just a screenshot crop. This is the single spacing value
          // between EVERY child here (the preview, the Metadata header,
          // and every field row alike).
          spacing: 12
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

            // clip on a Rectangle only clips to its plain bounding box --
            // `radius` never participates in child clipping, confirmed
            // live (the first attempt still rendered square corners). A
            // real mask is what actually rounds a child Image's corners
            // -- same MultiEffect technique already used for the
            // notification thumbnail in ruixen.notch/DashboardContent.qml
            // (source Image + an invisible layered mask Rectangle + the
            // MultiEffect that composites them). PreserveAspectCrop
            // (rather than the Fit used elsewhere) so the image always
            // fills this rect edge-to-edge.
            Item {
              anchors.fill: parent
              visible: detailsPanel.isImagePreview

              Image {
                id: thumbnailImage
                anchors.fill: parent
                source: detailsPanel.isImagePreview && detailsPanel.result ? "file://" + detailsPanel.result.action.path : ""
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                cache: false
                smooth: true
                visible: false
              }

              Rectangle {
                id: thumbnailMask
                anchors.fill: parent
                radius: 12
                color: "#ffffff"
                visible: false
                layer.enabled: true
              }

              MultiEffect {
                anchors.fill: parent
                source: thumbnailImage
                maskEnabled: true
                maskSource: thumbnailMask
                maskThresholdMin: 0.5
                maskThresholdMax: 1.0
              }
            }

            Text {
              anchors.centerIn: parent
              visible: !detailsPanel.isImagePreview
              text: detailsPanel.result ? detailsPanel.result.icon : ""
              // Same folder-only accent as the list row's own icon.
              color: detailsPanel.result && detailsPanel.result.kind === "Folder" ? root.accent : root.textColor
              font.family: root.fontFamily
              font.pixelSize: 150
            }
          }

          // Same muted/uppercase/bold section-header style as the
          // results list's own section headers above. Removed once
          // during compacting, restored once that compaction turned
          // out to leave real slack to spare ("we have alot more space
          // now").
          Text {
            visible: detailsPanel.details !== null
            text: "Metadata"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
            font.capitalization: Font.AllUppercase
            font.bold: true
          }

          Repeater {
            // Dimensions/Duration/Created only appear when actually
            // available -- an IIFE (same pattern as sourceFilterButton's
            // own currentLabel above) rather than a flat literal, since
            // "insert this field only if truthy" isn't expressible as a
            // single ternary once there are three independent optional
            // fields instead of one.
            model: detailsPanel.details ? (function() {
              var out = [
                { label: "Name", value: detailsPanel.result ? detailsPanel.result.label : "" },
                { label: "Type", value: detailsPanel.details.type }
              ]
              // Mutually exclusive in practice (isImagePreview's own
              // type list and videoExtensions never overlap), but
              // checked independently rather than else-if -- neither
              // depends on the other being absent.
              if (detailsPanel.imageDimensions) out.push({ label: "Dimensions", value: detailsPanel.imageDimensions })
              if (fileSearchProvider.videoDuration) out.push({ label: "Duration", value: fileSearchProvider.videoDuration })
              out.push({ label: "Size", value: root.formatSize(detailsPanel.details.size) })
              out.push({ label: "Where", value: detailsPanel.result ? detailsPanel.result.breadcrumb : "" })
              // 0 means this filesystem doesn't track birth time (see
              // FileSearchProvider's own loadDetails comment) -- omit
              // rather than show a bogus 1970 date.
              if (detailsPanel.details.created) out.push({ label: "Created", value: root.formatDate(detailsPanel.details.created) })
              out.push({ label: "Modified", value: root.formatDate(detailsPanel.details.mtime) })
              out.push({ label: "Permissions", value: detailsPanel.details.permissions })
              return out
            })() : []

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
              required property int index
              width: parent.width
              // 20 -> 18 -> 20 -> 19 -- see Column's own spacing
              // comment above for why 20 (the fully-eased-back value)
              // overflowed once the header came back too; split the
              // difference rather than dropping all the way back to 18.
              height: 19

              // Zebra striping -- direct request: "dark light dark
              // light kinda tint" so adjacent rows are easier to track.
              // Outdents past the row's own text bounds (a wider band
              // than just the label/value) and a little vertical
              // padding.
              Rectangle {
                anchors.fill: parent
                anchors.leftMargin: -10
                anchors.rightMargin: -10
                anchors.topMargin: -4
                anchors.bottomMargin: -4
                radius: 4
                color: field.index % 2 === 0 ? Qt.rgba(0, 0, 0, 0.18) : "transparent"
              }

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

      // Bottom fade on both panels -- a static decorative hint that
      // content could keep going below ("infinite flow"), not tied to
      // actual scroll position at all. Direct request: no smart scroll-
      // position detection needed if this just sits in a good spot
      // regardless of whether there's actually more to see. Anchored
      // off each panel's own resolved edges (resultsList.right is
      // itself conditional on root.filesMode, so anchoring here needs
      // no separate logic to stay in sync) rather than duplicating
      // their geometry. A plain Rectangle with no MouseArea doesn't
      // intercept clicks to whatever row sits underneath it.
      Rectangle {
        visible: !root.showNoResults
        anchors.left: resultsList.left
        anchors.right: resultsList.right
        anchors.bottom: resultsList.bottom
        height: 36
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(root.glassBackground.r, root.glassBackground.g, root.glassBackground.b, 0) }
          GradientStop { position: 1.0; color: root.glassBackground }
        }
      }

      Rectangle {
        visible: root.filesMode && !root.showNoResults
        anchors.left: detailsPanel.left
        anchors.right: detailsPanel.right
        anchors.bottom: detailsPanel.bottom
        height: 36
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.rgba(root.glassBackground.r, root.glassBackground.g, root.glassBackground.b, 0) }
          GradientStop { position: 1.0; color: root.glassBackground }
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
