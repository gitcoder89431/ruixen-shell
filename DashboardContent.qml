import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Networking
import Quickshell.Bluetooth

// Pure-frontend port of ambxst's WidgetsTab.qml (the actual content of
// their dashboard's default tab -- what most people mean by "the
// ambxst dashboard"). Four columns: player | quick controls + calendar
// | notification history | volume/brightness/mic dials. Deliberately
// NOT wired to real backends beyond what's trivial (the calendar is
// just Date math, genuinely correct) -- everything else here is a
// static visual reference for deciding what's worth actually hooking
// up later. Plain QML primitives throughout (Rectangle/Text/Canvas),
// not ambxst's own StyledRect/Styling/Colors design-token system,
// which doesn't exist in this project.
//
// Source layout reference: quickshell-ambxst/modules/widgets/dashboard/
// widgets/WidgetsTab.qml (their own implicitWidth/Height: 600x750 --
// ours is compressed to fit the notch's 900x344 dashboard size instead
// of a straight port).
Item {
  id: root

  property var shell: null
  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"

  // Media passthrough -- reads the same root-level properties Overlay.qml
  // itself already computes from ruixen.media, just handed down instead
  // of recomputed here.
  property var mediaService: null
  property var activePlayer: null
  property bool hasMedia: false
  property bool isPlaying: false
  property string playIcon: ""
  property string title: ""
  property string artist: ""
  property string album: ""
  property string artUrl: ""
  property real progressRatio: 0
  property real trackPosition: 0
  property real trackLength: 0
  property string userHost: ""
  property string displayedTitle: ""

  // Quick-controls backends -- wifi/bluetooth are real global Quickshell
  // singletons (not gated behind Omarchy's plugin registry at all);
  // nightlight/idle are Omarchy first-party "service" kind plugins, same
  // shell.firstPartyServiceFor() pattern mediaService above already uses.
  readonly property var bluetoothAdapter: Bluetooth.defaultAdapter
  readonly property var nightlightService: root.shell ? root.shell.firstPartyServiceFor("omarchy.nightlight") : null
  readonly property var idleService: root.shell ? root.shell.firstPartyServiceFor("omarchy.idle") : null

  function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(value / 60)
    var rest = value % 60
    return minutes + ":" + String(rest).padStart(2, "0")
  }

  // Shared "pane" look -- OLED-black fill (transparent over the notch's
  // own black background) with a visible grey outline, instead of a
  // filled tonal card. Reads as a thick border framing each column
  // rather than a lighter grey block sitting on black -- per direct
  // feedback that this looked cleaner than the earlier filled version.
  component Pane: Rectangle {
    radius: 10
    color: "transparent"
    border.color: Qt.rgba(1, 1, 1, 0.14)
    border.width: 1.5
    clip: true
  }

  // Quick-control toggle button -- accent-filled with black text/glyph
  // when on (same "primary" treatment the calendar's today-cell and the
  // active tab already use), grey tonal when off. The agent glyph is the
  // one exception left non-interactive (see below) -- active always
  // false, no onActivated wired.
  component QuickToggle: Rectangle {
    id: qt
    property string glyph: ""
    property bool active: false
    property int size: 32
    signal activated()

    width: size
    height: size
    radius: size / 4
    color: active ? root.accent : Qt.rgba(1, 1, 1, 0.06)
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: qt.glyph
      color: qt.active ? "#000000" : root.textColor
      font.family: root.fontFamily
      font.pixelSize: qt.size * 0.4
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: qt.activated()
    }
  }

  // Kept as the original filled tonal card -- notifications stays grey
  // per direct feedback, the one column that didn't switch to Pane's
  // black+border look above.
  component PaneFilled: Rectangle {
    radius: 10
    color: Qt.rgba(1, 1, 1, 0.05)
    clip: true
  }

  // Half-circle progress ring, arcing over the top of the album art
  // disc -- ambxst's own CircularSeekBar (modules/components/
  // CircularSeekBar.qml) does this with QtQuick.Shapes (PathAngleArc/
  // PathPolyline), draggable, dashed, with a handle indicator. That's a
  // lot more machinery than this notch needs -- ported just the visual
  // result with a Canvas instead, same technique WavyLine already uses
  // elsewhere in this file (a sine perturbation redrawn every frame),
  // just applied to an arc's radius instead of a straight line's y.
  // startAngle/spanAngle match their own values (180deg -> +180deg
  // sweep = the top half of the circle, left-to-right through 12
  // o'clock) -- not arbitrary, that's what "arcs over the top" means
  // geometrically in canvas angle convention (0 = 3 o'clock, clockwise).
  component CircularSeek: Canvas {
    id: seek
    property real value: 0
    property color trackColor: Qt.rgba(1, 1, 1, 0.15)
    property color progressColor: root.accent
    property real ringWidth: 4
    property color tipColor: "#ffffff"
    property bool wavy: false
    readonly property real startAngle: Math.PI
    readonly property real spanAngle: Math.PI
    property real wavePhase: 0

    onValueChanged: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    onWavePhaseChanged: requestPaint()

    FrameAnimation {
      running: seek.wavy && seek.visible
      onTriggered: seek.wavePhase = (Date.now() / 300.0) % (Math.PI * 2)
    }

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      ctx.clearRect(0, 0, width, height)
      if (width <= 0 || height <= 0) return

      var cx = width / 2
      var cy = height / 2
      // Extra -9 beyond ringWidth keeps the tip's thick outer edge
      // clear of the canvas boundary. -6 wasn't enough -- the tip's
      // sideways extent (at the arc's 9/3 o'clock start/end points)
      // was landing within ~1.25px of the canvas edge and visibly
      // clipping there.
      var r = Math.min(width, height) / 2 - seek.ringWidth - 9

      ctx.lineWidth = seek.ringWidth
      ctx.lineCap = "round"

      // Track -- full span, dim.
      ctx.strokeStyle = seek.trackColor
      ctx.beginPath()
      ctx.arc(cx, cy, r, seek.startAngle, seek.startAngle + seek.spanAngle)
      ctx.stroke()

      // Progress -- up to value, accent, wavy (a sine ripple on the
      // radius) only while actually playing.
      var clamped = Math.max(0, Math.min(1, seek.value))
      var endAngle = seek.startAngle + seek.spanAngle * clamped
      ctx.strokeStyle = seek.progressColor
      ctx.beginPath()
      var steps = 48
      for (var i = 0; i <= steps; i++) {
        var t = i / steps
        var angle = seek.startAngle + (endAngle - seek.startAngle) * t
        var rr = r
        if (seek.wavy) rr += Math.sin(angle * 16 + seek.wavePhase) * 2.5
        var x = cx + rr * Math.cos(angle)
        var y = cy + rr * Math.sin(angle)
        if (i === 0) ctx.moveTo(x, y)
        else ctx.lineTo(x, y)
      }
      ctx.stroke()

      // Tip -- a thick radial tick at the current progress position,
      // ported from ambxst's own CircularSeekBar handle (a fat line
      // straddling the track radius, not a dot on top of it).
      if (clamped > 0) {
        var tipOffset = 6
        var tipR1 = r - tipOffset
        var tipR2 = r + tipOffset
        var tx1 = cx + tipR1 * Math.cos(endAngle)
        var ty1 = cy + tipR1 * Math.sin(endAngle)
        var tx2 = cx + tipR2 * Math.cos(endAngle)
        var ty2 = cy + tipR2 * Math.sin(endAngle)
        ctx.lineWidth = seek.ringWidth * 1.5
        ctx.strokeStyle = seek.tipColor
        ctx.beginPath()
        ctx.moveTo(tx1, ty1)
        ctx.lineTo(tx2, ty2)
        ctx.stroke()
      }
    }
  }

  RowLayout {
    anchors.fill: parent
    // 8px, matching ambxst's own WidgetsTab.qml RowLayout spacing --
    // we were at 12, looser than their real column rhythm.
    spacing: 8

    // ---- Column 1: player -------------------------------------------
    // Own bespoke background instead of the shared Pane -- ambxst's real
    // FullPlayer.qml uses variant: "transparent" (their StyledRect variant
    // that forces border/radius-fill to 0, i.e. no visible border at all)
    // plus a blurred-album-art backdrop, not a flat black+border card like
    // the other 3 columns. Ported the blur technique from the same
    // backgroundArt trick the collapsed notch view already uses.
    Rectangle {
      id: playerCard
      Layout.preferredWidth: 210
      Layout.maximumWidth: 210
      Layout.fillHeight: true
      radius: 10
      // Genuinely transparent -- no fill at all, matching ambxst's real
      // StyledRect variant:"transparent" (opacity forced to 0, border
      // forced to 0 -- see Styling.qml's "transparent" case). No
      // separate card layer here means this area shows straight through
      // to the notch's own shared black base (notchBg, one file over in
      // Overlay.qml) when there's no art, and the blurred art itself is
      // the only "fill" once there is.
      color: "transparent"
      clip: true

      // Matches ambxst's real fallback exactly (checked their source
      // directly, not guessed): blur the track's own art when playing,
      // otherwise blur the actual desktop wallpaper file -- there's
      // always something to blur, never a blank/plain background. Not
      // a live compositor blur-through to whatever's behind the notch
      // (that was the wrong target entirely) -- ambxst's own player
      // never shows real desktop, just blurred art OR a blurred static
      // wallpaper image, same MultiEffect either way.
      readonly property string wallpaperPath: "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
      readonly property string playerBgSource: root.artUrl !== "" ? root.artUrl : wallpaperPath

      Image {
        id: playerBgArt
        anchors.fill: parent
        source: playerCard.playerBgSource
        sourceSize: Qt.size(64, 64)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
      }

      MultiEffect {
        anchors.fill: parent
        source: playerBgArt
        blurEnabled: true
        blurMax: 32
        blur: 1.0
        // 0.25, matching ambxst's own ratio exactly (was 0.35, a guess).
        opacity: 0.25
      }

      // Sharp-edge accent ring -- ambxst's own FullPlayer.qml layers a
      // SECOND, full-resolution (unblurred) copy of the same art/
      // wallpaper on top, masked with maskInverted: true against an
      // inset white rectangle (4px in on every side). Inverted means
      // the mask hides the interior and only lets the sharp image show
      // in the thin ring OUTSIDE that inset -- a crisp border around
      // the edge, blurred everywhere inside it. Ported directly from
      // their real innerAreaMask + fullArtEffect, not invented.
      Image {
        id: playerBgArtFull
        anchors.fill: parent
        source: playerCard.playerBgSource
        sourceSize: Qt.size(256, 256)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
      }

      Item {
        id: innerAreaMask
        anchors.fill: parent
        visible: false
        layer.enabled: true

        Rectangle {
          x: 4
          y: 4
          width: parent.width - 8
          height: parent.height - 8
          radius: playerCard.radius - 4
          color: "#ffffff"
        }
      }

      MultiEffect {
        anchors.fill: parent
        source: playerBgArtFull
        maskEnabled: true
        maskSource: innerAreaMask
        maskInverted: true
        maskThresholdMin: 0.5
        maskSpreadAtMin: 1.0
      }

      // Plain Item + a centered inner ColumnLayout, not two fillHeight
      // spacers -- those didn't split evenly (ColumnLayout's flex-space
      // distribution isn't a clean 50/50 with this many mixed fixed/
      // flexible children), leaving the disc pinned near the top and
      // the transport row glued to the bottom edge. anchors.centerIn
      // is simple and predictable: centers the whole content block as
      // one group, no fighting flex-space math.
      Item {
        anchors.fill: parent

        ColumnLayout {
          anchors.centerIn: parent
          width: parent.width - 8
          spacing: 8

        // Disc + progress ring share one square container, both
        // centered -- the ring's radius is bigger than the disc's, so
        // it arcs over the disc's own top edge like a halo instead of
        // sitting as a separate row underneath.
        // Sizing history: 100/80 -> 140/110 (bigger, per request) ->
        // 180/110 (gap opened up, per request) -> 190/130 here (gap
        // pulled back in by growing the DISC instead of the ring --
        // ring container barely changed, per "progress bar is almost
        // fine, just make the album art circle bigger to get closer").
        //
        // A shorter clipped wrapper (190x160, shifted up 18px) was
        // tried here to crop the ring's own blank top strip, on the
        // assumption the topmost drawn pixel was always the plain
        // arc's own top point (~14px down). Wrong -- the THICK TIP
        // can swing further up than the plain arc at any progress
        // near the top of the sweep (its outer edge reaches within
        // ~4px of the square's top edge at ~50% progress), so an
        // 18px crop sliced the tip itself off at exactly the
        // progress values where it'd swing up that far. Reverted to
        // a plain, uncropped 190x190 square -- the ring must stay
        // fully unclipped at every progress value, not just the ones
        // tested. If the top padding needs trimming again, do it
        // above this Item (layout spacing), not by cropping the
        // canvas itself.
        Item {
          Layout.preferredWidth: 190
          Layout.preferredHeight: 190
          Layout.alignment: Qt.AlignHCenter
          visible: root.artUrl !== ""

          CircularSeek {
            anchors.fill: parent
            value: root.progressRatio
            wavy: root.isPlaying
            ringWidth: 5
          }

          // ClippingRectangle, not a plain Rectangle -- confirmed the
          // hard way: plain QtQuick Rectangle.clip only clips children
          // to the bounding BOX, it does not follow radius, regardless
          // of how high radius is set. Quickshell's own ClippingRectangle
          // (Quickshell.Widgets) is what ambxst's real clippedDisc uses
          // for exactly this reason.
          ClippingRectangle {
            width: 130
            height: 130
            anchors.centerIn: parent
            radius: width / 2
            color: "transparent"

            Image {
              anchors.fill: parent
              source: root.artUrl
              sourceSize: Qt.size(260, 260)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
            }
          }
        }

        // Title + album + artist as three centered lines, matching
        // ambxst's own metadata ColumnLayout exactly (title bold, TWO
        // secondary lines dimmer -- album was missing entirely before,
        // not just the ordering being off).
        ColumnLayout {
          Layout.fillWidth: true
          Layout.alignment: Qt.AlignHCenter
          spacing: 2

          Text {
            Layout.fillWidth: true
            text: root.hasMedia ? root.title : root.displayedTitle
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 12
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: root.hasMedia && root.album !== ""
            text: root.album
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: root.hasMedia && root.artist !== ""
            text: root.artist
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }

        // Fixed gap, not a fillHeight spacer -- the whole block is
        // already centered by the outer Item's anchors.centerIn now.
        // Trimmed from 12 -- too much air between the artist line and
        // the transport controls.
        Item { Layout.preferredHeight: 4 }

        // No Layout.fillWidth here -- a plain Row doesn't center its
        // own children, it just left-packs them from x=0. fillWidth
        // stretched the Row to the card's full width while the icons
        // stayed left-anchored inside it; Layout.alignment only
        // centers the Row ITSELF within the parent, which only works
        // if the Row is sized to its own content instead of stretched.
        Row {
          Layout.alignment: Qt.AlignHCenter
          spacing: 18

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰒮"
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 14
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.runAction("previous", false)
            }
          }

          // Play/pause -- bigger, tonal accent-filled chip. Rounded
          // SQUARE, not a circle -- same radius:size/4 proportion
          // QuickToggle uses for the wifi/bluetooth quick-controls
          // buttons, per direct request to match that shape instead of
          // ambxst's own fully-round playPauseBtn. Prev/next stay plain
          // glyphs with no background.
          Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 34
            height: 34
            radius: 8
            color: root.accent

            Text {
              anchors.centerIn: parent
              text: root.playIcon
              color: "#000000"
              font.family: root.fontFamily
              font.pixelSize: 16
            }

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false)
            }
          }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰒭"
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 14
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.mediaService) root.mediaService.runAction("next", false)
            }
          }
        }

        // Duration -- ambxst's own "Duration Area" text, same
        // position/opacity (formatTime(position) + " / " +
        // formatTime(length), muted).
        Text {
          Layout.alignment: Qt.AlignHCenter
          text: root.hasMedia
            ? (root.formatTime(root.trackPosition) + " / " + root.formatTime(root.trackLength))
            : "--:-- / --:--"
          color: root.muted
          font.family: root.fontFamily
          font.pixelSize: 9
        }
        }
      }
    }

    // ---- Column 2: quick controls + calendar -------------------------
    ColumnLayout {
      Layout.preferredWidth: 250
      Layout.maximumWidth: 250
      Layout.fillHeight: true
      spacing: 8

      // Quick controls -- 5 buttons again: the Agents glyph is back per
      // direct request, still non-interactive (that widget has no
      // "service" kind to read from). At size 40 with the column now
      // 250px wide, 5 icons + 4 gaps fits with room to spare -- spacing
      // trimmed 10->8 to keep a comfortable margin from the frame's own
      // border instead of crowding it.
      Pane {
        Layout.fillWidth: true
        Layout.preferredHeight: 60
        // Thicker/more visible frame than the other Panes, per direct
        // request -- overrides the shared component's default 1.5px.
        border.width: 2.5
        radius: 14

        Row {
          anchors.centerIn: parent
          spacing: 8

          QuickToggle {
            size: 40
            glyph: "󰖩"
            active: Networking.wifiEnabled
            onActivated: Networking.wifiEnabled = !Networking.wifiEnabled
          }

          QuickToggle {
            size: 40
            glyph: "󰂯"
            active: root.bluetoothAdapter ? root.bluetoothAdapter.enabled : false
            // Not adapter.enabled = !adapter.enabled: that writes BlueZ's
            // Powered directly, which nothing persists, so it comes back
            // on at next boot. omarchy-bluetooth-power moves the rfkill
            // soft block instead (same helper omarchy.bluetooth's own
            // panel uses) -- systemd-rfkill restores that across reboots.
            onActivated: {
              if (!root.bluetoothAdapter) return
              Quickshell.execDetached(["omarchy-bluetooth-power", root.bluetoothAdapter.enabled ? "off" : "on"])
            }
          }

          QuickToggle {
            size: 40
            glyph: "󰖨"
            active: root.nightlightService ? root.nightlightService.enabled : false
            onActivated: if (root.nightlightService) root.nightlightService.toggle()
          }

          QuickToggle {
            size: 40
            glyph: "󰛊"
            active: root.idleService ? root.idleService.stayAwake : false
            // setIdleEnabled(current stayAwake value) IS the toggle --
            // see ruixen.stayawake's own StayAwake.qml for the same
            // pattern: stayAwake and idleEnabled are semantic opposites,
            // so passing the about-to-be-old stayAwake value in flips it.
            onActivated: if (root.idleService) root.idleService.setIdleEnabled(active)
          }

          QuickToggle {
            size: 40
            glyph: "󱚣"
          }
        }
      }

      // Calendar -- genuinely functional (plain Date math, no backend
      // needed), unlike everything else in this file. Prev/next month
      // arrows work; today's cell is highlighted.
      //
      // Structure ported literally from ambxst's own Calendar.qml this
      // time (checked directly, not guessed): outer frame is grey
      // ("pane"), with the title text, each chevron, and the whole
      // day-grid as their own separate BLACK ("internalbg") sub-panels
      // nested inside it -- the grey only ever shows as the gutter
      // around/between those black panels, never as a fill behind text
      // itself. The current week row gets a grey ("pane") highlight
      // inside the black day-grid, same as ambxst's currentWeekRow.
      Rectangle {
        id: calendarPane
        Layout.fillWidth: true
        Layout.fillHeight: true
        radius: 10
        color: Qt.rgba(1, 1, 1, 0.08)
        clip: true

        property int monthShift: 0
        readonly property date viewingDate: {
          var base = new Date()
          return new Date(base.getFullYear(), base.getMonth() + monthShift, 1)
        }
        readonly property date today: new Date()

        // Monday-first 6x7 grid, padded with leading/trailing days from
        // the adjacent months so every week row stays full. currentWeekRow
        // mirrors ambxst's own field of the same name -- which row (if
        // any) contains today, -1 when viewing a different month.
        readonly property var calendarData: {
          var first = viewingDate
          var year = first.getFullYear()
          var month = first.getMonth()
          var firstWeekday = (first.getDay() + 6) % 7 // 0=Mon
          var daysInMonth = new Date(year, month + 1, 0).getDate()
          var prevMonthDays = new Date(year, month, 0).getDate()
          var cells = []
          // Leading days -- the tail end of the previous month, shown
          // muted (inMonth: false) instead of left blank.
          for (var i = 0; i < firstWeekday; i++) {
            cells.push({ day: String(prevMonthDays - firstWeekday + 1 + i), inMonth: false, isToday: false })
          }
          for (var d = 1; d <= daysInMonth; d++) {
            var isToday = monthShift === 0 && d === today.getDate()
            cells.push({ day: String(d), inMonth: true, isToday: isToday })
          }
          // Trailing days -- the start of next month, same muted
          // treatment.
          var nextDay = 1
          while (cells.length % 7 !== 0) {
            cells.push({ day: String(nextDay), inMonth: false, isToday: false })
            nextDay++
          }
          var rows = []
          var currentWeekRow = -1
          for (var r = 0; r < cells.length; r += 7) {
            var row = cells.slice(r, r + 7)
            if (row.some(function(c) { return c.isToday })) currentWeekRow = rows.length
            rows.push(row)
          }
          return { weeks: rows, currentWeekRow: currentWeekRow }
        }
        readonly property var weeks: calendarData.weeks
        readonly property int currentWeekRow: calendarData.currentWeekRow

        ColumnLayout {
          id: calendarColumn
          anchors.fill: parent
          anchors.margins: 4
          spacing: 4

          // Header row -- title pill fills the remaining width, each
          // chevron is its own fixed-width pill, all black, all the
          // same height. Matches ambxst's titleRect/leftButton/
          // rightButton trio exactly (just without their hover/press
          // accent-color swap).
          RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 28
            Layout.maximumHeight: 28
            spacing: 4

            Rectangle {
              Layout.fillWidth: true
              Layout.fillHeight: true
              radius: 8
              color: "#000000"

              Text {
                anchors.centerIn: parent
                text: calendarPane.viewingDate.toLocaleDateString(Qt.locale(), "MMMM yyyy")
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 13
                font.bold: true
              }
            }

            Rectangle {
              Layout.preferredWidth: 28
              Layout.fillHeight: true
              radius: 8
              color: "#000000"

              Text {
                anchors.centerIn: parent
                text: "󰅁"
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 14
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: calendarPane.monthShift -= 1
              }
            }

            Rectangle {
              Layout.preferredWidth: 28
              Layout.fillHeight: true
              radius: 8
              color: "#000000"

              Text {
                anchors.centerIn: parent
                text: "󰅂"
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 14
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: calendarPane.monthShift += 1
              }
            }
          }

          // Day-grid -- one black sub-panel holding the weekday labels
          // and all 6 week rows, matching ambxst's own second
          // "internalbg" StyledRect. Sized to its actual content
          // instead of Layout.fillHeight -- fillHeight let it stretch
          // to whatever leftover height calendarPane had, and
          // ColumnLayout spread that leftover space out as visible gaps
          // between every week row instead of just trailing space
          // ("too hamburger"). Row/cell size bumped (20px -> 30px rows,
          // 20px -> 26px "today" circle) to actually use most of
          // calendarPane's available height instead of leaving a big
          // block of empty grey space below a small fixed-size grid.
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 268
            Layout.maximumHeight: 268
            Layout.alignment: Qt.AlignTop
            radius: 6
            color: "#000000"

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: 6
              spacing: 6

              // Weekday labels and every week row below both use
              // RowLayout with 7 fillWidth columns now, instead of a
              // plain Row of fixed-20px cells centered in the panel --
              // the fixed-width version left big empty gutters on both
              // sides once the day-grid panel became as wide as the
              // rest of this card (looked like the calendar itself was
              // "skinny" inside a wider black panel).
              RowLayout {
                Layout.fillWidth: true
                spacing: 2

                Repeater {
                  model: ["M", "T", "W", "T", "F", "S", "S"]
                  Text {
                    required property string modelData
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: root.muted
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.bold: true
                  }
                }
              }

              // Divider between the weekday labels and the day grid --
              // ambxst has the same Separator in this exact spot
              // (their own version also insets it, leftMargin/
              // rightMargin: 8, instead of running edge-to-edge).
              Rectangle {
                Layout.fillWidth: true
                Layout.leftMargin: 8
                Layout.rightMargin: 8
                Layout.preferredHeight: 1
                color: Qt.rgba(1, 1, 1, 0.14)
              }

              Repeater {
                model: calendarPane.weeks

                Rectangle {
                  required property var modelData
                  required property int index
                  Layout.fillWidth: true
                  Layout.preferredHeight: 30
                  radius: 10
                  color: index === calendarPane.currentWeekRow ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                  RowLayout {
                    anchors.fill: parent
                    spacing: 2

                    Repeater {
                      model: parent.parent.modelData

                      // fillWidth on the column keeps all 7 days evenly
                      // spread across the full row width; the "today"
                      // highlight stays a fixed 20x20 circle centered
                      // inside its (now wider) column instead of
                      // stretching into an ellipse.
                      Item {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        Rectangle {
                          anchors.centerIn: parent
                          width: 26
                          height: 26
                          radius: 13
                          color: parent.modelData.isToday ? root.accent : "transparent"

                          Text {
                            anchors.centerIn: parent
                            text: parent.parent.modelData.day
                            color: parent.parent.modelData.isToday ? "#000000" : (parent.parent.modelData.inMonth ? root.textColor : root.muted)
                            font.family: root.fontFamily
                            font.pixelSize: 11
                          }
                        }
                      }
                    }
                  }
                }
              }
            }
          }
        }
      }
    }

    // ---- Column 3: notification history (static placeholder) --------
    PaneFilled {
      Layout.fillWidth: true
      Layout.fillHeight: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        // Trimmed independently of the other 3 sides -- the header row
        // (title/bell/broom) sat too far from the card's own top edge.
        anchors.topMargin: 6
        spacing: 8

        RowLayout {
          Layout.fillWidth: true
          // 32px, matching ambxst's own header RowLayout
          // (Layout.maximumHeight: 32 in NotificationHistory.qml) --
          // we were at 26, visibly smaller than their real proportions.
          Layout.preferredHeight: 32
          Layout.maximumHeight: 32
          spacing: 6

          // Fills the remaining width instead of hugging the text --
          // matches ambxst's own titleRect (Layout.fillWidth: true
          // inside the same header RowLayout), not a snug-fit pill.
          Rectangle {
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: height / 2
            color: "#000000"

            Text {
              anchors.centerIn: parent
              text: "Notifications"
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 14
              font.bold: true
            }
          }

          // DND bell -- decorative for now, mirrors the collapsed
          // notch's own bell glyph. Not wired to omarchy.notifications
          // here (ruixen.dnd already owns that toggle, see the bar).
          Rectangle {
            Layout.preferredWidth: 32
            Layout.fillHeight: true
            radius: height / 2
            color: "#000000"

            Text {
              anchors.centerIn: parent
              text: "󰂛"
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 16
            }
          }

          // Clear-all "broom" -- ambxst's own NotificationHistory.qml
          // header has the same bell + broom pair. Decorative, no real
          // history to clear yet.
          Rectangle {
            Layout.preferredWidth: 32
            Layout.fillHeight: true
            radius: height / 2
            color: "#000000"

            Text {
              anchors.centerIn: parent
              text: "󰃢"
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 16
            }
          }
        }

        // No real history service wired here yet -- this is the "does
        // it fit, does it look right" placeholder ambxst's own
        // NotificationHistory.qml occupies.
        Item {
          Layout.fillWidth: true
          Layout.fillHeight: true

          Text {
            anchors.centerIn: parent
            text: "No notifications"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
          }
        }
      }
    }

    // ---- Column 4: volume / brightness / mic dials (static) ---------
    ColumnLayout {
      Layout.preferredWidth: 70
      Layout.maximumWidth: 70
      Layout.fillHeight: true
      // 8px, matching ambxst's own circular-controls column spacing.
      spacing: 8

      component Dial: Item {
        property string glyph: ""
        property real value: 0.7
        Layout.preferredWidth: 48
        Layout.preferredHeight: 48
        Layout.alignment: Qt.AlignHCenter

        Canvas {
          anchors.fill: parent
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2, cy = height / 2, r = width / 2 - 3
            ctx.lineWidth = 3
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.15)
            ctx.beginPath()
            ctx.arc(cx, cy, r, 0, Math.PI * 2)
            ctx.stroke()
            ctx.strokeStyle = root.accent
            ctx.beginPath()
            ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + value * Math.PI * 2)
            ctx.stroke()
          }
        }

        Text {
          anchors.centerIn: parent
          text: parent.glyph
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 14
        }
      }

      Item { Layout.fillHeight: true }
      Dial { glyph: "󰕾"; value: 0.65 }
      Dial { glyph: "󰍬"; value: 0.4 }
      Dial { glyph: "󰃟"; value: 0.8 }
      Item { Layout.fillHeight: true }
    }
  }
}
