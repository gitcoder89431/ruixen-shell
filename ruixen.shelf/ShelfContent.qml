import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "ShelfModel.js" as ShelfModel

// The Shelf window's content: a drop pocket. Drag files in from any app;
// drag them back out into another app or a terminal. Backing store +
// agent-facing API live in ShelfService.qml -- this file only renders it
// and calls the same service functions the IPC does. Hosted by Shelf.qml
// (its own small window under the notch, not a notch dashboard tab).
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
  property string fontFamily: "JetBrainsMono Nerd Font"
  property bool active: false
  property var shelfService: null

  signal closeRequested()

  readonly property var rows: root.shelfService
    ? ShelfModel.listEntries(root.shelfService.items, root.shelfService.stats, root.shelfService.checked)
    : []
  readonly property color tint: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.06)
  readonly property color tintStrong: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.12)

  // Paths can disappear while the notch is closed; re-check on open.
  onActiveChanged: if (root.active && root.shelfService) root.shelfService.refreshStats()

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

    // Header
    RowLayout {
      id: header
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: 12
      height: 28
      spacing: 8

      Text {
        text: "Shelf"
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 14
        font.bold: true
      }

      Text {
        text: ShelfModel.countLabel(root.rows.length)
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 11
      }

      Item { Layout.fillWidth: true }

      Rectangle {
        visible: root.rows.length > 0
        Layout.preferredWidth: clearLabel.implicitWidth + 20
        Layout.preferredHeight: 24
        radius: 6
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

      Rectangle {
        Layout.preferredWidth: 24
        Layout.preferredHeight: 24
        radius: 6
        color: closeArea.containsMouse ? root.tintStrong : "transparent"

        Text {
          anchors.centerIn: parent
          text: "\uf00d"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 12
        }

        MouseArea {
          id: closeArea
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: root.closeRequested()
        }
      }
    }

    // Empty state: the drop target itself.
    Rectangle {
      visible: root.rows.length === 0
      anchors.top: header.bottom
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: 12
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

    // Items
    ListView {
      id: list
      visible: root.rows.length > 0
      anchors.top: header.bottom
      anchors.bottom: parent.bottom
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.margins: 12
      anchors.topMargin: 6
      clip: true
      spacing: 6
      model: root.rows

      delegate: Item {
        id: row
        required property var modelData
        required property int index
        readonly property var entry: modelData
        readonly property bool missing: entry.exists === false
        width: ListView.view.width
        height: 56

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

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: 10
          anchors.rightMargin: 8
          spacing: 10

          // Thumbnail for images, glyph otherwise.
          Rectangle {
            Layout.preferredWidth: 38
            Layout.preferredHeight: 38
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
              sourceSize.width: 76
              sourceSize.height: 76
            }

            Text {
              anchors.centerIn: parent
              visible: row.missing || !ShelfModel.isImagePath(row.entry.path)
              text: root.glyphFor(row.entry)
              color: row.missing ? root.muted : root.accent
              font.family: root.fontFamily
              font.pixelSize: 18
            }
          }

          ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
              Layout.fillWidth: true
              spacing: 6

              Text {
                Layout.fillWidth: true
                text: row.entry.name
                elide: Text.ElideMiddle
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 13
                font.strikeout: row.missing
              }

              Rectangle {
                visible: row.entry.source === "agent"
                Layout.preferredWidth: agentLabel.implicitWidth + 12
                Layout.preferredHeight: 16
                radius: 8
                color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18)

                Text {
                  id: agentLabel
                  anchors.centerIn: parent
                  text: "agent"
                  color: root.accent
                  font.family: root.fontFamily
                  font.pixelSize: 9
                  font.bold: true
                }
              }
            }

            Text {
              Layout.fillWidth: true
              text: root.subtitleFor(row.entry)
              elide: Text.ElideMiddle
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 10
            }
          }

          // Hover actions (kept out of the drag MouseArea's way: they sit
          // above it, so a click on a button never starts a drag).
          Row {
            visible: rowHover.hovered
            spacing: 4

            Repeater {
              model: [
                { id: "copy", glyph: "" },
                { id: "open", glyph: "" },
                { id: "remove", glyph: "" }
              ]

              Rectangle {
                required property var modelData
                width: 26
                height: 26
                radius: 7
                color: btnArea.containsMouse ? root.tintStrong : "transparent"

                Text {
                  anchors.centerIn: parent
                  text: modelData.glyph
                  color: modelData.id === "remove" && btnArea.containsMouse ? "#e5484d" : root.textColor
                  font.family: root.fontFamily
                  font.pixelSize: 12
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
