import QtQuick

// Shared "device row" item -- Paired Devices and Available Devices are
// the same row shape (dot + name + status glyph), with Available's own
// rows additionally able to expand into a "Confirm Pair" button. Same
// "extract once 2 real uses exist" reasoning as every other item in this
// file, and the same dot-not-icon convention SettingsWifiRow.qml/Audio's
// device rows already use. Ported from
// ruixen.settings/BluetoothContent.qml + Settings.qml's own real
// Quickshell.Bluetooth backend.
//
// Simpler than Wi-Fi's own row: no password field at all -- pairing a
// brand-new device just shells out to `bluetoothctl pair` (BlueZ's
// default "Just Works" agent covers the common case), confirmed by
// reading omarchy-bluetooth-device directly, not the PIN/passkey flow
// assumed previously.
Item {
  id: root

  property string name: ""
  property bool connected: false
  property bool known: false
  // Only meaningful when known -- distinguishes "genuinely paired" from
  // "merely trusted" (a real gap: omarchy-bluetooth-device's pair action
  // calls trust_device() unconditionally, win or lose).
  property bool pairedFormally: true
  property bool busy: false
  // Known + not connected only -- always shown (dim, brightens on
  // hover), NOT hover-gated the way Wi-Fi's own forget icon is: direct
  // decision on the real page ("No longer hover-gated: it used to swap
  // in over the Connect label on hover, meaning the exact thing you
  // were aiming at disappeared right as the cursor arrived").
  property bool showForget: false
  // Other Devices only -- first click arms the row (shows Confirm
  // Pair), a real confirmation step nearby-but-unrecognized Bluetooth
  // devices need that Wi-Fi's own known-network flow doesn't.
  property bool armed: false
  property bool rowFocused: false
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  // Row click -- connect/disconnect for a known device, arm/disarm for
  // an unknown one (root.toggleBtConnection decides which).
  signal activated()
  // Confirm Pair button click, armed unknown rows only.
  signal confirmPair()
  signal forgetRequested()

  width: parent.width
  height: content.implicitHeight + 16
  Behavior on height { NumberAnimation { duration: 120 } }
  clip: true

  Rectangle {
    anchors.fill: parent
    radius: 8
    color: root.connected || root.armed ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
  }

  Rectangle {
    visible: root.rowFocused
    anchors.fill: parent
    anchors.margins: -4
    radius: 8
    color: "transparent"
    border.width: 1
    border.color: root.accent
  }

  Column {
    id: content
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.margins: 8
    spacing: 6

    Item {
      id: mainRow
      width: parent.width
      height: 20

      Rectangle {
        id: dot
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 6
        radius: 3
        color: root.connected ? root.accent : root.muted
      }

      Text {
        id: nameLabel
        anchors.left: dot.right
        anchors.leftMargin: 10
        anchors.right: statusGlyph.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.name + (root.known && !root.connected && !root.pairedFormally ? "  (unpaired)" : "")
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: root.connected ? Font.DemiBold : Font.Normal
        color: root.connected ? root.textColor : root.muted
      }

      // Busy -> spinner (rotating). Known -> plug (click to connect) or
      // a red X hint (click to disconnect). Other/unknown -> link
      // (click to arm pairing) -- a different glyph from the plug per
      // direct follow-up ("the reconnect and pair with the plug looks
      // weird, maybe another one for pair so its not too many plugs").
      Item {
        id: statusGlyph
        // Its own slot to the LEFT of forget's, not the same anchor --
        // real bug hit live: both were separately anchored to
        // parent.right, so a paired-but-disconnected row (forget
        // eligible AND a plug/spinner both visible at once, forget no
        // longer hover-gated) rendered the two glyphs stacked directly
        // on top of each other. Forget still gets the rightmost slot
        // when eligible; this one just steps left of it instead of
        // sharing the same position.
        anchors.right: root.showForget ? forgetGlyph.left : parent.right
        anchors.rightMargin: root.showForget ? 8 : 0
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        height: statusGlyphText.implicitHeight

        Text {
          id: statusGlyphText
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          text: root.busy ? "" : (root.known ? (root.connected ? "" : "") : "")
          font.family: root.fontFamily
          font.pixelSize: root.known && root.connected && !root.busy ? 12 : 13
          color: root.known && root.connected && !root.busy ? "#e05252" : root.muted
          // rotation forced to 0 whenever not busy, not left bound
          // straight to a running RotationAnimation -- that never resets
          // rotation when it stops, so the glyph could land mid-spin
          // instead of upright.
          rotation: root.busy ? spinAngle : 0
          property real spinAngle: 0

          NumberAnimation on spinAngle {
            running: root.busy
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 900
          }
        }
      }

      // Forget -- always shown (dim) once eligible, not hover-gated;
      // same z-above-rowMouse fix SettingsWifiRow.qml's own comment
      // documents (a later sibling MouseArea would otherwise swallow
      // this click and re-trigger connect instead).
      Text {
        id: forgetGlyph
        z: 1
        visible: root.showForget
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 16
        horizontalAlignment: Text.AlignRight
        text: ""
        font.family: root.fontFamily
        font.pixelSize: 12
        color: forgetArea.containsMouse ? "#e05252" : root.muted

        MouseArea {
          id: forgetArea
          anchors.fill: parent
          anchors.margins: -4
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.forgetRequested()
        }
      }

      MouseArea {
        id: rowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.activated()
      }
    }

    // Real confirmation step -- a bare single click used to pair
    // immediately with no confirmation, and unlike Wi-Fi (picking a
    // network you already recognize as yours) a nearby Bluetooth device
    // can easily belong to someone else in a shared space.
    Column {
      width: parent.width
      visible: root.armed
      spacing: 6

      Rectangle {
        width: parent.width
        height: 32
        radius: 10
        color: confirmMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)

        Text {
          anchors.centerIn: parent
          text: "Confirm Pair"
          font.family: root.fontFamily
          font.pixelSize: 12
          font.weight: Font.DemiBold
          color: root.textColor
        }

        MouseArea {
          id: confirmMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.confirmPair()
        }
      }
    }
  }
}
