import QtQuick

// Layout-only shell for the "Settings" extension -- direct request:
// "lets do the Settings as Extension so Settings 2nd Column Ruixen and
// type extension? itll be similar to the 2 panel layout where we have
// the Profile Launcher Bluetooth menu options on the left panel, then
// enter to go into the right panel where we have toggles and inputs
// and options. dont build out the whole thing yet... just start with
// the layout first then we can work on the panels?" -- so this is
// deliberately navigation + chrome only: a left category list (same 8
// sections ruixen.settings/Settings.qml already ships, same ids/
// labels/glyphs, ported not reinvented) and a right panel that shows
// only a "coming soon" placeholder once a category is opened. No
// toggles/inputs/real per-section content yet -- that's explicit
// later work.
//
// Deliberately its own list, not a reuse of ResultsList/ResultRow --
// those are wired to Launcher.qml's own result-row shape (score,
// sectionLabel grouping, provider dispatch, hover-arm gating) for a
// flat, virtualized, potentially-hundreds-of-rows list. 8 fixed
// category rows need none of that; a plain Column mirrors
// ruixen.settings' own sidebar (Rectangle rows, kbd-focus ring +
// selected fill, icon-in-a-fixed-width-slot + label) far more directly
// than bending a virtualized ListView to fit.
Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"
  property bool active: false

  // Same 8 sections, same ids/labels/glyphs as ruixen.settings/
  // Settings.qml's own root.sections -- confirmed by reading that file
  // directly, not guessed, so this list reads as the same feature, not
  // a fork of it. Glyph codepoints copied byte-for-byte from there too.
  readonly property var sections: [
    { id: "general", label: "Profile", glyph: "" },
    { id: "launcher", label: "Launcher", glyph: "" },
    { id: "audio", label: "Audio", glyph: "" },
    { id: "wifi", label: "Wi-Fi", glyph: "" },
    { id: "bluetooth", label: "Bluetooth", glyph: "" },
    { id: "display", label: "Display", glyph: "" },
    { id: "plugins", label: "Plugins", glyph: "" },
    { id: "about", label: "About", glyph: "" }
  ]

  // Keyboard cursor over the left list -- Up/Down move this; it does
  // NOT by itself change what the right panel shows (see openIndex
  // below), matching the user's own "then enter to go into the right
  // panel" phrasing rather than a live-preview-on-hover model.
  property int selectedIndex: 0
  // -1 means the right panel shows its own neutral empty state (no
  // category opened yet this session). Set by activateSelection()
  // (Enter), not by moveSelectionUp/Down.
  property int openIndex: -1

  function moveSelectionUp() {
    if (root.selectedIndex > 0) root.selectedIndex--
  }
  function moveSelectionDown() {
    if (root.selectedIndex < root.sections.length - 1) root.selectedIndex++
  }
  function activateSelection() {
    root.openIndex = root.selectedIndex
  }

  // Fresh state every time the extension is (re)entered -- same
  // "no stale cursor from last time" convention onFilesModeChanged/
  // onOpenedChanged already apply elsewhere in this plugin.
  onActiveChanged: {
    if (root.active) {
      root.selectedIndex = 0
      root.openIndex = -1
    }
  }

  Row {
    anchors.fill: parent
    spacing: 8

    Column {
      id: sidebar
      width: 180
      height: parent.height
      spacing: 4

      Repeater {
        model: root.sections

        Rectangle {
          id: sectionRow
          required property var modelData
          required property int index
          readonly property bool kbdFocused: root.selectedIndex === sectionRow.index
          readonly property bool opened: root.openIndex === sectionRow.index

          width: sidebar.width
          height: 32
          radius: 8
          color: sectionRow.opened ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
          border.width: sectionRow.kbdFocused ? 1 : 0
          border.color: root.accent

          Row {
            anchors.fill: parent
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            spacing: 8

            Item {
              width: 18
              height: parent.height

              Text {
                anchors.centerIn: parent
                text: sectionRow.modelData.glyph
                font.family: root.fontFamily
                font.pixelSize: 13
                color: sectionRow.opened ? root.accent : root.muted
              }
            }

            Text {
              text: sectionRow.modelData.label
              font.family: root.fontFamily
              font.pixelSize: 12
              font.weight: sectionRow.opened ? Font.DemiBold : Font.Normal
              color: sectionRow.opened ? root.textColor : root.muted
              anchors.verticalCenter: parent.verticalCenter
            }
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.selectedIndex = sectionRow.index
              root.openIndex = sectionRow.index
            }
          }
        }
      }
    }

    // Divider -- same vertical gradient line Launcher.qml itself draws
    // between resultsList and detailsPanel in Search Files mode, ported
    // in place here since this component owns its own two-pane split
    // rather than anchoring off Launcher.qml's siblings.
    Rectangle {
      width: 1
      height: parent.height
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.rgba(1, 1, 1, 0) }
        GradientStop { position: 0.3; color: Qt.rgba(1, 1, 1, 0.12) }
        GradientStop { position: 0.7; color: Qt.rgba(1, 1, 1, 0.12) }
        GradientStop { position: 1.0; color: Qt.rgba(1, 1, 1, 0) }
      }
    }

    // Right panel -- ghost surface, no fill of its own, same treatment
    // FileDetailsPanel.qml already gives Search Files' own detail pane
    // (direct precedent: "ghost it on the spotlight"). Just a
    // placeholder for now -- no toggles/inputs, per explicit scope.
    Item {
      width: parent.width - sidebar.width - 8 - 1
      height: parent.height

      Column {
        anchors.centerIn: parent
        spacing: 6
        visible: root.openIndex === -1

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: ""
          font.family: root.fontFamily
          font.pixelSize: 22
          color: root.muted
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Select a category and press Enter"
          font.family: root.fontFamily
          font.pixelSize: 12
          color: root.muted
        }
      }

      Column {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        spacing: 4
        visible: root.openIndex >= 0

        Text {
          text: root.openIndex >= 0 ? root.sections[root.openIndex].label : ""
          font.family: root.fontFamily
          font.pixelSize: 15
          font.weight: Font.DemiBold
          color: root.textColor
        }
        Text {
          text: "Coming soon"
          font.family: root.fontFamily
          font.pixelSize: 12
          color: root.muted
        }
      }
    }
  }
}
