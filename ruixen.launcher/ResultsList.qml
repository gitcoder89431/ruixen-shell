import QtQuick

// Issue #57: extracted from Launcher.qml verbatim. This component's
// root IS the ListView itself (not a wrapper Item around one) so a
// Launcher.qml instance (`ResultsList { id: resultsList }`) keeps every
// built-in ListView method/anchor line callers already relied on --
// positionViewAtIndex()/positionViewAtBeginning() (used by
// onSelectedIndexChanged's scrolloff logic and onQueryChanged) and
// implicit anchor lines like resultsList.right (used by
// FileDetailsPanel's own left edge and the separator line between
// them) all keep working exactly as before, unchanged.
//
// A real ListView, not a Column+Repeater -- once Commands lists every
// actionable entry (not just a handful), the row count can run into
// the hundreds, so this needs actual virtualization (only visible
// delegates exist) and real scrolling, not a clip:true Column that
// silently truncated. section.property groups by each row's own
// sectionLabel (set in Launcher.qml's own results) and draws its own
// header, so there's no manual nesting to keep selection math in sync
// with -- ResultRow's own `index` is already the same flat index as
// selectedIndex.
ListView {
  id: root

  property string fontFamily: ""
  property color mutedColor: "#888888"
  property color textColor: "#ffffff"
  property color accentColor: "#ffffff"
  property bool filesMode: false
  property int selectedIndex: 0
  property int rowHeightPx: 44
  property int sectionHeaderHeight: 26
  property var appLibrary: null

  // Bubbled straight from each ResultRow -- Launcher.qml owns
  // selectedIndex and activateSelected(), this list has no state of
  // its own beyond scroll position.
  signal rowHovered(int index)
  signal rowActivated(int index)

  clip: true
  spacing: 0
  // Same fix as ruixen.settings' own detail panel Flickable /
  // DashboardContent.qml's notification ListView -- no overscroll
  // bounce.
  boundsBehavior: Flickable.StopAtBounds

  section.property: "sectionLabel"
  section.criteria: ViewSection.FullString
  section.delegate: Item {
    width: root.width
    height: root.sectionHeaderHeight

    Text {
      anchors.left: parent.left
      anchors.leftMargin: 4
      anchors.verticalCenter: parent.verticalCenter
      text: section
      color: root.mutedColor
      font.family: root.fontFamily
      font.pixelSize: 10
      font.capitalization: Font.AllUppercase
      font.bold: true
    }
  }

  delegate: ResultRow {
    rowWidth: root.width
    rowHeightPx: root.rowHeightPx
    selectedIndex: root.selectedIndex
    filesMode: root.filesMode
    textColor: root.textColor
    mutedColor: root.mutedColor
    accentColor: root.accentColor
    fontFamily: root.fontFamily
    appLibrary: root.appLibrary
    onHovered: (idx) => root.rowHovered(idx)
    onActivated: (idx) => root.rowActivated(idx)
  }
}
