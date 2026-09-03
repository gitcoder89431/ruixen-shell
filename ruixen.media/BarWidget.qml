import QtQuick
import Quickshell
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "ruixen.media"

  // Direct review finding ("Support arbitrary third-party widgets in
  // the horizontal center region", #27): this widget's own bindings
  // used to read root.bar.foreground/fontFamily/barForeground/vertical
  // directly, unguarded, everywhere below -- harmless in vertical
  // mode (where it was already generically hosted), but this was the
  // FIRST time it ever actually got instantiated in horizontal mode
  // (center previously silently dropped it entirely), and that
  // exposed a real, pre-existing bug: `bar` is still null for these
  // properties' very first binding evaluation, before the host's own
  // injectProps() runs, so every one of them threw a "Cannot read
  // property ... of null" warning on load -- confirmed live, not
  // assumed, by actually turning this widget on in horizontal mode
  // for the first time and watching the journal. Same local-safe-
  // property pattern ruixen.tray/Tray.qml's own foreground/fontFamily
  // already use (and the base BarWidget's own already-guarded
  // `vertical`, used directly below instead of root.bar.vertical) --
  // one guarded
  // fallback declared once, instead of an `!root.bar ||` guard
  // repeated at every one of the many call sites below.
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color barForeground: bar ? bar.barForeground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var mediaService: bar?.shell?.firstPartyServiceFor("ruixen.media")
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property var sourcePlayers: mediaService ? mediaService.sourcePlayers : []

  // Passive "where you are in the song" display -- no seeking, just a
  // filled track + elapsed/total time. MPRIS doesn't push position
  // updates as playback progresses (only on seek/track-change), so it
  // has to be polled while the popup's actually open to read.
  property real trackPosition: 0
  readonly property real trackLength: activePlayer ? Math.max(0, Number(activePlayer.length || 0)) : 0

  function syncPosition() {
    trackPosition = activePlayer ? Math.max(0, Number(activePlayer.position || 0)) : 0
  }

  function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(value / 60)
    var rest = value % 60
    return minutes + ":" + String(rest).padStart(2, "0")
  }

  // Runs whenever something's playing, not just while the popup is open --
  // the mini progress bar in the collapsed bar icon needs live position
  // too now, not just the popup's own progress bar.
  Timer {
    interval: 500
    repeat: true
    running: root.activePlayer !== null && root.activePlayer.isPlaying
    triggeredOnStart: true
    onTriggered: root.syncPosition()
  }

  onPopupOpenChanged: if (popupOpen) syncPosition()

  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string playIcon: activePlayer && activePlayer.isPlaying ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""

  property bool popupOpen: false

  function close() { popupOpen = false }

  visible: hasMedia
  implicitWidth: hasMedia ? row.implicitWidth + Style.space(14) : 0
  implicitHeight: barSize

  // Declared before the Row on purpose: QML stacks later siblings on top
  // for both paint AND hit-testing, so this being first means the glyph's
  // own MouseArea below (nested inside the Row, declared after this) sits
  // in front and actually receives its clicks instead of this catching
  // everything first.
  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: root.activePlayer ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (!root.activePlayer) return
      // Left-clicks on the glyph badge are caught by its own MouseArea
      // (play/pause) before reaching here -- anything that does land here
      // (left elsewhere in the pill, or right-click anywhere) opens the
      // popup instead.
      if (mouse.button === Qt.MiddleButton) {
        if (root.mediaService) root.mediaService.runAction("next", false)
      } else {
        root.popupOpen = !root.popupOpen
      }
    }
    onWheel: function(wheel) {
      if (!root.activePlayer) return
      if (wheel.angleDelta.y > 0 && root.mediaService) root.mediaService.runAction("previous", false)
      else if (wheel.angleDelta.y < 0 && root.mediaService) root.mediaService.runAction("next", false)
    }
    onEntered: if (root.bar) root.bar.showTooltip(root, root.hasMedia ? (root.title + (root.artist ? " — " + root.artist : "")) : "")
    onExited: if (root.bar) root.bar.hideTooltip(root)
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    // Round color badge instead of a plain glyph -- green (go/play) when
    // paused, yellow (caution/pause) when playing, black icon on both for
    // contrast. Also doubles as the play/pause click target.
    Rectangle {
      id: playBadge
      anchors.verticalCenter: parent.verticalCenter
      // Style.space(16), not (20) -- direct correction: "the play pause
      // button is in a round pill that is way too big, needs to be more
      // around the icon". The glyph itself is Style.font.caption
      // (~10px); 20 left it sitting at roughly half the badge's own
      // diameter, same "slot way bigger than its icon" issue already
      // fixed for pinnedapps/tray. 16 hugs it closer without clipping.
      width: Style.space(16)
      height: Style.space(16)
      radius: width / 2
      color: activePlayer && activePlayer.isPlaying ? "#f5c518" : "#3ecf5b"
      Behavior on color {
        enabled: !root.bar || root.bar.foregroundAnimationEnabled
        ColorAnimation { duration: 160 }
      }

      Text {
        anchors.centerIn: parent
        text: root.playIcon
        color: "#000000"
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }

      // Its own click target so play/pause and "open the popup" don't
      // fight over the same click -- was undiscoverable before this,
      // since the whole pill toggled play/pause and only right-click (not
      // obvious) opened the popup with the title in it.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false)
      }
    }

    Rectangle {
      id: miniProgressTrack
      visible: !root.vertical && root.trackLength > 0
      width: Style.space(36)
      height: Style.space(3)
      radius: height / 2
      anchors.verticalCenter: parent.verticalCenter
      color: Qt.rgba(root.barForeground.r, root.barForeground.g, root.barForeground.b, 0.25)

      Rectangle {
        height: parent.height
        width: parent.width * Math.min(1, root.trackPosition / Math.max(1, root.trackLength))
        radius: height / 2
        color: root.barForeground
        Behavior on width { NumberAnimation { duration: 450 } }
      }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(320))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    Column {
      id: column
      anchors.fill: parent
      spacing: Style.space(10)

      Row {
        spacing: Style.space(10)
        width: parent.width

        BorderSurface {
          width: Style.space(64)
          height: Style.space(64)
          radius: Style.spacing.labelGap
          color: Style.normalFillFor(root.foreground, Color.accent)
          borderSpec: Border.controlSpec("normal", root.foreground, Color.accent)

          Image {
            anchors.fill: parent
            anchors.margins: Style.space(2)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            // Gated on hasMedia, not just activePlayer -- see
            // ruixen.notch's Overlay.qml for the zombie-MPRIS-
            // registration case this guards against (harmless here in
            // practice since the whole widget's visible: hasMedia
            // already hides this popup, but kept consistent in case that
            // ever changes).
            source: root.hasMedia && root.activePlayer && root.activePlayer.trackArtUrl ? root.activePlayer.trackArtUrl : ""
            visible: source !== ""
          }

          Text {
            anchors.centerIn: parent
            visible: !root.hasMedia || !root.activePlayer || !root.activePlayer.trackArtUrl
            text: "󰝚"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.displayLarge
          }
        }

        Column {
          spacing: Style.space(4)
          width: parent.width - Style.space(74)

          Text {
            text: root.title || "Nothing playing"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.subtitle
            font.bold: true
            elide: Text.ElideRight
            width: parent.width
          }

          Text {
            text: root.artist
            color: Qt.darker(root.foreground, 1.3)
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }

          Text {
            text: root.activePlayer && root.activePlayer.trackAlbum ? root.activePlayer.trackAlbum : ""
            color: Qt.darker(root.foreground, 1.6)
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
            width: parent.width
            visible: text !== ""
          }
        }
      }

      Item {
        width: parent.width
        height: Style.space(18)
        visible: root.trackLength > 0

        Rectangle {
          id: progressTrack
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Style.space(4)
          radius: height / 2
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)

          Rectangle {
            height: parent.height
            width: parent.width * Math.min(1, root.trackPosition / Math.max(1, root.trackLength))
            radius: height / 2
            color: Color.accent
            Behavior on width { NumberAnimation { duration: 450 } }
          }
        }

        Text {
          anchors.left: parent.left
          anchors.top: progressTrack.bottom
          anchors.topMargin: 2
          text: root.formatTime(root.trackPosition)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.58)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }

        Text {
          anchors.right: parent.right
          anchors.top: progressTrack.bottom
          anchors.topMargin: 2
          text: root.formatTime(root.trackLength)
          color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.58)
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: Style.space(6)

        Button {
          iconText: "󰒮"
          foreground: root.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && root.activePlayer.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("previous", false, root.mediaService.playerKey(root.activePlayer))
        }

        Button {
          iconText: root.activePlayer && root.activePlayer.isPlaying ? "󰏤" : "󰐊"
          foreground: root.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: root.activePlayer && (root.activePlayer.canTogglePlaying || root.activePlayer.canPlay || root.activePlayer.canPause)
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false, root.mediaService.playerKey(root.activePlayer))
        }

        Button {
          iconText: "󰒭"
          foreground: root.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.activePlayer && root.activePlayer.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: if (root.mediaService) root.mediaService.runAction("next", false, root.mediaService.playerKey(root.activePlayer))
        }
      }
    }
  }
}
