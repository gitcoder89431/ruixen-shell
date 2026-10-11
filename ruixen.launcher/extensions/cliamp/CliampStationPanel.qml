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
//
// Layout direct follow-up: "the now playing thing should be on top...
// look at our bjarneo [theme browser] layout... pretend that section
// on top is for now playing, and then zebra lines for the metadata".
// ThemeBrowserContent.qml's own right pane is the real precedent here
// (WallpapersContent.qml's own detail panel was removed a while back,
// despite stale comments elsewhere implying it still exists): a
// featured box on top, then a "Metadata" header and zebra-striped
// label/value rows below it -- same row shape Search Files' own
// FileDetailsPanel.qml originated (even-index rows tinted
// Qt.rgba(0,0,0,0.18), outdented -10/-4, radius 4). Cliamp has no
// station art to put in that top box (confirmed live against both its
// IPC and MPRIS Metadata), so Now Playing status takes that featured
// spot instead -- it's the one thing here that's genuinely global
// rather than per-row, so it reads naturally as the "always-on" top
// element the way a preview image would.
Item {
  id: root

  property var selectedRow: null
  property var nowPlaying: null
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  // fullName, not label -- the list row's own label has the country
  // suffix already stripped for a tighter list (direct follow-up), but
  // this panel still shows Country as its own field, so it needs the
  // untrimmed name to parse that back out of.
  readonly property var meta: root.selectedRow ? CliampStations.parseStationMeta(root.selectedRow.fullName || root.selectedRow.label) : null
  readonly property bool playing: root.nowPlaying && root.nowPlaying.state === "playing"
  readonly property bool hasNowPlaying: !!(root.nowPlaying && (root.nowPlaying.title || root.nowPlaying.station))

  // One row per known field, skipping anything with no value so the
  // zebra tint (by array position) never leaves a gap over an empty
  // row. Name goes through this same list rather than a separate
  // title -- same shape ThemeBrowserContent.qml's own first "Name" row
  // already uses ahead of its other metadata, so this reads as the
  // same convention everywhere it shows up in this plugin.
  readonly property var metadataFields: {
    if (!root.selectedRow) return []
    var out = []
    var name = root.meta ? root.meta.name : root.selectedRow.label
    out.push({ label: "Name", value: (root.selectedRow.favorite ? "★ " : "") + name })
    if (root.meta && root.meta.country !== "") out.push({ label: "Country", value: root.meta.country })
    if (root.meta && root.meta.bitrate !== "") out.push({ label: "Bitrate", value: root.meta.bitrate })
    out.push({
      label: "Source",
      value: root.selectedRow.providerId === "cliamp-track"
        ? (root.selectedRow.trackPath || "")
        : "Cliamp Radio catalog"
    })
    return out
  }

  Column {
    anchors.top: parent.top
    anchors.topMargin: 12
    anchors.horizontalCenter: parent.horizontalCenter
    width: parent.width - 32
    spacing: 16

    // Now Playing -- pinned at the top regardless of list selection
    // (what's actually on air can be a different station from
    // whichever row is merely highlighted below). Same rounded-card
    // treatment ThemeBrowserContent.qml's own preview box uses
    // (radius 10, dark tint) so this reads as the same "featured top
    // slot" pattern even without an image inside it.
    Rectangle {
      id: nowPlayingCard
      width: parent.width
      height: nowPlayingContent.implicitHeight + 24
      radius: 10
      color: Qt.rgba(0, 0, 0, 0.22)

      Column {
        id: nowPlayingContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 12
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
            text: "Now Playing" + (root.hasNowPlaying
              ? " · " + (root.nowPlaying.state.charAt(0).toUpperCase() + root.nowPlaying.state.slice(1))
              : "")
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
          text: root.hasNowPlaying ? (root.nowPlaying.station || root.nowPlaying.title || "") : "Nothing playing"
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 14
          font.weight: Font.DemiBold
        }

        Text {
          visible: root.hasNowPlaying && root.nowPlaying.station && root.nowPlaying.title && root.nowPlaying.title !== root.nowPlaying.station
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
          visible: root.hasNowPlaying && !!root.nowPlaying.artist
          width: parent.width
          elide: Text.ElideRight
          text: root.nowPlaying ? root.nowPlaying.artist : ""
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 10
        }
      }
    }

    // Station metadata -- whatever's highlighted in the list, zebra
    // rows same as FileDetailsPanel.qml's own (see this file's header
    // comment). Cliamp's own catalog/search rows carry nothing beyond
    // a display name (no separate bitrate/country/art fields,
    // confirmed live), so everything here except Source is parsed back
    // out of that name rather than invented.
    Column {
      width: parent.width
      spacing: 12
      visible: root.metadataFields.length > 0

      Text {
        text: "Metadata"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 10
        font.capitalization: Font.AllUppercase
        font.bold: true
      }

      Repeater {
        model: root.metadataFields

        Item {
          id: field
          required property var modelData
          required property int index
          width: parent.width
          height: 19

          Rectangle {
            anchors.fill: parent
            anchors.leftMargin: -10
            anchors.rightMargin: -10
            anchors.topMargin: -4
            anchors.bottomMargin: -4
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
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 13
          }
        }
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
}
