import QtQuick
import QtQuick.Effects
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
// Agent-native AND mouse/type friendly in-panel now. The board was
// originally CLI-only for any TEXT ENTRY (direct request at the time:
// "i rather do it from cli or tui tbh") with only advance/regress/
// remove as clicks -- REVERSED by a later direct request: "right now
// its not GUI friendly, meaning i can't manage tasks from there. i
// wanna be able to add, edit, delete check progress on the notch". So
// the panel now has its own add/edit/delete/progress affordances
// (per-column "+" with an inline new-card editor, per-card hover
// edit/delete with a two-click delete confirm, and a done/total
// progress row), all calling the exact same KanbanService.qml
// functions Overlay.qml's "ruixen.notch" IpcHandler target exposes
// (kanbanAddCard/kanbanRenameCard/kanbanRemoveCard/...) -- the panel
// and a CLI caller are the same API, neither is a second
// implementation. Column LABELS stay CLI-only (kanbanRenameColumn) --
// not part of that request, and the fixed-label layout guarantees
// this file's own comments document depend on them.
Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property color confirmColor: accent
  property color successColor: "#3ecf5b"
  property color dangerColor: "#e05252"
  property color warningColor: "#e8c34a"
  property color cardSurface: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.035)
  property color cardBorderColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.12)
  property color editorSurface: Qt.darker(cardSurface, 1.08)
  readonly property color readableAccentColor: readableSemanticColor(accent)
  property string fontFamily: "JetBrainsMono Nerd Font"
  property var kanbanService: null

  // ---- In-panel editing state (the GUI path -- see this file's own
  // header comment for why it exists now). Exactly ONE editor open at
  // a time across the whole board: opening an add or an edit closes
  // the other, so there is never a question of which surface a
  // keystroke belongs to.
  property string addColumnId: ""   // column with an open "new card" row ("" = none)
  property string addPriority: "medium"
  property string editingCardId: "" // card with an open inline editor ("" = none)
  property string editPriority: "medium"
  property string deleteArmedId: "" // card whose delete button is armed for its confirming second click

  function colorLuminance(c) {
    return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
  }

  function readableSemanticColor(c) {
    // Some Omarchy themes intentionally use muted semantic swatches
    // (Miasma red is closer to brown than alert red). Tiny action
    // glyphs need more contrast than full-size themed surfaces, so pull
    // weak semantic tokens toward the readable text color while keeping
    // the theme hue instead of hardcoding one global red/green/blue.
    var colorLum = root.colorLuminance(c)
    var textLum = root.colorLuminance(root.textColor)
    var needsLift = textLum > 0.5 && colorLum < 0.55
    var needsDrop = textLum <= 0.5 && colorLum > 0.55
    if (!needsLift && !needsDrop) return c
    var mix = needsLift ? 0.52 : 0.42
    return Qt.rgba(
      c.r + (root.textColor.r - c.r) * mix,
      c.g + (root.textColor.g - c.g) * mix,
      c.b + (root.textColor.b - c.b) * mix,
      c.a
    )
  }

  component KanbanActionButton : Rectangle {
    id: actionButton

    property string icon: ""
    property string iconFamily: ""
    property int iconPixelSize: 13
    property color accentColor: "#3ecf5b"
    property color idleColor: Qt.rgba(1, 1, 1, 0.08)
    property bool armed: false
    readonly property bool hovered: actionMouse.containsMouse
    readonly property color resolvedAccentColor: root.readableSemanticColor(accentColor)

    signal clicked()

    width: 20
    height: 20
    radius: 6
    color: (armed || hovered) ? resolvedAccentColor : idleColor

    Text {
      anchors.centerIn: parent
      text: actionButton.icon
      color: (actionButton.armed || actionButton.hovered) ? "#000000" : actionButton.resolvedAccentColor
      font.family: actionButton.iconFamily
      font.pixelSize: actionButton.iconPixelSize
    }

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: actionButton.clicked()
    }
  }

  component KanbanPriorityPill : Rectangle {
    id: priorityPill

    property string priority: "medium"

    signal clicked()

    implicitWidth: priorityLabel.implicitWidth + 30
    implicitHeight: priorityLabel.implicitHeight + 6
    radius: height / 2
    color: Qt.rgba(1, 1, 1, 0.10)

    Row {
      anchors.centerIn: parent
      spacing: 4

      Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: 6
        height: 6
        radius: 3
        color: priorityPill.priority === "high" ? root.dangerColor
          : priorityPill.priority === "low" ? root.muted
          : root.warningColor
      }

      Text {
        id: priorityLabel
        anchors.verticalCenter: parent.verticalCenter
        text: priorityPill.priority
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 9
      }
    }

    MouseArea {
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onClicked: priorityPill.clicked()
    }
  }

  function openAdd(columnId) {
    root.editingCardId = ""
    root.deleteArmedId = ""
    root.addPriority = "medium"
    root.addColumnId = columnId
  }

  function openEdit(card) {
    root.addColumnId = ""
    root.deleteArmedId = ""
    root.editPriority = card.priority
    root.editingCardId = card.id
  }

  function cyclePriority(priority) {
    return priority === "medium" ? "high" : priority === "high" ? "low" : "medium"
  }

  // Progress row inputs -- done/total across the whole board. cards is
  // reassigned (never mutated in place) on every KanbanService
  // mutation, so both bindings re-evaluate on any add/move/remove.
  readonly property int totalCards: kanbanService ? kanbanService.cards.length : 0
  readonly property int doneCards: kanbanService ? kanbanService.cardsInColumn("done").length : 0
  readonly property real doneRatio: totalCards > 0 ? Math.min(doneCards / totalCards, 1) : 0
  readonly property int donePercent: Math.round(doneRatio * 100)

  // Delete confirm window -- a second click on the same card's delete
  // button inside this window removes the card; letting it lapse
  // disarms. A dialog would be a third surface convention this plugin
  // doesn't have; the armed button itself IS the confirmation.
  Timer {
    interval: 3000
    running: root.deleteArmedId !== ""
    onTriggered: root.deleteArmedId = ""
  }

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

    // Header -- the label itself stays read-only (renaming a column is
    // still CLI/agent-only via kanbanRenameColumn; not part of the GUI
    // request). The label and count share one compact pill; the add/
    // clear action is a separate wider click target.
    RowLayout {
      Layout.fillWidth: true
      Layout.leftMargin: 10
      Layout.rightMargin: 10
      spacing: 6

      Rectangle {
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: headerLabelRow.implicitWidth + 18
        implicitHeight: 24
        radius: height / 2
        color: Qt.rgba(1, 1, 1, 0.08)

        Row {
          id: headerLabelRow
          anchors.centerIn: parent
          spacing: 6

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: columnRoot.modelData.label
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 12
            font.bold: true
            elide: Text.ElideRight
          }

          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            implicitWidth: Math.max(18, countText.implicitWidth + 10)
            implicitHeight: 18
            radius: height / 2
            color: Qt.rgba(root.readableAccentColor.r, root.readableAccentColor.g, root.readableAccentColor.b, 0.16)

            Text {
              id: countText
              anchors.centerIn: parent
              horizontalAlignment: Text.AlignHCenter
              text: String(columnRoot.columnCards.length)
              color: root.readableAccentColor
              font.family: root.fontFamily
              font.pixelSize: 11
              font.bold: true
            }
          }
        }
      }

      Item { Layout.fillWidth: true }

      // In-panel add button -- opens this column's inline "new card"
      // row (see the addRow comment inside the card area). It stays
      // visible as an active green pill while this column's editor is
      // open, so the header keeps showing what mode the column is in.
      // Wider than the old tiny "+" target for easier clicking.
      Rectangle {
        id: addActionButton

        readonly property bool active: root.addColumnId === columnRoot.columnId
        readonly property color readableSuccessColor: root.readableSemanticColor(root.successColor)

        visible: columnRoot.columnId !== "done"
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: addActionRow.implicitWidth + 16
        implicitHeight: 24
        radius: height / 2
        color: addActionButton.active || addMouse.containsMouse ? addActionButton.readableSuccessColor : Qt.rgba(1, 1, 1, 0.12)

        Row {
          id: addActionRow
          anchors.centerIn: parent
          spacing: 4

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "+"
            color: addActionButton.active || addMouse.containsMouse ? "#000000" : addActionButton.readableSuccessColor
            font.family: root.fontFamily
            font.pixelSize: 12
            font.bold: true
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Add"
            color: addActionButton.active || addMouse.containsMouse ? "#000000" : addActionButton.readableSuccessColor
            font.family: root.fontFamily
            font.pixelSize: 10
            font.bold: true
          }
        }

        MouseArea {
          id: addMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.openAdd(columnRoot.columnId)
        }
      }

      Rectangle {
        visible: columnRoot.columnId === "done"
        Layout.alignment: Qt.AlignVCenter
        implicitWidth: clearDoneRow.implicitWidth + 16
        implicitHeight: 24
        radius: height / 2
        color: clearDoneMouse.containsMouse ? "#e0a050" : Qt.rgba(1, 1, 1, 0.12)

        Row {
          id: clearDoneRow
          anchors.centerIn: parent
          spacing: 4

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "\udb80\udce2"
            color: clearDoneMouse.containsMouse ? "#000000" : "#e0a050"
            font.family: root.fontFamily
            font.pixelSize: 12
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "Clear"
            color: clearDoneMouse.containsMouse ? "#000000" : "#e0a050"
            font.family: root.fontFamily
            font.pixelSize: 10
            font.bold: true
          }
        }

        MouseArea {
          id: clearDoneMouse
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.kanbanService) root.kanbanService.clearDone()
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
		          id: cardsArea
		          anchors.fill: parent
		          clip: true
		          contentHeight: cardsColumn.implicitHeight
		          boundsBehavior: Flickable.StopAtBounds

          ColumnLayout {
            id: cardsColumn
            width: parent.width
            spacing: 8

            // In-panel "new card" row -- the GUI half of the add path,
            // opened by the column header's own "+" (one editor open
            // board-wide at a time -- see root's openAdd). Commits
            // through KanbanService.addCard, the same function
            // kanbanAddCard IPC wraps, which does the clamping and
            // priority defaulting, so this row carries none of that
            // itself. Blank title + Enter is a deliberate no-op (a
            // card can never be blank); description is optional and is
            // written immediately after addCard returns the new id.
            // Esc cancels LOCALLY with the event accepted, so it never
            // bubbles up to notchOuter's own Escape handling and closes
            // the whole panel mid-edit.
            Rectangle {
              id: addRow
              visible: root.addColumnId === columnRoot.columnId
              Layout.fillWidth: true
              Layout.preferredHeight: addEditorContent.implicitHeight + 16
              radius: 8
              color: root.editorSurface
              border.color: root.accent
              border.width: 1.5

              onVisibleChanged: if (visible) Qt.callLater(function() { addInput.forceActiveFocus() })

              function commitAdd() {
                if (addInput.text.trim() === "" || !root.kanbanService) return
                var cardId = root.kanbanService.addCard(addInput.text, columnRoot.columnId, root.addPriority)
                if (cardId !== "" && addDescInput.text.trim() !== "")
                  root.kanbanService.setDescription(cardId, addDescInput.text)
                root.addColumnId = ""
              }

              ColumnLayout {
                id: addEditorContent
                anchors.fill: parent
                anchors.margins: 8
                spacing: 4

                Item {
                  Layout.fillWidth: true
                  Layout.preferredHeight: 16

                  TextInput {
                    id: addInput
                    anchors.fill: parent
                    verticalAlignment: TextInput.AlignVCenter
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    clip: true
                    onAccepted: addRow.commitAdd()
                    Keys.onEscapePressed: function(event) {
                      event.accepted = true
                      root.addColumnId = ""
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      visible: addInput.text.length === 0
                      text: "New task..."
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: 11
                    }
                  }
                }

                TextInput {
                  id: addDescInput
                  Layout.fillWidth: true
                  text: ""
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: 10
                  wrapMode: TextInput.Wrap
                  clip: true
                  selectByMouse: true
                  onAccepted: addRow.commitAdd()
                  Keys.onEscapePressed: function(event) {
                    event.accepted = true
                    root.addColumnId = ""
                  }

                  Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: addDescInput.text.length === 0
                    text: "Add description..."
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: 10
                  }
                }

                RowLayout {
                  Layout.fillWidth: true
                  spacing: 6

                  Item { Layout.fillWidth: true }

                  // Priority for the card about to be created -- click
                  // cycles medium -> high -> low. Default medium, same
                  // as addCard's own default when the CLI omits it.
                  KanbanPriorityPill {
                    id: addPriorityPill
                    Layout.alignment: Qt.AlignVCenter
                    priority: root.addPriority
                    onClicked: root.addPriority = root.cyclePriority(root.addPriority)
                  }

                  KanbanActionButton {
                    id: addCommitButton
                    icon: "✓"
                    accentColor: root.confirmColor
                    onClicked: addRow.commitAdd()
                  }

                  KanbanActionButton {
                    id: addCancelButton
                    icon: "✕"
                    accentColor: root.dangerColor
                    onClicked: root.addColumnId = ""
                  }
	        }

	      }
	    }

              Repeater {
              model: columnRoot.columnCards

              Rectangle {
                id: cardRoot
                required property var modelData
                // This card is the one with the open inline editor /
                // armed delete confirm (root holds the single source of
                // truth -- exactly one editor board-wide, one armed
                // delete at a time).
                readonly property bool isEditing: root.editingCardId === cardRoot.modelData.id
                readonly property bool deleteArmed: root.deleteArmedId === cardRoot.modelData.id
                Layout.fillWidth: true
                // Taller while the editor is open -- the editor's own
                // fields are taller than the display content they
                // replace, and the invisible cardContent (Layouts drop
                // invisible children) would otherwise collapse the card
                // around the open editor.
                Layout.preferredHeight: (cardRoot.isEditing ? editContent.implicitHeight : cardContent.implicitHeight) + 16
                radius: 8
                // Theme-aware surface, passed from Overlay.qml. It is
                // derived from text color instead of the pane fill, so
                // cards remain visible on both dark and light themes.
                color: root.cardSurface
                // Accent border on hover -- direct request ("better
                // visibility on hover of the row... so i know what im
                // clicking or moving around"). A plain border directly
                // on this Rectangle, unlike the notification row's own
                // top-layer overlay trick -- that workaround exists
                // there specifically because a thumbnail image paints
                // over a Rectangle's own border; this card has no such
                // overlapping content, so the direct border just works.
                border.color: cardRoot.deleteArmed ? root.dangerColor
                  : (cardArea.containsMouse || editButton.hovered || deleteButton.hovered) ? root.accent
                  : root.cardBorderColor
                border.width: cardRoot.deleteArmed || cardArea.containsMouse || editButton.hovered || deleteButton.hovered ? 1.5 : 1
                Behavior on border.color { ColorAnimation { duration: 100 } }
                layer.enabled: true
                layer.smooth: true
                layer.effect: MultiEffect {
                  shadowEnabled: true
                  shadowColor: "#000000"
                  shadowOpacity: cardArea.containsMouse || editButton.hovered || deleteButton.hovered ? 0.48 : 0.35
                  shadowBlur: 0.28
                  shadowHorizontalOffset: 0
                  shadowVerticalOffset: cardArea.containsMouse || editButton.hovered || deleteButton.hovered ? 4 : 3
                }

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
                    // While this card's editor is open, the card body
                    // itself is inert -- a stray click inside the editor
                    // (on padding, not a field) must never advance or
                    // regress the card being edited.
                    if (cardRoot.isEditing) return
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
                  visible: !cardRoot.isEditing
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
                        color: cardRoot.modelData.priority === "high" ? root.dangerColor
                          : cardRoot.modelData.priority === "low" ? root.muted
                          : root.warningColor
                      }

                      Text {
                        visible: columnRoot.columnId === "done"
                        anchors.centerIn: parent
                        text: "✓"
                        color: root.successColor
                        font.pixelSize: 13
                      }
                    }

                    Text {
                      Layout.fillWidth: true
                      text: cardRoot.modelData.title
                      // PlainText -- card text is user/agent-typed and
                      // Text's AutoText default would interpret markup.
                      textFormat: Text.PlainText
	                      color: root.textColor
	                      font.family: root.fontFamily
	                      font.pixelSize: 11
	                      elide: Text.ElideRight
	                      maximumLineCount: 1
	                    }

                    // Fixed right reserve for the hover edit/delete
                    // buttons overlaying this corner (cardActions below)
                    // -- reserved on every card, not just while hovered,
                    // so the title's wrap point never jumps when the
                    // buttons appear.
                    Item { Layout.preferredWidth: 48 }
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
                    textFormat: Text.PlainText
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
                      textFormat: Text.PlainText
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
                      color: KanbanModel.isOverdue(cardRoot.modelData, Date.now()) ? root.dangerColor : root.muted
                      font.family: root.fontFamily
                      font.pixelSize: 9
                    }
                  }
                }

                // Inline edit mode -- the GUI half of rename/describe/
                // re-prioritize (hover ✎ on a card, see
                // cardActions below). Prefills from the card itself;
                // saves through the SAME KanbanService functions
                // the kanbanRenameCard/kanbanSetDescription/
                // kanbanSetPriority IPC functions
                // wrap -- identical clamps (title 48 / description 60,
                // applied by the model), identical blank-title no-op.
                // Due-date editing stays CLI-only for now: the former
                // yyyy-mm-dd field made the confirm button overflow in
                // Todo/Done's narrower columns. Enter in any field
                // saves; Esc cancels LOCALLY (event accepted) so it
                // never bubbles up to notchOuter and closes the panel.
                ColumnLayout {
                  id: editContent
                  visible: cardRoot.isEditing
                  anchors.fill: parent
                  anchors.margins: 8
                  spacing: 4

                  onVisibleChanged: if (visible) Qt.callLater(function() { editTitleInput.forceActiveFocus() })

                  function commitEdit() {
                    if (!root.kanbanService || !cardRoot.isEditing) return
                    root.kanbanService.renameCard(cardRoot.modelData.id, editTitleInput.text)
                    root.kanbanService.setDescription(cardRoot.modelData.id, editDescInput.text)
                    root.kanbanService.setPriority(cardRoot.modelData.id, root.editPriority)
                    root.editingCardId = ""
                  }

                  TextInput {
                    id: editTitleInput
                    Layout.fillWidth: true
                    text: cardRoot.modelData.title
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: 11
                    wrapMode: TextInput.Wrap
                    clip: true
                    selectByMouse: true
                    onAccepted: editContent.commitEdit()
                    Keys.onEscapePressed: function(event) {
                      event.accepted = true
                      root.editingCardId = ""
                    }
                  }

                  TextInput {
                    id: editDescInput
                    Layout.fillWidth: true
                    text: cardRoot.modelData.description
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: 10
                    wrapMode: TextInput.Wrap
                    clip: true
                    selectByMouse: true
                    onAccepted: editContent.commitEdit()
                    Keys.onEscapePressed: function(event) {
                      event.accepted = true
                      root.editingCardId = ""
                    }

                    Text {
                      anchors.verticalCenter: parent.verticalCenter
                      visible: editDescInput.text.length === 0
                      text: "description..."
                      color: root.muted
                      font.family: root.fontFamily
                      font.pixelSize: 10
                    }
                  }

                  RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Item { Layout.fillWidth: true }

                    // Priority -- click cycles medium -> high -> low,
                    // same order/rank the model sorts by. State lives
                    // on root (editPriority), not in this delegate, so
                    // the chip's own label re-renders on click.
                    KanbanPriorityPill {
                      id: editPriorityPill
                      Layout.alignment: Qt.AlignVCenter
                      priority: root.editPriority
                      onClicked: root.editPriority = root.cyclePriority(root.editPriority)
                    }

                    KanbanActionButton {
                      id: saveEditButton
                      icon: "✓"
                      accentColor: root.confirmColor
                      onClicked: editContent.commitEdit()
                    }

                  }
                }

                // Hover actions -- edit/delete, the only NEW click
                // targets on a card. Declared LAST inside the card so
                // they stack above the whole-row MouseArea (cardArea):
                // a click on a button must never also advance the card
                // underneath it. The title row's fixed right reserve
                // (see cardContent) keeps the title's wrap point stable
                // whether or not these are showing. Their own hover
                // keeps them visible while the pointer is ON them --
                // cardArea.containsMouse drops the moment a button
                // takes the hover, and without these terms the buttons
                // would vanish under the cursor exactly when reached.
                Row {
                  id: cardActions
                  anchors.top: parent.top
                  anchors.right: parent.right
	                  anchors.margins: 4
	                  spacing: 4
                  visible: !cardRoot.isEditing
                    && (cardArea.containsMouse || cardRoot.deleteArmed
                        || editButton.hovered || deleteButton.hovered)

                  KanbanActionButton {
                    id: editButton
                    icon: "\uf044"
                    iconFamily: root.fontFamily
                    iconPixelSize: 11
                    accentColor: root.successColor
                    onClicked: root.openEdit(cardRoot.modelData)
                  }

                  KanbanActionButton {
                    id: deleteButton
                    // Two-click delete -- the armed red button IS the
                    // confirmation (this plugin has no dialog surface
                    // convention); root's own 3s Timer disarms it.
                    icon: "✕"
                    iconPixelSize: 11
                    accentColor: root.dangerColor
                    armed: cardRoot.deleteArmed
                    onClicked: {
                      if (!root.kanbanService) return
                      if (cardRoot.deleteArmed) {
                        root.deleteArmedId = ""
                        root.kanbanService.removeCard(cardRoot.modelData.id)
                      } else {
                        root.deleteArmedId = cardRoot.modelData.id
                      }
                    }
                  }
                }
              }
          }
        }
      }

	      }
	    }

	    Rectangle {
	      id: doneProgressCard
	      visible: columnRoot.columnId === "done"
	      Layout.fillWidth: true
	      Layout.preferredHeight: 92
	      radius: 10
	      color: Qt.rgba(1, 1, 1, 0.05)

	      property real value: root.doneRatio
	      onValueChanged: doneDial.requestPaint()

	      RowLayout {
	        anchors.centerIn: parent
	        spacing: 10

	        Item {
	          Layout.preferredWidth: 58
	          Layout.preferredHeight: 58
	          Layout.alignment: Qt.AlignVCenter

	          Canvas {
	            id: doneDial
	            anchors.fill: parent
	            onWidthChanged: requestPaint()
	            onHeightChanged: requestPaint()
	            onPaint: {
	              var ctx = getContext("2d")
	              ctx.reset()
	              var cx = width / 2, cy = height / 2, r = width / 2 - 6
	              var startAngle = Math.PI / 2 + Math.PI / 4
	              var totalSweep = Math.PI * 2 - Math.PI / 2
	              var endAngle = startAngle + Math.max(0, Math.min(1, doneProgressCard.value)) * totalSweep
	              var handleSpacing = 5
	              var gapRad = handleSpacing / r
	              ctx.lineWidth = 4
	              ctx.lineCap = "round"
	              ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.15)
	              var trackStart = endAngle + gapRad
	              var trackEnd = startAngle + totalSweep
	              if (trackStart < trackEnd) {
	                ctx.beginPath()
	                ctx.arc(cx, cy, r, trackStart, trackEnd)
	                ctx.stroke()
	              }

	              ctx.strokeStyle = root.accent
	              ctx.beginPath()
	              var progressEnd = Math.max(startAngle, endAngle - gapRad)
	              ctx.arc(cx, cy, r, startAngle, progressEnd)
	              ctx.stroke()

	              var tipR1 = r - 2
	              var tipR2 = r + 3
	              var tx1 = cx + tipR1 * Math.cos(endAngle)
	              var ty1 = cy + tipR1 * Math.sin(endAngle)
	              var tx2 = cx + tipR2 * Math.cos(endAngle)
	              var ty2 = cy + tipR2 * Math.sin(endAngle)
	              ctx.lineWidth = 5
	              ctx.lineCap = "round"
	              ctx.strokeStyle = "#ffffff"
	              ctx.beginPath()
	              ctx.moveTo(tx1, ty1)
	              ctx.lineTo(tx2, ty2)
	              ctx.stroke()
	            }
	          }

	          Text {
	            anchors.centerIn: parent
	            text: root.donePercent + "%"
	            color: root.textColor
	            font.family: root.fontFamily
	            font.pixelSize: 14
	            font.weight: Font.DemiBold
	          }
	        }

	        ColumnLayout {
	          Layout.preferredWidth: 74
	          Layout.alignment: Qt.AlignVCenter
	          spacing: 4

	          Text {
	            text: "Progress"
	            color: root.muted
	            font.family: root.fontFamily
	            font.pixelSize: 10
	            font.bold: true
	          }

	          Text {
	            text: root.doneCards + "/" + root.totalCards + " done"
	            color: root.textColor
	            font.family: root.fontFamily
	            font.pixelSize: 13
	            font.weight: Font.DemiBold
	          }
	        }
	      }
	    }

	    // Superseded -- the "no in-panel text entry" rule this comment used
    // to document was reversed by the later "its not GUI friendly"
    // request: each column header now has a "+" opening this file's own
    // inline add editor, and each card carries hover edit/delete. The
    // only thing still CLI/agent-only on this board is RENAMING A
    // COLUMN (kanbanRenameColumn). Advancing, regressing, and the Done
    // dismiss stay plain clicks, same as they always were.
  }

  // Root keeps the column row as the only top-level visual now; board
  // completion lives in the Done header instead of a separate toolbar-like
  // strip above the board.
  ColumnLayout {
    anchors.fill: parent
    spacing: 0

    RowLayout {
      id: columnsRow
      Layout.fillWidth: true
      Layout.fillHeight: true
      // Extra clearance on the right -- direct report ("thrid panel
      // sits too close to edge"), confirmed live: the Done column's own
      // right edge sat only a few px from the notch's own curved right
      // edge. Same fix, same value, as MetricsContent.qml's own
      // Layout.rightMargin: 10 on its stat-tile grid (its own comment:
      // "the expanded panel's outer anchors.rightMargin... wasn't enough
      // breathing room on its own for this dense a grid") -- this tab is
      // the same shape of problem, a full-width grid of tonal panels
      // reaching the panel's own right edge.
      Layout.rightMargin: 10
      // Same reasoning, bottom edge -- direct follow-up: "the buttom of
      // the panel stil ends too close to the buttom of the notch edge".
      // The notch's own signature shape has its rounded corners at the
      // BOTTOM (see Overlay.qml's own bottomLeftRadius/bottomRightRadius
      // on the notch shape itself), so a full-height panel reaching the
      // shared 12px outer bottomMargin needs real clearance from that
      // curve, same as the right edge did.
      Layout.bottomMargin: 10
      spacing: 8

      Repeater {
        model: root.kanbanService ? root.kanbanService.columns : []
        delegate: KanbanColumn {}
      }
    }
  }
}
