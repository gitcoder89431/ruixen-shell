import QtQuick

// Shared "segmented option" item card -- direct follow-up after Window
// Curvature/Window Spacing/Animation Style shipped as three nearly-
// identical hand-copied blocks (same framed dark-tonal card, same
// label, same row-of-N-buttons, differing only in label/options/
// current value/what gets called): "how do we keep this pattern
// going? easy to reuse". This is that one shared shape, extracted once
// three real uses already existed rather than guessed at speculatively
// -- Bar Layout (Floating/Docked) is the fourth.
//
// Deliberately doesn't own any keyboard-focus STATE itself (which item
// in some list is Tab-focused, which option the arrow-key cursor sits
// on) -- that coordination lives in SettingsContent.qml's own
// currentItems/focusedItemIndex/focusedOptionIndex, the same single
// source of truth every category's items read from. This component
// only takes the two resulting booleans/index (cardFocused,
// focusedOptionIndex) and draws them; it has no opinion on WHY they're
// set.
//
// Profile Picture (the avatar/DiceBear picker) stays its own bespoke
// Rectangle, not rebuilt on top of this -- it has real custom content
// (a live image preview, a username line) beyond "pick one of N
// labeled options," a genuinely different shape, not just a
// differently-labeled copy of this one.
Rectangle {
  id: root

  property string label: ""
  // [{ id, label }, ...]
  property var options: []
  property string current: ""
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"
  // Tab-focused card -- draws the same accent ring every item card
  // convention already uses.
  property bool cardFocused: false
  // Keyboard cursor position within `options` -- -1 means no option
  // has the cursor (card isn't the focused one right now).
  property int focusedOptionIndex: -1
  // Gates the buttons themselves (e.g. Window Curvature's own "needs a
  // repo checkout" case) -- true by default since most items have
  // nothing to gate.
  property bool optionsEnabled: true
  // Shown under the row only while optionsEnabled is false.
  property string disabledHint: ""

  signal activated(string id)

  width: parent.width
  height: content.implicitHeight + 24
  radius: 10
  color: Qt.rgba(0, 0, 0, 0.18)
  border.width: root.cardFocused ? 1 : 0
  border.color: root.accent

  Column {
    id: content
    anchors.fill: parent
    anchors.margins: 12
    spacing: 12

    Text {
      text: root.label
      font.family: root.fontFamily
      font.pixelSize: 12
      font.weight: Font.DemiBold
      color: root.textColor
    }

    Row {
      width: parent.width
      spacing: 6

      Repeater {
        model: root.options

        Rectangle {
          id: optBtn
          required property var modelData
          required property int index
          readonly property bool isCurrent: root.current === optBtn.modelData.id
          readonly property bool isFocused: root.focusedOptionIndex === optBtn.index

          // Divides evenly regardless of option count (2 for Sharp/
          // Rounded and Comfy/Tight, 3 for Calm/Bubbly/Snappy, or any
          // future count) -- the old per-item copies each hardcoded
          // their own /2 or /3.
          width: (parent.width - (root.options.length - 1) * parent.spacing) / root.options.length
          height: 28
          radius: 6
          color: optBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
          border.width: 1
          border.color: optBtn.isCurrent ? root.accent : Qt.rgba(1, 1, 1, 0.12)
          opacity: root.optionsEnabled ? 1 : 0.5

          Text {
            id: optLabel
            anchors.centerIn: parent
            text: optBtn.modelData.label
            font.family: root.fontFamily
            font.pixelSize: 11
            font.weight: optBtn.isCurrent ? Font.DemiBold : Font.Normal
            color: optBtn.isCurrent ? root.textColor : root.muted
          }

          // Accent-colored underline for the keyboard cursor -- a real
          // bar, not font.underline, so it stays clearly visible even
          // when the label itself is muted (focused but not current).
          Rectangle {
            visible: optBtn.isFocused
            anchors.top: optLabel.bottom
            anchors.horizontalCenter: optLabel.horizontalCenter
            width: optLabel.paintedWidth
            height: 1
            color: root.accent
          }

          MouseArea {
            anchors.fill: parent
            enabled: root.optionsEnabled
            cursorShape: Qt.PointingHandCursor
            onClicked: root.activated(optBtn.modelData.id)
          }
        }
      }
    }

    Text {
      visible: !root.optionsEnabled && root.disabledHint !== ""
      width: parent.width
      text: root.disabledHint
      wrapMode: Text.WordWrap
      font.family: root.fontFamily
      font.pixelSize: 10
      color: root.muted
    }
  }
}
