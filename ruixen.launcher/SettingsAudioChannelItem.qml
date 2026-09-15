import QtQuick

// Shared "audio channel" card -- Output and Input are the exact same
// shape (mute icon + slider + percentage, then a selectable device
// list), only the underlying Pipewire node/property set differs. Same
// "extract once 2 real uses exist" reasoning as every other shared
// item in this file. Ported from ruixen.settings/AudioContent.qml,
// same real Quickshell.Services.Pipewire backend (see
// SettingsContent.qml's own comment) -- no repo-checkout dependency,
// no shell restart, standalone-safe by construction.
Rectangle {
  id: root

  property string label: ""
  property real volume: 0
  property bool channelMuted: false
  property var devices: []
  property var defaultDevice: null
  // Output uses the speaker glyphs, Input the microphone ones -- the
  // device-row icon is always the same as the unmuted glyph for that
  // channel type (confirmed directly against AudioContent.qml, not
  // guessed: both Output's device rows and its unmuted state use
  // U+F028, both Input's use U+F130).
  property string iconMuted: ""
  property string iconUnmuted: ""
  // Presentation stays free of Pipewire's own node-label cleanup logic
  // (nickname/description fallback + driver-name trimming) -- that's
  // real backend logic living on SettingsContent.qml's own root as
  // deviceLabel(), passed in here as a plain function reference, same
  // "activate" pattern every other item's data table already uses.
  property var labelFor: function(node) { return node ? String(node.name || "Unknown") : "Unknown" }
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"
  // Keyboard focus, direct follow-up: "wanna do the tab kbd now?" --
  // mute+slider is ONE combined keyboard item (Left/Right adjusts,
  // Enter toggles mute, like a real volume knob: turn to adjust, press
  // to mute) rather than two separate stops, and each device row is
  // its own selectable item. Both ring styles mirror
  // SettingsToggleRow.rowFocused -- a row-level ring, not a whole-card
  // one, since multiple focusable rows share this one card.
  property bool volumeFocused: false
  property int focusedDeviceIndex: -1

  // Exposed so SettingsContent.qml's own scrollToFocusedItem() can
  // find these nested rows -- ids aren't visible from outside this
  // file otherwise.
  property alias volumeRowItem: volumeRow
  function deviceRowAt(index) { return deviceRepeater.itemAt(index) }

  signal muteToggled()
  signal volumeAdjusted(real value)
  signal deviceSelected(var node)

  width: parent.width
  height: content.implicitHeight + 24
  radius: 10
  color: Qt.rgba(0, 0, 0, 0.18)

  Column {
    id: content
    anchors.fill: parent
    anchors.margins: 12
    spacing: 10

    Text {
      text: root.label
      font.family: root.fontFamily
      font.pixelSize: 12
      font.weight: Font.DemiBold
      color: root.textColor
    }

    Item {
      id: volumeRow
      width: parent.width
      height: 20

      Rectangle {
        visible: root.volumeFocused
        anchors.fill: parent
        anchors.margins: -4
        radius: 6
        color: "transparent"
        border.width: 1
        border.color: root.accent
      }

      Text {
        id: muteGlyph
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: root.channelMuted ? root.iconMuted : root.iconUnmuted
        font.family: root.fontFamily
        font.pixelSize: 15
        color: root.textColor

        MouseArea {
          anchors.fill: parent
          anchors.margins: -6
          cursorShape: Qt.PointingHandCursor
          onClicked: root.muteToggled()
        }
      }

      // Same track/fill/tip language as ruixen.notch's own sliders --
      // ported from AudioContent.qml's own slider verbatim (same
      // gapPx derivation and tip proportions).
      Rectangle {
        id: track
        anchors.left: muteGlyph.right
        anchors.leftMargin: 10
        anchors.right: percentLabel.left
        anchors.rightMargin: 10
        anchors.verticalCenter: parent.verticalCenter
        height: 6
        radius: 3
        color: "transparent"

        readonly property real value: Math.max(0, Math.min(1, root.volume))
        readonly property real valueX: width * value
        readonly property real gapPx: 7

        Rectangle {
          anchors.left: parent.left
          anchors.top: parent.top
          anchors.bottom: parent.bottom
          width: Math.max(0, parent.valueX - parent.gapPx)
          radius: 3
          color: root.channelMuted ? root.muted : root.accent
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
          onPressed: (mouse) => root.volumeAdjusted(mouse.x / width)
          onPositionChanged: (mouse) => { if (pressed) root.volumeAdjusted(mouse.x / width) }
          // Scroll to adjust -- 5% per notch, same clamp the
          // click/drag handlers above already apply.
          onWheel: (wheel) => root.volumeAdjusted(Math.max(0, Math.min(1, root.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
        }
      }

      Text {
        id: percentLabel
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        horizontalAlignment: Text.AlignRight
        text: Math.round(root.volume * 100) + "%"
        font.family: root.fontFamily
        font.pixelSize: 12
        color: root.muted
      }
    }

    Column {
      width: parent.width
      spacing: 4

      Repeater {
        id: deviceRepeater
        model: root.devices

        Rectangle {
          id: deviceRow
          required property var modelData
          required property int index
          readonly property bool isDefault: root.defaultDevice && deviceRow.modelData
            && root.defaultDevice.id === deviceRow.modelData.id

          width: parent.width
          height: 28
          radius: 8
          color: deviceRow.isDefault ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
          border.width: root.focusedDeviceIndex === deviceRow.index ? 1 : 0
          border.color: root.accent

          Item {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8

            Text {
              id: deviceIcon
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              text: root.iconUnmuted
              font.family: root.fontFamily
              font.pixelSize: 13
              color: deviceRow.isDefault ? root.accent : root.muted
            }

            Text {
              anchors.left: deviceIcon.right
              anchors.leftMargin: 8
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              text: root.labelFor(deviceRow.modelData)
              font.family: root.fontFamily
              font.pixelSize: 12
              font.weight: deviceRow.isDefault ? Font.DemiBold : Font.Normal
              color: deviceRow.isDefault ? root.textColor : root.muted
              elide: Text.ElideRight
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.deviceSelected(deviceRow.modelData)
          }
        }
      }
    }
  }
}
