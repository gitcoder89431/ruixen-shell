import QtQuick
import ".."

// Issue #102 phase 9: extracted from SettingsContent.qml's own
// Bluetooth section (163 lines of pure visual markup). Same pattern as
// every prior page -- see PluginsPage.qml's own header for the full
// reasoning (live property bindings via settingsRoot, never a
// one-time copy; a Column wrapper with its own matching spacing/
// visible so an inactive section collapses to zero space in the outer
// Column exactly like individually-hidden siblings did). import ".."
// exposes SettingsBtRow/SettingsToggleRow, still siblings one
// directory up.
//
// btRadioRow/knownBtRepeater/otherBtRepeater are exposed because
// SettingsContent.qml's own shared, cross-section focusedItemVisual()
// keyboard-navigation coordinator needs to reach them regardless of
// which page owns them.
Column {
  id: root
  required property Item settingsRoot

  width: parent.width
  spacing: 16
  visible: settingsRoot.btOpen

  readonly property alias btRadioRow: btRadioRow
  readonly property alias knownBtRepeater: knownBtRepeater
  readonly property alias otherBtRepeater: otherBtRepeater

  // Bluetooth's own three items -- radio toggle, then Paired Devices
  // and Available Devices, both on SettingsBtRow.qml (see its own
  // header comment). Real backend on root above, ported from
  // ruixen.settings/BluetoothContent.qml + Settings.qml.
  Rectangle {
    id: btRadioItem
    width: parent.width
    height: btRadioContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.btOpen

    Column {
      id: btRadioContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Bluetooth"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      SettingsToggleRow {
        id: btRadioRow
        label: "Enabled"
        checked: settingsRoot.btEnabled
        rowFocused: settingsRoot.btOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 0
        textColor: settingsRoot.textColor
        accent: settingsRoot.accent
        fontFamily: settingsRoot.fontFamily
        onToggled: settingsRoot.toggleBluetoothRadio()
      }
    }
  }

  Rectangle {
    id: pairedDevicesItem
    width: parent.width
    height: pairedDevicesContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.btOpen && settingsRoot.btEnabled

    Column {
      id: pairedDevicesContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Paired Devices"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      Column {
        width: parent.width
        spacing: 4

        Repeater {
          id: knownBtRepeater
          model: settingsRoot.knownBtRows

          SettingsBtRow {
            required property var modelData
            required property int index
            width: parent.width
            name: modelData.name
            connected: modelData.connected
            known: true
            pairedFormally: modelData.pairedFormally
            busy: settingsRoot.btBusyAddress === modelData.address
            showForget: !modelData.connected
            rowFocused: settingsRoot.btOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === (1 + index)
            textColor: settingsRoot.textColor
            muted: settingsRoot.muted
            accent: settingsRoot.accent
            fontFamily: settingsRoot.fontFamily
            onActivated: settingsRoot.toggleBtConnection(modelData)
            onForgetRequested: settingsRoot.forgetBtDevice(modelData)
          }
        }

        Text {
          visible: settingsRoot.knownBtRows.length === 0
          text: "No paired devices"
          font.family: settingsRoot.fontFamily
          font.pixelSize: 11
          color: settingsRoot.muted
        }
      }
    }
  }

  Rectangle {
    id: availableDevicesItem
    width: parent.width
    height: availableDevicesContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.btOpen && settingsRoot.btEnabled && settingsRoot.otherBtRows.length > 0

    Column {
      id: availableDevicesContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Available Devices"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      Column {
        width: parent.width
        spacing: 4

        Repeater {
          id: otherBtRepeater
          model: settingsRoot.otherBtRows

          SettingsBtRow {
            required property var modelData
            required property int index
            width: parent.width
            name: modelData.name
            connected: false
            known: false
            busy: settingsRoot.btBusyAddress === modelData.address
            armed: settingsRoot.btPairArmedAddress === modelData.address
            rowFocused: settingsRoot.btOpen && settingsRoot.rightFocused
              && settingsRoot.focusedItemIndex === (1 + settingsRoot.knownBtRows.length + index)
            textColor: settingsRoot.textColor
            muted: settingsRoot.muted
            accent: settingsRoot.accent
            fontFamily: settingsRoot.fontFamily
            onActivated: settingsRoot.toggleBtConnection(modelData)
            onConfirmPair: settingsRoot.confirmPairBtDevice(modelData)
          }
        }
      }
    }
  }

  Text {
    visible: settingsRoot.btOpen && !settingsRoot.btEnabled
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    topPadding: 24
    text: "Turn on Bluetooth to see nearby devices"
    font.family: settingsRoot.fontFamily
    font.pixelSize: 12
    color: settingsRoot.muted
  }
}
