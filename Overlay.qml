import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Wayland

// Shape ported pixel-for-pixel from
// ~/REPOS/PLUGINS/quickshell-ambxst/modules/notch/Notch.qml +
// modules/corners/RoundCorner.qml (see the long comment this used to have
// -- unchanged, still applies). This pass ports the DEFAULT VIEW's actual
// widget design too (modules/widgets/defaultview/*.qml): avatar | divider
// | wavy player | divider | bell, matching their mainRow layout. Still
// design-first, not full backend -- bell is a static placeholder (no
// notification service wired up), avatar reads the same ~/.face.icon
// convention they use, wave slider shows real position/length but isn't
// drag-to-seek yet.
//
// The wave itself is WavyLine.qml ported verbatim (modules/components/
// WavyLine.qml) -- a Canvas drawing a sine wave whose phase increments
// off Date.now(), driven by FrameAnimation while playing. Genuinely
// self-contained, no shader/effect dependency.
//
// Icons: ambxst uses a "Phosphor-Bold" icon font for its player controls
// and Material Symbols codepoints for source-app icons (Spotify/Firefox/
// etc via Nerd Font). Phosphor isn't installed here, so kept the same
// Nerd Font glyphs already proven working in ruixen.media/ruixen.dnd
// instead of pulling in a new font dependency for this pass.
Item {
  id: root
  property var shell: null
  property var manifest: null

  readonly property color notchColor: "#000000"
  readonly property color textColor: "#ffffff"
  readonly property color muted: Qt.rgba(1, 1, 1, 0.5)
  readonly property color accent: "#3ecf5b"
  readonly property string fontFamily: "JetBrainsMono Nerd Font"

  readonly property var mediaService: shell ? shell.firstPartyServiceFor("ruixen.media") : null

  // Same first-party service ruixen.dnd reads -- the bell here just
  // reflects the real state, doesn't own it.
  readonly property var notificationService: shell ? shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property bool isPlaying: activePlayer ? activePlayer.isPlaying === true : false
  readonly property string playIcon: isPlaying ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string artUrl: activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""

  // ambxst falls back to the focused window's title, then "user@host",
  // rather than ever showing a blank "no media" state. We don't have a
  // compositor-window-title service wired up (that's ruixen.bar's own
  // ActiveWindow territory, unrelated to this plugin), so fall back
  // straight to user@host for now.
  readonly property string userHost: Quickshell.env("USER") + "@" + Quickshell.env("HOSTNAME")
  readonly property string displayedTitle: hasMedia
    ? (artist ? artist + " - " + title : title)
    : userHost

  property real trackPosition: 0
  readonly property real trackLength: activePlayer ? Math.max(0, Number(activePlayer.length || 0)) : 0
  readonly property real progressRatio: trackLength > 0 ? Math.min(1, trackPosition / trackLength) : 0

  function syncPosition() {
    trackPosition = activePlayer ? Math.max(0, Number(activePlayer.position || 0)) : 0
  }

  function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(value / 60)
    var rest = value % 60
    return minutes + ":" + String(rest).padStart(2, "0")
  }

  Timer {
    interval: 500
    repeat: true
    running: root.isPlaying
    triggeredOnStart: true
    onTriggered: root.syncPosition()
  }

  // Quarter-circle silhouette, one corner at a time -- used as mask
  // material for the concave flanks. Ported verbatim from RoundCorner.qml.
  component RoundCorner: Item {
    id: rc
    // 0 TopLeft, 1 TopRight, 2 BottomLeft, 3 BottomRight
    property int corner: 0
    property int cornerSize: 20
    property color fillColor: "#ffffff"

    implicitWidth: cornerSize
    implicitHeight: cornerSize

    onFillColorChanged: canvas.requestPaint()
    onCornerChanged: canvas.requestPaint()
    onCornerSizeChanged: canvas.requestPaint()
    onVisibleChanged: if (visible) canvas.requestPaint()

    Canvas {
      id: canvas
      anchors.fill: parent
      antialiasing: true
      onPaint: {
        var ctx = getContext("2d")
        var r = rc.cornerSize
        ctx.clearRect(0, 0, width, height)
        ctx.beginPath()
        switch (rc.corner) {
          case 0: ctx.arc(r, r, r, Math.PI, 3 * Math.PI / 2); ctx.lineTo(0, 0); break
          case 1: ctx.arc(0, r, r, 3 * Math.PI / 2, 2 * Math.PI); ctx.lineTo(r, 0); break
          case 2: ctx.arc(r, 0, r, Math.PI / 2, Math.PI); ctx.lineTo(0, r); break
          case 3: ctx.arc(0, 0, r, 0, Math.PI / 2); ctx.lineTo(r, r); break
        }
        ctx.closePath()
        ctx.fillStyle = rc.fillColor
        ctx.fill()
      }
    }
  }

  // Ported verbatim from WavyLine.qml. The actual "wave" -- a sine wave
  // whose phase increments off Date.now(), so it undulates continuously
  // while `running`, redrawn every frame via FrameAnimation.
  component WavyLine: Canvas {
    id: wave
    property color lineColor: "#ffffff"
    property real lineWidth: 2
    property real frequency: 2
    property real amplitudeMultiplier: 0.5
    property real fullLength: width
    property bool running: true

    readonly property bool shouldAnimate: running && visible && width > 0 && opacity > 0

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (width <= 0 || height <= 0) return

      var amp = wave.lineWidth * wave.amplitudeMultiplier
      var freq = wave.frequency
      var phase = Date.now() / 400.0
      var centerY = height / 2

      ctx.strokeStyle = wave.lineColor
      ctx.lineWidth = wave.lineWidth
      ctx.lineCap = "round"
      ctx.beginPath()

      for (var x = ctx.lineWidth / 2; x <= wave.width - ctx.lineWidth / 2; x += 1) {
        var waveY = centerY + amp * Math.sin(freq * 2 * Math.PI * x / wave.fullLength + phase)
        if (x === ctx.lineWidth / 2) ctx.moveTo(x, waveY)
        else ctx.lineTo(x, waveY)
      }
      ctx.stroke()
    }

    FrameAnimation {
      running: wave.shouldAnimate
      onTriggered: wave.requestPaint()
    }
  }

  // Small circular user avatar, same ~/.face.icon convention as
  // UserInfo.qml. Falls back to a plain dark circle if the file doesn't
  // exist -- Image just shows nothing, the Rectangle behind it still
  // reads as an avatar-shaped placeholder.
  component UserAvatar: Item {
    id: avatar
    property int avatarSize: 20

    implicitWidth: avatarSize
    implicitHeight: avatarSize

    // Placeholder shown until/unless ~/.face.icon exists -- a gradient
    // circle instead of a shipped PNG asset, so there's no fixed
    // resolution/ratio to pick and it scales cleanly at any avatarSize.
    // Sits underneath the real image below; once that loads it fully
    // covers this (opaque), so no conditional visibility needed.
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      gradient: Gradient {
        GradientStop { position: 0.0; color: "#5b6ee8" }
        GradientStop { position: 1.0; color: "#8a4fd6" }
      }
    }

    Image {
      id: avatarImage
      anchors.fill: parent
      source: "file://" + Quickshell.env("HOME") + "/.face.icon"
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      visible: false
    }

    // Item.clip is rectangular -- circular crop needs an actual mask,
    // same MultiEffect technique as the notch shape itself.
    Rectangle {
      id: avatarMask
      anchors.fill: parent
      radius: width / 2
      color: "#ffffff"
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: parent
      source: avatarImage
      maskEnabled: true
      maskSource: avatarMask
      maskThresholdMin: 0.5
      maskThresholdMax: 1.0
    }
  }

  // Thin vertical divider, ported from Separator.qml.
  component NotchSeparator: Rectangle {
    implicitWidth: 1
    implicitHeight: 16
    color: "#ffffff"
    opacity: 0.1
  }

  PanelWindow {
    id: panel
    visible: true
    anchors { top: true; left: true; right: true }
    implicitHeight: 220
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "ruixen-notch"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    mask: Region {
      x: notchOuter.x
      y: notchOuter.y
      width: notchOuter.width
      height: notchOuter.height
    }

    property bool pinnedOpen: false
    property bool hoverOpen: false
    readonly property bool expanded: pinnedOpen || hoverOpen

    Item {
      id: notchOuter
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      readonly property int cornerSize: 18
      readonly property int bodyWidth: panel.expanded ? 360 : 220
      width: bodyWidth + cornerSize * 2
      height: panel.expanded ? 190 : 36

      Behavior on width { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
      Behavior on height { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }

      // Painted background, masked into the notch silhouette below.
      Rectangle {
        id: notchBg
        anchors.fill: parent
        color: root.notchColor

        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: notchMask
          maskThresholdMin: 0.5
          maskThresholdMax: 1.0
          maskSpreadAtMin: 1.0
        }

        // Blurred album-art background, matching CompactPlayer.qml's
        // backgroundArt treatment. Only visible when there is art and
        // the notch is collapsed to a plain single-row pill -- once
        // expanded the art moves into its own small thumbnail instead
        // (see below), same as ambxst fading the full-bleed art out on
        // hover.
        Image {
          id: bgArt
          anchors.fill: parent
          source: root.artUrl
          sourceSize: Qt.size(64, 64)
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          visible: false
        }

        MultiEffect {
          anchors.fill: bgArt
          source: bgArt
          blurEnabled: root.artUrl !== ""
          blurMax: 32
          blur: 0.75
          opacity: (root.artUrl !== "" && !panel.expanded) ? 0.35 : 0.0
          Behavior on opacity { NumberAnimation { duration: 200 } }
        }
      }

      // Mask silhouette: left flank (concave toward center) + center
      // block (square top, animated round bottom) + right flank
      // (concave toward center). Never drawn directly -- only sampled
      // as texture by notchBg's layer.effect above.
      Item {
        id: notchMask
        visible: false
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true

        RoundCorner {
          id: leftFlank
          anchors.top: parent.top
          anchors.left: parent.left
          cornerSize: notchOuter.cornerSize
          corner: 1
          fillColor: "#ffffff"
        }

        Rectangle {
          id: centerMask
          anchors.top: parent.top
          anchors.left: leftFlank.right
          anchors.right: rightFlank.left
          height: parent.height
          color: "#ffffff"
          topLeftRadius: 0
          topRightRadius: 0
          bottomLeftRadius: panel.expanded ? 26 : 16
          bottomRightRadius: panel.expanded ? 26 : 16

          Behavior on bottomLeftRadius { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
          Behavior on bottomRightRadius { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
        }

        RoundCorner {
          id: rightFlank
          anchors.top: parent.top
          anchors.right: parent.right
          cornerSize: notchOuter.cornerSize
          corner: 0
          fillColor: "#ffffff"
        }
      }

      MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onEntered: panel.hoverOpen = true
        onExited: panel.hoverOpen = false
        onClicked: panel.pinnedOpen = !panel.pinnedOpen
      }

      Item {
        anchors.fill: parent
        anchors.leftMargin: notchOuter.cornerSize
        anchors.rightMargin: notchOuter.cornerSize
        clip: true

        // Collapsed: avatar | divider | play glyph + small wave | divider | bell.
        // Matches DefaultView.qml's mainRow layout.
        Row {
          id: collapsedContent
          visible: !panel.expanded
          opacity: panel.expanded ? 0 : 1
          anchors.centerIn: parent
          spacing: 8
          Behavior on opacity { NumberAnimation { duration: 140 } }

          UserAvatar { anchors.verticalCenter: parent.verticalCenter }
          NotchSeparator { anchors.verticalCenter: parent.verticalCenter }

          Row {
            anchors.verticalCenter: parent.verticalCenter
            spacing: 6

            Text {
              id: collapsedPlayGlyph
              anchors.verticalCenter: parent.verticalCenter
              text: root.playIcon
              color: root.hasMedia ? root.textColor : root.muted
              font.family: root.fontFamily
              font.pixelSize: 11

              // Own click target, same reasoning as ruixen.media's play
              // badge: this sits inside the notch's big MouseArea
              // (hover=expand, click=pin), so without its own handler a
              // click here would just toggle the pin instead of playback.
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                enabled: root.hasMedia
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false)
              }
            }

            // Track (full length, dim) + wave (played portion only, up
            // to progressRatio) -- actually reflects position now,
            // instead of a decorative full-width wave. No drag-to-seek
            // yet, position display only.
            Item {
              anchors.verticalCenter: parent.verticalCenter
              width: 60
              height: 12

              Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width
                height: 2
                radius: 1
                color: Qt.rgba(1, 1, 1, 0.15)
              }

              WavyLine {
                width: parent.width * root.progressRatio
                height: parent.height
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                lineColor: root.hasMedia ? root.accent : root.muted
                lineWidth: 2
                frequency: 6
                amplitudeMultiplier: root.isPlaying ? 1.4 : 0.15
                fullLength: 60
                running: root.isPlaying
              }
            }
          }

          NotchSeparator { anchors.verticalCenter: parent.verticalCenter }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰂛"
            color: root.dnd ? "#e05252" : root.muted
            font.family: root.fontFamily
            font.pixelSize: 12

            Behavior on color { ColorAnimation { duration: 160 } }
          }
        }

        // Expanded: blurred-art thumbnail, title/artist, big wave
        // progress, transport controls.
        Column {
          id: expandedContent
          visible: panel.expanded
          opacity: panel.expanded ? 1 : 0
          anchors.fill: parent
          anchors.topMargin: 20
          anchors.bottomMargin: 12
          spacing: 10
          Behavior on opacity { NumberAnimation { duration: 160 } }

          Row {
            width: parent.width
            spacing: 10

            Item {
              width: 36
              height: 36
              anchors.verticalCenter: parent.verticalCenter
              visible: root.artUrl !== ""

              Rectangle {
                anchors.fill: parent
                radius: 8
                color: "transparent"
                clip: true

                Image {
                  anchors.fill: parent
                  source: root.artUrl
                  sourceSize: Qt.size(72, 72)
                  fillMode: Image.PreserveAspectCrop
                  asynchronous: true
                }
              }
            }

            Column {
              anchors.verticalCenter: parent.verticalCenter
              width: parent.width - (root.artUrl !== "" ? 46 : 0)
              spacing: 2

              Text {
                text: root.title || root.userHost
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 13
                font.weight: Font.Bold
                elide: Text.ElideRight
                width: parent.width
              }

              Text {
                text: root.artist
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: 10
                elide: Text.ElideRight
                width: parent.width
                visible: text !== ""
              }
            }
          }

          Item {
            id: expandedProgress
            width: parent.width
            height: 22
            visible: root.trackLength > 0

            Rectangle {
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: 6
              height: 2
              radius: 1
              color: Qt.rgba(1, 1, 1, 0.15)
            }

            WavyLine {
              anchors.left: parent.left
              anchors.top: parent.top
              width: parent.width * root.progressRatio
              height: 14
              lineColor: root.accent
              lineWidth: 2
              frequency: 10
              amplitudeMultiplier: root.isPlaying ? 1.2 : 0.1
              fullLength: parent.width
              running: root.isPlaying
            }

            // Position marker -- no drag-to-seek yet, display only.
            Rectangle {
              width: 6
              height: 6
              radius: 3
              color: root.textColor
              anchors.verticalCenter: parent.top
              anchors.verticalCenterOffset: 7
              x: parent.width * root.progressRatio - width / 2
              visible: root.hasMedia

              Behavior on x { NumberAnimation { duration: 450 } }
            }

            Text {
              anchors.left: parent.left
              anchors.top: parent.top
              anchors.topMargin: 16
              text: root.formatTime(root.trackPosition)
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 9
            }

            Text {
              anchors.right: parent.right
              anchors.top: parent.top
              anchors.topMargin: 16
              text: root.formatTime(root.trackLength)
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 9
            }
          }

          Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 18

            Text {
              text: "󰒮"
              color: root.activePlayer && root.activePlayer.canGoPrevious ? root.textColor : Qt.rgba(1, 1, 1, 0.3)
              font.family: root.fontFamily
              font.pixelSize: 13

              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.mediaService) root.mediaService.runAction("previous", false)
              }
            }

            Text {
              text: root.playIcon
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 16

              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false)
              }
            }

            Text {
              text: "󰒭"
              color: root.activePlayer && root.activePlayer.canGoNext ? root.textColor : Qt.rgba(1, 1, 1, 0.3)
              font.family: root.fontFamily
              font.pixelSize: 13

              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.mediaService) root.mediaService.runAction("next", false)
              }
            }
          }
        }
      }
    }
  }
}
