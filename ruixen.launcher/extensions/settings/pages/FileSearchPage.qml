import QtQuick
import ".."

// Issue #102 phase 7: extracted from SettingsContent.qml's own
// Launcher (File Search) section (196 lines of pure visual markup).
// Same pattern as every prior page -- see PluginsPage.qml's own header
// for the full reasoning (live property bindings via settingsRoot,
// never a one-time copy; a Column wrapper with its own matching
// spacing/visible so an inactive section collapses to zero space in
// the outer Column exactly like individually-hidden siblings did).
// import ".." exposes SettingsAddListItem/SettingsToggleRow, still
// siblings of SettingsContent.qml one directory up.
//
// includeHomeRow/includeMountedRow/mountRepeater/customRootsItem/
// excludedPathsItem/excludedNamesItem are exposed because
// SettingsContent.qml's own shared, cross-section focusedItemVisual()
// keyboard-navigation coordinator needs to reach them regardless of
// which page owns them. customRootsItem/excludedPathsItem/
// excludedNamesItem are ALSO exposed for the same reason by
// SettingsContent.qml's own launcherItems keyboard-nav data model
// (same role as pluginItems/audioItems/profileItems before it) --
// its own text-entry rows need to actually focus the real input, not
// just report focus.
Column {
  id: root
  required property Item settingsRoot

  width: parent.width
  spacing: 16
  visible: settingsRoot.launcherOpen

  readonly property alias includeHomeRow: includeHomeRow
  readonly property alias includeMountedRow: includeMountedRow
  readonly property alias mountRepeater: mountRepeater
  readonly property alias customRootsItem: customRootsItem
  readonly property alias excludedPathsItem: excludedPathsItem
  readonly property alias excludedNamesItem: excludedNamesItem

  // Launcher's own first item -- two on/off toggles grouped in one
  // card, matching ruixen.settings/LauncherSettingsContent.qml's own
  // "Launcher" card exactly (both toggles together, not one card
  // each). Mouse-only for this pass, deliberately not wired into the
  // Tab/Up-Down/Left-Right/Enter keyboard model SettingsSegmentedItem
  // items use -- a toggle's own natural interaction (flip it directly)
  // doesn't fit that "cycle between N options" shape, and building a
  // real keyboard model for it is its own separate piece of work, not
  // a same-shape extension of this one. The mounted-drives checklist,
  // custom roots, and path/name exclusions from the real page are
  // real follow-on work too, not part of this pass.
  Rectangle {
    id: launcherToggleItem
    width: parent.width
    height: launcherToggleContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.launcherOpen

    Column {
      id: launcherToggleContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Search Settings"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      SettingsToggleRow {
        id: includeHomeRow
        label: "Include Home"
        checked: settingsRoot.launcherSearchConfig.includeHome
        rowFocused: settingsRoot.launcherOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 0
        textColor: settingsRoot.textColor
        accent: settingsRoot.accent
        fontFamily: settingsRoot.fontFamily
        onToggled: (value) => settingsRoot.setLauncherIncludeHome(value)
      }

      SettingsToggleRow {
        id: includeMountedRow
        label: "Auto-include Mounted Drives"
        checked: settingsRoot.launcherSearchConfig.includeMountedRoots
        rowFocused: settingsRoot.launcherOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 1
        textColor: settingsRoot.textColor
        accent: settingsRoot.accent
        fontFamily: settingsRoot.fontFamily
        onToggled: (value) => settingsRoot.setLauncherIncludeMountedRoots(value)
      }
    }
  }

  // Launcher's second item -- one toggle per discovered mount, ported
  // from ruixen.settings/LauncherSettingsContent.qml's own "MOUNTED
  // DRIVES" checklist. A disabled-but-unmounted entry (see
  // toggleLauncherAutoRootDisabled's own comment) shows its own "Not
  // currently connected" subtitle via SettingsToggleRow's own
  // `subtitle` -- the exact shape that prop was added for.
  Rectangle {
    id: mountedDrivesItem
    width: parent.width
    height: mountedDrivesContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: settingsRoot.launcherOpen

    Column {
      id: mountedDrivesContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 10

      Text {
        text: "Mounted Drives"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      // Centered icon + caption, matching ruixen.launcher's own
      // EmptyState.qml "No Results" treatment -- same fa-hdd_o
      // (U+F0A0) glyph, confirmed present in JetBrainsMono Nerd Font's
      // cmap directly (same convention as every other \u-escaped glyph
      // in this file).
      Column {
        width: parent.width
        visible: settingsRoot.mountChecklist.length === 0
        spacing: 4

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: ""
          font.family: settingsRoot.fontFamily
          font.pixelSize: 20
          color: settingsRoot.muted
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "No drives detected"
          font.family: settingsRoot.fontFamily
          font.pixelSize: 11
          color: settingsRoot.muted
        }
      }

      Column {
        width: parent.width
        spacing: 10

        Repeater {
          id: mountRepeater
          model: settingsRoot.mountChecklist

          SettingsToggleRow {
            required property var modelData
            required property int index
            width: parent.width
            label: modelData.path
            subtitle: modelData.connected ? "" : "Not currently connected"
            elideLabel: true
            checked: !modelData.disabled
            rowFocused: settingsRoot.launcherOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === (2 + index)
            textColor: settingsRoot.textColor
            muted: settingsRoot.muted
            accent: settingsRoot.accent
            fontFamily: settingsRoot.fontFamily
            onToggled: settingsRoot.toggleLauncherAutoRootDisabled(modelData.path)
          }
        }
      }
    }
  }

  // Launcher's third/fourth/fifth items -- the three remaining
  // sections from ruixen.settings/LauncherSettingsContent.qml, all on
  // SettingsAddListItem.qml (see its own header comment for why one
  // component covers all three shapes).
  SettingsAddListItem {
    id: customRootsItem
    label: "Custom Search Roots"
    placeholder: "~/Work or /mnt/Documents"
    items: settingsRoot.launcherSearchConfig.roots
    // launcherItems' own order: 2 fixed toggles, then one per mount,
    // then these three text-entry cards last.
    cardFocused: settingsRoot.launcherOpen && settingsRoot.rightFocused
      && settingsRoot.focusedItemIndex === 2 + settingsRoot.mountChecklist.length
    visible: settingsRoot.launcherOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onAdded: (value) => settingsRoot.addLauncherRoot(value)
    onRemoved: (value) => settingsRoot.removeLauncherRoot(value)
    onCancelled: settingsRoot.returnFocusRequested()
  }

  SettingsAddListItem {
    id: excludedPathsItem
    label: "Excluded Paths"
    placeholder: "~/VMs or ~/Downloads/ISOs"
    items: settingsRoot.launcherSearchConfig.excludePaths
    cardFocused: settingsRoot.launcherOpen && settingsRoot.rightFocused
      && settingsRoot.focusedItemIndex === 3 + settingsRoot.mountChecklist.length
    visible: settingsRoot.launcherOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onAdded: (value) => settingsRoot.addLauncherExcludePath(value)
    onRemoved: (value) => settingsRoot.removeLauncherExcludePath(value)
    onCancelled: settingsRoot.returnFocusRequested()
  }

  SettingsAddListItem {
    id: excludedNamesItem
    label: "Excluded Directory Names"
    placeholder: "e.g. dist or .venv"
    chipMode: true
    items: settingsRoot.launcherSearchConfig.excludeNames
    cardFocused: settingsRoot.launcherOpen && settingsRoot.rightFocused
      && settingsRoot.focusedItemIndex === 4 + settingsRoot.mountChecklist.length
    visible: settingsRoot.launcherOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onAdded: (value) => settingsRoot.addLauncherExcludeName(value)
    onRemoved: (value) => settingsRoot.removeLauncherExcludeName(value)
    onCancelled: settingsRoot.returnFocusRequested()
  }
}
