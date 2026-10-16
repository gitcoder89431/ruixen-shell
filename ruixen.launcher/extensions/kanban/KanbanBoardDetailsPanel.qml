import QtQuick
import "KanbanModel.js" as KanbanModel

// Right-pane detail for the selected card -- same zebra-striped label/
// value row shape FileDetailsPanel.qml originated and every other
// 2-panel extension in this plugin already reuses (ClipboardDetailsPanel.qml,
// CliampStationPanel.qml, ThemeBrowserContent.qml's own right pane).
// Read-only except for ONE narrow exception: a rename field that
// appears in place of the Title row when root.renaming is true --
// direct design call after "not sure how i would combine add/edit
// task here. two panel then on tab edit the right panel changes to
// input style or edit style?": the panel does NOT swap into a general
// edit form (no precedent for that anywhere in this plugin), it's one
// explicit action (Tab menu's own Rename) that opens one field, same
// narrow-inline-input shape AboutPage.qml's own uninstallConfirmField
// already uses for an identical "one deliberate text entry, not a
// whole form" need.
Rectangle {
  id: root

  property var row: null
  readonly property var card: row ? row.card : null
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  property bool renaming: false
  property string renameText: ""
  readonly property alias renameField: renameInput

  signal renameCommitted(string text)
  signal renameCancelled()

  // renameInput's own `text: root.renameText` binding below is only a
  // SEED -- once the user types into it, QML severs that binding (the
  // field's own keystrokes become the authoritative source), same as
  // any editable TextInput. Without this, a second rename later in the
  // same still-running launcher process redisplays whatever text was
  // left over from the FIRST rename, not the newly selected card's own
  // title -- confirmed live: renaming a second card showed the first
  // card's old (already-committed) text still sitting in the field.
  // Re-seeding imperatively on every renaming:true transition re-syncs
  // the field for real, regardless of whether the declarative binding
  // is still intact.
  onRenamingChanged: if (root.renaming) renameInput.text = root.renameText

  property bool editingDescription: false
  property string descriptionText: ""
  readonly property alias descriptionField: descriptionInput

  signal descriptionCommitted(string text)
  signal descriptionCancelled()

  // Same re-seed-on-every-open fix renameInput needed above -- see that
  // property's own comment for why a plain declarative binding isn't
  // enough once the field has been edited once.
  onEditingDescriptionChanged: if (editingDescription) descriptionInput.text = descriptionText

  readonly property var priorityColor: ({
    "high": "#e05252",
    "medium": root.textColor,
    "low": root.muted
  })

  function formatDate(epochMs) {
    if (!epochMs) return ""
    var d = new Date(epochMs)
    var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
    return months[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear()
  }

  readonly property bool overdue: !!card && KanbanModel.isOverdue(card, Date.now())

  // Skips anything with no value, same reasoning every other panel's
  // own metadataFields comment gives -- never leave the zebra tint (by
  // array position) with a gap over an empty row. Description is NOT
  // in this list -- it gets its own expanded, word-wrapped block right
  // under the title instead (see the Column below), not a single
  // elided line squeezed into this zebra shape with everything else.
  readonly property var metadataFields: {
    if (!root.card) return []
    var out = [
      { label: "Column", value: root.columnLabel },
      { label: "Priority", value: root.card.priority.charAt(0).toUpperCase() + root.card.priority.slice(1) }
    ]
    if (root.card.label !== "") out.push({ label: "Label", value: root.card.label })
    if (root.card.dueAt > 0) out.push({ label: "Due", value: root.formatDate(root.card.dueAt) + (root.overdue ? " (overdue)" : "") })
    out.push({ label: "Created", value: root.formatDate(root.card.createdAt) })
    return out
  }

  // The real column label (possibly renamed, e.g. "Backlog" instead of
  // "Todo") -- set externally by KanbanBoardContent.qml, which already
  // has the board's own columns list loaded.
  property string columnLabel: ""

  color: "transparent"
  radius: 12
  clip: true

  Column {
    anchors.fill: parent
    anchors.margins: 16
    spacing: 16
    visible: root.card !== null

    // --- Title, or the inline rename field in its place.
    Item {
      width: parent.width
      height: 28

      Text {
        visible: !root.renaming
        anchors.fill: parent
        verticalAlignment: Text.AlignVCenter
        elide: Text.ElideRight
        text: root.card ? root.card.title : ""
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 15
        font.weight: Font.DemiBold
      }

      Rectangle {
        visible: root.renaming
        anchors.fill: parent
        radius: 8
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: root.accent

        TextInput {
          id: renameInput
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          verticalAlignment: TextInput.AlignVCenter
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 13
          clip: true
          text: root.renameText
          onTextChanged: root.renameText = text
          onAccepted: root.renameCommitted(text)
          Keys.onEscapePressed: root.renameCancelled()
        }
      }
    }

    // --- Description, or the inline edit field in its place -- same
    // "one deliberate text entry, not a form" shape the rename field
    // above already uses, not a second general edit mode. Expanded and
    // word-wrapped here (this panel has the room), unlike the notch's
    // own always-single-elided-line treatment of the same field.
    Column {
      width: parent.width
      spacing: 6
      visible: root.card !== null && (root.card.description !== "" || root.editingDescription)

      Text {
        text: "Description"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 10
        font.capitalization: Font.AllUppercase
        font.bold: true
      }

      Text {
        visible: !root.editingDescription
        width: parent.width
        text: root.card ? root.card.description : ""
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 12
      }

      Rectangle {
        visible: root.editingDescription
        width: parent.width
        height: 32
        radius: 8
        color: Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: root.accent

        TextInput {
          id: descriptionInput
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 10
          verticalAlignment: TextInput.AlignVCenter
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 13
          clip: true
          text: root.descriptionText
          onTextChanged: root.descriptionText = text
          onAccepted: root.descriptionCommitted(text)
          Keys.onEscapePressed: root.descriptionCancelled()
        }
      }
    }

    Text {
      text: "Metadata"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: 10
      font.capitalization: Font.AllUppercase
      font.bold: true
    }

    Column {
      width: parent.width
      spacing: 0

      Repeater {
        model: root.metadataFields

        Item {
          id: field
          required property var modelData
          required property int index
          width: parent.width
          height: 26

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -10
            anchors.rightMargin: -10
            anchors.topMargin: -2
            anchors.bottomMargin: -2
            radius: 4
            color: field.index % 2 === 0 ? Qt.rgba(0, 0, 0, 0.18) : "transparent"
          }

          Text {
            id: fieldLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: field.modelData.label
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 11
            font.capitalization: Font.AllUppercase
          }
          Text {
            anchors.left: fieldLabel.right
            anchors.leftMargin: 12
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideMiddle
            text: field.modelData.value
            color: field.modelData.label === "Priority" && root.card
              ? root.priorityColor[root.card.priority]
              : (field.modelData.label === "Due" && root.overdue ? "#e05252" : root.textColor)
            font.family: root.fontFamily
            font.pixelSize: 12
          }
        }
      }
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.card === null
    text: "Select a task to see its details"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: 12
  }
}
