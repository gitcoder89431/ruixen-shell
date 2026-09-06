import QtQuick
import QtQuick.Layouts
import "KanbanModel.js" as KanbanModel

// 4th dashboard tab -- a fixed 3-column Kanban board (Todo/In
// Progress/Done by default), backed by KanbanService.qml. Direct
// request: "less dynamic fill stuff to worry about" -- exactly 3
// columns always, only a column's own label is editable, never the
// count, which sidesteps the whole class of Layout-collapse bugs a
// variable-width/count layout would otherwise risk (this session
// already hit several of those elsewhere in this same plugin).
//
// Agent-native by design, and CLI-only for any TEXT ENTRY -- direct
// request ("i rather do it from cli or tui tbh"): adding a card and
// renaming a column both go through KanbanService.qml's own functions
// via Overlay.qml's "ruixen.notch" IpcHandler target
// (kanbanAddCard/kanbanRenameColumn/...), never an in-panel TextInput.
// This panel is otherwise mouse-driven (advance/regress/remove a
// card), just never for typing a title or a label.
Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"
  property var kanbanService: null

  // Direct request: the column panel itself reads as a grey tonal
  // surface (same translucent-white fill this plugin already uses for
  // dial backgrounds/toggle tracks), with the cards inside it as
  // black-on-white-text instead -- swapped from the first pass, which
  // had this inverted (black panel, grey cards). Matches the
  // notification history cards' own black/white contrast for the same
  // reason: better readability.
  component KanbanColumn: Rectangle {
    id: columnRoot
    required property var modelData
    readonly property string columnId: modelData.id
    readonly property var columnCards: root.kanbanService ? root.kanbanService.cardsInColumn(columnId) : []

    Layout.fillWidth: true
    Layout.fillHeight: true
    radius: 10
    // No border -- a tonal panel like this floats on its own fill,
    // per direct request ("we dont need thick borders on the panel
    // they float").
    color: Qt.rgba(1, 1, 1, 0.06)

    ColumnLayout {
      anchors.fill: parent
      anchors.margins: 10
      spacing: 8

      // Header -- read-only. Renaming a column is CLI/agent-only
      // (kanbanRenameColumn), per direct request ("i rather do it from
      // cli or tui tbh") -- no in-panel typing at all, not just for
      // adding cards.
      RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Text {
          Layout.fillWidth: true
          text: columnRoot.modelData.label
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 12
          font.bold: true
          elide: Text.ElideRight
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
      // Wrapping Item, not just the Flickable directly -- the empty-
      // state Text below is a SIBLING of the Flickable, centered in
      // this whole card area, rather than a child of cardsColumn
      // (a top-down ColumnLayout, which only ever put it near the top
      // of the column, not centered in the available height). Direct
      // follow-up: "the empty text are center but not middle".
      Item {
        Layout.fillWidth: true
        Layout.fillHeight: true

        Text {
          visible: columnRoot.columnCards.length === 0
          anchors.centerIn: parent
          text: KanbanModel.emptyStateLabel(columnRoot.columnId)
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 11
        }

        Flickable {
          anchors.fill: parent
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
                // Black card, white text -- same contrast as the
                // notification history cards, better readability than
                // the grey tonal fill this used before.
                color: "#000000"

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
      }

      // No in-panel "add card"/rename input -- CLI/agent-only for any
      // text entry (kanbanAddCard/kanbanRenameColumn), per direct
      // request ("i rather do it from cli or tui tbh"). Advancing,
      // regressing, and removing a card stay mouse-driven here since
      // those are plain clicks, not typing.
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
