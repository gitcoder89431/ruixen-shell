import QtQuick

// Issue #57: extracted from Launcher.qml's own `searchBox` Rectangle
// verbatim -- the collapsed search bar only (icon/back-arrow, text
// input, the source-filter button's CLOSED control, the Enter-hint
// chip). The actual dropdown POPUP (sourceFilterList) and its outside-
// click-to-close handler deliberately stay inline in Launcher.qml
// instead of nesting here: they need to remain true siblings of
// resultsList/detailsPanel within `card`'s own z-stack (the popup's own
// z:100 has to outrank those two, and the outside-click catcher's z:50
// has to sit BELOW this search bar's own default z but ABOVE them) --
// nesting the popup inside this component would force elevating this
// WHOLE component's z to make the nested popup outrank resultsList/
// detailsPanel, which would also let this search bar itself intercept
// clicks the outside-click MouseArea is supposed to catch first while
// the dropdown is open (confirmed by working through Qt Quick's own
// z-stacking rules before writing this: z only orders siblings sharing
// one immediate parent, so a nested child can't outrank its own
// parent's siblings without the parent itself being elevated). Keeping
// the popup external avoids that regression entirely.
Item {
  id: root

  property bool filesMode: false
  property int resultCount: 0
  property string selectedSourcePath: ""
  property var sources: []
  property int sourceFilterWidth: 150
  // Two-way from the caller's perspective: this component's own
  // sourceFilterButton toggles it; Launcher.qml's externally-owned
  // popup and outside-click catcher both read/clear it too, so both
  // sides always agree on open/closed state.
  property bool dropdownOpen: false

  property color textColor: "#ffffff"
  property color mutedColor: "#888888"
  property string fontFamily: ""

  // Two-way: Launcher.qml clears this on close (`searchHeader.text =
  // ""`); typing here bubbles out via the auto-generated onTextChanged
  // alias signal, same as any other property.
  property alias text: searchInput.text

  signal upPressed()
  signal downPressed()
  signal enterPressed()
  // Fired only once this component's OWN dropdown is already closed --
  // Escape's first priority (closing an open dropdown) is handled
  // entirely internally, since Launcher.qml has no reason to know
  // about that transient state.
  signal escapePressed()
  signal backClicked()

  function focusInput() { searchInput.forceActiveFocus() }

  anchors.top: parent.top
  anchors.left: parent.left
  anchors.right: parent.right
  anchors.margins: 8
  height: 48

  // fa-search (U+F002), same glyph as the Search Files fallback row's
  // own icon. Positioned with the exact same leftMargin/width/
  // centering as a result row's own icon Text (ResultRow.qml) --
  // this search bar and resultsList share the same leftMargin (8) off
  // the card, and a ListView delegate's own x is that view's x with no
  // further offset, so matching leftMargin+width here lines this
  // glyph's column up with every row's icon column exactly, not just
  // approximately.
  Text {
    id: searchIcon
    anchors.left: parent.left
    anchors.leftMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    width: 22
    horizontalAlignment: Text.AlignHCenter
    // fa-search (U+F002) normally; swaps to fa-arrow-left (U+F060) in
    // Search Files mode, doubling as a real back button -- direct
    // request: clicking it there exits Search Files, same as Escape's
    // own first step, rather than dismissing the whole palette.
    text: root.filesMode ? "" : ""
    color: root.mutedColor
    font.family: root.fontFamily
    font.pixelSize: 16

    MouseArea {
      anchors.fill: parent
      anchors.margins: -4
      // Only interactive in Search Files mode -- there is nothing to
      // "go back" from otherwise, so the plain magnifying glass stays
      // decorative the rest of the time.
      enabled: root.filesMode
      cursorShape: root.filesMode ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: root.backClicked()
    }
  }

  // Search Files only -- filters fd's own search roots to just one
  // drive. Meaningless outside Search Files (Applications/Commands
  // have no "drive"), so hidden the rest of the time -- TextInput's
  // own rightMargin below only makes room for it while it's visible.
  // Ghost trigger, not a nested pill -- no background surface of its
  // own (a faint hover/open tint is the only visual affordance), so it
  // reads as part of the search input rather than a separate control
  // sitting on top of it. Fixed width shared with the popup (set by
  // Launcher.qml to the same sourceFilterWidth) so the closed control
  // and the opened menu share one width -- reads as a single dropdown
  // widget rather than a button with a mismatched panel. No hover tint
  // -- the chevron itself flipping to point up is the only "open"
  // affordance needed.
  Item {
    id: sourceFilterButton
    visible: root.filesMode
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    width: root.sourceFilterWidth
    height: 28

    readonly property string currentLabel: root.selectedSourcePath === "" ? "All Sources" : (function() {
      for (var i = 0; i < root.sources.length; i++) if (root.sources[i].path === root.selectedSourcePath) return root.sources[i].label
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

    // fa-chevron-down (U+F078) -- rotates to point up while the menu
    // is open, same convention as a native <select>.
    Text {
      id: sourceFilterChevron
      anchors.right: parent.right
      anchors.rightMargin: 10
      anchors.verticalCenter: parent.verticalCenter
      text: ""
      color: root.mutedColor
      font.family: root.fontFamily
      font.pixelSize: 9
      rotation: root.dropdownOpen ? 180 : 0
      transformOrigin: Item.Center
      Behavior on rotation { NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }
    }

    MouseArea {
      anchors.fill: parent
      onClicked: root.dropdownOpen = !root.dropdownOpen
    }
  }

  // Keyboard hint for the primary action -- direct request: "this
  // space is empty... make it kbd good". Styled like an actual
  // physical key cap (bordered chip, not just bare text) so it reads
  // as "press this key" at a glance, same convention every real
  // Raycast-style launcher uses for its own primary-action hint. Only
  // where sourceFilterButton isn't already occupying this same right-
  // aligned spot (Search Files mode), and only when there's actually
  // something Enter would do -- an empty results list (no Suggestions,
  // no matches, nothing) has no primary action to hint at.
  Rectangle {
    visible: !root.filesMode && root.resultCount > 0
    anchors.right: parent.right
    anchors.rightMargin: 12
    anchors.verticalCenter: parent.verticalCenter
    width: 28
    height: 22
    radius: 6
    color: Qt.rgba(1, 1, 1, 0.06)
    border.width: 1
    border.color: Qt.rgba(1, 1, 1, 0.12)

    Text {
      anchors.centerIn: parent
      text: "↵"
      color: root.mutedColor
      font.family: root.fontFamily
      font.pixelSize: 13
    }
  }

  TextInput {
    id: searchInput
    anchors.fill: parent
    // searchIcon's own leftMargin (12) + width (22) + a 10px gap.
    anchors.leftMargin: 44
    // sourceFilterWidth + sourceFilterButton's own rightMargin (12) +
    // a small gap, only while it's actually showing; otherwise room
    // for the Enter-hint chip (28 wide + 12 rightMargin) once there's
    // a result for it to hint at, or the plain 16 default with neither
    // showing.
    anchors.rightMargin: root.filesMode ? (root.sourceFilterWidth + 12 + 10)
      : (root.resultCount > 0 ? (28 + 12 + 10) : 16)
    verticalAlignment: TextInput.AlignVCenter
    color: root.textColor
    font.family: root.fontFamily
    font.pixelSize: 16
    clip: true

    Text {
      anchors.verticalCenter: parent.verticalCenter
      text: root.filesMode ? "Search files..." : "Search actions and apps..."
      color: root.mutedColor
      font.family: root.fontFamily
      font.pixelSize: 16
      visible: searchInput.text.length === 0
    }

    // Same Escape/Up/Down/Enter shape LauncherContent.qml's own
    // launcherSearchInput already proves out -- Escape closes an open
    // dropdown first (handled entirely internally); Launcher.qml's own
    // onEscapePressed handles the rest of the original priority order
    // (drill out of Search Files, then dismiss).
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape) {
        if (root.dropdownOpen) root.dropdownOpen = false
        else root.escapePressed()
        event.accepted = true
      } else if (event.key === Qt.Key_Up) {
        root.upPressed()
        event.accepted = true
      } else if (event.key === Qt.Key_Down) {
        root.downPressed()
        event.accepted = true
      } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
        root.enterPressed()
        event.accepted = true
      }
    }
  }
}
