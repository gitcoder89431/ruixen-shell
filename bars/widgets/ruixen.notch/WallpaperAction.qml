import QtQuick
import QtQuick.Controls as Controls

Controls.Button {
  id: root
  hoverEnabled: true
  property color accent: "#3ecf5b"
  property color textColor: "white"
  property bool selected: false
  property bool primary: false
  implicitHeight: 32
  leftPadding: 12; rightPadding: 12
  font.family: "JetBrainsMono Nerd Font"
  font.pixelSize: 11
  opacity: enabled ? 1 : 0.4
  contentItem: Text {
    text: root.text
    font: root.font
    color: root.primary ? "#000000" : root.textColor
    horizontalAlignment: Text.AlignHCenter
    verticalAlignment: Text.AlignVCenter
    elide: Text.ElideRight
  }
  background: Rectangle {
    radius: 9
    color: root.primary ? root.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, root.hovered || root.selected ? 0.10 : 0.05)
    border.width: root.selected || root.activeFocus ? 1 : 0
    border.color: root.accent
  }
}
