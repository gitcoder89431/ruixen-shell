import QtQuick

// Layout-only shell for the "Settings" extension -- direct request:
// "lets do the Settings as Extension so Settings 2nd Column Ruixen and
// type extension? itll be similar to the 2 panel layout where we have
// the Profile Launcher Bluetooth menu options on the left panel, then
// enter to go into the right panel where we have toggles and inputs
// and options. dont build out the whole thing yet... just start with
// the layout first then we can work on the panels?" -- deliberately
// navigation + chrome only: a left category list and a right panel
// that shows only a "coming soon" placeholder once a category is
// opened. No toggles/inputs/real per-section content yet -- that's
// explicit later work.
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

  // Same 8 sections, same ids/labels/glyphs as ruixen.settings/
  // Settings.qml's own root.sections -- confirmed by reading that file
  // directly, not guessed, so this list reads as the same feature, not
  // a fork of it. Glyph codepoints copied byte-for-byte from there too.
  readonly property var sections: [
    { id: "general", label: "Profile", glyph: "" },
    { id: "launcher", label: "Launcher", glyph: "" },
    { id: "audio", label: "Audio", glyph: "" },
    { id: "wifi", label: "Wi-Fi", glyph: "" },
    { id: "bluetooth", label: "Bluetooth", glyph: "" },
    { id: "display", label: "Display", glyph: "" },
    { id: "plugins", label: "Plugins", glyph: "" },
    { id: "about", label: "About", glyph: "" }
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
  // Index into root.sections (the FULL list, unaffected by filtering)
  // -- -1 means the right panel shows its own neutral empty state (no
  // category opened yet this session). Set by activateSelection()
  // (Enter) or a real row click, matching ResultsList's own
  // rowActivated meaning everywhere else it's used.
  property int openIndex: -1

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
      root.openIndex = -1
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

  Item {
    parent: panel.rightPane
    anchors.fill: parent

    Column {
      anchors.centerIn: parent
      spacing: 6
      visible: root.openIndex === -1

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

    Column {
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: 4
      visible: root.openIndex >= 0

      Text {
        text: root.openIndex >= 0 ? root.sections[root.openIndex].label : ""
        font.family: root.fontFamily
        font.pixelSize: 15
        font.weight: Font.DemiBold
        color: root.textColor
      }
      Text {
        text: "Coming soon"
        font.family: root.fontFamily
        font.pixelSize: 12
        color: root.muted
      }
    }
  }
}
