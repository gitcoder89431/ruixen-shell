import QtQuick
import ".."
import "../../../search/AppLauncherGlyphs.js" as AppLauncherGlyphs

// Issue #102 phase 5: extracted from SettingsContent.qml's own Bar
// section (266 lines of pure visual markup -- Bar Layout, Frame Color,
// Surface Material, Icon Tone, Notch visibility, and the App Launcher
// icon picker all live on this page together). Same pattern as
// VisualizerPage.qml/DisplayPage.qml/AudioPage.qml/PluginsPage.qml --
// see PluginsPage.qml's own header for the full reasoning (live
// property bindings via settingsRoot, never a one-time copy; a Column
// wrapper with its own matching spacing/visible so an inactive section
// collapses to zero space in the outer Column exactly like
// individually-hidden siblings did). import ".." exposes
// SettingsSegmentedItem, still a sibling of SettingsContent.qml one
// directory up.
//
// iconRepeater/barLayoutItem/frameColorModeItem/surfaceMaterialItem/
// iconToneItem/notchVisibilityItem/appLauncherIconItem are exposed
// because SettingsContent.qml's own shared, cross-section
// focusedItemVisual() keyboard-navigation coordinator (used by every
// section, stays centralized there on purpose) needs to reach the
// actual focused visual Item regardless of which section owns it.
Column {
  id: root
  required property Item settingsRoot

  width: parent.width
  spacing: 16
  visible: settingsRoot.barOpen

  readonly property alias iconRepeater: iconRepeater
  readonly property alias barLayoutItem: barLayoutItem
  readonly property alias frameColorModeItem: frameColorModeItem
  readonly property alias surfaceMaterialItem: surfaceMaterialItem
  readonly property alias iconToneItem: iconToneItem
  readonly property alias notchVisibilityItem: notchVisibilityItem
  readonly property alias appLauncherIconItem: appLauncherIconItem
  readonly property alias frameEnabledItem: frameEnabledItem

  // Issue #114 follow-up, direct request: "move the settings toggle in
  // the bar menu so the toggle is the top option... looks cleaner" --
  // Frame Border moved here from right under Bar Layout (index 1) to
  // first (index 0); every focusedItemIndex below was renumbered to
  // match (Bar Layout 0 -> 1, everything else unchanged -- only the
  // first two swapped). SettingsToggleRow is deliberately just the row
  // (see its own header comment) -- this Rectangle is the same plain
  // card wrapper appLauncherIconItem below already uses, not a
  // separate shared-card case like Visualizer's own Enabled/Mirror pair
  // (this page has only the one toggle).
  Rectangle {
    width: parent.width
    height: frameEnabledItem.height + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.settingsRoot.barOpen

    // Dimmed + a subtitle while docked (same "explain why, don't just
    // silently ignore the click" shape cavaEnableRow's own
    // toggleEnabled/subtitle pair already uses for "cava not
    // installed"), since docked mode forces this on regardless of what
    //'s stored here -- setFrameEnabled's own no-op guard means a click
    // here while docked would otherwise look like it did nothing, with
    // no explanation why.
    SettingsToggleRow {
      id: frameEnabledItem
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.margins: 12
      label: "Frame Border"
      subtitle: root.settingsRoot.barMode === "docked" ? "Always on while docked" : ""
      toggleEnabled: root.settingsRoot.barMode !== "docked"
      checked: root.settingsRoot.frameEnabled
      rowFocused: root.settingsRoot.rightFocused && root.settingsRoot.focusedItemIndex === 0
      textColor: root.settingsRoot.textColor
      accent: root.settingsRoot.accent
      fontFamily: root.settingsRoot.fontFamily
      onToggled: root.settingsRoot.setFrameEnabled(!root.settingsRoot.frameEnabled)
    }
  }

  // Bar's own layout switch -- direct request: "think we're ready for
  // the bar page next, it should just be one setting option there for
  // bar layout floating or dock." Used to sit first (it changes the
  // shell chrome shape/reload behavior more than the purely visual
  // options below), but a later direct follow-up moved Frame Border
  // above it instead, purely for a cleaner-looking top of the page --
  // see Frame Border's own card comment above.
  SettingsSegmentedItem {
    id: barLayoutItem
    label: "Bar Layout"
    options: [
      { id: "floating", label: "Floating" },
      { id: "docked", label: "Docked" }
    ]
    current: settingsRoot.barMode
    cardFocused: settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 1
    focusedOptionIndex: cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.barOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setBarMode(id)
  }

  // Surface color -- theme it (tracks the active theme's own background
  // live) or plain black. Same "Themed"/mode-name wording ruixen.settings'
  // own Glass Tint card already established elsewhere in this file, for
  // consistency across the two closest analogous settings. Was a
  // Themed/Custom split with its own 3-swatch "Custom Color" card right
  // below this one -- direct correction after live testing: "some themes
  // uses white like lupine and few other light theme, this would make
  // the notch unusable... remove white from the setting as an option
  // then and just leave Black and Theme." Down to one card, one choice.
  //
  // Moved here from the Desktop page. It now shapes the bar's own
  // floating pills plus frame/docked-shoulder surface (see AGENTS.md #9's
  // "coupled visual surfaces"), not anything Desktop-page-specific.
  SettingsSegmentedItem {
    id: frameColorModeItem
    label: "Surface Color"
    options: [
      { id: "black", label: "Black" },
      { id: "theme", label: "Theme" }
    ]
    current: settingsRoot.frameColorMode
    cardFocused: settingsRoot.barOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 2
    focusedOptionIndex: frameColorModeItem.cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.barOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setFrameColorMode(id)
  }

  SettingsSegmentedItem {
    id: surfaceMaterialItem
    label: "Surface Material"
    options: [
      { id: "glass", label: "Glass" },
      { id: "solid", label: "Solid" }
    ]
    current: settingsRoot.barSurfaceMaterial
    cardFocused: settingsRoot.barOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 3
    focusedOptionIndex: surfaceMaterialItem.cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.barOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setBarSurfaceMaterial(id)
  }

  SettingsSegmentedItem {
    id: iconToneItem
    label: "Icon Tone"
    options: [
      { id: "accent", label: "Accent" },
      { id: "mono", label: "Mono" }
    ]
    current: settingsRoot.barIconTone
    cardFocused: settingsRoot.barOpen && settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 4
    focusedOptionIndex: iconToneItem.cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.barOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.setBarIconTone(id)
  }

  // Direct request: "instead of having people run the disable cli
  // command, allow Notch show or hidden as an option" -- same shape as
  // Bar Layout right above (a segmented control, not a toggle switch),
  // since this page already established that visual language for a
  // multi-state bar setting. Hidden flips the exact same enabled state
  // the Plugins page's own "Ruixen Notch" row toggles
  // (settingsRoot.notchPluginRow above), through the same omarchy plugin
  // enable/disable call togglePluginEnabled already runs for every
  // other plugin row -- not a lighter-weight visibility flag, since
  // the notch is keepLoaded and this IS meant to be the GUI form of
  // that same disable/enable action, just reachable from the page
  // where it's contextually relevant instead of buried in the full
  // Plugins list.
  //
  // On Hover, added per direct follow-up ("we had it before and it
  // knows not to [show] in fullscreen"): a real, different feature
  // from the hover-to-EXPAND ruixen.notch/Overlay.qml's own comment
  // documents removing -- this only fades the collapsed pill's own
  // paint in/out on hover, it does not open the dashboard. Keeps the
  // plugin enabled (hover detection needs the live service running,
  // unlike Hidden) and just persists notchVisibilityMode to the small
  // shared state file Overlay.qml itself watches -- see
  // notchVisibilityCurrentId()/activateNotchVisibility() above for the
  // shared logic both this item and its keyboard-nav twin
  // (settingsRoot.barItems) call into. Fullscreen-hiding needs no new code
  // here at all: Overlay.qml's own panel.visible already goes false
  // during fullscreen for an unrelated, pre-existing reason (settingsRoot.
  // fullscreenActive), which also fully unmaps the surface hover
  // detection would otherwise run through.
  SettingsSegmentedItem {
    id: notchVisibilityItem
    // Direct request: "rename Notch inside the bars setting to Notch
    // Visibility" -- label only, id/state/function names unchanged
    // (same reasoning as the Desktop/"visualizer" id split above: an
    // internal key, never shown).
    label: "Notch Visibility"
    options: [
      { id: "show", label: "Show" },
      { id: "hover", label: "On Hover" },
      { id: "hidden", label: "Hidden" }
    ]
    current: settingsRoot.notchVisibilityCurrentId()
    // 5 -- Bar Layout, Frame Border, Surface Color/Material, and Icon
    // Tone sit above it.
    cardFocused: settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 5
    focusedOptionIndex: cardFocused ? settingsRoot.focusedOptionIndex : -1
    visible: settingsRoot.barOpen
    textColor: settingsRoot.textColor
    muted: settingsRoot.muted
    accent: settingsRoot.accent
    fontFamily: settingsRoot.fontFamily
    onActivated: (id) => settingsRoot.activateNotchVisibility(id)
  }

  // "Launcher Mark" -- direct request: "allow more glyph as an option
  // in the bars panel setting so user can pick different ones... they
  // call it launcher mark". A grid of every
  // verified-present glyph (AppLauncherGlyphs.js, 112 options) instead
  // of a segmented control -- SettingsSegmentedItem's own row-of-N-
  // buttons shape doesn't scale past a handful of options the way Bar
  // Layout/Notch above use it.
  //
  // Keyboard nav added per direct follow-up ("that setting option i
  // cant tab into and use dpad to select a new icon") -- this card
  // slotted into barItems above (index 5) as an ordinary {options,
  // current, activate} entry, same shape as every other item, so
  // Tab/Left/Right/Enter all already work generically; only the
  // VISUAL focus indicators below are specific to this card (the
  // card-level ring mirrors profilePictureItem's own convention, the
  // per-tile underline mirrors collectionBtn's own, both already
  // proven elsewhere in this file for the exact same "Flow of many
  // options" shape).
  Rectangle {
    id: appLauncherIconItem
    width: parent.width
    height: appLauncherIconContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    // Card-level focus ring -- same convention profilePictureItem's
    // own comment documents ("tab between cards... then left or right
    // direction and enter for that option"). 6 -- Bar Layout, Frame
    // Border, Surface Color/Material, Icon Tone, and Notch Visibility
    // sit above it on this page.
    border.width: settingsRoot.rightFocused && settingsRoot.focusedItemIndex === 6 ? 1 : 0
    border.color: settingsRoot.accent
    visible: settingsRoot.barOpen

    Column {
      id: appLauncherIconContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 10

      Text {
        text: "Launcher Mark"
        font.family: settingsRoot.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: settingsRoot.textColor
      }

      // Selecting one both picks it (highlighted border) AND
      // immediately applies it -- same "no separate apply step"
      // convention the avatar picker above already uses. Flow, not a
      // fixed-column Grid: 111 tiles wrap naturally to however many
      // fit this panel's own width, same reasoning the avatar
      // picker's own Flow comment gives.
      Flow {
        width: parent.width
        spacing: 6

        Repeater {
          id: iconRepeater
          model: AppLauncherGlyphs.iconIds()

          Rectangle {
            id: iconBtn
            required property string modelData
            required property int index
            readonly property bool isCurrent: settingsRoot.appLauncherIconId === iconBtn.modelData
            // Keyboard cursor position, distinct from isCurrent (the
            // actually-applied value) -- same split collectionBtn's
            // own isFocused/isCurrent already establishes above for
            // the identical reason (an all-white border here would
            // clobber the accent ring's own "this is applied"
            // meaning).
            // 6 -- Bar Layout, Frame Border, Surface Color/Material,
            // Icon Tone, and Notch Visibility sit above it on this page.
            readonly property bool isFocused: settingsRoot.rightFocused
              && settingsRoot.focusedItemIndex === 6 && settingsRoot.focusedOptionIndex === iconBtn.index

            width: 32
            height: 32
            radius: 6
            color: iconBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08)
              : (iconMa.containsMouse ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
            border.width: 1
            border.color: iconBtn.isCurrent ? settingsRoot.accent
              : (iconMa.containsMouse ? Qt.rgba(1, 1, 1, 0.3) : Qt.rgba(1, 1, 1, 0.12))
            Behavior on border.color { ColorAnimation { duration: 120 } }
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
              anchors.centerIn: parent
              text: AppLauncherGlyphs.iconGlyph(iconBtn.modelData)
              font.family: settingsRoot.fontFamily
              font.pixelSize: 15
              color: iconBtn.isCurrent ? settingsRoot.textColor : settingsRoot.muted
            }

            // Keyboard-focus indicator -- same accent underline
            // convention collectionBtn's own isFocused treatment uses
            // above, adapted to sit inside this tile's own bounds
            // instead of below external label text (these tiles have
            // none).
            Rectangle {
              visible: iconBtn.isFocused
              anchors.bottom: parent.bottom
              anchors.bottomMargin: 3
              anchors.horizontalCenter: parent.horizontalCenter
              width: 14
              height: 2
              radius: 1
              color: settingsRoot.accent
            }

            MouseArea {
              id: iconMa
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: settingsRoot.setAppLauncherIconId(iconBtn.modelData)
            }
          }
        }
      }
    }
  }
}
