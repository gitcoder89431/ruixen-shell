import QtQuick
import QtQuick.Effects

// Issue #62: a compact, keyboard-first contextual action list for the
// currently selected Search Files result -- opened via Tab (see
// SearchHeader.qml's own tabPressed signal and Launcher.qml's
// openActionsMenu()), navigated with the same Up/Down/Enter/Escape keys
// the main results list already uses (Launcher.qml redirects them here
// while this menu is open, rather than this component owning its own
// separate key handling). Purely presentational, same convention as
// every other component from the #57 split -- Launcher.qml owns
// `actions`/`selectedIndex`, this just renders them.
//
// Visually modeled on Launcher.qml's own inline sourceFilterList
// (same glass-popup treatment, same shadow fix for Hyprland's
// ignore_alpha layer_rule threshold) so a second, differently-styled
// popup doesn't appear in the same card.
Rectangle {
  id: root

  property var actions: []
  property int selectedIndex: 0
  property color textColor: "#ffffff"
  property color accentColor: "#ffffff"
  property color glassTint: "#000000"
  property color glassBorder: "#ffffff"
  property string fontFamily: ""

  signal actionHovered(int index)
  signal actionActivated(string id)

  visible: root.actions.length > 0
  width: 240
  height: root.actions.length * 28 + 8
  radius: 10
  // Fully solid, not just "near-opaque" like sourceFilterList's own
  // 0.95 -- confirmed live that even 0.98 still let real result-row
  // text visibly bleed through once this menu started opening directly
  // over busy rows (a later follow-up to this issue) instead of the
  // near-empty space below the search bar sourceFilterList itself
  // always opens over. This is a functional context menu, not a
  // stylistic glass surface -- there's no real reason for it to stay
  // translucent at all once it's reliably sitting on top of dense
  // content.
  color: Qt.rgba(root.glassTint.r, root.glassTint.g, root.glassTint.b, 1.0)
  border.width: 1
  border.color: root.glassBorder
  z: 100

  layer.enabled: true
  layer.effect: MultiEffect {
    shadowEnabled: true
    shadowColor: "#000000"
    // Same fix as the card's own shadow / sourceFilterList's own --
    // this shadow's semi-transparent falloff would otherwise cross the
    // layer_rule's own ignore_alpha threshold (0.4) and get blurred a
    // second time on top of its own already-soft edge.
    shadowOpacity: 0.3
    shadowBlur: 0.4
    shadowVerticalOffset: 3
  }

  Column {
    anchors.fill: parent
    anchors.margins: 4

    Repeater {
      model: root.actions

      delegate: Rectangle {
        id: actionRow
        required property var modelData
        required property int index
        width: root.width - 8
        height: 28
        radius: 5
        color: actionRow.index === root.selectedIndex ? Qt.rgba(root.accentColor.r, root.accentColor.g, root.accentColor.b, 0.14) : "transparent"

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 10
          anchors.right: parent.right
          anchors.rightMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          elide: Text.ElideRight
          text: actionRow.modelData.label
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 12
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onEntered: root.actionHovered(actionRow.index)
          onClicked: root.actionActivated(actionRow.modelData.id)
        }
      }
    }
  }
}
