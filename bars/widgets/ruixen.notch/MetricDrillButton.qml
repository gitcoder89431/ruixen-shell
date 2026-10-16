import QtQuick
import QtQuick.Controls

Button {
  id: root
  property string metricLabel: ""
  property color accent: "#8aadf4"
  Accessible.name: "Show " + metricLabel + " details"
  padding: 0
  background: Rectangle {
    radius: 10
    color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, root.hovered || root.activeFocus ? .08 : 0)
  }
  contentItem: Item {}
}
