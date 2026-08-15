import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

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
  // Same theme-aware-with-safety-net treatment as ruixen.bar's
  // pillForeground (see Bar.qml for the full reasoning): this notch is
  // always OLED black too, so use the theme's own foreground when it's
  // light enough to read against that, else fall back to a fixed light
  // color. Keeps each theme's actual look (off-white on nearly every
  // dark theme) instead of a single hardcoded white, while still
  // catching the real exceptions (light themes, Rose Pine's dark
  // purple foreground).
  readonly property color themeForeground: Color.bar.text
  readonly property real themeForegroundLuminance: 0.299 * themeForeground.r + 0.587 * themeForeground.g + 0.114 * themeForeground.b
  readonly property color safeForeground: "#e8e8e8"
  readonly property color textColor: themeForegroundLuminance > 0.45 ? themeForeground : safeForeground
  readonly property color muted: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5)
  // Deliberately not theme-linked -- a fixed "media is active" semantic
  // color, same pattern as ruixen.media's green/yellow play-pause badge.
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
  // Gated on hasMedia, not just activePlayer -- a closed app can leave a
  // zombie MPRIS registration behind (confirmed: chromium after quitting
  // still owns org.mpris.MediaPlayer2.chromium.* on the session bus,
  // PlaybackStatus "Stopped", with a stale mpris:artUrl but no title/
  // artist). Without this gate the blurred background art below kept
  // showing that stale art forever since it only checked "is artUrl
  // non-empty", not whether there's actually anything playing.
  readonly property string artUrl: hasMedia && activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""

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
    implicitWidth: 3
    implicitHeight: 16
    radius: width / 2
    color: root.textColor
    opacity: 0.1
  }

  // Left-side vertical tab-bar button, matching ambxst's Dashboard.qml
  // tabsContainer icon buttons (Widgets/Wallpapers/Metrics stacked, plus
  // a settings gear pinned at the bottom). Just a plain icon + tonal
  // hover/active background, no ambxst StyledRect dependency, same
  // approach as every other component ported into this file.
  component TabButton: Rectangle {
    id: tabBtn
    property string glyph: ""
    property bool active: false
    signal activated()

    Layout.preferredWidth: 30
    Layout.preferredHeight: 30
    Layout.alignment: Qt.AlignHCenter
    radius: 8
    color: active ? Qt.rgba(1, 1, 1, 0.14) : (tabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: tabBtn.glyph
      color: tabBtn.active ? root.accent : root.textColor
      font.family: root.fontFamily
      font.pixelSize: 14
    }

    MouseArea {
      id: tabMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tabBtn.activated()
    }
  }

  PanelWindow {
    id: panel
    visible: true
    // bottom:true too, not just top/left/right -- the click-away-to-
    // dismiss MouseArea (see below) needs the panel's own surface to
    // actually reach the full screen height for its widened mask to
    // cover anywhere outside the notch. Anchoring both top and bottom
    // makes the surface fill the full height regardless of
    // implicitHeight; exclusionMode stays Ignore so this never reserves
    // screen space the way ruixen.bar's own window does.
    anchors { top: true; left: true; right: true; bottom: true }
    margins.top: 4
    implicitHeight: 220
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "ruixen-notch"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // Stays None always -- the launcher is click-only (a few favorite
    // app icons, no search box), so this surface never needs keyboard
    // input, same as every other passive hover state in this file.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Widens to the full panel only while the launcher is open, so a
    // click anywhere outside the notch itself actually reaches this
    // surface (see dismissArea below) instead of passing straight
    // through to whatever's behind, like every other collapsed/media
    // state does via the tight notchOuter-sized mask.
    mask: Region {
      x: panel.launcherOpen ? 0 : notchOuter.x
      y: panel.launcherOpen ? 0 : notchOuter.y
      width: panel.launcherOpen ? panel.width : notchOuter.width
      height: panel.launcherOpen ? panel.height : notchOuter.height
    }

    property bool pinnedOpen: false
    property bool hoverOpen: false
    // Third mode, alongside collapsed/media -- quick app launcher (a
    // few favorite icons), triggered by ruixen.applauncher's own bar
    // icon over IPC (see IpcHandler below), not by hover/click on the
    // notch itself like pinnedOpen/hoverOpen.
    property bool launcherOpen: false
    readonly property bool expanded: pinnedOpen || hoverOpen || launcherOpen

    // Which dashboard tab is showing (media/media hover/pin state only --
    // launcher mode is unrelated). 0 Widgets (DashboardContent, the real
    // port), 1 Wallpapers, 2 Metrics -- the latter two are stub panes for
    // now, shell only, per direct request to build the tab switcher
    // before the actual pages.
    property int dashboardTab: 0

    IpcHandler {
      target: "ruixen.notch"
      function openLauncher(): void { panel.launcherOpen = true }
      function closeLauncher(): void { panel.launcherOpen = false }
      function toggleLauncher(): void { panel.launcherOpen = !panel.launcherOpen }
    }

    // Fire-once, not auto-running -- triggered by the tab bar's settings
    // button (see expandedContent below). Opens Omarchy's own real
    // settings menu rather than reimplementing a settings page here:
    // "setup" is the root omarchy-menu.jsonc entry, aliased "settings",
    // confirmed working via `omarchy-menu summon settings`.
    Process {
      id: settingsProc
      command: ["omarchy-menu", "summon", "settings"]
      running: false
    }

    // Click-away-to-dismiss -- covers the whole (now-widened) mask
    // while the launcher's open. Declared before notchOuter on purpose:
    // later siblings win hit-testing in QML, so notchOuter's own content
    // (icon cards, the hover/pin MouseArea) still gets first crack at
    // any click within its own bounds; this only ever catches clicks
    // that land outside the notch shape entirely.
    MouseArea {
      anchors.fill: parent
      enabled: panel.launcherOpen
      onClicked: panel.launcherOpen = false
    }

    Item {
      id: notchOuter
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      // Ambxst derives its own notch corner geometry from its window
      // rounding config (roundness=16 default): cornerSize=roundness+4,
      // collapsed radius=roundness+4, expanded radius=roundness+20. Our
      // frame/Hyprland rounding is 24, not 16 -- same formula, our own
      // rounding: cornerSize=28, collapsed radius=28 (see centerMask
      // below), expanded radius=44.
      readonly property int cornerSize: 28
      // Collapsed width trimmed from ambxst's own 290 (matched to their
      // actual DefaultView.qml row) -- our actual content (avatar +
      // divider + play glyph/wave + divider + bell) is narrower than
      // theirs, so 290 left a big empty gap between the avatar/bell and
      // the notch's own curved edges. First attempt went to 240, but
      // collapsedContent's real parent is a clip:true Item sized to
      // exactly bodyWidth (see below) -- content measures ~236-240px
      // wide (avatar 20 + 2 dividers + wave-track 140 + play glyph +
      // bell + Row spacing), landing right at that clip edge and cutting
      // the bell off. 260 gives real margin instead of a knife's-edge
      // fit. Expanded width (420) is unrelated -- ambxst's
      // notificationMinWidth target, still fits our own expanded content.
      // Media hover/pin now tries ambxst's own real dashboard size
      // (DashboardView.qml: implicitWidth 900, implicitHeight 56+48*6 =
      // 344) instead of reusing the smaller 420x190 -- untested territory
      // for this notch (only 44 and 190 are proven safe against the
      // masking bug below), so watch for the same flat-bottom-corner
      // symptom if this doesn't pan out.
      //
      // launcherOpen deliberately does NOT follow this -- it keeps its
      // own separate 420x190 branch, proven safe, since an earlier
      // attempt at a new size for launcher specifically (340x260, then
      // up to 360) hit that exact masking bug. Decoupled from
      // pinnedOpen/hoverOpen here so a size change on one never risks
      // the other.
      readonly property int bodyWidth: panel.launcherOpen ? 420 : ((panel.pinnedOpen || panel.hoverOpen) ? 900 : 260)
      width: bodyWidth + cornerSize * 2
      // Full ambxst parity (44px collapsed) -- ruixen-bar's own reserved
      // screen zone (notchClearance) was bumped to cover this plus a
      // buffer, so it no longer overlaps tiled windows the way it did
      // when this was smaller but the reserved zone was still just
      // barSize-sized.
      height: panel.launcherOpen ? 190 : ((panel.pinnedOpen || panel.hoverOpen) ? 344 : 44)

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
          bottomLeftRadius: panel.expanded ? 44 : 28
          bottomRightRadius: panel.expanded ? 44 : 28

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
          // expanded already folds in launcherOpen (see panel.expanded),
          // so !expanded alone correctly excludes launcher mode too.
          visible: !panel.expanded
          opacity: panel.expanded ? 0 : 1
          anchors.centerIn: parent
          // The frame visually eats the top ~6px (it merges into the
          // frame's own border there), so centering in the notch's full
          // height reads as shifted too high relative to the actually
          // visible space below that. Nudge down to compensate.
          anchors.verticalCenterOffset: 2
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
              // Matches the bar's new icon standard (18px, tuned to
              // ambxst's own bar-icon size) -- was 11, visibly undersized
              // next to the 20px avatar in this same row.
              font.pixelSize: 18

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
              width: 140
              height: 12

              Rectangle {
                // Unplayed remainder only -- starts right where the wave
                // ends, instead of running the full width underneath it.
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width * (1 - root.progressRatio)
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
                fullLength: 140
                running: root.isPlaying
              }

              // Playhead -- vertical line right where the wave meets the
              // dim (unplayed) track.
              Rectangle {
                width: 2
                height: parent.height
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.textColor
                x: parent.width * root.progressRatio - width / 2
                visible: root.hasMedia

                Behavior on x { NumberAnimation { duration: 450 } }
              }
            }
          }

          NotchSeparator { anchors.verticalCenter: parent.verticalCenter }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰂛"
            color: root.dnd ? "#e05252" : root.muted
            font.family: root.fontFamily
            font.pixelSize: 18

            Behavior on color { ColorAnimation { duration: 160 } }
          }
        }

        // Expanded: blurred-art thumbnail, title/artist, big wave
        // progress, transport controls.
        // Expanded: dashboard content (player + quick controls/calendar +
        // notifications + volume dials), ported from ambxst's
        // WidgetsTab.qml -- see DashboardContent.qml for the full
        // breakdown. Media data/colors passed through from the same
        // root-level properties the collapsed view already reads.
        Item {
          id: expandedContent
          visible: panel.expanded && !panel.launcherOpen
          opacity: panel.expanded && !panel.launcherOpen ? 1 : 0
          anchors.fill: parent
          anchors.topMargin: 20
          anchors.bottomMargin: 12
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          Behavior on opacity { NumberAnimation { duration: 160 } }

          RowLayout {
            anchors.fill: parent
            spacing: 10

            // Left vertical tab bar -- ambxst's Dashboard.qml
            // tabsContainer: Widgets/Wallpapers/Metrics stacked icon
            // buttons, settings gear pinned at the bottom via a
            // fillHeight spacer above it. Shell only for now: Wallpapers
            // and Metrics are non-functional stub panes (see the content
            // area below) -- only the tab switching itself and the real
            // settings action are wired up.
            ColumnLayout {
              Layout.preferredWidth: 30
              Layout.maximumWidth: 30
              Layout.fillHeight: true
              spacing: 6

              TabButton {
                glyph: "󰕰"
                active: panel.dashboardTab === 0
                onActivated: panel.dashboardTab = 0
              }
              TabButton {
                glyph: ""
                active: panel.dashboardTab === 1
                onActivated: panel.dashboardTab = 1
              }
              TabButton {
                glyph: ""
                active: panel.dashboardTab === 2
                onActivated: panel.dashboardTab = 2
              }

              Item { Layout.fillHeight: true }

              // The one real action in this tab bar -- opens Omarchy's
              // actual settings menu (see settingsProc above), not a
              // notch-local settings page.
              TabButton {
                glyph: ""
                onActivated: settingsProc.running = true
              }
            }

            // Right: active tab's content.
            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

              DashboardContent {
                anchors.fill: parent
                visible: panel.dashboardTab === 0
                shell: root.shell
                textColor: root.textColor
                muted: root.muted
                accent: root.accent
                fontFamily: root.fontFamily
                mediaService: root.mediaService
                activePlayer: root.activePlayer
                hasMedia: root.hasMedia
                isPlaying: root.isPlaying
                playIcon: root.playIcon
                title: root.title
                artist: root.artist
                artUrl: root.artUrl
                progressRatio: root.progressRatio
                trackPosition: root.trackPosition
                trackLength: root.trackLength
                userHost: root.userHost
                displayedTitle: root.displayedTitle
              }

              // Stub panes -- tab switching works, real content doesn't
              // exist yet. Per direct request: build the tab bar first,
              // not the actual wallpaper/metrics pages.
              Text {
                anchors.centerIn: parent
                visible: panel.dashboardTab === 1
                text: "Wallpapers -- coming soon"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: 12
              }

              Text {
                anchors.centerIn: parent
                visible: panel.dashboardTab === 2
                text: "Metrics -- coming soon"
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: 12
              }
            }
          }
        }

        // Quick app launcher -- a handful of pinned favorites, click to
        // launch. No search box, no keyboard focus, no scrolling -- v1's
        // search-box version needed WlrKeyboardFocus.Exclusive and a new
        // notch size (340x260/etc) to fit a scrollable list, and that new
        // size turned out to hit a real, non-deterministic bug in the
        // notchBg masking (MultiEffect layer effect below) at taller
        // heights. Simplified per direct feedback: a few favorite apps
        // don't need any of that -- this reuses the exact same 260x44
        // collapsed-state dimensions (see bodyWidth/height above), the
        // most-exercised, proven-stable code path in this whole file.
        //
        // Favorites are a plain hardcoded list of desktop-entry ids --
        // edit favoriteAppIds below to change which apps show. Reads
        // shell.appLibrary the same way the search version did, just
        // looks entries up by id instead of running a search query.
        // Laid out as a grid (3 columns) since the notch expands to the
        // full 420x190 media size now -- plenty of room for icons at
        // full size across two rows instead of squeezing everything
        // into one cramped line.
        Grid {
          id: launcherContent
          visible: panel.launcherOpen
          opacity: panel.launcherOpen ? 1 : 0
          anchors.centerIn: parent
          columns: 4
          spacing: 20
          Behavior on opacity { NumberAnimation { duration: 160 } }

          readonly property var favoriteAppIds: ["kitty", "org.gnome.Nautilus", "chromium", "code", "spotify", "Discord", "obsidian", "1password"]
          readonly property var favoriteEntries: {
            if (!panel.launcherOpen || !root.shell || !root.shell.appLibrary) return []
            var all = root.shell.appLibrary.sortedEntries("")
            var byId = {}
            for (var i = 0; i < all.length; i++) byId[all[i].entry.id] = all[i].entry
            var picked = []
            for (var j = 0; j < favoriteAppIds.length; j++) {
              if (byId[favoriteAppIds[j]]) picked.push(byId[favoriteAppIds[j]])
            }
            return picked
          }

          Repeater {
            model: launcherContent.favoriteEntries

            Item {
              id: favIcon
              required property var modelData
              width: 64
              height: 64

              // Tonal card behind the icon -- lets the icon itself stay
              // modest (32px) while the tile as a whole still fills a
              // comfortable amount of space, instead of just blowing the
              // icon up to fill the grid cell.
              Rectangle {
                anchors.fill: parent
                radius: 14
                color: cardMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                Behavior on color { ColorAnimation { duration: 120 } }
              }

              Image {
                anchors.centerIn: parent
                width: 32
                height: 32
                sourceSize: Qt.size(32, 32)
                asynchronous: true
                source: root.shell.appLibrary.iconSource(favIcon.modelData.icon)
              }

              MouseArea {
                id: cardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  root.shell.appLibrary.launch(favIcon.modelData.id, root.shell.appLibrary.entryName(favIcon.modelData))
                  panel.launcherOpen = false
                }
              }
            }
          }
        }
      }
    }
  }
}
