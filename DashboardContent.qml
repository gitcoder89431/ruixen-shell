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
  // Real DND state passthrough, same first-party service the collapsed
  // notch's own bell already reads -- was undefined here, the
  // notification header's bell was purely decorative.
  property bool dnd: false

  // Idle-state artist placeholder -- a small ROW of braille cells with
  // one lit dot scanning back and forth (Cylon/KITT-scanner style),
  // not one single big spinner glyph. First attempt used ONE braille
  // character bumped to 16px+bold to be legible at all -- per direct
  // follow-up ("taking too much space... multiple braille patterns
  // looping in one row, not really a big braille... like ascii art
  // pattern"), that was the wrong shape of animation entirely. This
  // builds a fixed-width string of brailleCells characters every tick,
  // one "lit" cell (full block) at the scanning position and dim
  // resting dots everywhere else, so it reads as a small loading-bar
  // ASCII animation at the SAME 10px size the album/artist lines
  // already use, instead of a single oversized glyph.
  readonly property int brailleCells: 6
  property int brailleStep: 0
  // Ping-pong 0..brailleCells-1..0 instead of wrapping, so the lit
  // dot visibly scans back and forth rather than jump-cutting.
  readonly property int braillePeriod: (brailleCells - 1) * 2
  readonly property int brailleActiveIndex: {
    var p = brailleStep % braillePeriod
    return p < brailleCells ? p : braillePeriod - p
  }
  readonly property string brailleSpinner: {
    var s = ""
    for (var i = 0; i < brailleCells; i++)
      s += (i === brailleActiveIndex ? "⣿" : "⠒")
    return s
  }

  Timer {
    interval: 1000
    repeat: true
    running: !root.hasMedia
    onTriggered: root.brailleStep++
  }

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
      // "butt", not "round" -- same lesson learned from the small
      // dial's ring: a round cap on a TRIMMED arc/polyline endpoint
      // visually extends the stroke past its own geometric point by
      // roughly half the line width, which would bleed straight back
      // into the gap below and erase it. Tip gets its own round cap,
      // set right before it's drawn.
      ctx.lineCap = "butt"

      // Track -- ONLY the unplayed remainder, not the full span. The
      // wavy progress stroke's radius wobbles around r (the sine
      // perturbation), so a full-span grey arc drawn underneath it
      // peeked through in slivers wherever the wave's radius differed
      // from the plain track's -- a "tail" of grey bleeding around the
      // wave. Same fix the linear compact-notch WavyLine already uses:
      // its Canvas width IS parent.width * progressRatio, so the dim
      // track only ever covers what's actually unplayed. Matched here
      // by drawing the grey arc from endAngle onward instead of the
      // full sweep.
      var clamped = Math.max(0, Math.min(1, seek.value))
      var endAngle = seek.startAngle + seek.spanAngle * clamped
      // Small gap on both sides of the tip, same design now used for
      // the dials/brightness bar elsewhere in this file -- per direct
      // request to bring this ring in line with that. gapPx as an arc
      // length (not a fixed radian value) so it stays visually
      // consistent regardless of this ring's own radius.
      var gapPx = 8
      var gapRad = gapPx / r
      ctx.strokeStyle = seek.trackColor
      ctx.beginPath()
      ctx.arc(cx, cy, r, Math.min(seek.startAngle + seek.spanAngle, endAngle + gapRad), seek.startAngle + seek.spanAngle)
      ctx.stroke()
      // Fake round cap at the track's own natural end (the ring's true
      // terminus, unrelated to the tip/gap) -- "butt" above keeps the
      // gap-side end flat on purpose, but that flattened BOTH ends of
      // the arc since lineCap applies uniformly to a whole stroke. A
      // small filled circle here restores the soft rounded look at
      // just this one end, matching what "round" used to give it
      // before the gap fix needed "butt" globally.
      {
        var trackEndAngle = seek.startAngle + seek.spanAngle
        ctx.fillStyle = seek.trackColor
        ctx.beginPath()
        ctx.arc(cx + r * Math.cos(trackEndAngle), cy + r * Math.sin(trackEndAngle), seek.ringWidth / 2, 0, Math.PI * 2)
        ctx.fill()
      }

      // Progress -- up to value, accent, wavy (a sine ripple on the
      // radius) only while actually playing. Trimmed short of the
      // tip's true position (endAngle) by gapRad, same as the track
      // above.
      var progressEndAngle = Math.max(seek.startAngle, endAngle - gapRad)
      ctx.strokeStyle = seek.progressColor
      ctx.beginPath()
      var steps = 48
      var startX, startY
      for (var i = 0; i <= steps; i++) {
        var t = i / steps
        var angle = seek.startAngle + (progressEndAngle - seek.startAngle) * t
        var rr = r
        if (seek.wavy) rr += Math.sin(angle * 16 + seek.wavePhase) * 2.5
        var x = cx + rr * Math.cos(angle)
        var y = cy + rr * Math.sin(angle)
        if (i === 0) { ctx.moveTo(x, y); startX = x; startY = y }
        else ctx.lineTo(x, y)
      }
      ctx.stroke()
      // Same fake round cap, at the progress stroke's own natural
      // start (seek.startAngle, unrelated to the tip) -- uses the
      // polyline's own actual first point so it matches exactly even
      // with the wave's sine perturbation applied.
      if (progressEndAngle > seek.startAngle) {
        ctx.fillStyle = seek.progressColor
        ctx.beginPath()
        ctx.arc(startX, startY, seek.ringWidth / 2, 0, Math.PI * 2)
        ctx.fill()
      }

      // Tip -- a thick radial tick at the current progress position,
      // ported from ambxst's own CircularSeekBar handle (a fat line
      // straddling the track radius, not a dot on top of it). Always
      // drawn now, even at value: 0 (clamped === 0 just means it sits
      // right at the arc's own start point) -- per direct request to
      // keep it visible at the head of the ring in the idle/no-media
      // state too, instead of disappearing entirely.
      {
        var tipOffset = 6
        var tipR1 = r - tipOffset
        var tipR2 = r + tipOffset
        var tx1 = cx + tipR1 * Math.cos(endAngle)
        var ty1 = cy + tipR1 * Math.sin(endAngle)
        var tx2 = cx + tipR2 * Math.cos(endAngle)
        var ty2 = cy + tipR2 * Math.sin(endAngle)
        ctx.lineWidth = seek.ringWidth * 1.5
        ctx.lineCap = "round"
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
    // ClippingRectangle, not a plain Rectangle -- the same gotcha
    // documented below for the album art disc applies here too: plain
    // Rectangle.clip only clips children to the bounding BOX, it does
    // not follow radius. That left the sharp-edge accent ring's outer
    // boundary as a literal square (playerCard's full rectangular
    // bounds) while its inner boundary (from innerAreaMask) was
    // correctly rounded -- the mismatch read as "straight corners" on
    // the border specifically, even though playerCard's own radius:10
    // was set correctly the whole time.
    ClippingRectangle {
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
        // A crop wrapper was tried once already for the TOP of this
        // container and reverted -- the thick tip swings up into that
        // zone depending on progress angle, so cropping it was unsafe
        // at every playback position. The BOTTOM is different: the
        // ring's sweep (startAngle: PI, spanAngle: PI, i.e. angle in
        // [PI, 2*PI]) has sin(angle) <= 0 throughout that whole range,
        // so cx/cy math never places the ring OR its tip below the
        // container's own vertical center, at any progress value --
        // only the disc's own lower half lives down there, and the
        // disc's position doesn't move with progress at all. Safe to
        // crop unconditionally: disc bottom sits at a fixed 160 (95
        // center + 65 radius) inside the 190-tall square, so a 165px
        // wrapper trims the genuinely-always-empty 25px below it
        // without risking clipping the disc itself under any state.
        // Always visible now, even with nothing playing -- per direct
        // feedback ("keep all the stuff shown so it doesnt get
        // jumpy"), the whole card used to disappear down to just a
        // title line when there was no active player, then pop back
        // to full size the moment something started playing. Falls
        // back to the desktop wallpaper (playerCard.playerBgSource
        // already resolves that) instead of the track art when idle.
        Item {
          Layout.preferredWidth: 190
          Layout.preferredHeight: 165
          Layout.alignment: Qt.AlignHCenter
          clip: true

          Item {
            width: 190
            height: 190

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
                source: playerCard.playerBgSource
                sourceSize: Qt.size(260, 260)
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
              }
            }
          }
        }

        // Title + album + artist as three centered lines, matching
        // ambxst's own metadata ColumnLayout exactly (title bold, TWO
        // secondary lines dimmer -- album was missing entirely before,
        // not just the ordering being off).
        // leftMargin/rightMargin -- long titles/artists were eliding
        // (or just wrapping) right up against playerCard's own edge,
        // only ~4px of natural clearance from the card's rounded
        // corner. 10px each side gives real breathing room before the
        // ellipsis, per direct feedback ("text looks ugly when it
        // gets so close to the edge").
        ColumnLayout {
          Layout.fillWidth: true
          Layout.leftMargin: 10
          Layout.rightMargin: 10
          Layout.alignment: Qt.AlignHCenter
          spacing: 2

          // Placeholder title/album/artist below (not root.displayedTitle,
          // which is "user@host" -- meant for the collapsed notch's own
          // fallback, not this dashboard) -- fixed, made-up text so the
          // whole 3-line block stays visible and sized identically
          // whether or not anything's actually playing, matching the
          // "no jumpiness" goal above.
          Text {
            Layout.fillWidth: true
            text: root.hasMedia ? root.title : "Nothing Playing"
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 12
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: root.hasMedia ? root.album !== "" : true
            text: root.hasMedia ? root.album : "Enjoy the Silence"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }

          Text {
            Layout.fillWidth: true
            visible: root.hasMedia ? root.artist !== "" : true
            text: root.hasMedia ? root.artist : root.brailleSpinner
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 10
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
          }
        }

        // No Layout.fillWidth here -- a plain Row doesn't center its
        // own children, it just left-packs them from x=0. fillWidth
        // stretched the Row to the card's full width while the icons
        // stayed left-anchored inside it; Layout.alignment only
        // centers the Row ITSELF within the parent, which only works
        // if the Row is sized to its own content instead of stretched.
        // Icon sizes scaled up to match the album art disc's own
        // growth (80 -> 130 across earlier passes) -- play/pause
        // grown to ambxst's real 44x44 playPauseBtn dimension
        // (previously 34, undersized for how big the disc got since),
        // prev/next and spacing scaled by the same ~1.3x factor.
        Row {
          Layout.alignment: Qt.AlignHCenter
          spacing: 22

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰒮"
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 18
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
            width: 44
            height: 44
            radius: 11
            color: root.accent

            Text {
              anchors.centerIn: parent
              // Plain square-outline (md-square_outline, U+F0763) in
              // the genuinely idle state instead of the play triangle
              // -- a stop symbol reads as "stopped", not "ready to
              // play something that isn't there". First attempt used
              // md-stop_circle_outline (a square-in-a-circle) -- per
              // direct follow-up ("looks weird with the circle, just
              // use the square icon"), dropped the circle wrapper
              // entirely for a plain hollow square.
              text: root.hasMedia ? root.playIcon : "󰝣"
              color: "#000000"
              font.family: root.fontFamily
              font.pixelSize: 20
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
            font.pixelSize: 18
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
        // formatTime(length), muted). topMargin on top of the
        // ColumnLayout's own 8px spacing, per direct feedback --
        // wanted a bit more separation here specifically, not a
        // blanket increase to every gap in the column.
        Text {
          Layout.alignment: Qt.AlignHCenter
          Layout.topMargin: 10
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
        // Monday-first index (0=Mon..6=Sun) matching the M T W T F S S
        // label order -- JS getDay() is Sunday-first (0=Sun), so +6 %7
        // shifts it. -1 (never matches) when viewing a different month,
        // same guard isToday already uses for the day cells.
        readonly property int currentDayOfWeek: monthShift === 0 ? (today.getDay() + 6) % 7 : -1

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
          // Header grown 28px -> 36px (title 13px -> 16px, chevron
          // pills 28px -> 36px, glyphs 14px -> 16px) and the day-grid
          // below shrunk to compensate -- per direct feedback, the
          // weekday label row was drawing too much attention next to
          // this comparatively small header.
          RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 36
            Layout.maximumHeight: 36
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
                font.pixelSize: 16
                font.bold: true
              }
            }

            Rectangle {
              Layout.preferredWidth: 36
              Layout.fillHeight: true
              radius: 8
              color: "#000000"

              Text {
                anchors.centerIn: parent
                text: "󰅁"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: 16
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: calendarPane.monthShift -= 1
              }
            }

            Rectangle {
              Layout.preferredWidth: 36
              Layout.fillHeight: true
              radius: 8
              color: "#000000"

              Text {
                anchors.centerIn: parent
                text: "󰅂"
                color: root.accent
                font.family: root.fontFamily
                font.pixelSize: 16
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
          // Shrunk 268px -> 230px alongside the header growing above --
          // weekday labels, row height, today-circle, and day-number
          // size all pulled back a notch so this panel reads calmer
          // next to the now-bigger header, per direct feedback ("M T W
          // T F takes too much of the attention"). That overshot: the
          // header grew +8px (28->36) but this only shrank by the OLD
          // pre-header-growth amount, opening a real ~30px grey gap
          // below the day-grid within calendarPane -- confirmed by
          // sampling actual rendered pixel colors down the column
          // (grey #2E363C starting well past where the black panel
          // should have ended). 230 -> 260 restores calendarColumn's
          // total content height back to what it was before any of
          // this pass (margins 8 + header 36 + spacing 4 + 260 = 308,
          // matching the original 8 + 28 + 4 + 268 = 308 exactly) --
          // the header's own growth is now actually compensated for
          // instead of guessed at via font-size nudges.
          Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 260
            Layout.maximumHeight: 260
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
                    required property int index
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    // Today's own weekday letter reads brighter (full
                    // textColor) than the rest (muted/dim), per direct
                    // request.
                    color: index === calendarPane.currentDayOfWeek ? root.textColor : root.muted
                    font.family: root.fontFamily
                    // Bumped back up a touch (10px -> 12px) -- the
                    // 230px day-grid shrink left it ending a bit early
                    // within calendarPane, per direct feedback.
                    font.pixelSize: 12
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
                  Layout.preferredHeight: 26
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
                          width: 22
                          height: 22
                          radius: 11
                          color: parent.modelData.isToday ? root.accent : "transparent"

                          Text {
                            anchors.centerIn: parent
                            text: parent.parent.modelData.day
                            color: parent.parent.modelData.isToday ? "#000000" : (parent.parent.modelData.inMonth ? root.textColor : root.muted)
                            font.family: root.fontFamily
                            font.pixelSize: 10
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

          // DND bell -- mirrors the collapsed notch's own bell glyph,
          // now reading the same real dnd state (was undefined/
          // decorative here before). Still not clickable -- the actual
          // toggle stays owned by ruixen.dnd, this just reflects state.
          // Accent (theme token) when notifications are live, the same
          // fixed red the collapsed notch's own bell uses when silenced
          // -- kept as a fixed semantic color rather than theme-linked,
          // same reasoning as accent itself before it got theme-linked:
          // "DND active" needs to read as alarm/urgent regardless of
          // theme, not blend into it.
          Rectangle {
            Layout.preferredWidth: 32
            Layout.fillHeight: true
            radius: height / 2
            color: "#000000"

            Text {
              anchors.centerIn: parent
              text: "󰂛"
              color: root.dnd ? "#e05252" : root.accent
              font.family: root.fontFamily
              font.pixelSize: 16
            }
          }

          // Clear-all "broom" -- ambxst's own NotificationHistory.qml
          // header has the same bell + broom pair. Decorative, no real
          // history to clear yet. Fixed orange (not theme-linked, same
          // "state semantic" reasoning as the bell's red above) --
          // deliberately different from the bell's red so "DND active"
          // and "clear/destructive action" don't share one color.
          Rectangle {
            Layout.preferredWidth: 32
            Layout.fillHeight: true
            radius: height / 2
            color: "#000000"

            Text {
              anchors.centerIn: parent
              text: "󰃢"
              color: "#e0a050"
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
      // 70 -> 78, matching the left-rail tab bar's own width bump --
      // per direct request to grow both rails together.
      Layout.preferredWidth: 78
      Layout.maximumWidth: 78
      Layout.fillHeight: true
      // 8px, matching ambxst's own circular-controls column spacing.
      spacing: 8

      // Round tonal badge wrapping icon + ring together, matching
      // ambxst's real CircularControl.qml directly (checked the actual
      // component, not just its usage in WidgetsTab.qml) -- it's a
      // StyledRect (tonal panel) containing both the Canvas ring AND
      // the icon Text as children, not a bare ring floating on the
      // card background like this was before. Per direct request
      // ("wrap/frame the tonal badge so the mic icon and the progress
      // bar is together like ambxst... inside a round tonal badge").
      // Ring inset bumped 3px -> 8px to match their own ratio (their
      // ring radius is a fixed 16 inside a 48px box, i.e. width/2 - 8)
      // -- 3px sat the ring almost flush against the badge's own edge.
      component Dial: Rectangle {
        property string glyph: ""
        property real value: 0.7
        // 48 -> 56, matching the left-rail tab bar's own bump -- also
        // grows the ring radius (width/2-8) and makes the tip's gap
        // relatively easier to see, both per direct request.
        Layout.preferredWidth: 56
        Layout.preferredHeight: 56
        Layout.alignment: Qt.AlignHCenter
        radius: width / 2
        color: Qt.rgba(1, 1, 1, 0.06)

        // Not a full circle -- ambxst's own ring has a 45deg gap on
        // each side (their gapAngle: 45), starting at ~7:30 on a clock
        // face and sweeping 270deg clockwise back around to ~4:30,
        // leaving the gap sitting at the bottom of the badge. Matched
        // their exact angle math (baseStartAngle = 90deg + gapAngle,
        // totalAngle = 360deg - 2*gapAngle) in this Canvas's own radian
        // terms, per direct request ("doesnt have like a full
        // circle... goes from i guess 4 o'clock to 7 o'clock").
        Canvas {
          anchors.fill: parent
          onPaint: {
            var ctx = getContext("2d")
            ctx.reset()
            var cx = width / 2, cy = height / 2, r = width / 2 - 8
            var startAngle = Math.PI / 2 + Math.PI / 4
            var totalSweep = Math.PI * 2 - Math.PI / 2
            var endAngle = startAngle + value * totalSweep
            // Small angular gap on both sides of the tip (~3px of arc
            // length, converted to radians via arc-length/radius) so
            // neither arc actually touches it -- ambxst's own handle
            // has this exact detail (their handleGapRad), trimming
            // both the progress arc's end and the remaining track's
            // start short of the handle position. Subtle on purpose,
            // per direct request ("slight gap... subtle, small
            // detail").
            var gapRad = 3 / r
            ctx.lineWidth = 3
            // "butt", not "round", for these two -- a round cap on the
            // TRIMMED end of an arc visually extends the stroke past
            // its own geometric endpoint by ~half the lineWidth, which
            // was bleeding straight back into the gap above and
            // erasing it. The tip below still gets its own round cap,
            // set right before it's drawn.
            ctx.lineCap = "butt"
            ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.15)
            ctx.beginPath()
            ctx.arc(cx, cy, r, Math.min(startAngle + totalSweep, endAngle + gapRad), startAngle + totalSweep)
            ctx.stroke()
            // Fake round cap at the track's own natural end (the
            // ring's true ~4:30 terminus, unrelated to the tip) --
            // "butt" above flattened both ends of the arc, same fix
            // as the player ring's CircularSeek.
            ctx.fillStyle = Qt.rgba(1, 1, 1, 0.15)
            ctx.beginPath()
            ctx.arc(cx + r * Math.cos(startAngle + totalSweep), cy + r * Math.sin(startAngle + totalSweep), 1.5, 0, Math.PI * 2)
            ctx.fill()

            ctx.strokeStyle = root.accent
            ctx.beginPath()
            var dialProgressEnd = Math.max(startAngle, endAngle - gapRad)
            ctx.arc(cx, cy, r, startAngle, dialProgressEnd)
            ctx.stroke()
            // Same fake round cap, at the progress arc's own natural
            // start (~7:30, unrelated to the tip).
            if (dialProgressEnd > startAngle) {
              ctx.fillStyle = root.accent
              ctx.beginPath()
              ctx.arc(cx + r * Math.cos(startAngle), cy + r * Math.sin(startAngle), 1.5, 0, Math.PI * 2)
              ctx.fill()
            }

            // Thick tip at the current value, same treatment as the
            // player card's own CircularSeek tip -- a fat radial tick,
            // not a dot, white for contrast against the accent arc.
            // Ambxst's own handle here is the SAME width as the ring
            // itself (their lineWidth: 4 reused for both) -- went
            // noticeably thicker instead per direct request ("pretty
            // thick"), matching how the bigger player ring's tip
            // already reads chunkier than its own track.
            if (value > 0) {
              // Shortened -- r-3/r+5 (an 8px span) stuck out too far
              // past the ring, per direct feedback.
              var tipR1 = r - 2
              var tipR2 = r + 3
              var tx1 = cx + tipR1 * Math.cos(endAngle)
              var ty1 = cy + tipR1 * Math.sin(endAngle)
              var tx2 = cx + tipR2 * Math.cos(endAngle)
              var ty2 = cy + tipR2 * Math.sin(endAngle)
              ctx.lineWidth = 5
              ctx.lineCap = "round"
              ctx.strokeStyle = "#ffffff"
              ctx.beginPath()
              ctx.moveTo(tx1, ty1)
              ctx.lineTo(tx2, ty2)
              ctx.stroke()
            }
          }
        }

        Text {
          anchors.centerIn: parent
          text: parent.glyph
          color: root.textColor
          font.family: root.fontFamily
          // Matches the left-rail tab bar's own glyph size (20px,
          // bumped alongside it from 18) -- was 14 originally, read
          // small next to it, per direct feedback.
          font.pixelSize: 20
        }
      }

      // Rail restructured to mirror the left tab bar's own header/
      // footer pattern, per direct request: brightness icon pinned as
      // the rail's HEADER (top, no spacer above it), speaker+mic
      // dials pinned as the FOOTER (bottom, no spacer below them),
      // and the brightness bar sits in the middle, centered in
      // whatever space is left by a fillHeight spacer on each side --
      // same "header content, spacer, footer content" shape the tab
      // bar already uses for its settings gear, just with a middle
      // element added here.
      //
      // Checked ambxst's real source directly for the icon+bar SHAPE
      // itself (WidgetsTab.qml's brightnessContainer: icon on top, a
      // vertical bar below it, NOT a circular dial like speaker/mic
      // get) -- this reorder doesn't change that shape, just where
      // the pieces sit in the column.
      Rectangle {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 38
        Layout.preferredHeight: 38
        radius: 12
        color: Qt.rgba(1, 1, 1, 0.06)

        Text {
          anchors.centerIn: parent
          text: "󰃟"
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 20
        }
      }

      // Same gap+tip language as the Dial's own ring -- a white tip
      // straddling a small gap at the current value, much clearer on
      // a straight bar than the small circular dial.
      //
      // Layout.fillHeight, not a fixed preferredHeight sandwiched
      // between two spacers -- per direct follow-up ("isnt filling in
      // between header and footer... just like a small bar in the
      // middle"), the bar itself is now the flexible element that
      // consumes the actual leftover space between the icon above and
      // the dials below, instead of floating at a fixed 56px with
      // empty spacer gaps on both sides. valueY/gapPx below already
      // reference `height` reactively, so this needs no other changes
      // -- they recompute correctly at whatever height fillHeight
      // resolves to.
      // No longer draws the dim track itself directly (color:
      // transparent) -- per direct feedback ("the tail has it but the
      // head doesnt have the cap"), the track was still spanning the
      // bar's FULL height uncut, so it ran right up against the tip's
      // own top edge with zero separation while the fill (already
      // explicitly trimmed short below the tip) had a real gap. Track
      // is now its own explicitly-trimmed Rectangle too, stopping
      // short ABOVE the tip by the same gapPx the fill already stops
      // short below it -- a real, symmetric gap on both sides now,
      // not just one.
      Rectangle {
        id: brightnessBar
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 7
        Layout.fillHeight: true
        radius: 3
        color: "transparent"

        property real value: 0.8
        // Distance from the bar's own top edge to the value line --
        // both track and fill stop short of it by gapPx, the tip sits
        // centered right on it, straddling into both gaps.
        readonly property real valueY: height * (1 - value)
        // Bumped 4 -> 8 alongside the tip's own growth (5px -> 7px
        // tall) -- the trim needs to clear the tip's now-bigger
        // half-height (3.5px) with real margin, or the "gap" ends up
        // a sub-pixel sliver again, same lesson as the dial's tip.
        readonly property real gapPx: 8

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.top: parent.top
          height: Math.max(0, parent.valueY - parent.gapPx)
          radius: 3
          color: Qt.rgba(1, 1, 1, 0.15)
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          height: Math.max(0, parent.height - parent.valueY - parent.gapPx)
          radius: 3
          color: root.accent
        }

        // Sticks out further past the bar's own edges (+4 -> +12) and
        // grown a bit taller (5 -> 7) -- per direct feedback it read
        // too small/subtle before.
        Rectangle {
          anchors.horizontalCenter: parent.horizontalCenter
          y: parent.valueY - height / 2
          width: parent.width + 12
          height: 7
          radius: 3.5
          color: "#ffffff"
        }
      }

      Dial { glyph: "󰕾"; value: 0.65 }
      Dial { glyph: "󰍬"; value: 0.4 }
    }
  }
}
