import QtQuick
import ".."

// Issue #102 phase 2: extracted from SettingsContent.qml's own Audio
// section (103 lines of pure visual markup). No behavior or visual
// change: every settingsRoot.* read below is a live property binding
// (never a one-time copy -- see ExtensionTwoPanel.qml's own header for
// why that distinction matters here specifically, a real bug this
// plugin already hit once), same as every other already-split file in
// this plugin reads its own outer root directly. import ".." exposes
// SettingsAudioChannelItem/SettingsToggleRow, both still siblings of
// SettingsContent.qml one directory up -- the same directory-import
// mechanism SettingsContent.qml itself already uses for "services"/
// "pages", just reaching the other direction.
//
// A Column, not a plain Item -- see PluginsPage.qml's own header for
// why (SettingsContent.qml's own rightContentColumn used to hold these
// as direct, individually visible-gated siblings; this wraps them as
// ONE child instead, with its own matching spacing and top-level
// visible so an inactive section still collapses to zero height/
// spacing exactly like the individually-hidden siblings did).
//
// audioRadioRow/outputChannelItem/inputChannelItem are exposed because
// SettingsContent.qml's own shared, cross-section focusedItemVisual()/
// scrollToFocusedItem() keyboard-navigation coordinator (used by every
// section, stays centralized there on purpose) needs to reach the
// actual focused visual Item regardless of which section owns it.
Column {
  id: root
  required property Item settingsRoot

  width: parent.width
  spacing: 16
  visible: settingsRoot.audioOpen

  readonly property alias audioRadioRow: audioRadioRow
  readonly property alias outputChannelItem: outputChannelItem
  readonly property alias inputChannelItem: inputChannelItem

  // Audio's own radio toggle -- direct request: "on omarchy theres a
  // toggle for on and off, we have this for bluetooth and wifi as the
  // top option, can we have an audio on and off toggle too." Same
  // mute-both semantics as Omarchy's own hero switch (see
  // settingsRoot.toggleAllMuted()'s own comment) -- reused SettingsToggleRow
  // directly, same card-wrapped shape Wi-Fi/Bluetooth's own radio uses.
  Rectangle {
    id: audioRadioItem
    width: parent.width
    height: audioRadioContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.audioOpen

    Column {
      id: audioRadioContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Audio"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      SettingsToggleRow {
        id: audioRadioRow
        label: "Enabled"
        checked: settingsRoot.anyAudible
        rowFocused: settingsRoot.audioOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 0
        textColor: settingsRoot.textColor
        accent: settingsRoot.accent
        fontFamily: settingsRoot.fontFamily
        onToggled: settingsRoot.toggleAllMuted()
      }
    }
  }

  // Audio's own two channel items -- Output and Input, both on
  // SettingsAudioChannelItem.qml (see its own header comment). Mouse/
  // scroll-wheel only for this pass, same as Profile Picture's own
  // avatar picker started out -- a continuous slider is a genuinely
  // different keyboard shape (adjust a value, not cycle/flip/type)
  // from every item already wired into currentItems, real follow-on
  // work rather than a same-shape extension of any of them.
  SettingsAudioChannelItem {
    id: outputChannelItem
    label: "Output"
    volume: settingsRoot.outputVolume
    channelMuted: settingsRoot.outputMuted
    devices: settingsRoot.outputDevices
    defaultDevice: settingsRoot.outputSink
    // Output's own items are index 1 (volume/mute, right after the
    // radio toggle at index 0) through 1 + outputDevices.length (the
    // last device) in audioItems above.
    volumeFocused: settingsRoot.audioOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 1
    focusedDeviceIndex: (settingsRoot.audioOpen && settingsRoot.rightFocused
      && settingsRoot.focusedItemIndex >= 2 && settingsRoot.focusedItemIndex <= 1 + settingsRoot.outputDevices.length)
      ? settingsRoot.focusedItemIndex - 2 : -1
    iconMuted: ""
    iconUnmuted: ""
    labelFor: settingsRoot.deviceLabel
    visible: settingsRoot.audioOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onMuteToggled: settingsRoot.toggleOutputMute()
    onVolumeAdjusted: (value) => settingsRoot.setOutputVolume(value)
    onDeviceSelected: (node) => settingsRoot.setDefaultOutput(node)
  }

  SettingsAudioChannelItem {
    id: inputChannelItem
    label: "Input"
    volume: settingsRoot.inputVolume
    channelMuted: settingsRoot.inputMuted
    devices: settingsRoot.inputDevices
    defaultDevice: settingsRoot.inputSource
    // Input's items pick up right where Output's own leave off -- 1 +
    // settingsRoot.outputItemCount is exactly the offset both this file and
    // focusedItemVisual()/audioItems above already agree on (the extra
    // +1 is the radio toggle at index 0).
    volumeFocused: settingsRoot.audioOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 1 + settingsRoot.outputItemCount
    focusedDeviceIndex: (settingsRoot.audioOpen && settingsRoot.rightFocused
      && settingsRoot.focusedItemIndex > 1 + settingsRoot.outputItemCount
      && settingsRoot.focusedItemIndex <= 1 + settingsRoot.outputItemCount + settingsRoot.inputDevices.length)
      ? settingsRoot.focusedItemIndex - settingsRoot.outputItemCount - 2 : -1
    iconMuted: ""
    iconUnmuted: ""
    labelFor: settingsRoot.deviceLabel
    visible: settingsRoot.audioOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onMuteToggled: settingsRoot.toggleInputMute()
    onVolumeAdjusted: (value) => settingsRoot.setInputVolume(value)
    onDeviceSelected: (node) => settingsRoot.setDefaultInput(node)
  }
}
