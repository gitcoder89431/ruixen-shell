import QtQuick

Rectangle {
  id: root

  property string label: ""
  property string icon: ""
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  signal clicked()

  width: Math.max(76, content.implicitWidth + 22)
  height: 30
  radius: 9
  color: area.containsMouse ? root.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
  border.width: 1
  border.color: area.containsMouse ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.65) : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.1)

  Row {
    id: content
    anchors.centerIn: parent
    spacing: 7

    Text {
      text: root.icon
      color: area.containsMouse ? "#050505" : root.accent
      font.family: root.fontFamily
      font.pixelSize: 12
    }

    Text {
      text: root.label
      color: area.containsMouse ? "#050505" : root.textColor
      font.family: root.fontFamily
      font.pixelSize: 11
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
