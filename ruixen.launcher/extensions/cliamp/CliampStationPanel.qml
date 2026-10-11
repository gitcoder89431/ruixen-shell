import QtQuick
import "CliampStations.js" as CliampStations
import "CliampFavorites.js" as CliampFavorites

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

  // Live-ticking "how long you've been listening" clock -- re-synced
  // to cliamp's own real position every status poll (onNowPlayingChanged),
  // then advanced locally once a second in between polls so it reads
  // as genuinely alive rather than jumping every 2s with the poll
  // interval. Frozen (Timer stopped) while paused rather than counting
  // through a pause that isn't really elapsed listening time.
  property real elapsedBase: 0
  property real elapsedBaseAt: 0
  property int elapsedTick: 0

  function syncElapsed() {
    root.elapsedBase = (root.nowPlaying && typeof root.nowPlaying.position === "number") ? root.nowPlaying.position : 0
    root.elapsedBaseAt = Date.now()
  }

  onNowPlayingChanged: root.syncElapsed()

  readonly property string elapsedText: {
    root.elapsedTick // dependency only -- forces re-evaluation every tick
    var secs = root.elapsedBase + (Date.now() - root.elapsedBaseAt) / 1000
    return CliampStations.formatElapsed(secs)
  }

  Timer {
    interval: 1000
    running: root.playing
    repeat: true
    onTriggered: root.elapsedTick++
  }

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
    // Our own local layer (see CliampContent.qml's own header for why
    // it isn't cliamp's own data) -- last row in the group rather than
    // ahead of Source, direct follow-up. Omitted entirely for a
    // station never played this way before, same "skip empty"
    // convention every other field here already follows.
    var lastPlayed = CliampFavorites.formatLastPlayed(root.selectedRow.lastPlayedAt)
    if (lastPlayed !== "") out.push({ label: "Last Played", value: lastPlayed })
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
    // treatment ThemeBrowserContent.qml's own preview box uses (radius
    // 10, dark tint). Direct follow-up after the first text-only pass
    // read as flat: "it needs to be like atleast better... more
    // spotify" -- an avatar tile standing in for the art cliamp
    // doesn't have (direct follow-up: swapped from a plain monogram
    // letter to a play/pause glyph reflecting the real state, same
    // idea as a play-button overlay on art everywhere else), a
    // LIVE/PAUSED badge, and a live-ticking elapsed clock are what
    // make this read as a real player card instead of a
    // status line (a blurred-wallpaper backdrop, the notch's own
    // trick, was considered and dropped -- it'd just be decorating
    // with the wallpaper, unrelated to the station actually playing).
    Rectangle {
      id: nowPlayingCard
      width: parent.width
      height: nowPlayingContent.implicitHeight + 24
      radius: 10
      color: Qt.rgba(0, 0, 0, 0.22)

      Row {
        id: nowPlayingContent
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.margins: 12
        spacing: 12

        Rectangle {
          id: avatarTile
          anchors.verticalCenter: parent.verticalCenter
          width: 52
          height: 52
          radius: 10
          color: root.hasNowPlaying ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.22) : Qt.rgba(1, 1, 1, 0.06)

          // Read-only status, not a label on a clickable control --
          // the tile still isn't a button (the notch owns transport),
          // same idea as the LIVE/PAUSED badge already is. Paused
          // shows a plain play glyph; while actually playing, direct
          // follow-up: "instead of the pause button showing... can we
          // do like a bar spectrum wave animation icon thing instead"
          // -- three bars on their own fixed-duration loop (eqBars
          // below) rather than a static glyph.
          Text {
            anchors.centerIn: parent
            visible: root.hasNowPlaying && !root.playing
            text: ""
            color: root.accent
            font.family: root.fontFamily
            font.pixelSize: 20
          }
          Text {
            anchors.centerIn: parent
            visible: !root.hasNowPlaying
            text: ""
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 18
          }

          // Each bar runs its own fixed min/max/duration loop rather
          // than a shared one -- different durations put them out of
          // phase with each other for free, no randomness needed (and
          // nothing to re-seed), so it reads as a live spectrum
          // instead of three bars bouncing in mechanical unison.
          Row {
            id: eqBars
            visible: root.playing
            anchors.centerIn: parent
            height: 16
            spacing: 3

            Repeater {
              model: [
                { min: 4, max: 15, duration: 420 },
                { min: 6, max: 17, duration: 340 },
                { min: 4, max: 13, duration: 500 }
              ]

              delegate: Rectangle {
                id: eqBar
                required property var modelData
                width: 3
                radius: 1.5
                color: root.accent
                anchors.bottom: parent.bottom
                height: modelData.min

                SequentialAnimation on height {
                  running: root.playing
                  loops: Animation.Infinite
                  NumberAnimation { to: eqBar.modelData.max; duration: eqBar.modelData.duration; easing.type: Easing.InOutSine }
                  NumberAnimation { to: eqBar.modelData.min; duration: eqBar.modelData.duration; easing.type: Easing.InOutSine }
                }
              }
            }
          }
        }

        Column {
          width: parent.width - avatarTile.width - parent.spacing
          spacing: 4

          // Badge + elapsed clock live ON the title line itself, not a
          // row of their own above it -- direct report: "kinda
          // jumpy... dont want a new row to come in and out". That
          // row's own visible: hasNowPlaying meant the card gained or
          // lost an entire line (and resized) every time playback
          // started/stopped/paused. One fixed-height line now, always
          // present, with the title truncating to make room instead.
          //
          // Badge/clock sit right-aligned in their own group rather
          // than leading the line -- direct follow-up: having them
          // come first read as backwards, since the station name is
          // the actual headline here. Row (not manual anchor-chaining)
          // for the group since Row already skips invisible children
          // when sizing itself, so liveBadge/pausedLabel swapping
          // in and out never leaves a gap for elapsedLabel to chase.
          Item {
            id: titleRow
            width: parent.width
            height: Math.max(titleText.implicitHeight, statusPill.height)

            Text {
              id: titleText
              anchors.left: parent.left
              anchors.right: statusPill.left
              anchors.rightMargin: root.hasNowPlaying ? 8 : 0
              anchors.verticalCenter: parent.verticalCenter
              elide: Text.ElideRight
              maximumLineCount: 1
              text: root.hasNowPlaying ? (root.nowPlaying.station || root.nowPlaying.title || "") : "Nothing playing"
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 14
              font.weight: Font.DemiBold
            }

            // Badge + clock as one grouped pill (direct follow-up:
            // "group them together so it looks like a tab design, but
            // like keep the live part colored") rather than two loose
            // floating pieces. Per-corner radius on each segment
            // (round on its outer edge, square on the inner seam)
            // instead of a clip:true mask -- clip only clips to an
            // item's rectangular bounding box, never to its own
            // radius, so that first pass actually rendered square
            // corners despite radius: height/2 on the mask (direct
            // report: "no sharp edges... make the corners round as
            // well"). Same per-corner pattern BarPanel.qml's own
            // docked-chrome pills already use elsewhere in this repo.
            Item {
              id: statusPill
              visible: root.hasNowPlaying
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: pillRow.implicitWidth
              height: 15

              Row {
                id: pillRow
                height: parent.height
                spacing: 0

                Rectangle {
                  height: parent.height
                  width: statusLabel.implicitWidth + 16
                  color: root.playing ? root.accent : Qt.rgba(1, 1, 1, 0.12)
                  topLeftRadius: height / 2
                  bottomLeftRadius: height / 2
                  Text {
                    id: statusLabel
                    anchors.centerIn: parent
                    text: root.playing ? "LIVE" : "PAUSED"
                    color: root.playing ? "#000000" : root.muted
                    font.family: root.fontFamily
                    font.pixelSize: 9
                    font.bold: true
                  }
                }
                Rectangle {
                  height: parent.height
                  width: elapsedLabel.implicitWidth + 14
                  color: Qt.rgba(1, 1, 1, 0.06)
                  topRightRadius: height / 2
                  bottomRightRadius: height / 2
                  Text {
                    id: elapsedLabel
                    anchors.centerIn: parent
                    text: root.elapsedText
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: 10
                  }
                }
              }
            }
          }

          Text {
            visible: root.hasNowPlaying && root.nowPlaying.station && root.nowPlaying.title && root.nowPlaying.title !== root.nowPlaying.station
            width: parent.width
            elide: Text.ElideRight
            maximumLineCount: 1
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
