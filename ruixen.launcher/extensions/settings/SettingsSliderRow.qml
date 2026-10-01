import QtQuick

// Shared "icon + slider + percentage" row -- Display's own Brightness
// card is the exact same shape Audio's own Output/Input volume rows
// already use, just with a plain glyph (no mute state to flip) and no
// device list underneath. Same "extract once a second/third real use
// exists" reasoning as every other shared item in this file -- kept
// deliberately simpler than SettingsAudioChannelItem's own slider
// (no muted-state color swap, no click-to-mute) rather than forcing
// this to take on audio-specific concepts it has no use for.
Item {
  id: root

  property string icon: ""
  // 0-1, same normalized range every slider in this plugin already
  // uses -- the caller (SettingsContent.qml) converts to/from whatever
  // real scale its own backend expects (Brightness is 0-100).
  property real value: 0
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"
  // Overrides the auto percent readout below -- Visualizer's own
  // Height slider shows a real pixel count ("160px"), not "58%", since
  // a raw fraction means nothing without knowing the underlying pixel
  // range. Empty (every existing caller -- Brightness) keeps the
  // original percent-of-0..1 behavior untouched.
  property string valueLabel: ""

  signal adjusted(real value)

  width: parent.width
  height: 20

  Text {
    id: iconGlyph
    anchors.left: parent.left
    anchors.verticalCenter: parent.verticalCenter
    text: root.icon
    font.family: root.fontFamily
    font.pixelSize: 15
    color: root.textColor
  }

  // Same track/fill/tip language as ruixen.notch's own sliders --
  // ported verbatim from SettingsAudioChannelItem.qml's own slider
  // (which itself already matches DisplayContent.qml's real one).
  Rectangle {
    id: track
    anchors.left: iconGlyph.right
    anchors.leftMargin: 10
    anchors.right: percentLabel.left
    anchors.rightMargin: 10
    anchors.verticalCenter: parent.verticalCenter
    height: 6
    radius: 3
    color: "transparent"

    readonly property real value: Math.max(0, Math.min(1, root.value))
    readonly property real valueX: width * value
    readonly property real gapPx: 7

    Rectangle {
      anchors.left: parent.left
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.max(0, parent.valueX - parent.gapPx)
      radius: 3
      color: root.accent
      Behavior on width { NumberAnimation { duration: 120 } }
    }

    Rectangle {
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.bottom: parent.bottom
      width: Math.max(0, parent.width - parent.valueX - parent.gapPx)
      radius: 3
      color: Qt.rgba(1, 1, 1, 0.1)
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      x: parent.valueX - width / 2
      width: 4
      height: parent.height + 8
      radius: 2
      color: "#ffffff"
      Behavior on x { NumberAnimation { duration: 120 } }
    }

    MouseArea {
      anchors.fill: parent
      anchors.topMargin: -8
      anchors.bottomMargin: -8
      onPressed: (mouse) => root.adjusted(mouse.x / width)
      onPositionChanged: (mouse) => { if (pressed) root.adjusted(mouse.x / width) }
      // Scroll to adjust -- 5% per notch, same clamp/step as every
      // other slider in this plugin.
      onWheel: (wheel) => root.adjusted(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
  }

  Text {
    id: percentLabel
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    width: root.valueLabel.length > 0 ? 48 : 32
    horizontalAlignment: Text.AlignRight
    text: root.valueLabel.length > 0 ? root.valueLabel : (Math.round(root.value * 100) + "%")
    font.family: root.fontFamily
    font.pixelSize: 12
    color: root.muted
  }
}
