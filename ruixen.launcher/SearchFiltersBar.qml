import QtQuick

// Issue #60: a slim, keyboard-free filter row for Search Files -- Type
// (file category), Search scope (Names/Contents/Both), and a Hidden-
// files toggle. Visible only in Search Files mode; collapses to zero
// height (not just hidden) outside it so the normal Applications/
// Commands view's own layout is completely unaffected -- see
// Launcher.qml's own instantiation for how resultsList/detailsPanel
// anchor off this component's bottom edge unconditionally.
//
// Type deliberately cycles on click rather than opening a dropdown
// popup -- avoids the exact z-stacking trap SearchHeader.qml's own
// header comment documents for the source-filter popup (nesting a
// popup here would force elevating this WHOLE row's z to outrank
// resultsList/detailsPanel, which would let ITS OTHER controls swallow
// clicks meant for an outside-click-to-close catcher). A handful of
// categories cycling forward on repeated clicks is a fully adequate,
// much simpler interaction for this few options.
Item {
  id: root

  property bool active: false
  property string categoryFilter: "All"
  property string searchScope: "both"
  property bool hiddenEnabled: false
  property color textColor: "#ffffff"
  property color mutedColor: "#888888"
  property color accentColor: "#ffffff"
  property string fontFamily: ""

  signal categorySelected(string category)
  signal scopeSelected(string scope)
  signal hiddenToggled()

  readonly property var categoryNames: ["All", "Folders", "Documents", "Images", "Video", "Audio", "Archives", "Code/Text"]

  function cycleCategory() {
    var idx = root.categoryNames.indexOf(root.categoryFilter)
    var next = root.categoryNames[(idx + 1) % root.categoryNames.length]
    root.categorySelected(next)
  }

  anchors.left: parent.left
  anchors.right: parent.right
  anchors.leftMargin: 8
  anchors.rightMargin: 8
  height: root.active ? 32 : 0
  clip: true

  Row {
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    spacing: 6
    visible: root.active

    Rectangle {
      id: categoryButton
      width: Math.max(76, categoryLabel.implicitWidth + 20)
      height: 24
      radius: 6
      color: Qt.rgba(1, 1, 1, 0.06)
      border.width: 1
      border.color: Qt.rgba(1, 1, 1, 0.12)

      Text {
        id: categoryLabel
        anchors.centerIn: parent
        text: "Type: " + root.categoryFilter
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 11
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.cycleCategory()
      }
    }

    Row {
      spacing: 2

      Repeater {
        model: [{ id: "both", label: "Both" }, { id: "names", label: "Names" }, { id: "contents", label: "Contents" }]

        delegate: Rectangle {
          id: scopeButton
          required property var modelData
          readonly property bool isActive: root.searchScope === scopeButton.modelData.id
          width: scopeLabel.implicitWidth + 16
          height: 24
          radius: 6
          color: scopeButton.isActive ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) : Qt.rgba(1, 1, 1, 0.06)
          border.width: 1
          border.color: scopeButton.isActive ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45) : Qt.rgba(1, 1, 1, 0.12)

          Text {
            id: scopeLabel
            anchors.centerIn: parent
            text: scopeButton.modelData.label
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 11
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.scopeSelected(scopeButton.modelData.id)
          }
        }
      }
    }

    Rectangle {
      width: hiddenLabel.implicitWidth + 16
      height: 24
      radius: 6
      color: root.hiddenEnabled ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.18) : Qt.rgba(1, 1, 1, 0.06)
      border.width: 1
      border.color: root.hiddenEnabled ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.45) : Qt.rgba(1, 1, 1, 0.12)

      Text {
        id: hiddenLabel
        anchors.centerIn: parent
        text: "Hidden"
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 11
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.hiddenToggled()
      }
    }
  }
}
