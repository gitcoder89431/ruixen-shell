import QtQuick
import "CliampStations.js" as CliampStations

// Right-pane station info for the Cliamp Radio extension. Deliberately
// not a transport controller -- direct follow-up: "on the right panel
// we dont need a controller... we have the notch to control the music
// already". Confirmed live: cliamp registers org.mpris.MediaPlayer2.
// cliamp on D-Bus the instant it starts (playing or not), so the
// notch's own MPRIS-driven media widget already has real play/pause/
// next/prev over it -- duplicating that here would just be a second,
// out-of-sync set of buttons for the same player. This panel shows
// what cliamp actually knows about a station instead: CliampContent.qml
// owns all real state, this only draws what it's told.
Item {
  id: root

  property var selectedRow: null
  property var nowPlaying: null
  property bool cliampRunning: true
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  readonly property var meta: root.selectedRow ? CliampStations.parseStationMeta(root.selectedRow.label) : null
  readonly property bool playing: root.nowPlaying && root.nowPlaying.state === "playing"
  readonly property bool hasNowPlaying: !!(root.nowPlaying && (root.nowPlaying.title || root.nowPlaying.station))

  signal startRequested()

  Column {
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    anchors.topMargin: 12
    width: parent.width - 32
    anchors.horizontalCenter: parent.horizontalCenter
    spacing: 20
    visible: root.cliampRunning

    // Station info -- whatever's highlighted in the list on the left,
    // not necessarily what's playing. Cliamp's own catalog/search rows
    // carry nothing beyond a display name (no separate bitrate/country/
    // art fields, confirmed live), so country and bitrate here are
    // parsed back out of that name rather than invented.
    Column {
      width: parent.width
      spacing: 10
      visible: !!root.selectedRow

      Item {
        width: parent.width
        height: nameText.implicitHeight

        Text {
          id: favoriteGlyph
          visible: root.selectedRow && root.selectedRow.favorite
          anchors.left: parent.left
          anchors.top: parent.top
          text: ""
          color: root.accent
          font.family: root.fontFamily
          font.pixelSize: 12
        }
        Text {
          id: nameText
          anchors.left: favoriteGlyph.visible ? favoriteGlyph.right : parent.left
          anchors.leftMargin: favoriteGlyph.visible ? 6 : 0
          anchors.right: parent.right
          wrapMode: Text.WordWrap
          text: root.meta ? root.meta.name : ""
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 15
          font.weight: Font.DemiBold
        }
      }

      Column {
        width: parent.width
        spacing: 4

        Row {
          visible: root.meta && root.meta.country !== ""
          spacing: 8
          Text { text: "Country"; color: root.muted; font.family: root.fontFamily; font.pixelSize: 10; width: 70 }
          Text { text: root.meta ? root.meta.country : ""; color: root.textColor; font.family: root.fontFamily; font.pixelSize: 11 }
        }
        Row {
          visible: root.meta && root.meta.bitrate !== ""
          spacing: 8
          Text { text: "Bitrate"; color: root.muted; font.family: root.fontFamily; font.pixelSize: 10; width: 70 }
          Text { text: root.meta ? root.meta.bitrate : ""; color: root.textColor; font.family: root.fontFamily; font.pixelSize: 11 }
        }
        Row {
          visible: root.selectedRow && root.selectedRow.providerId === "cliamp-track"
          spacing: 8
          Text { text: "Source"; color: root.muted; font.family: root.fontFamily; font.pixelSize: 10; width: 70 }
          Text {
            width: parent.parent.width - 78
            elide: Text.ElideMiddle
            text: root.selectedRow ? root.selectedRow.trackPath : ""
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 10
          }
        }
        Row {
          visible: root.selectedRow && root.selectedRow.providerId === "cliamp-station"
          spacing: 8
          Text { text: "Source"; color: root.muted; font.family: root.fontFamily; font.pixelSize: 10; width: 70 }
          Text { text: "Cliamp Radio catalog"; color: root.textColor; font.family: root.fontFamily; font.pixelSize: 11 }
        }
      }
    }

    Rectangle {
      visible: !!root.selectedRow && root.hasNowPlaying
      width: parent.width
      height: 1
      color: Qt.rgba(1, 1, 1, 0.1)
    }

    // Read-only -- what's actually on air right now, independent of
    // whichever row happens to be selected above. No controls here;
    // see this file's own header comment for why.
    Column {
      width: parent.width
      spacing: 6
      visible: root.hasNowPlaying

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
          text: "Now Playing · " + (root.nowPlaying ? (root.nowPlaying.state.charAt(0).toUpperCase() + root.nowPlaying.state.slice(1)) : "")
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
        text: root.nowPlaying ? (root.nowPlaying.station || root.nowPlaying.title || "") : ""
        color: root.textColor
        font.family: root.fontFamily
        font.pixelSize: 13
      }

      Text {
        visible: root.nowPlaying && root.nowPlaying.station && root.nowPlaying.title && root.nowPlaying.title !== root.nowPlaying.station
        width: parent.width
        wrapMode: Text.WordWrap
        maximumLineCount: 2
        elide: Text.ElideRight
        text: root.nowPlaying ? root.nowPlaying.title : ""
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 10
      }

      Text {
        visible: root.nowPlaying && !!root.nowPlaying.artist
        width: parent.width
        elide: Text.ElideRight
        text: root.nowPlaying ? root.nowPlaying.artist : ""
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 10
      }
    }

    Text {
      visible: !root.selectedRow
      width: parent.width
      wrapMode: Text.WordWrap
      text: "Select a station to see its details"
      color: root.muted
      font.family: root.fontFamily
      font.pixelSize: 11
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
