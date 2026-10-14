import QtQuick
import Quickshell.Networking
import ".."

// Issue #102 phase 8: extracted from SettingsContent.qml's own Wi-Fi
// section (278 lines of pure visual markup). Same pattern as every
// prior page -- see PluginsPage.qml's own header for the full
// reasoning (live property bindings via settingsRoot, never a
// one-time copy; a Column wrapper with its own matching spacing/
// visible so an inactive section collapses to zero space in the outer
// Column exactly like individually-hidden siblings did). import ".."
// exposes SettingsWifiRow/SettingsToggleRow, still siblings one
// directory up. The Networking singleton (used to gate the Available
// Networks list and the "turn on Wi-Fi" empty state) needs its own
// explicit import here too -- it was reached for free before via
// SettingsContent.qml's own top-level import.
//
// wifiRadioRow/wifiQrButton/wifiSpeedTestButton/knownRepeater/
// otherRepeater are exposed because SettingsContent.qml's own shared,
// cross-section focusedItemVisual() keyboard-navigation coordinator
// needs to reach them regardless of which page owns them.
// otherRepeater is ALSO used by SettingsContent.qml's own wifiItems
// keyboard-nav data model (wifiOtherRowItem specifically), to hand
// real Qt focus to a just-opened password field.
Column {
  id: root
  required property Item settingsRoot

  width: parent.width
  spacing: 16
  visible: settingsRoot.wifiOpen

  readonly property alias wifiRadioRow: wifiRadioRow
  readonly property alias wifiQrButton: wifiQrButton
  readonly property alias wifiSpeedTestButton: wifiSpeedTestButton
  readonly property alias knownRepeater: knownRepeater
  readonly property alias otherRepeater: otherRepeater

  // Wi-Fi's own three items -- the radio toggle (reuses
  // SettingsToggleRow.qml directly, same as Launcher's own toggles),
  // then QR-share and Speed Test buttons (real Omarchy panel plugins,
  // summoned via the unscoped omarchy-shell CLI -- see summonWifiQr()/
  // summonSpeedTest()'s own comment for why NOT the in-process
  // settingsRoot.shell), then Known Networks and Available Networks, both on
  // SettingsWifiRow.qml (see its own header comment). Real backend on
  // root above, ported from
  // ruixen.settings/WifiContent.qml + Settings.qml.
  Rectangle {
    id: wifiRadioItem
    width: parent.width
    height: wifiRadioContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.wifiOpen

    Column {
      id: wifiRadioContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Wi-Fi"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      SettingsToggleRow {
        id: wifiRadioRow
        label: "Enabled"
        checked: Networking.wifiEnabled
        rowFocused: settingsRoot.wifiOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 0
        textColor: settingsRoot.textColor
        accent: settingsRoot.accent
        fontFamily: settingsRoot.fontFamily
        onToggled: settingsRoot.toggleWifiRadio()
      }

      Row {
        width: parent.width
        spacing: 8

        Rectangle {
          id: wifiQrButton
          width: (parent.width - 8) / 2
          height: 32
          radius: 8
          color: wifiQrMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
          border.width: settingsRoot.wifiOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 1 ? 1 : 0
          border.color: settingsRoot.accent

          Row {
            anchors.centerIn: parent
            spacing: 8

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: ""
              font.family: settingsRoot.fontFamily
              font.pixelSize: 13
              color: settingsRoot.textColor
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "QR Code"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 12
              color: settingsRoot.textColor
            }
          }

          MouseArea {
            id: wifiQrMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: settingsRoot.summonWifiQr()
          }
        }

        Rectangle {
          id: wifiSpeedTestButton
          width: (parent.width - 8) / 2
          height: 32
          radius: 8
          color: wifiSpeedTestMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
          border.width: settingsRoot.wifiOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 2 ? 1 : 0
          border.color: settingsRoot.accent

          Row {
            anchors.centerIn: parent
            spacing: 8

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: ""
              font.family: settingsRoot.fontFamily
              font.pixelSize: 13
              color: settingsRoot.textColor
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Speed Test"
              font.family: settingsRoot.fontFamily
              font.pixelSize: 12
              color: settingsRoot.textColor
            }
          }

          MouseArea {
            id: wifiSpeedTestMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: settingsRoot.summonSpeedTest()
          }
        }
      }
    }
  }

  Rectangle {
    id: knownNetworksItem
    width: parent.width
    height: knownNetworksContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.wifiOpen && Networking.wifiEnabled

    Column {
      id: knownNetworksContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Known Networks"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      // Connection stats -- describes whichever known network is
      // currently active, same placement as the real page.
      Column {
        width: parent.width
        visible: settingsRoot.connectedWifiNetwork !== null
        spacing: 2

        Item {
          width: parent.width
          height: 16
          Text { anchors.left: parent.left; text: "IP Address"; font.family: settingsRoot.fontFamily; font.pixelSize: 11; color: settingsRoot.muted }
          Text { anchors.right: parent.right; text: settingsRoot.netInfo.ip || "--"; font.family: settingsRoot.fontFamily; font.pixelSize: 11; color: settingsRoot.textColor; elide: Text.ElideLeft }
        }
        Item {
          width: parent.width
          height: 16
          Text { anchors.left: parent.left; text: "Gateway"; font.family: settingsRoot.fontFamily; font.pixelSize: 11; color: settingsRoot.muted }
          Text { anchors.right: parent.right; text: settingsRoot.netInfo.gateway || "--"; font.family: settingsRoot.fontFamily; font.pixelSize: 11; color: settingsRoot.textColor; elide: Text.ElideLeft }
        }
        Item {
          width: parent.width
          height: 16
          Text { anchors.left: parent.left; text: "Ping"; font.family: settingsRoot.fontFamily; font.pixelSize: 11; color: settingsRoot.muted }
          Text { anchors.right: parent.right; text: settingsRoot.netInfo.internet_ping_ms ? Math.round(parseFloat(settingsRoot.netInfo.internet_ping_ms)) + " ms" : "--"; font.family: settingsRoot.fontFamily; font.pixelSize: 11; color: settingsRoot.textColor }
        }
      }

      Column {
        width: parent.width
        spacing: 4

        Repeater {
          id: knownRepeater
          model: settingsRoot.knownWifiRows

          SettingsWifiRow {
            required property var modelData
            required property int index
            width: parent.width
            ssid: modelData.ssid
            connected: modelData.connected
            signalPercent: modelData.signal
            secured: !settingsRoot.isOpenNetwork(modelData.security)
            showForget: !modelData.connected
            rowFocused: settingsRoot.wifiOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === (3 + index)
            textColor: settingsRoot.textColor
            muted: settingsRoot.muted
            accent: settingsRoot.accent
            fontFamily: settingsRoot.fontFamily
            onActivated: settingsRoot.connectToWifi(modelData)
            onForgetRequested: settingsRoot.forgetWifi(modelData)
          }
        }

        Text {
          visible: settingsRoot.knownWifiRows.length === 0
          text: "No known networks"
          font.family: settingsRoot.fontFamily
          font.pixelSize: 11
          color: settingsRoot.muted
        }
      }
    }
  }

  Rectangle {
    id: otherNetworksItem
    width: parent.width
    height: otherNetworksContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.wifiOpen && Networking.wifiEnabled && settingsRoot.otherWifiRows.length > 0

    Column {
      id: otherNetworksContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 10

      Text {
        text: "Available Networks"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      Column {
        width: parent.width
        spacing: 4

        Repeater {
          id: otherRepeater
          model: settingsRoot.otherWifiRows

          SettingsWifiRow {
            required property var modelData
            required property int index
            width: parent.width
            ssid: modelData.ssid
            connected: modelData.connected
            signalPercent: modelData.signal
            secured: !settingsRoot.isOpenNetwork(modelData.security)
            expanded: settingsRoot.wifiPasswordSsid === modelData.ssid
            connecting: settingsRoot.wifiConnecting
            errorText: settingsRoot.wifiPasswordSsid === modelData.ssid ? settingsRoot.wifiConnectError : ""
            rowFocused: settingsRoot.wifiOpen && settingsRoot.rightFocused
              && settingsRoot.focusedItemIndex === (3 + settingsRoot.knownWifiRows.length + index)
            textColor: settingsRoot.textColor
            muted: settingsRoot.muted
            accent: settingsRoot.accent
            fontFamily: settingsRoot.fontFamily
            onActivated: settingsRoot.connectToWifi(modelData)
            onPasswordSubmitted: (password) => settingsRoot.submitWifiPassword(password)
            onCancelled: { settingsRoot.closeWifiPasswordPrompt(); settingsRoot.returnFocusRequested() }
          }
        }
      }
    }
  }

  Text {
    visible: settingsRoot.wifiOpen && !Networking.wifiEnabled
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    topPadding: 24
    text: "Turn on Wi-Fi to see nearby networks"
    font.family: settingsRoot.fontFamily
    font.pixelSize: 12
    color: settingsRoot.muted
  }
}
