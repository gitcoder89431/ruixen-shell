import QtQuick
import QtQuick.Controls as Controls

Controls.CheckBox {
  id: root
  property color accent: "#3ecf5b"
  property color textColor: "white"
  implicitHeight: 30
  spacing: 8
  padding: 0
  font.family: "JetBrainsMono Nerd Font"
  font.pixelSize: 11
  opacity: enabled ? 1 : 0.4
  indicator: Rectangle {
    implicitWidth: 30; implicitHeight: 18
    x: root.leftPadding
    y: (root.height - height) / 2
    radius: 9
    color: root.checked ? root.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.15)
    border.width: root.activeFocus ? 1 : 0
    border.color: root.accent
    Rectangle {
      width: 12; height: 12; radius: 6
      x: root.checked ? parent.width - width - 3 : 3
      y: 3
      color: root.checked ? "#000000" : root.textColor
      Behavior on x { NumberAnimation { duration: 120 } }
    }
  }
  contentItem: Text {
    text: root.text
    font: root.font
    color: root.textColor
    leftPadding: root.indicator.width + root.spacing
    verticalAlignment: Text.AlignVCenter
  }
}
