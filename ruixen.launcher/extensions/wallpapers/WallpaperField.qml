import QtQuick
import QtQuick.Controls as Controls

Controls.TextField {
  id: root
  property color accent: "#3ecf5b"
  property color textColor: "white"
  implicitHeight: 34
  leftPadding: 12; rightPadding: 12
  color: textColor
  font.family: "JetBrainsMono Nerd Font"
  font.pixelSize: 11
  selectByMouse: true
  selectedTextColor: "#000000"
  selectionColor: accent
  placeholderTextColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5)
  background: Rectangle {
    radius: 9
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
    border.width: root.activeFocus ? 1 : 0
    border.color: root.accent
  }
}
