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

  // Display-only formatting -- KanbanModel.js stores dueAt as a plain
  // epoch millisecond number (locale-independent, easy to test in
  // Node); turning that into "Sep 12" is a view concern, kept here
  // rather than in the model.
  function formatDueDate(dueAt) {
    if (!(dueAt > 0)) return ""
    return Qt.formatDate(new Date(dueAt), "MMM d")
  }

  // Exposes the outer columnsRow's own measured width to KanbanColumn
  // (an inline `component`, so it cannot see a sibling id the way a
  // plain nested object could -- only this document's own root id is
  // reachable from inside it, same as every root.textColor/root.muted/
  // etc reference already relies on elsewhere in this file).
  property alias columnsRowWidth: columnsRow.width
  property alias columnsRowSpacing: columnsRow.spacing

  // In Progress reading wider than Todo/Done started as an accidental
  // side effect of switching the column wrapper to a ColumnLayout (see
  // KanbanColumn's own comment) -- direct follow-up once seen live: "i
  // kinda like it, makes it the focus, but make sure the code is
  // proper though." Made deliberate here: an explicit weight keyed off
  // each column's stable id, not its label (a column's label is
  // CLI/agent-renamable via kanbanRenameColumn and must never be able
  // to shift the layout just by being long or short). 1.8 reproduces
  // roughly the same proportions the accidental version happened to
  // land on (measured live: ~198px/365px/198px), just as an intentional
  // number instead of a coincidence of "In Progress" being a longer
  // string than "Todo"/"Done".
  function columnWidthWeight(columnId) {
    return columnId === "in-progress" ? 1.8 : 1
  }
  // Fixed 3-column board (see KanbanModel.js's own COLUMN_IDS comment:
  // "Deliberately fixed at exactly 3 columns, not a dynamic N-column"),
  // so the total weight is a constant, not something summed at
  // runtime over a variable column list.
  readonly property real totalColumnWeight: 1 + 1.8 + 1

  // Direct follow-up ("separate the header row... outside of the
  // panel? kinda feature it more"), matching Material 3's own pattern
  // of a section title sitting above its content surface rather than
  // baked into it. The column is now a two-piece ColumnLayout: a plain
  // header row directly on the notch background (no fill/radius -- it
  // is not itself a surface), then the tonal panel below holding only
  // the card area. Left/right Layout margins on the header mirror the
  // panel's own anchors.margins: 10 so the label lines up with the
  // card edges it is labeling, even though it is no longer a child of
  // that panel.
  component KanbanColumn: ColumnLayout {
    id: columnRoot
    required property var modelData
    readonly property string columnId: modelData.id
    readonly property var columnCards: root.kanbanService ? root.kanbanService.cardsInColumn(columnId) : []

    readonly property real widthWeight: root.columnWidthWeight(columnRoot.columnId)

    Layout.fillWidth: true
    Layout.fillHeight: true
    // A ColumnLayout auto-computes its own implicitWidth from its
    // children, unlike the plain Rectangle this used to be -- left
    // alone, the header's own natural text width (whichever label is
    // longest) would leak in as this column's Layout.preferredWidth
    // default (Qt Quick Layouts uses implicitWidth as that fallback),
    // and fillWidth only ever adds an equal slice of LEFTOVER space on
    // top of each column's own, already-unequal, natural size -- it
    // never rebalances the base allocation itself. That was the actual
    // bug the first two attempts here got wrong: Layout.minimumWidth
    // only matters when shrinking under space pressure (there was
    // none, so it changed nothing), and a blanket Layout.preferredWidth:
    // 0 does force genuinely equal thirds, but overwrote the very
    // emphasis on In Progress that turned out to be wanted once seen
    // live. Binding preferredWidth explicitly to this column's own
    // weight (see root.columnWidthWeight) replaces both -- the ratio is
    // now a deliberate constant instead of an emergent side effect of
    // whatever text happens to be in the header, and it sums to
    // exactly the available width, leaving fillWidth nothing ambiguous
    // to distribute.
    Layout.minimumWidth: 0
    Layout.preferredWidth: root.columnsRowWidth > 0
      ? (root.columnsRowWidth - 2 * root.columnsRowSpacing) * columnRoot.widthWeight / root.totalColumnWeight
      : 0
    spacing: 8

    // Header -- read-only. Renaming a column is CLI/agent-only
    // (kanbanRenameColumn), per direct request ("i rather do it from
    // cli or tui tbh") -- no in-panel typing at all, not just for
    // adding cards.
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: 10
      Layout.rightMargin: 10
      spacing: 6

      Text {
        Layout.fillWidth: true
        text: columnRoot.modelData.label
        color: root.textColor
        font.family: root.fontFamily
        // A size step up from the old in-panel version (12 -> 14, via
        // an intermediate 13) -- now that it reads as its own section
        // title instead of a row inside the card surface, it earns a
        // little more presence. Direct follow-up ("maybe a bit
        // bigger?") after seeing 13 live.
        font.pixelSize: 14
        font.bold: true
        elide: Text.ElideRight
      }

      // A small tonal pill instead of plain muted text -- Material 3's
      // own count-badge convention for a section header, and more
      // legible now that the header floats directly on the notch
      // background rather than the panel's own tonal fill behind it.
      // Sized from the count text's own implicitWidth (plus fixed
      // padding), not a hardcoded slot -- a header count only ever
      // changes on a card add/move/remove, a discrete state change,
      // never a live-updating number, so there is no rapid-resize
      // flicker risk the way a live percentage elsewhere in this
      // plugin family has to guard against.
      Rectangle {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: Math.max(countText.implicitHeight, countText.implicitWidth + 12)
        implicitHeight: countText.implicitHeight + 6
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.12)

        Text {
          id: countText
          anchors.centerIn: parent
          text: String(columnRoot.columnCards.length)
          color: root.textColor
          font.family: root.fontFamily
          // Sized up alongside the label (10 -> 11) -- direct
          // follow-up ("maybe a bit bigger?"). The pill itself needs
          // no separate change: its own implicitWidth/implicitHeight
          // are already derived from this Text's own size above.
          font.pixelSize: 11
          font.bold: true
        }
      }
    }

    // The panel itself is now just the card surface -- same tonal fill
    // and no-border floating look as before, just without the header
    // baked in. Direct request, unchanged from the original panel:
    // "we dont need thick borders on the panel they float".
    Rectangle {
      Layout.fillWidth: true
      Layout.fillHeight: true
      radius: 10
      color: Qt.rgba(1, 1, 1, 0.06)

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
        anchors.fill: parent
        anchors.margins: 10

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
                // Accent border on hover -- direct request ("better
                // visibility on hover of the row... so i know what im
                // clicking or moving around"). A plain border directly
                // on this Rectangle, unlike the notification row's own
                // top-layer overlay trick -- that workaround exists
                // there specifically because a thumbnail image paints
                // over a Rectangle's own border; this card has no such
                // overlapping content, so the direct border just works.
                border.color: cardArea.containsMouse ? root.accent : "transparent"
                border.width: 1.5
                Behavior on border.color { ColorAnimation { duration: 100 } }

                // Whole-row click, no chevrons -- direct follow-up
                // ("i need the same pattern to go back from done to in
                // progress... just click to advance or dismiss and
                // right click to back"). Right-click is now uniformly
                // "go back" on every column, no exception (a no-op on
                // Todo, nothing before it, already handled by
                // prevColumnId's own clamp). Left-click advances one
                // step everywhere except Done, where there's nothing
                // after it, so it dismisses instead -- the terminal
                // version of "the forward action" rather than a no-op.
                MouseArea {
                  id: cardArea
                  anchors.fill: parent
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: function(mouse) {
                    if (!root.kanbanService) return
                    if (mouse.button === Qt.RightButton) {
                      root.kanbanService.regressCard(cardRoot.modelData.id)
                    } else if (columnRoot.columnId === "done") {
                      root.kanbanService.removeCard(cardRoot.modelData.id)
                    } else {
                      root.kanbanService.advanceCard(cardRoot.modelData.id)
                    }
                  }
                }

                // ColumnLayout, not a single row, now that a card can
                // carry a description line plus a label/due-date row
                // below its title -- direct follow-up requesting all
                // three fields. An invisible QtQuick.Layouts child
                // reserves no space, so a card with none of them set
                // (every card before this pass, and any new one that
                // never gets any) renders byte-for-byte the same
                // single-row height as before -- confirmed live, not
                // assumed.
                ColumnLayout {
                  id: cardContent
                  anchors.fill: parent
                  anchors.margins: 8
                  spacing: 2

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // Priority dot on every column except Done, where a
                    // green checkmark takes its place instead -- direct
                    // follow-up ("instead of the check green being on
                    // the right, can we just replace the dots with the
                    // check on done then"). Both live inside one fixed-
                    // size wrapper Item (not two separately-toggled
                    // RowLayout siblings) -- Qt Quick Layouts don't
                    // collapse an invisible item's own reserved space, so
                    // two visibility-toggled Layout children here would
                    // leave a gap; plain anchored children of one
                    // Layout-managed wrapper sidesteps that entirely.
                    // Read-only either way, no click handler -- the
                    // agent sets priority via kanbanSetPriority/
                    // kanbanAddCard, this just displays it.
                    Item {
                      Layout.preferredWidth: 10
                      Layout.preferredHeight: 10
                      Layout.alignment: Qt.AlignVCenter

                      Rectangle {
                        visible: columnRoot.columnId !== "done"
                        anchors.centerIn: parent
                        width: 6
                        height: 6
                        radius: 3
                        // Red/yellow/muted for high/medium/low -- medium
                        // reuses the same yellow the settings page's own
                        // "pending update" dot already established.
                        color: cardRoot.modelData.priority === "high" ? "#e05252"
                          : cardRoot.modelData.priority === "low" ? root.muted
                          : "#e8c34a"
                      }

                      Text {
                        visible: columnRoot.columnId === "done"
                        anchors.centerIn: parent
                        text: "✓"
                        color: "#3ecf5b"
                        font.pixelSize: 13
                      }
                    }

                    Text {
                      Layout.fillWidth: true
                      text: cardRoot.modelData.title
                      color: root.textColor
                      font.family: root.fontFamily
                      font.pixelSize: 11
                      wrapMode: Text.WordWrap
                    }
                  }

                  // Description -- always a single elided line, never
                  // wrapped, unlike the title above. Direct request:
                  // "i wanna see a short title and description... the
                  // notch kanban should feel more like observation or
                  // monitor kinda feel" -- a card here is a glance
                  // surface, so this can never grow taller than one
                  // line no matter how it is set. CLI/agent-set only
                  // (kanbanSetDescription), same "no in-panel typing"
                  // rule as everything else here. leftMargin 16 lines
                  // it up under the title, same as the meta row below.
                  Text {
                    visible: cardRoot.modelData.description !== ""
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    text: cardRoot.modelData.description
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    elide: Text.ElideRight
                    maximumLineCount: 1
                  }

                  // Label + due date -- both optional, CLI/agent-set
                  // only (kanbanSetLabel/kanbanSetDueDate), same "no
                  // in-panel typing" rule as everything else here.
                  // leftMargin 16 lines it up under the title, past the
                  // priority dot's own 10px slot + 6px spacing above.
                  RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    spacing: 6
                    visible: cardRoot.modelData.label !== "" || cardRoot.modelData.dueAt > 0

                    Text {
                      visible: cardRoot.modelData.label !== ""
                      Layout.maximumWidth: 90
                      text: cardRoot.modelData.label
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: 9
                      elide: Text.ElideRight
                    }

                    // The sole flexible element -- pushes the due date
                    // to the row's right edge whether or not a label is
                    // also present (a label-only fillWidth would only
                    // do that when both are shown).
                    Item { Layout.fillWidth: true }

                    // Red once actually overdue -- KanbanModel.isOverdue
                    // already excludes Done (a shipped card is not
                    // late), so this can never flag a finished card.
                    Text {
                      visible: cardRoot.modelData.dueAt > 0
                      text: root.formatDueDate(cardRoot.modelData.dueAt)
                      color: KanbanModel.isOverdue(cardRoot.modelData, Date.now()) ? "#e05252" : root.muted
                      font.family: root.fontFamily
                      font.pixelSize: 9
                    }
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

  RowLayout {
    id: columnsRow
    anchors.fill: parent
    // Extra clearance on the right -- direct report ("thrid panel
    // sits too close to edge"), confirmed live: the Done column's own
    // right edge sat only a few px from the notch's own curved right
    // edge. Same fix, same value, as MetricsContent.qml's own
    // Layout.rightMargin: 10 on its stat-tile grid (its own comment:
    // "the expanded panel's outer anchors.rightMargin... wasn't enough
    // breathing room on its own for this dense a grid") -- this tab is
    // the same shape of problem, a full-width grid of tonal panels
    // reaching the panel's own right edge.
    anchors.rightMargin: 10
    // Same reasoning, bottom edge -- direct follow-up: "the buttom of
    // the panel stil ends too close to the buttom of the notch edge".
    // The notch's own signature shape has its rounded corners at the
    // BOTTOM (see Overlay.qml's own bottomLeftRadius/bottomRightRadius
    // on the notch shape itself), so a full-height panel reaching the
    // shared 12px outer bottomMargin needs real clearance from that
    // curve, same as the right edge did.
    anchors.bottomMargin: 10
    spacing: 8

    Repeater {
      model: root.kanbanService ? root.kanbanService.columns : []
      delegate: KanbanColumn {}
    }
  }
}
