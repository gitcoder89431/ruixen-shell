import QtQuick

// Shared on/off toggle row -- same "extract once a second real use
// exists" reasoning SettingsSegmentedItem.qml's own header comment
// documents. Launcher Search needs two of these (Include Home,
// Auto-include Mounted Drives) side by side in one card, then a third
// shape (one row per discovered mount, path + an optional "not
// currently connected" subtitle) for the Mounted Drives checklist --
// `subtitle` covers that second shape without a second component. Same
// visual as ruixen.settings' own toggle switches (32x16 track, 12px
// knob), ported directly rather than redesigned.
//
// Deliberately just the ROW (label + switch), not a whole framed
// card like SettingsSegmentedItem -- the real Launcher page groups
// multiple toggles inside ONE shared card under one title, not one
// card per toggle, so the card itself stays the caller's own plain
// Rectangle, this is only what goes inside it.
Item {
  id: root

  property string label: ""
  // Empty (the common case) collapses back to the original single-
  // line row -- only the mount checklist's "Not currently connected"
  // case needs this.
  property string subtitle: ""
  property bool checked: false
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"
  // Path labels can run long -- elided rather than pushed under/behind
  // the switch. Plain short labels (Include Home, ...) never hit this.
  property bool elideLabel: false
  // Keyboard cursor on THIS row -- direct report: "the tab kbd stuff
  // not working on launcher setting". Unlike SettingsSegmentedItem's
  // own card-level ring, this row often shares a card with siblings
  // (Include Home + Auto-include Mounted Drives both live in one
  // card), so the ring needs to outline the ROW itself, not whatever
  // card happens to contain it.
  property bool rowFocused: false
  // Same "gate the control, dim it, let subtitle explain why" shape
  // SettingsSegmentedItem's own optionsEnabled/disabledHint pair
  // already uses -- direct request (Visualizer's own Enable row, when
  // cava isn't installed): "a new row? thats jumpy, on the enable or
  // visualer row then?" Named toggleEnabled, not enabled -- Item
  // already has a real, built-in `enabled` (it gates input handling
  // for the whole Item and its children), so redeclaring that name
  // would collide with it; optionsEnabled avoids the exact same
  // collision on the segmented item for the same reason.
  property bool toggleEnabled: true

  signal toggled(bool value)

  width: parent.width
  height: root.subtitle !== "" ? 28 : 20
  opacity: root.toggleEnabled ? 1 : 0.5

  Rectangle {
    visible: root.rowFocused
    anchors.fill: parent
    anchors.margins: -4
    radius: 6
    color: "transparent"
    border.width: 1
    border.color: root.accent
  }

  Column {
    anchors.left: parent.left
    anchors.right: track.left
    anchors.rightMargin: 8
    anchors.verticalCenter: parent.verticalCenter
    spacing: 1

    Text {
      width: parent.width
      text: root.label
      elide: root.elideLabel ? Text.ElideMiddle : Text.ElideNone
      font.family: root.fontFamily
      font.pixelSize: 12
      color: root.textColor
    }

    Text {
      visible: root.subtitle !== ""
      text: root.subtitle
      font.family: root.fontFamily
      font.pixelSize: 9
      color: root.muted
    }
  }

  Rectangle {
    id: track
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: 32
    height: 16
    radius: 8
    color: root.checked ? root.accent : Qt.rgba(1, 1, 1, 0.15)
    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
      width: 12
      height: 12
      radius: 6
      color: "#ffffff"
      anchors.verticalCenter: parent.verticalCenter
      x: root.checked ? parent.width - width - 2 : 2
      Behavior on x { NumberAnimation { duration: 120 } }
    }

    MouseArea {
      anchors.fill: parent
      enabled: root.toggleEnabled
      cursorShape: Qt.PointingHandCursor
      onClicked: root.toggled(!root.checked)
    }
  }
}
