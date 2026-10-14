import QtQuick
import ".."

// Issue #102 phase 3: extracted from SettingsContent.qml's own Display
// section (95 lines of pure visual markup). Same pattern as
// AudioPage.qml/PluginsPage.qml -- see PluginsPage.qml's own header for
// the full reasoning (live property bindings via settingsRoot, never a
// one-time copy; a Column wrapper with its own matching spacing/visible
// so an inactive section collapses to zero space in the outer Column
// exactly like individually-hidden siblings did). import ".." exposes
// SettingsSegmentedItem/SettingsSliderRow/SettingsToggleRow, still
// siblings of SettingsContent.qml one directory up.
//
// nightLightRow/brightnessItem/displayScaleItem are exposed because
// SettingsContent.qml's own shared, cross-section focusedItemVisual()
// keyboard-navigation coordinator (used by every section, stays
// centralized there on purpose) needs to reach the actual focused
// visual Item regardless of which section owns it.
Column {
  id: root
  required property Item settingsRoot

  width: parent.width
  spacing: 16
  visible: settingsRoot.displayOpen && settingsRoot.brightnessAvailable

  readonly property alias nightLightRow: nightLightRow
  readonly property alias brightnessItem: brightnessItem
  readonly property alias displayScaleItem: displayScaleItem

  // Display's own three items, top to bottom -- Night Light (direct
  // follow-up: "put it as the top option above brightness"),
  // Brightness (a plain slider, no mute concept, hence
  // SettingsSliderRow.qml rather than SettingsAudioChannelItem's own),
  // and Display Scale (a plain segmented item, same shape as Bar
  // Layout/Window Curvature). All three gated on brightnessAvailable,
  // same as ruixen.settings' own DisplayContent.qml -- a laptop-less/
  // headless session has no backlight to control (Night Light itself
  // doesn't strictly need this gate, see displayItems' own comment for
  // why it's bundled under it anyway).
  Rectangle {
    id: nightLightItem
    width: parent.width
    height: nightLightContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.displayOpen && settingsRoot.brightnessAvailable

    Column {
      id: nightLightContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Night Light"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      SettingsToggleRow {
        id: nightLightRow
        label: "Enabled"
        checked: settingsRoot.nightLightEnabled
        rowFocused: settingsRoot.displayOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 0
        textColor: settingsRoot.textColor
        accent: settingsRoot.accent
        fontFamily: settingsRoot.fontFamily
        onToggled: settingsRoot.toggleNightLight()
      }
    }
  }

  Rectangle {
    id: brightnessItem
    width: parent.width
    height: brightnessContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    border.width: (settingsRoot.displayOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 1) ? 1 : 0
    border.color: settingsRoot.accent
    visible: settingsRoot.displayOpen && settingsRoot.brightnessAvailable

    Column {
      id: brightnessContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Brightness"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      SettingsSliderRow {
        icon: ""
        value: settingsRoot.brightnessPercent / 100
        textColor: settingsRoot.textColor
        muted: settingsRoot.muted
        accent: settingsRoot.accent
        fontFamily: settingsRoot.fontFamily
        onAdjusted: (value) => settingsRoot.setBrightness(value * 100)
      }
    }
  }

  SettingsSegmentedItem {
    id: displayScaleItem
    label: "Display Scale"
    options: settingsRoot.scalePresets.map(function(s) { return { id: s, label: s + "x" } })
    current: settingsRoot.displayScale
    cardFocused: settingsRoot.displayOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 2
    focusedOptionIndex: displayScaleItem.cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.displayOpen && settingsRoot.brightnessAvailable
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setDisplayScale(id)
  }
}
