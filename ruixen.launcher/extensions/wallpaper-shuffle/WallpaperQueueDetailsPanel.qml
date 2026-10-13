import QtQuick

// Right-pane preview for the selected queue entry -- deliberately
// simple compared to ClipboardDetailsPanel.qml's own richer metadata
// list: a wallpaper's own content IS the useful detail here, not a
// field list, so this is mostly a large preview image plus the handful
// of facts that actually matter (filename, kind, queue position,
// whether it's the one currently on screen).
Rectangle {
  id: root

  property var row: null
  readonly property var entry: row ? row.entry : null
  property string currentBackground: ""
  readonly property bool isCurrent: !!root.entry && root.entry.identity === root.currentBackground
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  signal applyRequested()

  color: "transparent"
  radius: 12
  clip: true

  Column {
    anchors.fill: parent
    anchors.margins: 16
    spacing: 12
    visible: root.entry !== null

    Rectangle {
      width: parent.width
      height: width / 1.6
      radius: 10
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, .08)
      border.width: 1
      border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, .25)
      clip: true

      Image {
        anchors.fill: parent
        source: root.entry ? ("file://" + root.entry.display) : ""
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
      }

      Rectangle {
        visible: root.isCurrent
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 8
        width: currentLabel.implicitWidth + 16
        height: 22
        radius: 6
        color: root.accent
        Text {
          id: currentLabel
          anchors.centerIn: parent
          text: "CURRENT"
          color: "#000000"
          font.family: root.fontFamily
          font.pixelSize: 10
        }
      }
    }

    Text {
      width: parent.width
      text: root.row ? root.row.label : ""
      color: root.textColor
      font.family: root.fontFamily
      font.pixelSize: 13
      elide: Text.ElideMiddle
    }

    Text {
      width: parent.width
      text: root.row ? (root.row.kind + " · " + root.row.breadcrumb + " in queue") : ""
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: 11
    }

    Rectangle {
      width: applyLabel.implicitWidth + 24
      height: 30
      radius: 8
      color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, .15)
      border.width: 1
      border.color: Qt.rgba(root.accent.r, root.accent.g, root.accent.b, .4)

      Text {
        id: applyLabel
        anchors.centerIn: parent
        text: "Set as wallpaper now"
        color: root.accent
        font.family: root.fontFamily
        font.pixelSize: 11
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: root.applyRequested()
      }
    }

    Text {
      width: parent.width
      text: "Tab for Move up/Move down"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: 10
    }
  }

  Text {
    anchors.centerIn: parent
    visible: root.entry === null
    text: "No wallpapers found"
    color: root.muted
    font.family: root.fontFamily
    font.pixelSize: 12
  }
}
