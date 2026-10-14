import QtQuick
import ".."

// Issue #102 phase 4: extracted from SettingsContent.qml's own
// Visualizer ("Desktop" label, id stays visualizer -- internal only,
// see that section data's own comment) section (170 lines of pure
// visual markup). Same pattern as DisplayPage.qml/AudioPage.qml/
// PluginsPage.qml -- see PluginsPage.qml's own header for the full
// reasoning (live property bindings via settingsRoot, never a one-time
// copy; a Column wrapper with its own matching spacing/visible so an
// inactive section collapses to zero space in the outer Column exactly
// like individually-hidden siblings did). import ".." exposes
// SettingsSegmentedItem/SettingsSliderRow/SettingsToggleRow, still
// siblings of SettingsContent.qml one directory up.
//
// cavaEnableRow/cavaMirrorRow/cavaStyleItem/cavaPositionItem/
// cavaBandsItem/cavaThicknessItem are exposed because
// SettingsContent.qml's own shared, cross-section focusedItemVisual()
// keyboard-navigation coordinator (used by every section, stays
// centralized there on purpose) needs to reach the actual focused
// visual Item regardless of which section owns it.
Column {
  id: root
  required property Item settingsRoot

  width: parent.width
  spacing: 16
  visible: settingsRoot.visualizerOpen

  readonly property alias cavaEnableRow: cavaEnableRow
  readonly property alias cavaMirrorRow: cavaMirrorRow
  readonly property alias cavaStyleItem: cavaStyleItem
  readonly property alias cavaPositionItem: cavaPositionItem
  readonly property alias cavaBandsItem: cavaBandsItem
  readonly property alias cavaThicknessItem: cavaThicknessItem

  // Visualizer -- direct request. Enable toggle same shape as
  // Night Light's own card above; Position/Bands/Size are plain
  // segmented items, same shape as Bar Layout/Display Scale. The actual
  // effect lives entirely in a separate, always-loaded plugin
  // (ruixen.cava/Overlay.qml) -- this page only ever writes
  // cava-visualizer.json, same Settings-writes/plugin-reads split as
  // Notch above.
  Rectangle {
    id: cavaEnableItem
    width: parent.width
    height: cavaEnableContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.visualizerOpen

    Column {
      id: cavaEnableContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Visualizer"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      // Same row, same card -- direct request/answer to "where does an
      // install hint go? a new row? thats jumpy, on the enable or
      // visualer row then?" Swaps the switch's own dim state and adds
      // an inline subtitle when cava isn't found, rather than a
      // separate settings block appearing/disappearing above or below
      // this one.
      SettingsToggleRow {
        id: cavaEnableRow
        label: "Enabled"
        subtitle: settingsRoot.cavaInstalled ? "" : "cava not found — install: sudo pacman -S cava"
        toggleEnabled: settingsRoot.cavaInstalled
        checked: settingsRoot.cavaEnabled
        rowFocused: settingsRoot.visualizerOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 0
        textColor: settingsRoot.textColor
        accent: settingsRoot.accent
        fontFamily: settingsRoot.fontFamily
        onToggled: if (settingsRoot.cavaInstalled) settingsRoot.setCavaEnabled(!settingsRoot.cavaEnabled)
      }

      // Mirror -- real bass-on-both-edges/treble-in-the-center, not a
      // plain left-to-right sweep. Grouped into the same card as
      // Enabled, right below it -- direct follow-up: "might as well
      // put the toggles together" (was its own separate card between
      // Bands and Height). Direct follow-up after shipping the same
      // fold on the compact notch's own mini cava first ("looks better
      // that way for aesthetic").
      SettingsToggleRow {
        id: cavaMirrorRow
        label: "Mirror"
        checked: settingsRoot.cavaMirror
        rowFocused: settingsRoot.visualizerOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 1
        textColor: settingsRoot.textColor
        accent: settingsRoot.accent
        fontFamily: settingsRoot.fontFamily
        onToggled: settingsRoot.setCavaMirror(!settingsRoot.cavaMirror)
      }
    }
  }

  // Style -- Bars vs Segments, direct follow-up: "so for the segment,
  // i guess its pretty much similar kinda vibe right" / "yup lets do
  // it." Same card shape as Position/Bands right below; Segments
  // reuses every other knob on this page unchanged.
  SettingsSegmentedItem {
    id: cavaStyleItem
    label: "Style"
    options: [
      { id: "bars", label: "Bars" },
      { id: "segments", label: "Segments" },
      { id: "wave", label: "Wave" }
    ]
    current: settingsRoot.cavaStyle
    cardFocused: settingsRoot.visualizerOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 2
    focusedOptionIndex: cavaStyleItem.cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.visualizerOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setCavaStyle(id)
  }

  SettingsSegmentedItem {
    id: cavaPositionItem
    label: "Position"
    options: [
      { id: "top", label: "Top" },
      { id: "bottom", label: "Bottom" },
      { id: "left", label: "Left" },
      { id: "right", label: "Right" }
    ]
    current: settingsRoot.cavaPosition
    cardFocused: settingsRoot.visualizerOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 3
    focusedOptionIndex: cavaPositionItem.cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.visualizerOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setCavaPosition(id)
  }

  SettingsSegmentedItem {
    id: cavaBandsItem
    label: "Bands"
    options: [
      { id: 32, label: "32" },
      { id: 48, label: "48" },
      { id: 64, label: "64" },
      { id: 96, label: "96" }
    ]
    current: settingsRoot.cavaBands
    cardFocused: settingsRoot.visualizerOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 4
    focusedOptionIndex: cavaBandsItem.cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.visualizerOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setCavaBands(id)
  }

  // Height -- a real pixel slider, not Small/Medium/Large. Same
  // Rectangle-card + labeled SettingsSliderRow shape as Display's own
  // Brightness card right above in this file, not a new pattern.
  Rectangle {
    id: cavaThicknessItem
    width: parent.width
    height: cavaThicknessContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    border.width: (settingsRoot.visualizerOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 5) ? 1 : 0
    border.color: settingsRoot.accent
    visible: settingsRoot.visualizerOpen

    Column {
      id: cavaThicknessContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Height"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      SettingsSliderRow {
        icon: ""
        value: (settingsRoot.cavaThickness - settingsRoot.cavaThicknessMin) / (settingsRoot.cavaThicknessMax - settingsRoot.cavaThicknessMin)
        valueLabel: settingsRoot.cavaThickness + "px"
        textColor: settingsRoot.textColor
        muted: settingsRoot.muted
        accent: settingsRoot.accent
        fontFamily: settingsRoot.fontFamily
        onAdjusted: (value) => settingsRoot.setCavaThickness(settingsRoot.cavaThicknessMin + value * (settingsRoot.cavaThicknessMax - settingsRoot.cavaThicknessMin))
      }
    }
  }
}
