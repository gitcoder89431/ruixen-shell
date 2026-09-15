import QtQuick

// Shared "network row" item -- Known Networks and Available Networks are
// the same row shape (dot + SSID + lock + signal%), with Available's own
// rows additionally able to expand in place for a password field on an
// unknown secured network. One component covers both, same "extract once
// 2 real uses exist" reasoning as every other item in this file. Ported
// from ruixen.settings/WifiContent.qml's own wifiRow/otherRow, with the
// dot standing in for its connected-glyph -- direct follow-up carried
// over from Audio's own device rows: "dont use the icon, just do a dot
// icon to show the active one in accent".
//
// Root (SettingsContent.qml) still owns all real state -- wifiRows,
// wifiPasswordSsid/Attempt/Connecting/Error, connect/forget/submit calls
// -- this only draws what it's told and emits signals, same split every
// other item in this file already uses.
Item {
  id: root

  property string ssid: ""
  property bool connected: false
  property int signalPercent: 0
  property bool secured: false
  // Only Known Networks' own not-currently-connected rows get a hover
  // forget affordance -- mirrors canForgetNetwork (known && !connected)
  // on the real page.
  property bool showForget: false
  // Password entry only renders while this row is the one
  // wifiPasswordSsid currently targets -- driven externally, this
  // component has no opinion on WHEN that should be true.
  property bool expanded: false
  property bool connecting: false
  property string errorText: ""
  property bool rowFocused: false
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  signal activated()
  signal passwordSubmitted(string password)
  signal cancelled()
  signal forgetRequested()

  // Called by SettingsContent.qml's own activateFocusedOption() right
  // after opening the prompt for this row -- hands real Qt focus to the
  // password TextInput, same handoff SettingsAddListItem.qml's own
  // focusTextInput() already does.
  function focusPasswordInput() { passwordInput.forceActiveFocus() }

  width: parent.width
  height: content.implicitHeight + 16
  Behavior on height { NumberAnimation { duration: 120 } }
  clip: true

  Rectangle {
    anchors.fill: parent
    radius: 8
    color: root.connected || root.expanded ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
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
        id: ssidLabel
        anchors.left: dot.right
        anchors.leftMargin: 10
        anchors.right: lockGlyph.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: root.ssid
        elide: Text.ElideRight
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: root.connected ? Font.DemiBold : Font.Normal
        color: root.connected ? root.textColor : root.muted
      }

      Text {
        id: lockGlyph
        visible: root.secured
        anchors.right: trailingLabel.left
        anchors.rightMargin: 8
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        font.family: root.fontFamily
        font.pixelSize: 10
        color: root.muted
      }

      // Swaps to a forget (trash) glyph on hover -- direct port of the
      // real page's own hover-to-forget affordance. Visibility is
      // driven by rowMouse's OWN hover below, not by this icon's own
      // (initially invisible) MouseArea -- an invisible item can never
      // receive the hover event that would make it visible, a real
      // chicken-and-egg bug caught before it shipped.
      Text {
        id: trailingLabel
        visible: !(root.showForget && rowMouse.containsMouse)
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 32
        horizontalAlignment: Text.AlignRight
        text: root.signalPercent + "%"
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.muted
      }

      Text {
        // z above rowMouse below -- confirmed real bug in
        // ruixen.settings' own WifiContent.qml/BluetoothContent.qml
        // without this: a later sibling (the row-wide MouseArea) stacks
        // on top and swallows the click before it reaches this nested
        // one, so the forget icon just re-triggers connect instead.
        z: 1
        visible: root.showForget && rowMouse.containsMouse
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: 32
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

    // Inline passphrase field -- same plain-primitive style
    // SettingsAddListItem.qml's own input box uses, not a new visual
    // language.
    Column {
      width: parent.width
      visible: root.expanded
      spacing: 6

      Item {
        width: parent.width
        height: 28

        Rectangle {
          anchors.left: parent.left
          anchors.right: submitBtn.left
          anchors.rightMargin: 6
          height: 28
          radius: 6
          color: Qt.rgba(1, 1, 1, 0.06)

          TextInput {
            id: passwordInput
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            verticalAlignment: TextInput.AlignVCenter
            echoMode: TextInput.Password
            enabled: !root.connecting
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 12
            clip: true

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.connecting ? "Connecting…" : "Enter password..."
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 12
              visible: passwordInput.text.length === 0
            }

            Keys.onReturnPressed: { root.passwordSubmitted(passwordInput.text); passwordInput.text = "" }
            Keys.onEscapePressed: root.cancelled()
          }
        }

        Rectangle {
          id: submitBtn
          anchors.right: parent.right
          width: 28
          height: 28
          radius: 6
          color: submitMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
          opacity: root.connecting ? 0.5 : 1

          Text {
            anchors.centerIn: parent
            text: ""
            font.family: root.fontFamily
            font.pixelSize: 12
            color: root.textColor
          }

          MouseArea {
            id: submitMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: !root.connecting
            cursorShape: Qt.PointingHandCursor
            onClicked: { root.passwordSubmitted(passwordInput.text); passwordInput.text = "" }
          }
        }
      }

      Text {
        visible: root.errorText !== ""
        text: root.errorText
        font.family: root.fontFamily
        font.pixelSize: 10
        color: "#e05252"
      }
    }
  }
}
