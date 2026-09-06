import QtQuick
import QtQuick.Layouts

// 4th dashboard tab -- a fixed 3-column Kanban board (Todo/In
// Progress/Done by default), backed by KanbanService.qml. Direct
// request: "less dynamic fill stuff to worry about" -- exactly 3
// columns always, only a column's own label is editable, never the
// count, which sidesteps the whole class of Layout-collapse bugs a
// variable-width/count layout would otherwise risk (this session
// already hit several of those elsewhere in this same plugin).
//
// Agent-native by design: KanbanService.qml's own functions
// (addCard/moveCard/removeCard/renameColumn) are also real IpcHandler
// functions on Overlay.qml's "ruixen.notch" target, so the board is
// meant to be driven from the CLI just as much as by hand here.
Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"
  property var kanbanService: null

  // Same OLED-black-card + subtle grey frame language already
  // established for the notification history cards in
  // DashboardContent.qml (color: "#000000", a translucent white
  // border rather than solid black -- solid black would be invisible
  // against this same black background).
  component KanbanColumn: Rectangle {
    id: columnRoot
    required property var modelData
    readonly property string columnId: modelData.id
    readonly property var columnCards: root.kanbanService ? root.kanbanService.cardsInColumn(columnId) : []

    Layout.fillWidth: true
    Layout.fillHeight: true
    radius: 10
    color: "#000000"
    border.color: Qt.rgba(1, 1, 1, 0.14)
    border.width: 1.5

    property bool editingLabel: false

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 10
      spacing: 8

      // Header -- click the label to rename it in place (the manual
      // path; renameColumn is also a real IPC function for the agent
      // path). Count badge next to it is read-only either way.
      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
          visible: !columnRoot.editingLabel
          Layout.fillWidth: true
          text: columnRoot.modelData.label
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 12
          font.bold: true
          elide: Text.ElideRight

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              columnLabelInput.text = columnRoot.modelData.label
              columnRoot.editingLabel = true
              columnLabelInput.forceActiveFocus()
              columnLabelInput.selectAll()
            }
          }
        }

        TextInput {
          id: columnLabelInput
          visible: columnRoot.editingLabel
          Layout.fillWidth: true
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 12
          font.bold: true

          function commit() {
            if (root.kanbanService && text.trim() !== "")
              root.kanbanService.renameColumn(columnRoot.columnId, text.trim())
            columnRoot.editingLabel = false
          }

          onAccepted: commit()
          onActiveFocusChanged: if (!activeFocus) commit()
          Keys.onEscapePressed: columnRoot.editingLabel = false
        }

        Text {
          text: String(columnRoot.columnCards.length)
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 10
        }
      }

      // Cards -- oldest first (KanbanService.cardsInColumn's own
      // order). No drag-and-drop: the manual path is the arrow pair
      // below (advance/regress one column), the primary path is the
      // agent calling moveCard directly. A plain Column, not a
      // ListView -- a handful of short text cards per column, no
      // scrolling machinery needed for that.
      Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        clip: true
        contentHeight: cardsColumn.implicitHeight
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
          id: cardsColumn
          width: parent.width
          spacing: 6

          Repeater {
            model: columnRoot.columnCards

            Rectangle {
              id: cardRoot
              required property var modelData
              Layout.fillWidth: true
              Layout.preferredHeight: cardContent.implicitHeight + 16
              radius: 8
              color: Qt.rgba(1, 1, 1, 0.06)

              RowLayout {
                id: cardContent
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                Text {
                  Layout.fillWidth: true
                  text: cardRoot.modelData.title
                  color: root.textColor
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  wrapMode: Text.WordWrap
                }

                // Regress -- hidden on the first column, nothing to
                // regress to.
                Text {
                  visible: columnRoot.columnId !== "todo"
                  text: "‹"
                  color: regressArea.containsMouse ? root.textColor : root.muted
                  font.pixelSize: 13

                  MouseArea {
                    id: regressArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.kanbanService) root.kanbanService.regressCard(cardRoot.modelData.id)
                  }
                }

                // Advance -- hidden on the last column, nothing to
                // advance to.
                Text {
                  visible: columnRoot.columnId !== "done"
                  text: "›"
                  color: advanceArea.containsMouse ? root.textColor : root.muted
                  font.pixelSize: 13

                  MouseArea {
                    id: advanceArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.kanbanService) root.kanbanService.advanceCard(cardRoot.modelData.id)
                  }
                }

                Text {
                  text: "✕"
                  font.pixelSize: 11
                  color: removeArea.containsMouse ? Qt.lighter("#e05252", 1.25) : "#e05252"

                  MouseArea {
                    id: removeArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (root.kanbanService) root.kanbanService.removeCard(cardRoot.modelData.id)
                  }
                }
              }
            }
          }
        }
      }

      // Add card -- collapsed to a plain "+" until clicked, matching
      // the dismiss-X-on-hover precedent elsewhere in this plugin of
      // not showing every possible action at once. Direct request
      // acknowledged this is the secondary path ("i dont see myself
      // ever typing shit out"), so it stays minimal: one line, Enter
      // to commit, no rich fields.
      Text {
        visible: !addCardInput.visible
        text: "+ Add card"
        color: addCardArea.containsMouse ? root.textColor : root.muted
        font.family: root.fontFamily
        font.pixelSize: 11

        MouseArea {
          id: addCardArea
          anchors.fill: parent
          anchors.margins: -4
          cursorShape: Qt.PointingHandCursor
          onClicked: {
            addCardInput.text = ""
            addCardInput.visible = true
            addCardInput.forceActiveFocus()
          }
        }
      }

      Rectangle {
        visible: addCardInput.visible
        Layout.fillWidth: true
        Layout.preferredHeight: 26
        radius: 6
        color: Qt.rgba(1, 1, 1, 0.06)

        TextInput {
          id: addCardInput
          visible: false
          anchors.fill: parent
          anchors.leftMargin: 8
          anchors.rightMargin: 8
          verticalAlignment: TextInput.AlignVCenter
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 11
          clip: true

          function commit() {
            if (root.kanbanService && text.trim() !== "")
              root.kanbanService.addCard(text.trim(), columnRoot.columnId)
            visible = false
          }

          onAccepted: commit()
          onActiveFocusChanged: if (!activeFocus) visible = false
          Keys.onEscapePressed: visible = false
        }
      }
    }
  }

  RowLayout {
    anchors.fill: parent
    spacing: 8

    Repeater {
      model: root.kanbanService ? root.kanbanService.columns : []
      delegate: KanbanColumn {}
    }
  }
}
