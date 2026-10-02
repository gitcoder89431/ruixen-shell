import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ShelfModel.js" as ShelfModel

// The Shelf window's content: a drop pocket. Drag files in from any app;
// drag them back out into another app or a terminal. Backing store +
// agent-facing API live in ShelfService.qml -- this file only renders it
// and calls the same service functions the IPC does. Hosted by Shelf.qml
// (its own panel that hangs from the frame at the notch's position, not a notch dashboard tab).
//
// Dragging OUT uses QML's own Drag.Automatic with both text/uri-list
// (file managers, browsers, chat apps) and text/plain (terminals: the
// path is inserted as text). The shelf holds references only -- a drag
// out copies nothing by itself.
Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  // The window's own surface color, passed in: the right-edge scroll fade
  // has to terminate on exactly what is behind it or it reads as a grey
  // band rather than an edge.
  property color surfaceColor: "#000000"
  property string fontFamily: "JetBrainsMono Nerd Font"
  property bool active: false
  property var shelfService: null

  signal closeRequested()

  readonly property var rows: root.shelfService
    ? ShelfModel.listEntries(root.shelfService.items, root.shelfService.stats, root.shelfService.checked)
    : []

  // The search box, and the rows it leaves visible. Empty query = every
  // row (no copy, no rebuild), so typing and clearing stay cheap.
  property string query: ""
  readonly property var filtered: ShelfModel.filterEntries(root.rows, root.query)
  readonly property bool filtering: root.query.trim() !== ""
  readonly property var visibleRows: root.filtering ? root.filtered : root.rows
  // Panel padding. Side and bottom are generous because the shelf hangs
  // from a rounded notch with wings on both sides -- cards sitting 12px
  // from those edges read as crowding the notch's own curve, and the
  // bottom edge is the panel's real outer edge. The top stays tight: it butts
  // up against the notch above it, so extra room there only adds a gap.
  // How far one arrow press moves the strip. A card plus its gap, so a
  // press lands on a card boundary instead of half-way through one.
  readonly property int keyScrollStep: 132

  readonly property int padTop: 12
  readonly property int padSide: 24
  readonly property int padBottom: 24

  readonly property color tint: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
  readonly property color tintStrong: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)

  // The count for the chip on the search row: "Shelf 16", or "Shelf 3 of 16"
  // while filtering. While filtering, report how many of the TOTAL matched,
  // not just the filtered count -- "16" flipping to "1" as you type reads
  // like items are being deleted.
  readonly property string chipCount: root.filtering
    ? (root.visibleRows.length === 1 ? "1 of " : root.visibleRows.length + " of ") + String(root.rows.length)
    : String(root.rows.length)

  // Paths can disappear while the notch is closed; re-check on open.
  onActiveChanged: if (root.active && root.shelfService) root.shelfService.refreshStats()

  // One place that moves the strip and clamps it. The wheel handler and the
  // arrow keys both go through this so they cannot drift apart on the bounds
  // math -- and it is the only thing allowed to write contentX.
  //
  // `step` is in pixels, positive meaning "toward the right".
  function scrollStripMax() {
    if (!list) return 0
    return Math.max(0, list.contentWidth - list.width)
  }

  // 0 = the left end, 1 = the right end, anything between is proportional.
  function scrollStripTo(fraction) {
    var max = root.scrollStripMax()
    if (max <= 0) return
    list.contentX = Math.max(0, Math.min(max, max * fraction))
  }

  // Arrows drive the strip. One handler, shared by the field and the list,
  // switching on the key explicitly: Qt's Keys attached type has no
  // onHomePressed/onEndPressed convenience signals, and guessing those
  // names fails at LOAD time ("Cannot assign to non-existent property"),
  // which takes the whole plugin down over a single key.
  function handleStripKey(event) {
    var step = root.keyScrollStep
    switch (event.key) {
      case Qt.Key_Left:  root.scrollStrip(-step); break
      case Qt.Key_Right: root.scrollStrip(step); break
      case Qt.Key_Home:  root.scrollStripTo(0); break
      case Qt.Key_End:   root.scrollStripTo(1); break
      default: return
    }
    event.accepted = true
  }

  function scrollStrip(step) {
    var max = root.scrollStripMax()
    if (max <= 0) return false
    var next = Math.max(0, Math.min(max, list.contentX + step))
    if (next === list.contentX) return false
    list.contentX = next
    return true
  }

  function formatSize(bytes) {
    if (bytes === null || bytes === undefined) return ""
    if (bytes < 1024) return bytes + " B"
    if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(bytes < 10240 ? 1 : 0) + " KB"
    if (bytes < 1024 * 1024 * 1024) return (bytes / (1024 * 1024)).toFixed(1) + " MB"
    return (bytes / (1024 * 1024 * 1024)).toFixed(1) + " GB"
  }

  function glyphFor(entry) {
    if (!entry.exists && entry.exists !== null) return ""
    if (entry.kind === "folder") return ""
    if (ShelfModel.isImagePath(entry.path)) return ""
    return ""
  }

  function subtitleFor(entry) {
    if (entry.exists === false) return "Missing · " + ShelfModel.dirName(entry.path)
    var parts = []
    if (entry.kind === "folder") parts.push("Folder")
    else if (entry.size !== null) parts.push(root.formatSize(entry.size))
    parts.push(ShelfModel.dirName(entry.path))
    return parts.join(" · ")
  }

  // Candidate shelf paths in a drag/drop event: local file URLs first, else
  // plain-text lines that are themselves absolute paths (a terminal or text
  // field can drag one). ShelfModel.normalizePath is the same gate the
  // service applies, so "acceptable here" and "accepted by the shelf" agree.
  // A dragged web image arrives as an http(s) URL and yields nothing.
  function dropPaths(ev) {
    var paths = []
    var urls = ev.urls || []
    for (var i = 0; i < urls.length; i++) {
      var p = ShelfModel.fileUrlToPath(String(urls[i]))
      if (ShelfModel.normalizePath(p) !== "") paths.push(p)
    }
    if (paths.length === 0 && ev.hasText) {
      var lines = String(ev.text).split("\n")
      for (var j = 0; j < lines.length; j++) {
        var line = lines[j].trim()
        if (ShelfModel.normalizePath(line) !== "") paths.push(line)
      }
    }
    return paths
  }

  // The shelf stores references and never moves or deletes the source, so
  // it only ever advertises/accepts COPY semantics -- explicitly, never
  // acceptProposedAction(), which would echo back a MoveAction a source app
  // proposed and let it believe the move succeeded.
  //
  // A drag that started from one of this shelf's own rows (drop.source is
  // set for in-process drags) is ignored, so dragging out and releasing back
  // over the panel doesn't reshuffle the list.
  function handleDrop(drop) {
    if (drop.source) return
    var paths = root.dropPaths(drop)
    if (paths.length === 0 || !root.shelfService) return
    var result = root.shelfService.addPaths(paths, "user")
    if (result.added.length > 0) drop.accept(Qt.CopyAction)
  }

  Process { id: copyProc }
  Process { id: openProc }

  DropArea {
    id: dropArea
    anchors.fill: parent
    onEntered: (drag) => { if (!drag.source && root.dropPaths(drag).length > 0) drag.accept(Qt.CopyAction) }
    onDropped: (drop) => root.handleDrop(drop)

    // "Shelf 16" identity + count, left of the search box on the same row.
    // Its own shape, not nested in the field: a chip drawn inside the
    // rounded box reads as part of the text input, and a click on it should
    // focus the field rather than land on the chip.
    Rectangle {
      id: shelfChip
      anchors.left: parent.left
      anchors.leftMargin: root.padSide
      // On the search box's row, not the panel's middle. searchBox is
      // declared below this, which is fine -- QML resolves ids regardless
      // of declaration order.
      anchors.verticalCenter: searchBox.verticalCenter
      width: chipRow.implicitWidth + 16
      // Same height as the field beside it, bound rather than repeated:
      // these are three controls on one row, and a row whose middle piece
      // is taller than its neighbours reads as broken, not nested.
      height: searchBox.height
      // Same radius as the field, for the same reason as the height.
      radius: searchBox.radius
      color: root.tint
      border.width: 1
      border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)

      Row {
        id: chipRow
        anchors.centerIn: parent
        spacing: 5

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: "Shelf"
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 11
          font.bold: true
        }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.chipCount
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 11
        }
      }
    }

    // Search box, and the count chip beside it, are the top row now. The
    // title/count bar that used to sit above them is gone: the chip carries
    // the same count, and Escape is the dismiss (there is no X).
    //
    // Plain TextInput rather than anything fancier: it takes focus only on
    // click, so it never steals the keyboard from the app the user is about
    // to drag into (the same reason the window is OnDemand, not Exclusive).
    Rectangle {
      id: searchBox
      anchors.top: parent.top
      anchors.topMargin: root.padTop
      // Starts after the count chip on the same row, rather than at the
      // panel's edge: the chip is its own shape, not part of the field.
      anchors.left: shelfChip.right
      anchors.right: parent.right
      anchors.leftMargin: 6
      // Gives up room on the right for the shelf-wide Clear that now sits on
      // this row, and takes it back when Clear hides (nothing to clear), so
      // the box never ends up with a mystery gap in an empty shelf.
      anchors.rightMargin: root.padSide + (clearShelfButton.visible ? clearShelfButton.width + 6 : 0)
      height: 30
      radius: 9
      color: searchInput.activeFocus ? root.tintStrong : root.tint
      border.width: 1
      border.color: searchInput.activeFocus
        ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.5)
        : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)

      Text {
        id: searchGlyph
        anchors.left: parent.left
        anchors.leftMargin: 9
        anchors.verticalCenter: parent.verticalCenter
        text: ""
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 12
      }

      TextInput {
        id: searchInput
        anchors.left: searchGlyph.right
        anchors.leftMargin: 7
        anchors.right: clearQuery.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 12
        selectByMouse: true
        clip: true
        onTextChanged: root.query = text
        Keys.onEscapePressed: {
          // Escape clears the filter first, and only dismisses the window
          // once there is nothing left to clear -- otherwise a stray
          // Escape mid-search throws away both the query and the shelf.
          if (root.query !== "") { text = ""; root.query = "" }
          else root.closeRequested()
        }
        Keys.onDownPressed: list.forceActiveFocus()
        Keys.onUpPressed: list.forceActiveFocus()
        // Left/right scroll the strip even with the field focused. A
        // single-line filter has no use for the caret to move along the
        // text, and the results are what the user is looking at.
        Keys.onPressed: (event) => root.handleStripKey(event)

        Text {
          anchors.verticalCenter: parent.verticalCenter
          visible: searchInput.text === ""
          text: "Filter by name or folder"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 12
        }
      }

      // Clear-search affordance, for the filter text only. The shelf-wide
      // Clear sits to the right of this box, so the two are on the same
      // row -- which is why this one is an unlabelled glyph (the field's
      // own X) and that one reads "Clear".
      Rectangle {
        id: clearQuery
        visible: searchInput.text !== ""
        anchors.right: parent.right
        anchors.rightMargin: 6
        width: 20
        height: 20
        radius: 6
        color: clearQueryArea.containsMouse ? root.tintStrong : "transparent"

        Text {
          anchors.centerIn: parent
          text: ""
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 11
        }

        MouseArea {
          id: clearQueryArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: { searchInput.text = ""; root.query = ""; searchInput.forceActiveFocus() }
        }
      }

      // Clicking anywhere in the box focuses the field. Declared last so
      // it can reference the field's x, but pushed UNDER it with z: -1 --
      // at the default z it would render on top of both the TextInput and
      // the clear button and swallow their clicks entirely.
      MouseArea {
        z: -1
        anchors.fill: parent
        anchors.leftMargin: searchInput.x - searchGlyph.width - 7
        anchors.rightMargin: clearQuery.width
        onClicked: searchInput.forceActiveFocus()
      }
    }

      // Shelf-wide Clear, moved down onto the search row's right side. It is
      // a sibling of searchBox rather than a child of it on purpose: inside
      // the rounded box it would read as part of the text field, and it is
      // the only button here that destroys the whole shelf's contents.
      Rectangle {
        id: clearShelfButton
        visible: root.rows.length > 0
        anchors.right: parent.right
        anchors.rightMargin: root.padSide
        anchors.verticalCenter: searchBox.verticalCenter
        width: clearLabel.implicitWidth + 20
        height: searchBox.height
        radius: searchBox.radius
        color: clearArea.containsMouse ? root.tintStrong : root.tint
        border.width: 1
        border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)

        Text {
          id: clearLabel
          anchors.centerIn: parent
          text: "Clear"
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 11
        }

        MouseArea {
          id: clearArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (root.shelfService) root.shelfService.clear()
        }
      }

    // Empty state: the drop target itself.
    Rectangle {
      visible: root.rows.length === 0
      anchors.top: searchBox.bottom
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: root.padTop
      anchors.bottomMargin: root.padBottom
      anchors.leftMargin: root.padSide
      anchors.rightMargin: root.padSide
      radius: 14
      color: dropArea.containsDrag ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.1) : "transparent"
      border.width: 2
      border.color: dropArea.containsDrag ? root.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.18)

      Column {
        anchors.centerIn: parent
        spacing: 10
        width: parent.width - 48

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: ""
          color: dropArea.containsDrag ? root.accent : root.muted
          font.family: root.fontFamily
          font.pixelSize: 44
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "Drop files here"
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 15
          font.bold: true
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: "Drag them back out into any app or terminal.\nAgents can add and read files with\nomarchy-shell ruixen.shelf add /path"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 11
          lineHeight: 1.2
        }
      }
    }

    // A filter that matched nothing. Deliberately distinct from the empty
    // shelf above: "nothing on the shelf" and "nothing MATCHES what you
    // typed" need different words, and only one of them is fixed by
    // dropping a different file in.
    Rectangle {
      visible: root.rows.length > 0 && root.filtering && root.visibleRows.length === 0
      anchors.top: searchBox.bottom
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: root.padTop
      anchors.bottomMargin: root.padBottom
      anchors.leftMargin: root.padSide
      anchors.rightMargin: root.padSide
      radius: 14
      color: "transparent"
      border.width: 2
      border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.18)

      Column {
        anchors.centerIn: parent
        spacing: 8
        width: parent.width - 48

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "No match"
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 14
          font.bold: true
        }

        Text {
          width: parent.width
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          text: "Nothing on the shelf matches “" + root.query.trim() + "”."
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 11
        }
      }
    }

    // Items, as a HORIZONTAL strip.
    //
    // Horizontal, not vertical, because that is what actually makes this a
    // drop pocket: the panel keeps a short fixed height (236) no matter how
    // many files are on it, so it stays out of the way of whatever you are
    // dragging into, and the whole thing still reads as a pocket growing
    // out of the notch. A vertical list instead grows downward into the
    // screen -- it was capped at 420px and then simply stopped showing new
    // items, which is the one thing a drop pocket must never do.
    //
    ListView {
      id: list
      visible: root.visibleRows.length > 0

      // Arrows drive the strip once the list itself has focus. Down/Up from
      // the search field hand focus over, and clicking the strip does too --
      // without the latter the arrows are unreachable for anyone who never
      // touches the field.
      Keys.onPressed: (event) => root.handleStripKey(event)
      Keys.onEscapePressed: root.closeRequested()

      // Clicking bare strip focuses the list, so the arrows are reachable
      // without going through the search field first. z: -1 puts it UNDER
      // the delegates, which own their own clicks and their drag-out.
      MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton
        onClicked: list.forceActiveFocus()
      }

      anchors.top: searchBox.bottom
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.topMargin: root.padTop
      anchors.bottomMargin: root.padBottom
      anchors.leftMargin: root.padSide
      anchors.rightMargin: root.padSide
      clip: true
      orientation: ListView.Horizontal
      spacing: 8
      model: root.visibleRows
      // NO explicit contentWidth here, deliberately. Binding it to
      // childrenRect.width looks harmless and is not: the view sizes its
      // own content item FROM contentWidth, so the binding is circular and
      // Qt reports a binding loop for the life of the window (it did, in
      // the journal, on every restart). The list already derives
      // contentWidth from its delegates' positions, which is what we
      // want, and the window itself has a fixed size -- an unbounded strip
      // cannot stretch it, because the view is anchored left and right
      // rather than sized to its content.
      flickDeceleration: 4000
      boundsBehavior: Flickable.StopAtBounds

      // Map the wheel onto the strip's own axis. Qt's Flickable does try
      // to handle a perpendicular wheel event itself, but not uniformly
      // across versions/orientations, and here there IS no perpendicular
      // axis to fall back on: if this handler is wrong, the shelf has no
      // way to scroll at all and files past the right edge are simply
      // unreachable. target: null keeps it deterministic instead of
      // letting it fight the view's own handling.
      // UNVERIFIED: this handler does not scroll in practice (the strip is
      // 2104px of content in an ~850px view, so there is definitely room to
      // move). Whether the handler is never invoked at all, or fires and the
      // math is wrong, is still unknown -- it could not be reproduced
      // headlessly because synthesizing a wheel event needs /dev/uinput
      // write access, which is not available. To settle it in one step, put
      // this back in onWheel and scroll with the cursor over the open shelf:
      //
      //   console.log("cw=" + list.contentWidth + " w=" + list.width
      //     + " cx=" + list.contentX + " dy=" + wheel.angleDelta.y)
      //   journalctl --user -b 0 --since "-1min" | grep cw=
      //
      // cw=2104 w=850  -> the handler IS firing, so the bug is below here.
      // (no output)      -> wheel events never reach this layer surface at
      //                    all, and the handler is the wrong place to fix it.
      WheelHandler {
        target: null
        onWheel: (wheel) => {
          // Wheel-up/deltaY-positive has always scrolled leftward here, and
          // that is the right way round for a horizontal strip.
          var dy = wheel.angleDelta.y + wheel.pixelDelta.y
          var dx = wheel.angleDelta.x + wheel.pixelDelta.x
          var delta = dx !== 0 ? dx : dy
          if (delta === 0) return
          if (root.scrollStrip(-delta)) wheel.accepted = true
        }
      }

      delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property var entry: modelData
        readonly property bool missing: entry.exists === false
        // A card, not a full-width row: the strip scrolls, so width is a
        // property of the item rather than of the panel. Fixed rather than
        // content-sized because a name of wildly different length must
        // not change how much of the strip is on screen.
        width: 124
        height: ListView.view.height

        Rectangle {
          anchors.fill: parent
          radius: 10
          color: rowHover.hovered || dragProxy.Drag.active ? root.tintStrong : root.tint
          opacity: row.missing ? 0.55 : 1
        }

        // Drag source. The proxy (not the visible row) is what the
        // MouseArea drags, so the row itself never moves; Drag.Automatic
        // hands the rest to the compositor, and the proxy is parked back
        // at 0,0 when the drag ends.
        Item {
          id: dragProxy
          width: 1
          height: 1
          Drag.dragType: Drag.Automatic
          Drag.supportedActions: Qt.CopyAction
          Drag.active: rowArea.drag.active
          Drag.mimeData: ({
            "text/uri-list": ShelfModel.uriList([row.entry.path]),
            "text/plain": row.entry.path
          })
          Drag.onDragFinished: { dragProxy.x = 0; dragProxy.y = 0 }
        }

        // Whole-row hover (covers the buttons too) for showing the actions.
        HoverHandler { id: rowHover }

        MouseArea {
          id: rowArea
          anchors.fill: parent
          hoverEnabled: true
          acceptedButtons: Qt.LeftButton
          cursorShape: Qt.OpenHandCursor
          drag.target: dragProxy
          drag.threshold: 6
          // The row lives inside a ListView, which would otherwise steal
          // the press/gesture (it wants to scroll) before a drag out can
          // begin.
          preventStealing: true
          onPressed: row.grabToImage(function(result) { dragProxy.Drag.imageSource = result.url })
          onDoubleClicked: openProc.exec(["xdg-open", row.entry.path])
        }

        // Card body: thumbnail on top, name + subtitle stacked under it.
        // Vertical INSIDE the card because the card itself is what moved --
        // turning the item into a horizontal strip is what buys the
        // thumbnail enough room to be recognisable at all.
        ColumnLayout {
          anchors.fill: parent
          anchors.margins: 8
          spacing: 6

          // Sized to fill the card rather than a fixed square, so no list
          // height is baked into it.
          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 8
            color: Qt.rgba(0, 0, 0, 0.2)
            clip: true

            Image {
              anchors.fill: parent
              visible: !row.missing && ShelfModel.isImagePath(row.entry.path)
              source: visible ? ShelfModel.uriFor(row.entry.path) : ""
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              cache: false
              sourceSize.width: 248
              sourceSize.height: 248
            }

            Text {
              anchors.centerIn: parent
              visible: row.missing || !ShelfModel.isImagePath(row.entry.path)
              text: root.glyphFor(row.entry)
              color: row.missing ? root.muted : root.accent
              font.family: root.fontFamily
              font.pixelSize: 26
            }
          }

          RowLayout {
            Layout.fillWidth: true
            spacing: 4

            Text {
              Layout.fillWidth: true
              text: row.entry.name
              // ElideRight, not ElideMiddle: in a 124px card the tail is
              // the informative part (-2, .tar.gz, final char), and
              // ElideMiddle dropping a middle character makes two
              // differently-named files look identically named.
              elide: Text.ElideRight
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 11
              font.strikeout: row.missing
            }

            Rectangle {
              visible: row.entry.source === "agent"
              Layout.preferredWidth: agentLabel.implicitWidth + 10
              Layout.preferredHeight: 14
              radius: 7
              color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)

              Text {
                id: agentLabel
                anchors.centerIn: parent
                text: "agent"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: 8
                font.bold: true
              }
            }
          }

          Text {
            Layout.fillWidth: true
            text: root.subtitleFor(row.entry)
            elide: Text.ElideRight
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 9
          }
        }

        // Hover actions, overlaid on the thumbnail rather than sitting in
        // the text stack: at 124px wide there is no room for three 24px
        // buttons beside a name, and in the layout they collided with the
        // elided name instead of with nothing.
        Rectangle {
          visible: rowHover.hovered
          anchors.top: parent.top
          anchors.right: parent.right
          anchors.margins: 6
          width: actionsRow.width
          height: actionsRow.height
          radius: 8
          color: Qt.rgba(0, 0, 0, 0.55)

          Row {
            id: actionsRow
            anchors.centerIn: parent
            spacing: 2

            Repeater {
              model: [
                { id: "copy", glyph: "\uf0c5" },
                { id: "open", glyph: "\uf35d" },
                { id: "remove", glyph: "\uf00d" }
              ]

              Rectangle {
                required property var modelData
                width: 24
                height: 24
                radius: 6
                color: btnArea.containsMouse ? root.tintStrong : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: modelData.glyph
                  color: modelData.id === "remove" && btnArea.containsMouse ? "#e5484d" : root.textColor
                  font.family: root.fontFamily
                  font.pixelSize: 11
                }

                MouseArea {
                  id: btnArea
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: {
                    if (modelData.id === "copy") copyProc.exec(["wl-copy", "--", row.entry.path])
                    else if (modelData.id === "open") openProc.exec(["xdg-open", row.entry.path])
                    else if (root.shelfService) root.shelfService.removeItem(row.entry.id)
                  }
                }
              }
            }
          }
        }
      }
    }

    // Right-edge fade. Anything past the edge fades instead of being
    // guillotined: a card sliced down the middle reads as broken, and this
    // window is a fixed size that deliberately cannot grow to reveal the
    // rest. Only shown when there IS more to scroll to -- a permanent fade
    // on a shelf that fits is just a grey smudge over the last card.
    Rectangle {
      visible: list.contentWidth > list.width && list.contentX < list.contentWidth - list.width - 1
      anchors.right: list.right
      anchors.top: list.top
      anchors.bottom: list.bottom
      width: 28
      gradient: Gradient {
        orientation: Gradient.Horizontal
        GradientStop { position: 0.0; color: "transparent" }
        GradientStop { position: 1.0; color: root.surfaceColor }
      }
    }

    // Whole-list drop highlight while something is dragged over it. A
    // sibling of the ListView (not a child): items declared inside a
    // ListView land in its scrolling content item.
    Rectangle {
      visible: root.rows.length > 0 && dropArea.containsDrag
      anchors.fill: list
      radius: 12
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.08)
      border.width: 2
      border.color: root.accent
    }
  }
}
