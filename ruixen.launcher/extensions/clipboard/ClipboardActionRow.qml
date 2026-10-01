import QtQuick

// One clickable row in the details panel's Actions group. Styled like the
// metadata rows above it (label left, value right) -- the right side
// carries the keyboard shortcut instead of a value.
Item {
  id: root

  property string label: ""
  property string icon: ""
  property string hint: ""
  property bool danger: false
  property bool striped: false
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property color dangerColor: "#e5484d"
  property string fontFamily: "JetBrainsMono Nerd Font"

  signal clicked()

  readonly property color tone: root.danger ? root.dangerColor : root.accent

  width: parent ? parent.width : 0
  height: 19

  Rectangle {
    anchors.fill: parent
    anchors.leftMargin: -10
    anchors.rightMargin: -10
    anchors.topMargin: -4
    anchors.bottomMargin: -4
    radius: 4
    color: area.containsMouse ? Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.22)
      : root.striped ? Qt.rgba(0, 0, 0, 0.18) : "transparent"
  }

  Text {
    id: iconText
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    width: 16
    text: root.icon
    color: root.tone
    font.family: root.fontFamily
    font.pixelSize: 12
  }

  Text {
    anchors.left: iconText.right
    anchors.leftMargin: 6
    anchors.verticalCenter: parent.verticalCenter
    text: root.label
    color: root.danger && area.containsMouse ? root.dangerColor : root.textColor
    font.family: root.fontFamily
    font.pixelSize: 13
  }

  Text {
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    text: root.hint
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: 11
  }

  MouseArea {
    id: area
    anchors.fill: parent
    anchors.margins: -4
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
