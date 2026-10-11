import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls

Controls.AbstractButton {
  id: root
  hoverEnabled: true
  property string title: ""
  property string summary: ""
  property string glyph: ""
  property bool expanded: false
  property color accent: "#3ecf5b"
  property color textColor: "white"
  property color muted: "#999999"
  property string fontFamily: "JetBrainsMono Nerd Font"
  implicitHeight: 30
  Accessible.name: title + ", " + summary
  contentItem: RowLayout {
    spacing: 10
    Text { text: root.glyph; color: root.accent; font.family: root.fontFamily; font.pixelSize: 17 }
    Text { text: root.title; color: root.textColor; font.family: root.fontFamily; font.pixelSize: 12; font.weight: Font.DemiBold }
    Item { Layout.fillWidth: true }
    Text { text: root.summary; color: root.muted; font.family: root.fontFamily; font.pixelSize: 10; elide: Text.ElideRight; Layout.maximumWidth: 170 }
    Text { text: root.expanded ? "−" : "+"; color: root.hovered || root.activeFocus ? root.accent : root.muted; font.pixelSize: 18 }
  }
  background: Rectangle { radius: 8; color: "transparent"; border.width: root.activeFocus ? 1 : 0; border.color: root.accent }
}
