import QtQuick

// Shared "add + list" item card -- Custom Search Roots and Excluded
// Paths are the exact same shape (a text input + Add button, then a
// vertical list of full-width rows each with a ✕ remove), and Excluded
// Directory Names is the same add-row with a wrapped chip list instead
// of a vertical one (short single-word names read better dense-packed
// than one per line) -- `chipMode` switches just that part. Three real
// uses justify the one component, same reasoning as
// SettingsSegmentedItem.qml/SettingsToggleRow.qml's own header
// comments.
//
// `items` is a plain array of strings; this component owns no state of
// its own beyond the input text -- add/remove are signals, the caller
// (SettingsContent.qml) still owns the real launcherSearchConfig data
// and persistence, same split every other item in this file already
// uses.
Rectangle {
  id: root

  property string label: ""
  property string placeholder: ""
  property var items: []
  property bool chipMode: false
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"
  // Tab/Up-Down-focused card ring, same convention SettingsSegmentedItem
  // uses -- direct follow-up: "why wouldnt the text entry work... i
  // just tab and go to it with d pad then type and enter to add."
  // Shown as soon as keyboard nav lands here, same moment Enter would
  // hand this card real Qt focus (see focusTextInput() below).
  property bool cardFocused: false

  signal added(string value)
  signal removed(string value)
  // Escape while actually typing -- real Qt focus needs somewhere to
  // go back to (SettingsContent.qml relays this up to Launcher.qml's
  // own searchHeader.focusInput(), the exact same handoff the search
  // box itself already uses on open).
  signal cancelled()

  // Called by SettingsContent.qml's own activateFocusedOption() when
  // Enter is pressed with this card as the keyboard-focused item --
  // hands real Qt focus to the actual TextInput, so typing just works
  // natively (arrow keys move the text cursor, not list navigation)
  // for as long as it holds focus.
  function focusTextInput() { input.forceActiveFocus() }

  width: parent.width
  height: content.implicitHeight + 24
  radius: 10
  color: Qt.rgba(0, 0, 0, 0.18)
  border.width: root.cardFocused ? 1 : 0
  border.color: root.accent

  Column {
    id: content
    anchors.fill: parent
    anchors.margins: 12
    spacing: 10

    Text {
      text: root.label
      font.family: root.fontFamily
      font.pixelSize: 12
      font.weight: Font.DemiBold
      color: root.textColor
    }

    Item {
      width: parent.width
      height: 28

      Rectangle {
        id: inputBox
        anchors.left: parent.left
        anchors.right: addBtn.left
        anchors.rightMargin: 6
        height: 28
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.12)

        TextInput {
          id: input
          anchors.fill: parent
          anchors.leftMargin: 8
          anchors.rightMargin: 8
          verticalAlignment: TextInput.AlignVCenter
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 12
          clip: true

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.placeholder
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 12
            visible: input.text.length === 0
          }

          Keys.onReturnPressed: { root.added(input.text); input.text = "" }
          // Hands real focus back out rather than closing anything --
          // the outer Escape (once real focus is back on the search
          // box) still backs out of keyboard-focus mode one level at a
          // time, same as every other item.
          Keys.onEscapePressed: root.cancelled()
        }
      }

      Rectangle {
        id: addBtn
        anchors.right: parent.right
        width: 50
        height: 28
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.08)

        Text {
          anchors.centerIn: parent
          text: "Add"
          font.family: root.fontFamily
          font.pixelSize: 12
          color: root.textColor
        }

        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: { root.added(input.text); input.text = "" }
        }
      }
    }

    Column {
      width: parent.width
      spacing: 6
      visible: !root.chipMode

      Repeater {
        model: root.items

        Item {
          id: listRow
          required property var modelData
          width: parent.width
          height: 20

          Text {
            anchors.left: parent.left
            anchors.right: removeGlyph.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: listRow.modelData
            font.family: root.fontFamily
            font.pixelSize: 12
            color: root.textColor
            elide: Text.ElideMiddle
          }

          Text {
            id: removeGlyph
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: "✕"
            font.family: root.fontFamily
            font.pixelSize: 12
            color: root.muted

            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: root.removed(listRow.modelData)
            }
          }
        }
      }
    }

    Flow {
      width: parent.width
      spacing: 6
      visible: root.chipMode

      Repeater {
        model: root.items

        Rectangle {
          id: chip
          required property var modelData
          width: chipRow.implicitWidth + 16
          height: 24
          radius: 6
          color: Qt.rgba(1, 1, 1, 0.06)
          border.width: 1
          border.color: Qt.rgba(1, 1, 1, 0.12)

          Row {
            id: chipRow
            anchors.centerIn: parent
            spacing: 6

            Text {
              text: chip.modelData
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.textColor
            }
            Text {
              text: "✕"
              font.family: root.fontFamily
              font.pixelSize: 11
              color: root.muted

              MouseArea {
                anchors.fill: parent
                anchors.margins: -4
                cursorShape: Qt.PointingHandCursor
                onClicked: root.removed(chip.modelData)
              }
            }
          }
        }
      }
    }
  }
}
