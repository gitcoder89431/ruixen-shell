import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io

// Layout-only shell for the "Settings" extension -- direct request:
// "lets do the Settings as Extension so Settings 2nd Column Ruixen and
// type extension? itll be similar to the 2 panel layout where we have
// the Profile Launcher Bluetooth menu options on the left panel, then
// enter to go into the right panel where we have toggles and inputs
// and options. dont build out the whole thing yet... just start with
// the layout first then we can work on the panels?" -- deliberately
// navigation + chrome only: a left category list and a right panel
// that opens straight onto Profile ("we can land in the profile
// page"). Direct follow-up landed Profile's own REAL content --
// avatar/username/DiceBear picker, ported byte-for-byte in spirit from
// ruixen.settings/GeneralContent.qml + the matching backend block in
// ruixen.settings/Settings.qml (avatarCollections/selectAvatar/the
// avatar.json state file) -- plugin folders can't share a file across
// install locations (same reason AppLibrary.qml/AppSearch.js already
// exist three times over, and LauncherSearchConfig.js twice), so this
// is a second, independent copy of that exact same mechanism, reading
// and writing the exact same real files (~/.face.icon, ~/.local/state/
// ruixen/avatar.json) -- picking an avatar here is visible in
// ruixen.notch's own UserAvatar too, same as picking one there is.
// Every OTHER category still gets the plain header + description
// treatment -- that's explicit later work, one category at a time.
//
// Direct follow-up chain after the first pass hand-rolled its own row
// visuals and its own margins: "it looks too much different than the
// file search, lets have some design consistency"; then, after a
// Loader/Component-based attempt at sharing that quietly broke font
// propagation: "why did you port it over from the ruixen settings
// menu... wouldnt it be a lot easier to just make a list of stuff like
// a list component from file search thats shared?" -- so the category
// list below IS ResultsList/ResultRow, the exact same component Search
// Files itself renders through (filesMode: true, same icon+label-only
// row), not a second implementation of "a list of rows". Only the
// outer 2-panel split (list width/detail width/divider) comes from
// ExtensionTwoPanel.qml, and even that owns geometry only -- every
// color/font binding below is a plain, direct binding off this file's
// own root, same as every other file in this plugin.
Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"
  property bool active: false
  // Fed from the outer SearchHeader/root.query, same single-search-box
  // convention Wallpapers already established ("we dont need two
  // search box, use the launcher for wallpaper search input") -- direct
  // follow-up: "does search work for menu items on the left too?"
  property string searchText: ""

  // --- Profile: avatar/username, ported from ruixen.settings -- see
  // this file's own header comment for why this is a second, real copy
  // rather than a shared import. Every property/function/Process name
  // below matches ruixen.settings/Settings.qml's own naming exactly,
  // so the two stay easy to compare/keep in sync by hand.
  readonly property string username: {
    var u = Quickshell.env("USER") || "user"
    return u.charAt(0).toUpperCase() + u.slice(1)
  }
  property string hardwareName: ""
  property int avatarCacheBust: 0
  property bool avatarBusy: false
  readonly property var avatarCollections: [
    { id: "gradient", label: "Gradient" },
    { id: "bottts-neutral", label: "Bottts", version: "10.x", format: "svg" },
    { id: "pixel-art", label: "Pixel Art" },
    { id: "pixelbot", label: "Pixelbot", version: "10.x", format: "svg" },
    { id: "identicon", label: "Identicon" },
    { id: "thumbs", label: "Thumbs" },
    { id: "sprouts", label: "Sprouts", version: "10.x", format: "svg" },
    { id: "critters", label: "Critters", version: "10.x", format: "svg" },
    { id: "moods", label: "Moods", version: "10.x", format: "svg" }
  ]
  property string avatarCollection: "gradient"
  property bool avatarStateLoaded: false
  readonly property string avatarStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/avatar.json"

  function loadAvatarState(raw) {
    if (root.avatarStateLoaded) return
    try {
      var parsed = JSON.parse(raw)
      if (parsed && typeof parsed.collection === "string") {
        var known = false
        for (var i = 0; i < root.avatarCollections.length; i++) {
          if (root.avatarCollections[i].id === parsed.collection) { known = true; break }
        }
        if (known) root.avatarCollection = parsed.collection
      }
    } catch (e) {}
    root.avatarStateLoaded = true
  }

  // Single entry point for every avatar-picker button -- "gradient"
  // deletes ~/.face.icon, any real DiceBear slug fetches a random
  // avatar from that collection.
  function selectAvatar(collection) {
    if (root.avatarBusy) return
    root.avatarBusy = true
    root.avatarCollection = collection
    var target = Quickshell.env("HOME") + "/.face.icon"
    if (collection === "gradient") {
      avatarProc.command = ["bash", "-c", "rm -f '" + target + "'"]
    } else {
      var seed = Math.random().toString(36).slice(2) + Date.now()
      var entry = null
      for (var i = 0; i < root.avatarCollections.length; i++) {
        if (root.avatarCollections[i].id === collection) { entry = root.avatarCollections[i]; break }
      }
      var version = (entry && entry.version) || "9.x"
      var format = (entry && entry.format) || "png"
      var url = "https://api.dicebear.com/" + version + "/" + collection + "/" + format + "?seed=" + seed
      avatarProc.command = ["bash", "-c", "curl -fsL '" + url + "' -o '" + target + "'"]
    }
    avatarProc.running = true
  }

  Process {
    id: identityProc
    command: ["fastfetch", "--format", "json", "-s", "Host"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          for (var i = 0; i < data.length; i++) {
            if (data[i].type === "Host") root.hardwareName = data[i].result.name || ""
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: ensureAvatarStateDirProc
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/ruixen"]
  }

  FileView {
    id: avatarStateFile
    path: root.avatarStatePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadAvatarState(text())
    onLoadFailed: root.loadAvatarState("")
  }

  Process {
    id: avatarProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      root.avatarBusy = false
      root.avatarCacheBust = root.avatarCacheBust + 1
      avatarStateFile.setText(JSON.stringify({ collection: root.avatarCollection }, null, 2) + "\n")
      // Tells ruixen.notch's own UserAvatar to re-read the file too --
      // it's a separate keepLoaded:true plugin process, so it has no
      // other way to know ~/.face.icon just changed.
      avatarNotifyProc.command = ["omarchy-shell", "-q", "ruixen.notch", "refreshAvatar"]
      avatarNotifyProc.running = true
    }
  }

  Process {
    id: avatarNotifyProc
  }

  Component.onCompleted: ensureAvatarStateDirProc.running = true

  // Same 8 sections, same ids/labels/glyphs as ruixen.settings/
  // Settings.qml's own root.sections -- confirmed by reading that file
  // directly, not guessed, so this list reads as the same feature, not
  // a fork of it. Glyph codepoints copied byte-for-byte from there too.
  // `description` is this pass's own addition -- direct request:
  // "instead of coming soon, just add a small one or two line
  // description for each of the settings? bespoke eloquent tone sounds
  // nice" -- one line each, replaced with real content once each
  // section's actual toggles/inputs land.
  readonly property var sections: [
    { id: "general", label: "Profile", glyph: "",
      description: "Your identity on this machine — display name, avatar, and the small touches that make Ruixen feel like yours." },
    { id: "launcher", label: "Launcher", glyph: "",
      description: "How this very launcher searches, ranks, and remembers what matters most the moment you reach for it." },
    { id: "audio", label: "Audio", glyph: "",
      description: "Volume, output routing, and the quieter details of how this machine sounds." },
    { id: "wifi", label: "Wi-Fi", glyph: "",
      description: "Known networks and the signal that keeps this machine reliably reachable." },
    { id: "bluetooth", label: "Bluetooth", glyph: "",
      description: "Paired devices and the wireless companions currently orbiting this machine." },
    { id: "display", label: "Display", glyph: "",
      description: "Bar layout, corner curvature, and the finer points of how this shell presents itself." },
    { id: "plugins", label: "Plugins", glyph: "",
      description: "Everything Ruixen has installed, kept updated, and quietly running." },
    { id: "about", label: "About", glyph: "",
      description: "Version, update status, and the fine print behind this shell." }
  ]

  // Filtered by label, same as ruixen.settings/Settings.qml's own
  // filteredSections -- ported logic, not reinvented. Keeps each row's
  // real position in root.sections (originalIndex) rather than the
  // filtered array's own position, same reasoning as that file's own
  // comment: openIndex should always point into the full list
  // underneath, so a since-filtered-out opened category stays correct
  // (just not visible in the list right now) instead of pointing at
  // the wrong section entirely.
  readonly property var filteredSections: {
    var q = root.searchText.trim().toLowerCase()
    var out = []
    for (var i = 0; i < root.sections.length; i++) {
      var s = root.sections[i]
      if (q.length === 0 || s.label.toLowerCase().includes(q))
        out.push({ id: s.id, label: s.label, glyph: s.glyph, originalIndex: i })
    }
    return out
  }

  // Each VISIBLE (filtered) section reshaped into the exact same
  // result-row object shape every other ResultsList model in this
  // plugin already uses (id/providerId/icon/label/breadcrumb/kind/
  // providerName/score/sectionLabel) -- ResultRow itself never needs to
  // know these came from Settings rather than a real provider.
  // providerId "settings-category" isn't dispatched anywhere (this
  // list's own onRowActivated below handles activation directly, the
  // same way Launcher.qml's resultsList does for real results), it's
  // just kept for shape-consistency/future-proofing.
  readonly property var sectionRows: {
    var rows = []
    for (var i = 0; i < root.filteredSections.length; i++) {
      var s = root.filteredSections[i]
      rows.push({
        id: "settings:" + s.id,
        providerId: "settings-category",
        icon: s.glyph,
        label: s.label,
        breadcrumb: "",
        kind: "",
        providerName: "",
        score: 0,
        sectionLabel: "Categories"
      })
    }
    return rows
  }

  // Keyboard cursor over the left list -- indexes into filteredSections
  // (the CURRENT visible list), not root.sections, same distinction
  // ruixen.settings' own sidebarFocusIndex draws. Up/Down move this; it
  // does NOT by itself change what the right panel shows (see openIndex
  // below), matching the user's own "then enter to go into the right
  // panel" phrasing rather than a live-preview-on-hover model.
  property int selectedIndex: 0
  // Index into root.sections (the FULL list, unaffected by filtering).
  // -1 means the right panel shows its own neutral empty state (kept
  // as a fallback, e.g. an out-of-range value); in practice this
  // starts on Profile (0) -- direct request: "we can land in the
  // profile page" -- and Enter/a real row click move it from there,
  // matching ResultsList's own rowActivated meaning everywhere else
  // it's used.
  property int openIndex: 0

  function moveSelectionUp() {
    if (root.selectedIndex > 0) root.selectedIndex--
  }
  function moveSelectionDown() {
    if (root.selectedIndex < root.filteredSections.length - 1) root.selectedIndex++
  }
  function activateSelection() {
    if (root.selectedIndex < root.filteredSections.length)
      root.openIndex = root.filteredSections[root.selectedIndex].originalIndex
  }

  // Fresh cursor on every new query, same as every other search
  // surface in this plugin (onQueryChanged/onFilesModeChanged) -- a
  // stale selectedIndex from before a keystroke could otherwise land
  // past the end of a now-shorter filtered list, or highlight a
  // visually different row than the one that was actually highlighted
  // a moment ago.
  onSearchTextChanged: root.selectedIndex = 0

  // Fresh state every time the extension is (re)entered -- same
  // "no stale cursor from last time" convention onFilesModeChanged/
  // onOpenedChanged already apply elsewhere in this plugin.
  onActiveChanged: {
    if (root.active) {
      root.selectedIndex = 0
      root.openIndex = 0
      // Same "fetch once" gate ruixen.settings' own onOpenedChanged
      // uses -- fastfetch is not free enough to re-run every time this
      // extension is (re)entered.
      if (root.hardwareName === "") identityProc.running = true
    }
  }

  ExtensionTwoPanel {
    id: panel
    anchors.fill: parent
  }

  // Reparented into panel's own left slot (see ExtensionTwoPanel.qml's
  // own header comment for why a slot Item + `parent:` beats a Loader/
  // Component here) -- every binding below is a plain, direct binding
  // off this file's own root, exactly like Launcher.qml's real
  // resultsList instantiation.
  ResultsList {
    parent: panel.leftPane
    anchors.fill: parent
    model: root.sectionRows
    // Icon+label only, no meta/kind/keybind columns -- the exact same
    // reduced row Search Files itself renders through this same flag,
    // which is the whole point: this isn't a look-alike, it's the same
    // component in the same mode.
    filesMode: true
    selectedIndex: root.selectedIndex
    textColor: root.textColor
    mutedColor: root.muted
    accentColor: root.accent
    fontFamily: root.fontFamily
    onRowHovered: (idx) => { root.selectedIndex = idx }
    onRowActivated: (idx) => {
      root.selectedIndex = idx
      if (idx < root.filteredSections.length)
        root.openIndex = root.filteredSections[idx].originalIndex
    }
  }

  // Same "typo'd query, empty sidebar" edge case ruixen.settings' own
  // empty state covers -- 8 rows is rare to filter down to nothing,
  // but not impossible.
  Text {
    parent: panel.leftPane
    anchors.centerIn: parent
    width: parent.width - 16
    visible: root.filteredSections.length === 0
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    text: "No matches"
    font.family: root.fontFamily
    font.pixelSize: 11
    color: root.muted
  }

  // Fallback only -- openIndex starts on Profile (0) now and every
  // activation/click keeps it in range, so this shouldn't normally be
  // reachable, but it's cheap insurance against an out-of-range value
  // rather than rendering nothing at all.
  Column {
    parent: panel.rightPane
    anchors.centerIn: parent
    spacing: 6
    visible: root.openIndex < 0 || root.openIndex >= root.sections.length

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: ""
      font.family: root.fontFamily
      font.pixelSize: 22
      color: root.muted
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Select a category and press Enter"
      font.family: root.fontFamily
      font.pixelSize: 12
      color: root.muted
    }
  }

  // True while Profile specifically is open -- checked by id, not the
  // bare index 0, so this stays correct even if sections' own order
  // ever changes.
  readonly property bool profileOpen: root.openIndex >= 0
    && root.openIndex < root.sections.length
    && root.sections[root.openIndex].id === "general"

  // Every category's right-panel content, Profile included, starts
  // with this same header (its own label) + short description -- a
  // plain layout convention every future real panel keeps building on
  // top of, not a separate component of its own (there's nothing else
  // here yet to warrant one). Direct correction: Profile's own real
  // content (below) had quietly REPLACED this instead of sitting under
  // it -- "why did you nuke the Profile and description subtitle we
  // had above it? keep it there please".
  //
  // 20/20/20 inset (top/left/right) -- direct report: "the header are
  // too close to the seperator" (this pane's own left edge sits right
  // against ExtensionTwoPanel's divider, and the previous version had
  // no top/left inset at all).
  Column {
    id: headerColumn
    parent: panel.rightPane
    anchors.top: parent.top
    anchors.topMargin: 20
    anchors.left: parent.left
    anchors.leftMargin: 20
    anchors.right: parent.right
    anchors.rightMargin: 20
    spacing: 6
    visible: root.openIndex >= 0 && root.openIndex < root.sections.length

    Text {
      width: parent.width
      text: root.openIndex >= 0 && root.openIndex < root.sections.length
        ? root.sections[root.openIndex].label : ""
      font.family: root.fontFamily
      font.pixelSize: 16
      font.weight: Font.DemiBold
      color: root.textColor
    }
    Text {
      width: parent.width
      text: root.openIndex >= 0 && root.openIndex < root.sections.length
        ? root.sections[root.openIndex].description : ""
      wrapMode: Text.WordWrap
      lineHeight: 1.3
      font.family: root.fontFamily
      font.pixelSize: 12
      color: root.muted
    }
  }

  // Profile's own real content -- centered avatar + username@machine,
  // then the DiceBear collection picker -- ported from ruixen.settings/
  // GeneralContent.qml's own avatar card (see this file's header
  // comment). Sits BELOW headerColumn (its "Profile" label + subtitle
  // stay in place), not instead of it. No card background/border here
  // (unlike the real app's own black card) -- this pane is already the
  // ghost/ContentPage treatment every extension's right side uses, a
  // second nested card would be a surface-on-a-surface with nothing to
  // visually separate.
  Column {
    parent: panel.rightPane
    anchors.top: headerColumn.bottom
    anchors.topMargin: 16
    anchors.left: parent.left
    anchors.leftMargin: 20
    anchors.right: parent.right
    anchors.rightMargin: 20
    spacing: 12
    visible: root.profileOpen

    // Each individual setting gets its OWN plain, descriptive label --
    // no separate subtitle underneath it -- direct correction: "it
    // looks a bit wierd without a header... for this first setting
    // option we can put Select Profile Picture. i dont think these
    // options need subtitle if we make the option... kind a
    // descriptive? itll be good for searching for them later too."
    // This is the per-ITEM label (distinct from headerColumn's own
    // per-PAGE "Profile" title above); every future real setting in
    // any category follows this same one-line, self-descriptive
    // convention rather than a title+subtitle pair.
    Text {
      text: "Select Profile Picture"
      font.family: root.fontFamily
      font.pixelSize: 12
      font.weight: Font.DemiBold
      color: root.textColor
    }

    Item {
      anchors.horizontalCenter: parent.horizontalCenter
      width: 64
      height: 64

      // Circular gradient fallback -- explicitly hidden once a real
      // image is loaded (not just painted over by an assumed-opaque
      // one), so nothing is left behind for any load-state edge case
      // to reveal.
      Rectangle {
        anchors.fill: parent
        radius: width / 2
        visible: avatarPreviewImage.status !== Image.Ready
        gradient: Gradient {
          GradientStop { position: 0.0; color: Qt.lighter(root.accent, 1.6) }
          GradientStop { position: 1.0; color: Qt.darker(root.accent, 1.4) }
        }
      }

      // "#" cache-bust fragment, not "?" -- Qt's local file:// loader
      // can try to resolve a "?"-suffixed string as a literal filename
      // instead of stripping it, unlike an HTTP server. A URL fragment
      // is always stripped before path resolution, busting the Image's
      // own source-string cache (needed since a new avatar overwrites
      // the exact same path) without that risk.
      Image {
        id: avatarPreviewImage
        anchors.fill: parent
        source: "file://" + Quickshell.env("HOME") + "/.face.icon#" + root.avatarCacheBust
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        visible: false
      }

      Rectangle {
        id: avatarPreviewMask
        anchors.fill: parent
        radius: width * 0.2
        color: "#ffffff"
        visible: false
        layer.enabled: true
      }

      MultiEffect {
        anchors.fill: parent
        source: avatarPreviewImage
        maskEnabled: true
        maskSource: avatarPreviewMask
        maskThresholdMin: 0.5
        maskThresholdMax: 1.0
      }
    }

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: Quickshell.env("USER") + "@" + root.hardwareName
      font.family: root.fontFamily
      font.pixelSize: 11
      color: root.muted
    }

    // Selecting one both picks it (highlighted border) AND immediately
    // applies it -- no separate "pick then press an action button"
    // step, same as the real picker. Flow, not a Row -- 9 labels don't
    // reliably fit one line at this panel's width.
    Flow {
      width: parent.width
      spacing: 6

      Repeater {
        model: root.avatarCollections

        Rectangle {
          id: collectionBtn
          required property var modelData
          readonly property bool isCurrent: root.avatarCollection === collectionBtn.modelData.id

          width: collectionLabel.implicitWidth + 16
          height: 24
          radius: 6
          color: collectionBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
          border.width: 1
          border.color: collectionBtn.isCurrent ? root.accent : Qt.rgba(1, 1, 1, 0.12)
          opacity: root.avatarBusy ? 0.5 : 1

          Text {
            id: collectionLabel
            anchors.centerIn: parent
            text: collectionBtn.modelData.label
            font.family: root.fontFamily
            font.pixelSize: 10
            font.weight: collectionBtn.isCurrent ? Font.DemiBold : Font.Normal
            color: collectionBtn.isCurrent ? root.textColor : root.muted
          }

          MouseArea {
            anchors.fill: parent
            enabled: !root.avatarBusy
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectAvatar(collectionBtn.modelData.id)
          }
        }
      }
    }
  }
}
