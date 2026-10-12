import QtQuick
import QtQuick.Controls as Controls

Controls.Slider {
  id: root
  property color accent: "#3ecf5b"
  property color textColor: "white"
  implicitHeight: 26
  leftPadding: 7; rightPadding: 7
  opacity: enabled ? 1 : 0.4
  background: Rectangle {
    x: root.leftPadding
    y: (root.height - height) / 2
    width: root.availableWidth
    height: 4
    radius: 2
    color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)
    Rectangle { width: root.visualPosition * parent.width; height: parent.height; radius: 2; color: root.accent }
  }
  handle: Rectangle {
    x: root.leftPadding + root.visualPosition * (root.availableWidth - width)
    y: (root.height - height) / 2
    width: 12; height: 12; radius: 6
    color: root.accent
    border.width: root.activeFocus ? 2 : 0
    border.color: root.textColor
  }
}
