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

  // EQ -- a global player setting, not per-station (see the EQ
  // section's own comment below for the full story). CliampContent.qml
  // owns the real preset list and the actual cliamp eq call; this
  // panel just draws whichever one is currently active and reports a
  // tap back up, same split every other piece of state in this panel
  // already follows.
  property var eqPresets: []
  readonly property string eqPreset: root.nowPlaying ? (root.nowPlaying.eqPreset || "Flat") : "Flat"
  signal eqPresetSelected(string name)

  // Packs the preset list into center-able rows instead of leaving it
  // to a plain Flow -- direct follow-up once all 15 shipped: "center
  // these chips so they line up better" (a Flow always left-aligns
  // every row, which reads fine for a full row but leaves a short
  // last row sitting flush-left with a big ragged gap on the right).
  // eqFontMetrics (declared alongside the chip delegates below, same
  // font/pixelSize as their own label Text) gives the real measured
  // width per label -- this plugin's own fontFamily is monospace, but
  // measuring directly instead of estimating by character count is
  // both just as cheap and genuinely exact, not an approximation that
  // could drift from what actually renders.
  function packEqRows(presets, maxWidth) {
    var rows = []
    var current = []
    var currentWidth = 0
    var spacing = 6
    for (var i = 0; i < presets.length; i++) {
      var chipWidth = eqFontMetrics.advanceWidth(presets[i]) + 20
      var neededWidth = current.length === 0 ? chipWidth : currentWidth + spacing + chipWidth
      if (current.length > 0 && neededWidth > maxWidth) {
        rows.push(current)
        current = [presets[i]]
        currentWidth = chipWidth
      } else {
        current.push(presets[i])
        currentWidth = neededWidth
      }
    }
    if (current.length > 0) rows.push(current)
    return rows
  }

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

    // Radio -- pinned at the top regardless of list selection (what's
    // actually on air can be a different station from whichever row is
    // merely highlighted below). Same rounded-card treatment
    // ThemeBrowserContent.qml's own preview box uses (radius 10, dark
    // tint). Direct follow-up after the first text-only pass read as
    // flat: "it needs to be like atleast better... more spotify" -- an
    // avatar tile standing in for the art cliamp doesn't have (direct
    // follow-up: swapped from a plain monogram letter to a play/pause
    // glyph reflecting the real state, same idea as a play-button
    // overlay on art everywhere else), a LIVE/PAUSED badge, and a
    // live-ticking elapsed clock are what make this read as a real
    // player card instead of a status line (a blurred-wallpaper
    // backdrop, the notch's own trick, was considered and dropped --
    // it'd just be decorating with the wallpaper, unrelated to the
    // station actually playing).
    //
    // Its own "Radio" header now, same plain muted-uppercase label
    // Metadata already uses below -- direct follow-up: "splitting them
    // out and putting the equalizer header for the equalizer group, so
    // it will be Radio Equalizer Metadata as the three group". EQ used
    // to live inside this same card (an earlier follow-up: "extend the
    // dark bg from the player to include the equalizer section too");
    // it's its own group again below now, with its own matching dark
    // card rather than sharing this one -- direct follow-up: "keep the
    // equalizer like having that darker panel underneath".
    Column {
      width: parent.width
      spacing: 12

      Text {
        text: "Radio"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 10
        font.capitalization: Font.AllUppercase
        font.bold: true
      }

      Rectangle {
        id: nowPlayingCard
        width: parent.width
        height: cardBody.implicitHeight + 24
        radius: 10
        color: Qt.rgba(0, 0, 0, 0.22)

        Column {
          id: cardBody
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 12

          Row {
            id: nowPlayingContent
            width: parent.width
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
      }
    }

    // EQ -- direct follow-up: "the equalizer options between the
    // player and metadata might be a nice touch if easy to add in". A
    // global player setting (cliamp's own `cliamp eq` command), not
    // tied to whichever station happens to be selected, so this sits
    // in its own group between Radio and Metadata rather than inside
    // either -- same "always visible regardless of list selection"
    // reasoning Radio's own header comment gives. All 15 of cliamp's
    // own real presets, not a curated subset -- direct follow-up once
    // a first pass shipped six: "we do have space... theres alot of
    // empty space on the panel anyways". Its own "Equalizer" header
    // now, matching Radio/Metadata -- direct follow-up: "splitting
    // them out and putting the equalizer header for the equalizer
    // group, so it will be Radio Equalizer Metadata as the three
    // group" (an earlier pass here had deliberately removed a label:
    // "remove the equalizer text row and then center these chips so
    // they line up better" -- centering itself (packEqRows' own
    // comment above covers why a plain Flow couldn't do that alone)
    // stays, just with a header above it again now that it's a real
    // top-level group rather than a sub-section of Radio). Same chip
    // look as ClipboardContent.qml's own Type/Sort row (24px pills,
    // accent-tinted when active) -- direct follow-up for visual
    // consistency across the plugin's own extensions.
    Column {
      width: parent.width
      spacing: 12

      Text {
        text: "Equalizer"
        color: root.muted
        font.family: root.fontFamily
        font.pixelSize: 10
        font.capitalization: Font.AllUppercase
        font.bold: true
      }

      // Same dark card treatment as Radio's own nowPlayingCard, not
      // left unfilled like Metadata -- direct follow-up: "keep the
      // equalizer like having that darker panel underneath".
      Rectangle {
        id: eqCard
        width: parent.width
        height: eqColumn.implicitHeight + 24
        radius: 10
        color: Qt.rgba(0, 0, 0, 0.22)

        Column {
          id: eqColumn
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.margins: 12
          spacing: 6

          FontMetrics {
            id: eqFontMetrics
            font.family: root.fontFamily
            font.pixelSize: 11
          }

          Repeater {
            model: root.packEqRows(root.eqPresets, eqColumn.width)

            Row {
              id: eqChipRow
              required property var modelData
              anchors.horizontalCenter: parent.horizontalCenter
              spacing: 6

              Repeater {
                model: eqChipRow.modelData

                Rectangle {
                  id: eqChip
                  required property string modelData
                  readonly property bool isActive: root.eqPreset === modelData
                  width: eqChipLabel.implicitWidth + 20
                  height: 24
                  radius: 6
                  color: isActive ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : Qt.rgba(1, 1, 1, 0.06)
                  border.width: 1
                  border.color: isActive ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) : Qt.rgba(1, 1, 1, 0.12)

                  Text {
                    id: eqChipLabel
                    anchors.centerIn: parent
                    text: eqChip.modelData
                    color: root.textColor
                    font.family: root.fontFamily
                    font.pixelSize: 11
                  }

                  MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.eqPresetSelected(eqChip.modelData)
                  }
                }
              }
            }
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
