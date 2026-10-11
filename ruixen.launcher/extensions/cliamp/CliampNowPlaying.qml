import QtQuick

// Right-pane transport/status display for the Cliamp Radio extension.
// Same split every other item/row component in this plugin already uses
// (SettingsWifiRow.qml, ClipboardDetailsPanel.qml): CliampContent.qml owns
// every Process call and all real state, this only draws what it's told
// and emits signals for a click to act on.
Item {
  id: root

  property var nowPlaying: null
  property bool cliampRunning: true
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  readonly property bool playing: root.nowPlaying && root.nowPlaying.state === "playing"
  readonly property bool hasTrack: !!(root.nowPlaying && (root.nowPlaying.title || root.nowPlaying.station))

  signal playPauseRequested()
  signal stopRequested()
  signal nextRequested()
  signal prevRequested()
  signal volumeDownRequested()
  signal volumeUpRequested()
  signal startRequested()

  component TransportButton: Rectangle {
    id: btn
    required property string glyph
    property bool enabled: true
    signal activated()

    width: 36
    height: 36
    radius: 18
    color: mouse.containsMouse && btn.enabled ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
    opacity: btn.enabled ? 1 : 0.4

    Text {
      anchors.centerIn: parent
      text: btn.glyph
      color: root.textColor
      font.family: root.fontFamily
      font.pixelSize: 14
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      enabled: btn.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.activated()
    }
  }

  Column {
    anchors.centerIn: parent
    width: parent.width - 32
    spacing: 18
    visible: root.cliampRunning

    Column {
      width: parent.width
      spacing: 6

      Row {
        spacing: 6
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: 7
          height: 7
          radius: 3.5
          color: root.playing ? root.accent : root.muted
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: root.nowPlaying ? (root.nowPlaying.state.charAt(0).toUpperCase() + root.nowPlaying.state.slice(1)) : "Idle"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 10
          font.capitalization: Font.AllUppercase
        }
      }

      Text {
        width: parent.width
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        text: root.hasTrack
          ? (root.nowPlaying.station || root.nowPlaying.title || "Unknown station")
          : "Nothing playing"
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 14
        font.weight: Font.DemiBold
      }

      Text {
        visible: root.hasTrack && root.nowPlaying.station && root.nowPlaying.title && root.nowPlaying.title !== root.nowPlaying.station
        width: parent.width
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        text: root.nowPlaying ? root.nowPlaying.title : ""
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 11
      }

      Text {
        visible: root.hasTrack && !!root.nowPlaying.artist
        width: parent.width
        wrapMode: Text.WordWrap
        maximumLineCount: 1
        elide: Text.ElideRight
        text: root.nowPlaying ? root.nowPlaying.artist : ""
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 10
      }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 10

      TransportButton { glyph: ""; enabled: root.hasTrack; onActivated: root.prevRequested() }
      TransportButton { glyph: root.playing ? "" : ""; enabled: root.hasTrack; onActivated: root.playPauseRequested() }
      TransportButton { glyph: ""; enabled: root.hasTrack; onActivated: root.stopRequested() }
      TransportButton { glyph: ""; enabled: root.hasTrack; onActivated: root.nextRequested() }
    }

    Row {
      anchors.horizontalCenter: parent.horizontalCenter
      spacing: 14

      TransportButton { glyph: ""; onActivated: root.volumeDownRequested() }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: 48
        horizontalAlignment: Text.AlignHCenter
        text: root.nowPlaying && root.nowPlaying.volume !== null ? (Math.round(root.nowPlaying.volume) + " dB") : "—"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 11
      }
      TransportButton { glyph: ""; onActivated: root.volumeUpRequested() }
    }
  }

  // cliamp has no default-running daemon -- this extension starts one
  // headless (--daemon --no-auto-play) on first use rather than making
  // that a precondition the user has to satisfy themselves first.
  Column {
    anchors.centerIn: parent
    width: parent.width - 32
    spacing: 10
    visible: !root.cliampRunning

    Text {
      width: parent.width
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
      text: "Cliamp isn't running"
      color: root.textColor
      font.family: root.fontFamily
      font.pixelSize: 13
    }

    Rectangle {
      anchors.horizontalCenter: parent.horizontalCenter
      width: startLabel.implicitWidth + 28
      height: 30
      radius: 8
      color: startMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)

      Text {
        id: startLabel
        anchors.centerIn: parent
        text: "Start Cliamp Radio"
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 11
      }

      MouseArea {
        id: startMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.startRequested()
      }
    }
  }
}
