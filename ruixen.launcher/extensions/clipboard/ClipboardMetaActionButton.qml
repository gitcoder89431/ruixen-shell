import QtQuick

Rectangle {
  id: root

  property string label: ""
  property string icon: ""
  property bool danger: false
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property color dangerColor: "#e5484d"
  property string fontFamily: "JetBrainsMono Nerd Font"

  signal clicked()

  readonly property color tone: root.danger ? root.dangerColor : root.accent

  width: Math.max(34, content.implicitWidth + 14)
  height: 22
  radius: 7
  color: area.containsMouse ? Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.28)
    : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
  border.width: 1
  border.color: area.containsMouse ? Qt.rgba(root.tone.r, root.tone.g, root.tone.b, 0.62)
    : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.10)

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 5

    Text {
      text: root.icon
      color: root.tone
      font.family: root.fontFamily
      font.pixelSize: 10
    }

    Text {
      text: root.label
      color: root.textColor
      font.family: root.fontFamily
      font.pixelSize: 10
      font.bold: true
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }
}
