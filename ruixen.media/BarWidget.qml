import QtQuick
import Quickshell
import Quickshell.Io
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

  // Reads Service.qml's own state file directly instead of
  // bar.shell.firstPartyServiceFor("ruixen.media") -- ruixen-shell issue
  // #39/#38: Omarchy v4.0.3 restricts that call to a fixed 4-item
  // allowlist of Omarchy's own services, which "ruixen.media" was never
  // going to be in regardless of caller. This widget is a separate QML
  // instance from Service.qml (only ever handed whatever ruixen.bar's
  // own ModuleSlot injects via `bar`, never a shell property of its
  // own), so the two now share state through a plain file instead of an
  // in-process object reference. The file is refreshed on a 500ms poll
  // on the writer side (Service.qml's own comment explains why polling,
  // not a signal, is needed for position specifically), and watched
  // here (watchChanges: true), which also replaces this widget's own
  // former "poll position every 500ms while playing" Timer -- the
  // reload IS the position update now, no separate polling needed on
  // this side either.
  readonly property string mediaStateHome: Quickshell.env("HOME")
  readonly property string mediaStatePath: mediaStateHome + "/.local/state/ruixen/media-state.json"

  property bool hasMedia: false
  property bool isPlaying: false
  property string title: ""
  property string artist: ""
  property string album: ""
  property string artUrl: ""
  property real trackLength: 0
  property real trackPosition: 0
  property bool canGoNext: false
  property bool canGoPrevious: false
  property bool canTogglePlaying: false
  property bool canPlay: false
  property bool canPause: false
  readonly property string playIcon: isPlaying ? "\udb80\udfe4" : "\udb81\udc0a"

  FileView {
    id: mediaStateFile
    path: root.mediaStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyMediaState(text())
    onLoadFailed: root.applyMediaState("")
  }

  function applyMediaState(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || "").trim() || "{}")
    } catch (e) {
      parsed = {}
    }
    root.hasMedia = parsed.hasMedia === true
    root.isPlaying = parsed.playing === true
    root.title = typeof parsed.title === "string" ? parsed.title : ""
    root.artist = typeof parsed.artist === "string" ? parsed.artist : ""
    root.album = typeof parsed.album === "string" ? parsed.album : ""
    root.artUrl = typeof parsed.artUrl === "string" ? parsed.artUrl : ""
    root.trackLength = Math.max(0, Number(parsed.length || 0))
    root.trackPosition = Math.max(0, Number(parsed.position || 0))
    root.canGoNext = parsed.canGoNext === true
    root.canGoPrevious = parsed.canGoPrevious === true
    root.canTogglePlaying = parsed.canTogglePlaying === true
    root.canPlay = parsed.canPlay === true
    root.canPause = parsed.canPause === true
  }

  function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(value / 60)
    var rest = value % 60
    return minutes + ":" + String(rest).padStart(2, "0")
  }

  // Fire-and-forget through ruixen.media's own existing "ruixen-media"
  // IpcHandler target instead of calling a live service object's
  // runAction() directly -- see Service.qml's own comment on its
  // parameterized runAction(action, showFeedback) IPC function for why
  // showFeedback is always false here (this widget already shows
  // playing state visually). Drops the third targetKey argument the
  // old direct calls passed (playerKey(activePlayer), pinning the
  // action to whichever player is currently displayed) -- runAction's
  // own fallback chain already prefers the service's own activePlayer
  // when it can handle the action, which is what this widget displays
  // anyway, so the two resolve to the same player in the cases that
  // matter.
  property bool mediaActionPending: false

  function sendMediaAction(action) {
    if (mediaActionProcess.running) return
    root.mediaActionPending = true
    mediaActionProcess.command = ["omarchy-shell", "ruixen-media", "runAction", String(action), "false"]
    mediaActionProcess.running = true
  }

  Process {
    id: mediaActionProcess
    running: false
    onExited: root.mediaActionPending = false
  }

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
    cursorShape: root.hasMedia ? Qt.PointingHandCursor : Qt.ArrowCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

    onClicked: function(mouse) {
      if (!root.hasMedia) return
      // Left-clicks on the glyph badge are caught by its own MouseArea
      // (play/pause) before reaching here -- anything that does land here
      // (left elsewhere in the pill, or right-click anywhere) opens the
      // popup instead.
      if (mouse.button === Qt.MiddleButton) {
        root.sendMediaAction("next")
      } else {
        root.popupOpen = !root.popupOpen
      }
    }
    onWheel: function(wheel) {
      if (!root.hasMedia) return
      if (wheel.angleDelta.y > 0) root.sendMediaAction("previous")
      else if (wheel.angleDelta.y < 0) root.sendMediaAction("next")
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
      color: isPlaying ? "#f5c518" : "#3ecf5b"
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
        onClicked: root.sendMediaAction("playPause")
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

    // Escape to dismiss, matching Omarchy's own dropdowns -- direct
    // request. See ruixen.pluginpins/BarWidget.qml's identical block
    // for the full "why" (PopupCard itself has no such handling,
    // xdg-popups can still receive keys once something inside holds
    // active focus). Confirmed live on that widget before rolling out
    // here.
    Item {
      id: escapeCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()
    }
    onOpenChanged: if (open) Qt.callLater(function() { escapeCatcher.forceActiveFocus() })

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
            // root.artUrl is already gated on hasMedia at the source
            // (Service.qml's own statusJson(), see its comment for the
            // zombie-MPRIS-registration case this guards against) --
            // this widget's own visible: hasMedia already hides this
            // popup anyway, but the gate stays consistent in case that
            // ever changes.
            source: root.artUrl
            visible: source !== ""
          }

          Text {
            anchors.centerIn: parent
            visible: root.artUrl === ""
            text: "\udb81\udf5a"
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
            text: root.album
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
          iconText: "\udb81\udcae"
          foreground: root.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.canGoPrevious
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.sendMediaAction("previous")
        }

        Button {
          iconText: root.playIcon
          foreground: root.foreground
          horizontalPadding: Style.spacing.panelGap
          verticalPadding: Style.spacing.controlPaddingY
          iconSize: Style.font.iconLarge
          enabled: root.canTogglePlaying || root.canPlay || root.canPause
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.sendMediaAction("playPause")
        }

        Button {
          iconText: "\udb81\udcad"
          foreground: root.foreground
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY
          enabled: root.canGoNext
          opacity: enabled ? 1.0 : 0.4
          onClicked: root.sendMediaAction("next")
        }
      }
    }
  }
}
