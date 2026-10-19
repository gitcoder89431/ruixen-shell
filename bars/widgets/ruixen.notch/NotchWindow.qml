import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons

// The notch's own visible window + its collapsed/expanded content --
// extracted out of Overlay.qml (direct user report: the notch
// never showed up on a second/external monitor in extended mode, since
// it was one single, unbound PanelWindow with no `screen:` and no
// Variants over Quickshell.screens, unlike ruixen.bar's own per-screen
// windows). Instantiated once per screen by Overlay.qml's own Variants
// block below, each given a `notchRoot: root` back-reference the same
// way ruixen.bar/Bar.qml's own Phase 6 refactor already wires
// FrameWindow/BarPanel/etc. -- a separate file gets no free access to
// the surrounding document's ids/properties the way a nested
// `component` declaration in the SAME document would, so every
// `root.foo` read below was rewritten to `notchRoot.foo`.
//
// RoundCorner/WavyLine/UserAvatar/NotchSeparator/TabButton below are
// nested `component` declarations inside this PanelWindow's own body,
// not standalone sibling files of their own (unlike ruixen.bar/Bar.qml's
// equivalent leaf extractions) -- a bare top-level `component`
// declaration before a file's own root object is a QML syntax error
// (confirmed live via qmllint: "Syntax error" on the first one), it has
// to be a statement inside some object's body. These five are used
// only by this window's own content, so nesting them here costs
// nothing and avoids giving each one its own back-reference wiring for
// no reason.
//
// Singleton services (NotificationService/KanbanService/AppLibrary/
// CavaFeed) and the "ruixen.notch" IpcHandler stay behind on
// Overlay.qml's own root, genuinely once each -- duplicating those per
// screen would register the IPC target N times (undefined/broken, not
// just wasteful) and give every monitor its own independent board/
// notification state instead of the one shared one. What's shared is
// instead a handful of plain properties on notchRoot itself
// (pinnedOpen/launcherOpen/dashboardTab/activeScreenName) that every
// one of these per-screen windows reads a GATED view of -- see
// panel.isActiveScreen's own comment below for why a flat shared
// boolean alone isn't enough (two layer-shell surfaces both grabbing
// Wayland's exclusive keyboard focus at once has no defined winner).

PanelWindow {
  id: panel

  component RoundCorner: Item {
    id: rc
    property int corner: 0
    property int cornerSize: 20
    property color fillColor: "#ffffff"

    implicitWidth: cornerSize
    implicitHeight: cornerSize

    onFillColorChanged: canvas.requestPaint()
    onCornerChanged: canvas.requestPaint()
    onCornerSizeChanged: canvas.requestPaint()
    onVisibleChanged: if (visible) canvas.requestPaint()

    readonly property var cornerGeometry: ([
      { centerX: 1, centerY: 1, startAngle: Math.PI, endAngle: 1.5 * Math.PI, pointX: 0, pointY: 0 },
      { centerX: 0, centerY: 1, startAngle: 1.5 * Math.PI, endAngle: 2 * Math.PI, pointX: 1, pointY: 0 },
      { centerX: 1, centerY: 0, startAngle: 0.5 * Math.PI, endAngle: Math.PI, pointX: 0, pointY: 1 },
      { centerX: 0, centerY: 0, startAngle: 0, endAngle: 0.5 * Math.PI, pointX: 1, pointY: 1 }
    ])

    Canvas {
      id: canvas
      anchors.fill: parent
      antialiasing: true
      onPaint: {
        var ctx = getContext("2d")
        var size = rc.cornerSize
        var g = rc.cornerGeometry[rc.corner]
        ctx.clearRect(0, 0, width, height)
        if (!g) return

        ctx.beginPath()
        ctx.arc(g.centerX * size, g.centerY * size, size, g.startAngle, g.endAngle)
        ctx.lineTo(g.pointX * size, g.pointY * size)
        ctx.closePath()
        ctx.fillStyle = rc.fillColor
        ctx.fill()
      }
    }
  }

  // A continuous sine-wave line, in the spirit of Material 3
  // Expressive's own wavy active-indicator pattern (amplitude +
  // wavelength describing the wave, animated by a looping phase
  // offset) -- written independently against that public design
  // language rather than ported from any one project's own
  // implementation. Parametrized directly in physical terms
  // (wavelengthPx: the px distance between crests) instead of a raw
  // cycle count relative to some separately-tracked reference length,
  // which also removes the need for a second "what is this frequency
  // relative to" property entirely -- the wave's spatial density no
  // longer depends on the canvas's own current width at all, so it
  // stays visually consistent even while that width is animating (see
  // the caller below, where the visible portion shrinks/grows as
  // playback progresses).
  //
  // Phase advances from an accumulated elapsed-time counter
  // (FrameAnimation's own per-frame frameTime, in seconds) rather than
  // dividing a raw Date.now() timestamp -- avoids the wave's motion
  // silently losing precision from an ever-growing epoch value over a
  // long-running session, and reads as "speed in radians/second"
  // directly instead of an opaque magic divisor.
  component WavyLine: Canvas {
    id: wave
    property color lineColor: "#ffffff"
    property real lineWidth: 2
    property real wavelengthPx: 24
    property real amplitudeRatio: 0.5
    property bool running: true
    // Radians/second -- 2.5 matches the undulation speed the previous
    // Date.now()/400 divisor gave (1000ms / 400 = 2.5 rad/s).
    property real phaseSpeed: 2.5

    readonly property bool shouldAnimate: running && visible && width > 0 && opacity > 0
    property real phase: 0

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (width <= 0 || height <= 0 || wave.wavelengthPx <= 0) return

      var amplitude = wave.lineWidth * wave.amplitudeRatio
      var angularStep = (2 * Math.PI) / wave.wavelengthPx
      var centerY = height / 2
      var halfStroke = wave.lineWidth / 2

      ctx.strokeStyle = wave.lineColor
      ctx.lineWidth = wave.lineWidth
      ctx.lineCap = "round"
      ctx.beginPath()

      var drawnFirstPoint = false
      for (var x = halfStroke; x <= wave.width - halfStroke; x += 1) {
        var y = centerY + amplitude * Math.sin(angularStep * x + wave.phase)
        if (!drawnFirstPoint) {
          ctx.moveTo(x, y)
          drawnFirstPoint = true
        } else {
          ctx.lineTo(x, y)
        }
      }
      ctx.stroke()
    }

    FrameAnimation {
      running: wave.shouldAnimate
      onTriggered: {
        wave.phase += wave.phaseSpeed * frameTime
        wave.requestPaint()
      }
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

    // AnimatedImage ONLY for a genuine multi-frame animation
    // (frameCount > 1) -- plain Image for everything else, including
    // every static DiceBear/GitHub/custom avatar. Direct live finding
    // (confirmed with temporary console.log instrumentation, then
    // isolated by forcing each element as the sole source in turn):
    // AnimatedImage decodes a NEW static image correctly every time
    // (status genuinely reaches Ready with the right content) but its
    // own texture update does not reliably propagate to MultiEffect past
    // the very first successful decode of its lifetime -- a second,
    // different static image assigned to the SAME AnimatedImage element
    // silently kept showing the first one on screen forever, while the
    // exact same reload sequence through plain Image alone refreshed
    // correctly every single time. Real animated GIFs are unaffected
    // either way (their own frame timer drives repaints through a
    // completely different path, confirmed live: frameCount > 1 still
    // animates correctly here) -- this only changes which element
    // renders STATIC content. .ico still needs the fallback too, for the
    // older, separate reason below (AnimatedImage's decoder errors out
    // on it outright).
    readonly property var activeAvatarImage: (avatarImage.status === Image.Ready && avatarImage.frameCount > 1)
      ? avatarImage : avatarImageFallback
    property int avatarFrameIndex: 0
    readonly property string avatarSource: panel.notchRoot.avatarAnimated
      ? "file://" + panel.notchRoot.avatarFrameDir + "/frame-" + ("00" + avatar.avatarFrameIndex).slice(-3) + ".png#" + panel.notchRoot.avatarCacheBust
      : "file://" + Quickshell.env("HOME") + "/.face.icon#" + panel.notchRoot.avatarCacheBust

    Timer {
      interval: panel.notchRoot.avatarFrameDelayMs
      running: panel.notchRoot.avatarAnimated && panel.notchRoot.avatarFrameCount > 1
      repeat: true
      onTriggered: avatar.avatarFrameIndex = (avatar.avatarFrameIndex + 1) % panel.notchRoot.avatarFrameCount
    }

    // Placeholder shown until/unless ~/.face.icon exists -- a gradient
    // square (see its own no-radius comment below) instead of a shipped
    // PNG asset, so there's no fixed resolution/ratio to pick and it
    // scales cleanly at any avatarSize. Explicitly hidden once a real
    // image is loaded, not just painted over by an assumed-opaque one
    // -- direct follow-up ("why do we need to keep showing the
    // fallback gradient, why cant gradient just be something on and
    // then off between dicebear... why do we need both to appear and
    // overlap"): the two layers overlapping regardless of load state
    // is exactly what let any imperfection show up as the gradient
    // visibly bleeding through, real bug hit live and fixed twice
    // before landing here. With this, the gradient is structurally
    // absent whenever a real avatar is showing.
    Rectangle {
      anchors.fill: parent
      // Circular, unlike the real DiceBear avatars this sits behind
      // (deliberately plain square now, see selectAvatar's own
      // comment) -- direct follow-up ("keep it for the gradient
      // though, the gradient default we load in is square now... why
      // not just make the gradient a circle"). Never shown at the same
      // time as a real avatar (visible below is gated on the image
      // NOT being ready), so the two shapes never need to match.
      radius: width / 2
      visible: !panel.notchRoot.avatarAnimated && avatar.activeAvatarImage.status !== Image.Ready
      // Theme-aware, not two hardcoded colors -- direct follow-up
      // ("install you get the fallback or default gradient, maybe
      // theme aware?"). notchRoot.accent is already Color.accent (see its
      // own declaration above), so this now follows the active
      // Omarchy theme instead of a fixed indigo/violet pair.
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.lighter(panel.notchRoot.accent, 1.6) }
        GradientStop { position: 1.0; color: Qt.darker(panel.notchRoot.accent, 1.4) }
      }
    }

    // No circular treatment -- direct follow-up chain: first "why do
    // we still hard cap a circle around it, doesnt dicebear take care
    // of it" (tried DiceBear's own radius=50 param, which scales each
    // style's content to fit a circle instead of the old MultiEffect
    // mask's blind crop), then, after actually seeing it, "the circle
    // is still there... the circle mask comes back" -- radius=50 still
    // produces a circle, just a better-behaved one, which wasn't the
    // actual ask. Dropped radius=50 too (see ruixen.settings'
    // selectAvatar).
    //
    // Rounded-square clip, not a hard rectangle though -- direct
    // follow-up ("on the site it shows it has like a curved around the
    // edge, its not suppose to be rectangular with hard edge"). That
    // curve is DiceBear's own website preview-card CSS, not part of
    // the fetched image -- confirmed by reading pixelbot's raw SVG
    // directly, rx="0" regardless of style, same as every other style
    // checked so far. So a real mask is what gets that look here, same
    // MultiEffect technique the notch's own shape uses, just a small
    // proportional radius instead of width/2 -- a rounded square, not
    // a circle (the circle stays for the gradient placeholder only,
    // per its own comment above).
    // AnimatedImage exists alongside plain Image so a picked GIF still
    // actually animates (activeAvatarImage's own comment above covers
    // when each one is actually selected) -- QMovie (the decoder behind
    // AnimatedImage) also supports a narrower format set than
    // QImageReader (behind plain Image): an .ico-format ~/.face.icon
    // decodes fine via Image but errors out via AnimatedImage every
    // time, confirmed live.
    AnimatedImage {
      id: avatarImage
      anchors.fill: parent
      source: avatar.avatarSource
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      visible: panel.notchRoot.avatarAnimated
    }

    Image {
      id: avatarImageFallback
      anchors.fill: parent
      source: avatar.avatarSource
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      visible: false
    }

    Rectangle {
      id: avatarImageMask
      anchors.fill: parent
      radius: width * 0.2
      color: "#ffffff"
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: parent
      source: avatar.activeAvatarImage
      visible: !panel.notchRoot.avatarAnimated
      maskEnabled: true
      maskSource: avatarImageMask
      maskThresholdMin: 0.5
      maskThresholdMax: 1.0
    }

    // The click target for opening the dashboard now that hover-to-
    // expand is gone -- per direct request. Only ever visible/hit-
    // testable in the collapsed row (its parent Row's own visible:
    // false while expanded already makes this inert then, no extra
    // guard needed). Margins widen the actual hit target past the
    // small 20px visual circle, same -6 pattern used elsewhere in this
    // file for small icons.
    MouseArea {
      anchors.fill: parent
      anchors.margins: -6
      cursorShape: Qt.PointingHandCursor
      onClicked: panel.openPinned()
    }
  }

  // Thin vertical divider, ported from Separator.qml.
  component NotchSeparator: Rectangle {
    implicitWidth: 3
    implicitHeight: 16
    radius: width / 2
    color: panel.notchRoot.textColor
    opacity: 0.1
  }

  // Left-side vertical tab-bar button (Widgets/Wallpapers/Metrics
  // stacked, plus a settings gear pinned at the bottom). Just a plain
  // icon + tonal hover/active background, no external styling
  // dependency, same approach as every other component in this file.
  component TabButton: Rectangle {
    id: tabBtn
    property string glyph: ""
    property bool active: false
    signal activated()

    // 48 -> 56, glyph 18 -> 20 -- per direct request to grow the
    // left/right rail icons together rather than keep chasing a
    // sub-pixel detail on the dial tip.
    Layout.preferredWidth: 56
    Layout.preferredHeight: 56
    Layout.alignment: Qt.AlignHCenter
    radius: 14
    color: active ? panel.notchRoot.surfaceTint(0.14) : (tabMouse.containsMouse ? panel.notchRoot.surfaceTint(0.07) : "transparent")
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: tabBtn.glyph
      // Direct request: always the theme accent color, not just while
      // active -- the active/inactive distinction stays on the pill
      // background behind this (tabBtn's own color: active ? surfaceTint
      // ... above), not on the glyph itself anymore.
      color: panel.notchRoot.accent
      font.family: panel.notchRoot.fontFamily
      font.pixelSize: 20
    }

    MouseArea {
      id: tabMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tabBtn.activated()
    }
  }


  visible: !notchRoot.fullscreenActive && !notchRoot.barHidden && !notchRoot.fullbarStyle
  // bottom:true too, not just top/left/right -- the click-away-to-
  // dismiss MouseArea (see below) needs the panel's own surface to
  // actually reach the full screen height for its widened mask to
  // cover anywhere outside the notch. Anchoring both top and bottom
  // makes the surface fill the full height regardless of
  // implicitHeight; exclusionMode stays Ignore so this never reserves
  // screen space the way ruixen.bar's own window does.
  anchors { top: true; left: true; right: true; bottom: true }
  // 0, not 4 -- direct report on "On Hover" mode: "theres a bit of
  // dead area on top of the notch... hitting the top edge right now
  // is considered not a on hover area". A Wayland layer-surface
  // margin genuinely shrinks the surface's own occupied/mapped
  // screen area, not just where its QML content starts drawing --
  // with this at 4, the true top 4 screen pixels belonged to no
  // surface's input region at all (ruixen.frame-widget's own
  // overlay is deliberately click/hover-through everywhere, mask:
  // Region {}, so nothing was there to catch it either), a real dead
  // strip impossible to reveal-by-hover into since there is nothing
  // to visually aim for while faded out. The former 4px inset moved
  // into notchOuter's own anchors.topMargin below instead (a plain
  // QML anchor, not a surface margin) -- the pill's own final
  // painted position on screen is unchanged, so ruixen.bar's own
  // notchCollapsedBottomEdge constant (still 48 = 0 surface margin +
  // notchOuter's own 4 anchor margin + 44 height) needs no change.
  margins.top: 0
  implicitHeight: 220
  exclusionMode: ExclusionMode.Ignore
  color: "transparent"

  WlrLayershell.namespace: "ruixen-notch"
  // REVERTED back to Overlay -- the Overlay -> Top change (made to
  // auto-hide over fullscreen windows) broke click-to-expand: this
  // namespace's own layer surface geometry spans nearly the full
  // screen (see `hyprctl layers`), overlapping omarchy-bar's own
  // surface, which is ALSO on `top`. Two same-layer surfaces with
  // overlapping geometry have compositor-decided (not
  // deterministic-to-us) stacking order for pointer hit-testing --
  // omarchy-bar apparently won that contest, eating clicks meant for
  // the notch pill before they ever reached this surface. Overlay is
  // strictly above every other layer including top, so there's no
  // same-layer contention -- confirmed working again after this
  // revert. Fullscreen-hide needs a different mechanism (real
  // fullscreen-state watching) that doesn't reuse a layer another
  // always-on surface already occupies.
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.exclusionMode: ExclusionMode.Ignore
  // None except while expanded (pinned dashboard or launcher), when it
  // switches to Exclusive (same mode ruixen.settings/Settings.qml and
  // Omarchy's own real Menu.qml use for their modal panels) so Escape
  // can dismiss either view and the launcher's own TextInput can
  // receive typed characters. Collapsed stays None -- passive hover, no
  // reason to grab keyboard input. v1 of the launcher's search box
  // needed this SAME flip, but combined it with a taller notch size,
  // which is what actually broke (see launcherContent's own comment
  // below) -- this flip alone, without the resize, is the untested
  // half of that old combination. Extending it to pinnedOpen too
  // carries the same low risk noted there: no new size involved, just
  // a focus-mode change on an already-proven 900x400 footprint.
  WlrLayershell.keyboardFocus: expanded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  // Widens to the full panel only while open (pinned or launcher --
  // see expanded below), so a click anywhere outside the notch itself
  // actually reaches this surface (see the click-away MouseArea
  // below) instead of passing straight through to whatever's behind.
  // Collapsed is the only other state now -- hover-to-expand was
  // removed (see expanded below), so there's no longer a third
  // "briefly widened but shouldn't swallow other clicks" case to
  // exclude here.
  //
  // Collapsed y is 0, not notchOuter's own resting offset -- this
  // Region is what actually tells the compositor which pixels of
  // this surface receive pointer input at all; leaving it at that
  // offset would reopen the exact "On Hover" dead-zone strip
  // margins.top's own comment above describes fixing, just moved
  // from a surface-level gap to a mask-level one. Height reaches
  // notchOuter's real RESTING bottom edge (notchOuter.restY +
  // notchOuter.height, i.e. notchCollapsedBottomEdge) -- deliberately
  // notchOuter.restY, not its live y: that now animates between
  // restY and a negative off-screen value for the slide-down reveal
  // (see notchOuter's own comment), and this mask has to stay fixed
  // at the resting footprint regardless of where the pill's paint
  // currently is mid-animation, or hover detection while fully
  // hidden (y at its most negative) would shrink toward a near-zero
  // or negative height and stop working -- the one moment it most
  // needs to keep working, since that is the state hovering is
  // supposed to reveal it FROM.
  mask: Region {
    x: panel.expanded ? 0 : notchOuter.x
    y: panel.expanded ? 0 : 0
    width: panel.expanded ? panel.width : notchOuter.width
    height: panel.expanded ? panel.height : (notchOuter.restY + notchOuter.height)
  }

  // Back-reference to Overlay.qml's own root -- this file is a
  // separate document now (ruixen-shell issue #96, multi-monitor
  // notch), so it gets no free access to `root`'s properties/
  // functions/singleton services the way a nested `component`
  // declaration in the SAME document would. Wired at the one
  // instantiation site below (Overlay.qml's own Variants block),
  // same `fooRoot: root` back-reference shape ruixen.bar/Bar.qml's
  // own Phase 6 extraction already established for FrameWindow.qml
  // et al.
  property var notchRoot: null

  // Hover-to-expand removed entirely, per direct request -- clicking
  // the avatar (see UserAvatar's own MouseArea) is now the only way
  // to open the dashboard, dismissing by clicking away (below).
  // Deliberate over accidental: hovering near the top of the screen
  // for an unrelated reason (dragging a window, reaching for
  // something else at the top edge) no longer pops the notch open.
  // This also removes the hoverExitTimer debounce hack that hover
  // needed (see the old git history if that's ever wanted back) --
  // a real click has no equivalent "did I actually mean to leave"
  // ambiguity a hover does.
  //
  // pinnedOpen/launcherOpen/dashboardTab themselves now live on
  // notchRoot -- genuinely shared, singleton state (the IpcHandler
  // driving them does too, see Overlay.qml), since this window is
  // instantiated once per screen but there is only one logical
  // dashboard/launcher. What's declared here is a GATED, per-screen
  // VIEW of that shared state: true only on the one screen that
  // actually opened it (notchRoot.activeScreenName), everywhere else
  // reads back false -- the same shared `pinnedOpen` flag that
  // would otherwise make every monitor simultaneously try to render
  // the full interactive dashboard and grab exclusive Wayland
  // keyboard focus at once (confirmed by tracing it, not live --
  // two layer-shell surfaces both requesting Exclusive focus has no
  // well-defined winner). Reads of panel.pinnedOpen/launcherOpen/
  // expanded/dashboardTab elsewhere in this file are UNCHANGED by
  // this -- they already meant "should the thing *I* am looking at
  // show as open" even back when there was only ever one screen to
  // ask that about.
  readonly property bool isActiveScreen: notchRoot.activeScreenName !== ""
    ? (panel.screen && panel.screen.name === notchRoot.activeScreenName)
    : panel.screen === Quickshell.screens[0]
  readonly property bool pinnedOpen: panel.isActiveScreen && notchRoot.pinnedOpen
  readonly property bool launcherOpen: panel.isActiveScreen && notchRoot.launcherOpen
  // Launcher mode grabs focus itself (its own TextInput needs it to
  // receive typed characters -- see launcherContent's onVisibleChanged
  // below). pinnedOpen has no such input by default, so it needs an
  // explicit focus target of its own for Escape to have anything to
  // bubble up from -- WlrKeyboardFocus.Exclusive alone only grants the
  // *surface* keyboard focus at the Wayland level, not Qt Quick's own
  // scene-level activeFocus (same lesson learned building the
  // launcher's search box). notchOuter is the shared ancestor of every
  // dashboard tab's content, so giving it focus here means Escape
  // closes the panel by default, and if the user then clicks into
  // WallpapersContent's own search box, focus moves there like normal
  // -- Escape typed there has nothing to handle it locally and bubbles
  // back up to notchOuter's own Keys.onPressed (see below), so it
  // keeps working either way without WallpapersContent.qml needing any
  // changes of its own.
  onPinnedOpenChanged: if (pinnedOpen) Qt.callLater(function() { notchOuter.forceActiveFocus() })
  // Only two ways to be open now (pinned or launcher), both from a
  // real click -- used directly for the widened click-away mask too
  // (see above), no separate "clickedOpen" needed anymore now that
  // there's no passing-hover state to exclude from it.
  readonly property bool expanded: pinnedOpen || launcherOpen

  // Which dashboard tab is showing (media/media hover/pin state only --
  // launcher mode is unrelated). 0 Widgets (DashboardContent, the real
  // port), 1 Wallpapers, 2 Metrics -- the latter two are stub panes for
  // now, shell only, per direct request to build the tab switcher
  // before the actual pages. Deliberately NOT gated by isActiveScreen
  // like pinnedOpen/launcherOpen above -- it's just an index into
  // which tab's content shows, harmless to read identically on every
  // screen, and the content it picks between is itself already hidden
  // on an inactive screen by expanded (see expandedContent's own
  // visible: below).
  readonly property int dashboardTab: notchRoot.dashboardTab

  // Claims this screen as the one actually showing the expanded view,
  // then opens it -- the one piece every "start showing the pinned
  // dashboard" call site needs, so a stray click on an inactive
  // screen's own still-collapsed pill cannot end up toggling state
  // that then paints wrong on whichever screen WAS already active.
  function openPinned() {
    notchRoot.activeScreenName = panel.screen ? panel.screen.name : ""
    notchRoot.pinnedOpen = true
  }

  // Hover-to-reveal for "On Hover" mode, LOCAL to this screen's own
  // window -- deliberately NOT on notchRoot. Sharing it there (as it
  // was before this file existed once per screen) would mean hovering
  // the pill on one monitor also faded it in on every other one, since
  // they'd all be reading the exact same flag. Everything else about
  // it is unchanged from before this split -- see the original
  // comment on notchVisibilityMode (notchRoot's own) for the feature
  // itself.
  property bool notchHovering: false

  Timer {
    id: notchHoverExitTimer
    interval: 250
    repeat: false
    onTriggered: panel.notchHovering = false
  }

  function notchHoverEntered() {
    notchHoverExitTimer.stop()
    panel.notchHovering = true
  }

  function notchHoverExited() {
    notchHoverExitTimer.restart()
  }

  // Whether the collapsed pill should actually be painted right now --
  // "always" mode (default, matches every prior release) or "hover"
  // mode while the cursor is actually near it, or whenever expanded
  // (opening it is proof enough it should be visible, independent of
  // exactly where the cursor sits at that instant). Only ever fades
  // notchOuter's own opacity, never its visible/geometry -- an
  // invisible Item stops receiving hover in Qt Quick, which would
  // make "on hover" unable to ever detect the hover that is
  // supposed to reveal it in the first place.
  readonly property bool notchPillRevealed: notchRoot.notchVisibilityMode !== "hover" || panel.notchHovering || panel.expanded

  // Fire-once, not auto-running -- triggered by the tab bar's bottom
  // button (see expandedContent below). Opens Omarchy's own real main
  // menu -- the exact same command Super+Space itself runs (confirmed
  // in ~/.config/hypr/bindings/utilities.lua: `o.bind("SUPER + SPACE",
  // "Omarchy menu", "omarchy-menu toggle")`) -- rather than jumping
  // straight to the settings submenu or reimplementing a menu here.
  Process {
    id: mainMenuProc
    command: ["omarchy-menu", "toggle"]
    running: false
  }

  // Click-away-to-dismiss -- covers the whole (now-widened) mask
  // while deliberately clicked open (pinned dashboard or launcher).
  // Declared before notchOuter on purpose: later siblings win
  // hit-testing in QML, so notchOuter's own content (tab buttons,
  // icon cards, the hover/pin MouseArea) still gets first crack at any
  // click within its own bounds; this only ever catches clicks that
  // land outside the notch shape entirely. Resets both flags rather
  // than picking one -- only one is ever true at a time in practice,
  // but clearing both is simpler than tracking which.
  MouseArea {
    anchors.fill: parent
    // Was panel.clickedOpen, a property that never existed on panel --
    // enabled evaluated to undefined (silently falsy), so click-away
    // never actually worked despite the comment above describing it as
    // live. Real fix: the same expanded flag everything else already
    // uses.
    enabled: panel.expanded
    onClicked: { panel.notchRoot.pinnedOpen = false; panel.notchRoot.launcherOpen = false }
  }

  // "On Hover" mode's own hover-detection zone -- a sibling of
  // notchOuter, not a HoverHandler nested inside it, specifically so
  // it can start at this surface's true top edge (y: 0) rather than
  // notchOuter's own resting offset (restY, 4 -- see that property's
  // own comment for why the dead zone existed). Same width as
  // notchOuter, height reaching down through its real RESTING bottom
  // edge (restY + height, deliberately not notchOuter's own live y,
  // which now animates for the slide-down reveal -- see notchOuter's
  // own comment) so the whole collapsed footprint -- including the
  // reclaimed strip above it -- stays one continuous, FIXED hoverable
  // area no matter where the pill's paint currently is mid-animation.
  // No visual of its own; purely observes hover, coexists fine with
  // notchOuter's own nested MouseAreas (avatar, play/pause, bell)
  // since HoverHandler does not consume/block those the way a
  // MouseArea's own click handling would.
  Item {
    id: notchHoverZone
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    width: notchOuter.width
    height: notchOuter.restY + notchOuter.height

    HoverHandler {
      onHoveredChanged: {
        if (hovered) panel.notchHoverEntered()
        else panel.notchHoverExited()
      }
    }
  }

  // Drag onto the Shelf: dragging local files over the collapsed pill asks
  // ruixen.shelf to open (over its own IPC target -- no live object shared
  // between the two plugins), so the drop can land in the open Shelf and be
  // seen. No highlight here: the Shelf opening IS the feedback. The Shelf
  // owns what happens next (it hides itself if the drag leaves without a
  // drop, and stays open once something lands -- see Shelf.qml).
  //
  // A drop that lands on the pill itself, before the Shelf has taken over
  // the drag, is still accepted and relayed (addMany), so a fast release
  // never loses the files. Same footprint as notchHoverZone above (a
  // sibling of notchOuter, so it keeps working while the pill is slid out
  // of view in "On Hover" mode; entering it reveals the pill the way
  // hovering does -- a drag doesn't deliver ordinary hover events, which is
  // why this reuses notchHoverEntered/Exited explicitly). Inert while the
  // notch is expanded: the dashboard/launcher own the surface then.
  //
  // Opening happens immediately on drag-enter (no dwell timer). Whether a
  // drag already in progress carries into the freshly mapped Shelf window is
  // compositor behavior that has to be confirmed live; if it does not, the
  // single call to remove is relayShelfOpen() in onEntered below, which
  // leaves the plain drop-on-the-pill path working.
  DropArea {
    id: shelfQuickDrop
    anchors.top: parent.top
    anchors.horizontalCenter: parent.horizontalCenter
    width: notchOuter.width
    height: notchOuter.restY + notchOuter.height
    enabled: !panel.expanded
    // file:// URLs only -- a web image dragged out of a browser arrives
    // as an http(s) URL and is ignored here, matching the Shelf's own
    // local-files-only contract.
    function localUrls(urls) {
      var out = []
      for (var i = 0; i < (urls || []).length; i++) {
        var s = String(urls[i])
        // A real path after the scheme -- "file:///" (the filesystem
        // root) is rejected by the Shelf anyway, so don't accept it here.
        if (/^file:\/\/(?:localhost)?\/.+/i.test(s)) out.push(s)
      }
      return out
    }
    // Copy semantics only, explicitly (never acceptProposedAction(),
    // which would echo a source app's proposed MoveAction): the Shelf
    // stores a reference and never moves or deletes the source.
    onEntered: (drag) => {
      if (shelfQuickDrop.localUrls(drag.urls).length > 0) {
        drag.accept(Qt.CopyAction)
        panel.notchHoverEntered()
        panel.notchRoot.relayShelfOpen()
      }
    }
    onExited: panel.notchHoverExited()
    onDropped: (drop) => {
      var urls = shelfQuickDrop.localUrls(drop.urls)
      panel.notchHoverExited()
      if (urls.length === 0) return
      panel.notchRoot.relayToShelf(urls)
      drop.accept(Qt.CopyAction)
    }
  }

  Item {
    id: notchOuter
    anchors.horizontalCenter: parent.horizontalCenter
    // y, not anchors.top/topMargin -- direct follow-up on "On Hover"
    // mode ("instead of fading in, can we make it slide down"): an
    // anchor continuously re-asserts position every frame, which
    // would fight a Behavior on y, so vertical position is now a
    // plain property instead. restY (4) is the exact same resting
    // offset the old anchors.topMargin gave it -- moved here
    // verbatim (see margins.top's own comment on the PanelWindow
    // above) so the pill's final on-screen position when revealed is
    // unchanged from before that fix.
    //
    // Collapses to 0 with Frame Border off -- direct follow-up on
    // issue #114 ("disable the top reserve space"): with no frame
    // painted to visually justify the gap, the resting 4px just read
    // as the pill floating off the true screen edge for no reason.
    readonly property int restY: panel.notchRoot.frameEnabled ? 4 : 0
    y: panel.notchPillRevealed ? restY : -(height + 8)
    Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    // Escape closes the expanded dashboard, same as the launcher's own
    // search box already does. Placed here (not on some deeper child)
    // so it catches Escape by default (see onPinnedOpenChanged's
    // forceActiveFocus above) and still catches it if focus later
    // moves to a child that doesn't handle Escape itself, since
    // unhandled key events bubble up the visual parent chain.
    //
    // Tab rotates the three real dashboard panels -- Widgets ->
    // Wallpapers -> Metrics -> back to Widgets, same as clicking each
    // TabButton in turn. The bottom button deliberately isn't part of
    // this cycle: it's a one-shot action (mainMenuProc, opens
    // Omarchy's real main menu), not a view, and landing on it via Tab
    // either fired it immediately (one direct report: "giving me a
    // jump scare") or needed a whole separate selected-vs-activated
    // state to avoid that -- simpler to just leave it mouse-only.
    // Guarded to pinnedOpen only so this never fights the launcher's
    // own Tab handler (launcherOpen's Tab is fully consumed inside
    // launcherContent before it could bubble here anyway, but the
    // guard makes the split explicit rather than relying on that).
    Keys.onPressed: function(event) {
      if (event.key === Qt.Key_Escape && panel.expanded) {
        panel.notchRoot.pinnedOpen = false
        panel.notchRoot.launcherOpen = false
        event.accepted = true
      } else if (event.key === Qt.Key_Tab && panel.pinnedOpen && !panel.launcherOpen) {
        panel.notchRoot.dashboardTab = (panel.notchRoot.dashboardTab + 1) % 4
        event.accepted = true
      }
    }
    // Notch corner geometry derived from this machine's own window
    // rounding (Hyprland rounding=24), not a flat guess:
    // cornerSize=roundness+4, collapsed radius=roundness+4, expanded
    // radius=roundness+20 -- cornerSize=28, collapsed radius=28 (see centerMask
    // below), expanded radius=44.
    //
    // Manually mirrored in ruixen.bar's own notchReservedWidth constant
    // (#28, ruixen.bar's own reserved-space calculation; #41/#38 for
    // why it's a plain constant there rather than a live read) --
    // change this value, change that one too.
    readonly property int cornerSize: 28
    // The mask/shadow silhouette is built from three adjacent pieces
    // (left flank, center, right flank). At fractional output scales,
    // exact edge-to-edge joins can sample as a 1px hairline where a
    // flank touches the center body. Overlap the center slightly
    // under both flanks so those joins overdraw instead of butt up
    // against each other. Keep this small: it is only a seam guard,
    // not a geometry change.
    readonly property int seamOverlap: 2
    // Collapsed width trimmed down from an initial 290 -- this row's
    // actual content (avatar + divider + play glyph/wave + divider +
    // bell) is narrower than that, so 290 left a big empty gap
    // between the avatar/bell and the notch's own curved edges. First
    // attempt went to 240, but collapsedContent's real parent is a
    // clip:true Item sized to exactly bodyWidth (see below) --
    // content measures ~236-240px wide (avatar 20 + 2 dividers +
    // wave-track 140 + play glyph + bell + Row spacing), landing
    // right at that clip edge and cutting the bell off. 260 gives
    // real margin instead of a knife's-edge fit. Expanded width (420)
    // still fits this notch's own expanded content comfortably.
    // Media hover/pin tries a real dashboard-sized target (implicitWidth
    // 900, implicitHeight 56+48*6 = 344) instead of reusing the
    // smaller 420x190 -- untested territory for this notch (only 44
    // and 190 are proven safe against the masking bug below), so
    // watch for the same flat-bottom-corner symptom if this doesn't
    // pan out.
    //
    // launcherOpen deliberately does NOT follow this -- it keeps its
    // own separate 420x190 branch, proven safe, since an earlier
    // attempt at a new size for launcher specifically (340x260, then
    // up to 360) hit that exact masking bug. Decoupled from
    // pinnedOpen here so a size change on one never risks the other.
    //
    // Collapsed 260 -> 284: the playerPill (see collapsedContent
    // below) added its own ~20px of internal padding around the play
    // glyph/wave that the old bare Row didn't have, pushing content
    // back out to ~260px total -- the exact knife's-edge fit 260 was
    // originally chosen to avoid. Per direct report ("avatar circle
    // and bell icon is too close to the notch edge now"), bumped by
    // roughly that same ~20-24px to restore real margin on both
    // sides again.
    //
    // The collapsed case (284, both launcherOpen/pinnedOpen false) is
    // manually mirrored in ruixen.bar's own notchReservedWidth constant
    // (#28, #41/#38) -- change this default, change that one too. The
    // 420/900 expanded cases are deliberately NOT reflected there:
    // ruixen.bar only ever needs to reserve space for the Notch's
    // always-present collapsed footprint, not its temporary expanded
    // states.
    readonly property int bodyWidth: panel.launcherOpen ? 420 : (panel.pinnedOpen ? 900 : 284)
    width: bodyWidth + cornerSize * 2
    // 44px collapsed -- ruixen-bar's own reserved screen zone
    // (notchClearance) was bumped to cover this plus a buffer, so it
    // no longer overlaps tiled windows the way it did when this was
    // smaller but the reserved zone was still just barSize-sized.
    // Dashboard height bumped past the initial 344 to 400 per direct
    // feedback ("a bit too short") -- past the
    // previously-tested-safe value, so stress-tested 3x (open/close
    // cycles, checking the bottom-corner mask each time) before
    // keeping it. Collapsed case (44) manually mirrored in ruixen.bar's
    // own notchCollapsedBottomEdge constant (#41/#38) -- change this
    // value, change that one too.
    height: panel.launcherOpen ? 190 : (panel.pinnedOpen ? 400 : 44)

    Behavior on width { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
    Behavior on height { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }

    // Painted background, masked into the notch silhouette below.
    // Back to a plain, always-real fill -- direct live regression:
    // "the notch bg is stuck on black, its not theme changing anymore".
    // Root cause of THAT bug: this was briefly made transparent when
    // collapsed (an interim step of the FrameWindow-merge experiment,
    // meant to let the frame's own paint show through from underneath
    // instead), but notchShadowBlur below is a SOLID filled shape, not
    // a thin ring -- with notchBg transparent, nothing in this window
    // covered that shadow's own opaque interior anymore, and since
    // ruixen.notch's own window stacks ABOVE FrameWindow in the
    // compositor, its solid black just sat on top of the frame's
    // theme-colored fill, visible everywhere instead of just the
    // surrounding halo. The frame-color sync itself was never actually
    // the problem THAT merge was solving -- notchRoot.notchColor already
    // tracks frameColorMode/Color.background correctly on its own (see
    // its own property block above), always did, via the same shared
    // state file both plugins read -- no FrameWindow-side hole-punch
    // was ever required for THAT part. Reverting this specific piece
    // fixes the regression AND restores the natural "shadow only
    // visible in the halo, covered by the real shape everywhere else"
    // behavior every normal drop shadow has, in both collapsed and
    // expanded.
    Rectangle {
      id: notchBg
      anchors.fill: parent
      color: panel.notchRoot.notchColor

      layer.enabled: true
      layer.smooth: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: notchMask
        maskThresholdMin: 0.5
        maskThresholdMax: 1.0
        maskSpreadAtMin: 1.0
      }

      // Tried, reverted: adding shadowEnabled/shadowColor/shadowBlur/
      // etc. to this same MultiEffect instance ("start with notch
      // then", trying the settings card's own shadow effect here
      // too). Direct live report at the pinned/dashboard size (900x400):
      // "the shape is completely broken, it has almost square edges
      // now, the curves are gone" -- this is exactly the documented,
      // non-deterministic masking bug this same effect has hit
      // before (see this file's own launcher-history comments),
      // reproduced live, not just a theoretical risk. Confirmed at
      // the collapsed and launcher (420x190) sizes without visible
      // breakage first, but the bug didn't show until the larger
      // pinned size -- matches its own documented non-determinism,
      // not a case of skipping the stress test. Reverted immediately
      // per this file's own standing rule: "if the masking bug
      // reproduces despite the size-avoidance, stop and report it
      // rather than pushing through." Do not re-add shadow
      // properties to this MultiEffect instance without solving the
      // underlying masking fragility first -- a real fix, not
      // another attempt at the same combination.

      // No blurred album-art here anymore -- was previously applied
      // across the WHOLE collapsed notch (matching CompactPlayer.qml's
      // backgroundArt treatment), but per direct feedback that "doesn't
      // look too nice on some theme[s]", the notch itself now stays
      // plain OLED black at all times. The art moved into its own
      // small pill instead, scoped to just the play/pause + wave
      // progress area below (see playerPill) -- avatar, dividers, and
      // bell all still sit directly on this same flat black.
    }

    // Shadow: a real, visible, BLURRED duplicate of the exact same
    // 3-piece silhouette as notchMask below (left flank + center block
    // + right flank), dark-filled, sitting BEHIND notchBg. Direct
    // pivot after the hand-rolled Canvas ring-shadow (the previous
    // version of this comment/block) kept getting the curve/radius
    // wrong every tuning pass -- "hard drop", then corner dot
    // artifacts, then a genuinely inverted "mustache" corner, then a
    // reach that compressed against the shape's own small size: "cant
    // the notch edges just produce its own shadow?"
    //
    // A PLAIN blur (MultiEffect's blurEnabled only) is a fundamentally
    // different, much safer code path than the ORIGINAL broken attempt
    // this file already has a hard-learned rule against: "Tried,
    // reverted: adding shadowEnabled/shadowColor/... to this same
    // MultiEffect instance [notchBg's own, which ALSO has maskEnabled]
    // ... the shape is completely broken... Do not re-add shadow
    // properties to this MultiEffect instance without solving the
    // underlying masking fragility first." That bug was specifically
    // shadowEnabled COMBINED with maskEnabled on one effect -- this
    // shape is never masked at all, it just IS the shape, rendered
    // directly and then blurred, so there's nothing for a mask+shadow
    // interaction to break. Guaranteed to match the real silhouette
    // exactly since it's the identical geometry (same cornerSize, same
    // bottomLeftRadius/bottomRightRadius binding), not a hand-derived
    // approximation that has to be kept in sync by hand.
    //
    // Direct live correction, right after this shipped: "check the
    // compact notch top edge, right now it has its own top shadow
    // which doesnt make sense cause its suppose to be part of the
    // frame as one surface illusion." MultiEffect's blur spreads
    // beyond its source item's own bounds in every direction by
    // default (autoPaddingEnabled) -- exactly what makes the halo
    // visible around the sides/bottom, but the same spillover was ALSO
    // bleeding upward past the notch's own top edge, into the frame's
    // own area, undermining the one thing this whole exclusion exists
    // for. notchShadowClip below cuts that off: flush with the notch's
    // own true top (no margin there, so nothing can ever render above
    // it), but expanded on the left/right/bottom by more than the
    // blur's own max reach, so the halo stays fully visible everywhere
    // else. Simpler than the old ring-shadow's own approach (an open,
    // top-excluding PATH) -- here the shape stays the full, real
    // silhouette (still guaranteed to match by construction), only
    // WHERE it's allowed to visibly render changes.
    Item {
      id: notchShadowClip
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.leftMargin: -40
      anchors.right: parent.right
      anchors.rightMargin: -40
      anchors.bottom: parent.bottom
      anchors.bottomMargin: -40
      z: -1
      clip: true

      // Shadow: a real, visible, BLURRED duplicate of the exact same
      // 3-piece silhouette as notchMask below (left flank + center
      // block + right flank), dark-filled. Direct pivot after the
      // hand-rolled Canvas ring-shadow kept getting the curve/radius
      // wrong every tuning pass -- "hard drop", corner dot artifacts,
      // an inverted "mustache" corner, a reach that compressed against
      // the shape's own small size: "cant the notch edges just produce
      // its own shadow?"
      //
      // A PLAIN blur (MultiEffect's blurEnabled only) is a
      // fundamentally different, much safer code path than the
      // ORIGINAL broken attempt this file already has a hard-learned
      // rule against: "Tried, reverted: adding shadowEnabled/
      // shadowColor/... to this same MultiEffect instance [notchBg's
      // own, which ALSO has maskEnabled]... the shape is completely
      // broken... Do not re-add shadow properties to this MultiEffect
      // instance without solving the underlying masking fragility
      // first." That bug was specifically shadowEnabled COMBINED with
      // maskEnabled on one effect -- this shape is never masked at
      // all, it just IS the shape, rendered directly and then blurred,
      // so there's nothing for a mask+shadow interaction to break.
      // Guaranteed to match the real silhouette exactly since it's the
      // identical geometry (same cornerSize, same bottomLeftRadius/
      // bottomRightRadius binding), not a hand-derived approximation
      // that has to be kept in sync by hand.
      //
      // anchors.margins: 40 + topMargin: 0 undoes notchShadowClip's own
      // asymmetric expansion above, so this shape's own bounds land
      // back on the notch's real, unexpanded geometry -- the outer
      // Item only exists to decide where blur is ALLOWED to spill
      // past those bounds, not to resize the shape itself.
      Item {
        id: notchShadowBlur
        anchors.fill: parent
        anchors.margins: 40
        anchors.topMargin: 0
        // 0.6 -> 0.9 -> 1.0. ruixen.bar's own frame shadow peaks at a
        // true 1.0 right at its own edge (frameShadowCanvas's own
        // alpha=1.0*t*t) -- 0.9 here was still a real, if small, gap
        // below that peak (this shape's visible portion is only ever
        // the blurred-out halo, its own true core hidden under
        // notchBg, so the halo's own darkest pixel topped out at 90%
        // black blended with wallpaper, never true black). Direct
        // live report the gap was visible: "it seems less then the
        // frame shadow setting." 1.0 matches the frame's own peak
        // exactly.
        opacity: 1.0

        RoundCorner {
          anchors.top: parent.top
          anchors.left: parent.left
          cornerSize: notchOuter.cornerSize
          corner: 1
          fillColor: "#000000"
        }

        Rectangle {
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.leftMargin: notchOuter.cornerSize - notchOuter.seamOverlap
          anchors.right: parent.right
          anchors.rightMargin: notchOuter.cornerSize - notchOuter.seamOverlap
          height: parent.height
          color: "#000000"
          topLeftRadius: 0
          topRightRadius: 0
          bottomLeftRadius: panel.expanded ? 44 : 28
          bottomRightRadius: panel.expanded ? 44 : 28

          Behavior on bottomLeftRadius { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
          Behavior on bottomRightRadius { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
        }

        RoundCorner {
          anchors.top: parent.top
          anchors.right: parent.right
          cornerSize: notchOuter.cornerSize
          corner: 0
          fillColor: "#000000"
        }

        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
          blurEnabled: true
          // Tried matching ruixen.bar's own frame shadow's numeric
          // reach (shadowReachPx: 8) by shrinking this to blurMax: 16
          // -- looked wrong live: "the shadow looks a little less...
          // not as soft". The frame's 8px is a hard-edge ring-gradient
          // reach, not directly comparable to a Gaussian blurMax; at
          // the higher 0.9 opacity above, a short reach reads as an
          // abrupt ring instead of a soft halo. Restored to the
          // original, larger distance -- the actual bug (wrong
          // curve/shape) is fixed independent of this value now, so
          // widening it back doesn't reintroduce the old corner
          // artifacts, it just fades over more distance again.
          blurMax: 32
          blur: 0.6
        }
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
        anchors.leftMargin: -notchOuter.seamOverlap
        anchors.right: rightFlank.left
        anchors.rightMargin: -notchOuter.seamOverlap
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

    // No general-purpose background MouseArea here anymore -- opening
    // is now only via clicking the avatar (see UserAvatar's own
    // MouseArea below), closing only via clicking away (the mask
    // MouseArea above). Individual interactive elements in the
    // collapsed row (avatar, play/pause, bell) each own their exact
    // click target instead of one catch-all area behind everything.

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

        // Art pill -- the ONLY place blurred album art shows in the
        // collapsed notch now (see notchBg above for why). Wraps just
        // the play/pause glyph + wave progress, per direct scoping
        // request ("leave the bell and avatar and separator bar
        // outside the pill as is"). ClippingRectangle, not a plain
        // Rectangle -- same documented gotcha as playerCard/the art
        // disc in DashboardContent.qml: plain Rectangle.clip only
        // clips to the bounding BOX, ignores radius.
        ClippingRectangle {
          id: playerPill
          anchors.verticalCenter: parent.verticalCenter
          width: pillRow.implicitWidth + pillPadding * 2
          height: 28
          radius: height / 2
          color: Color.background

          readonly property int pillPadding: 10
          // notchRoot.resolvedWallpaperPath (see its own comment) rather
          // than the symlink path directly -- see that comment for why.
          readonly property string wallpaperPath: panel.notchRoot.resolvedWallpaperPath !== ""
            ? "file://" + panel.notchRoot.resolvedWallpaperPath
            : "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
          readonly property string pillBgSource: panel.notchRoot.artUrl !== "" ? panel.notchRoot.artUrl : wallpaperPath

          Image {
            id: pillBgArt
            anchors.fill: parent
            source: playerPill.pillBgSource
            sourceSize: Qt.size(64, 64)
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            visible: false
          }

          MultiEffect {
            anchors.fill: parent
            source: pillBgArt
            blurEnabled: true
            blurMax: 32
            blur: 1.0
            opacity: 0.28
          }

          // Dark scrim on top of the blur so the glyph/wave/playhead
          // stay readable regardless of how bright the underlying art
          // is -- same reasoning as notchBg's own flat base color.
          Rectangle {
            anchors.fill: parent
            color: Qt.rgba(0, 0, 0, 0.35)
          }

          Row {
            id: pillRow
            anchors.centerIn: parent
            spacing: 6

            Text {
              id: collapsedPlayGlyph
              anchors.verticalCenter: parent.verticalCenter
              // Direct follow-up: "we dont need the inactive play
              // button to show then" -- showing a play/pause glyph
              // next to the active-window title (not a track) never
              // made sense once that title took over this slot.
              visible: panel.notchRoot.hasMedia
              text: panel.notchRoot.playIcon
              color: panel.notchRoot.textColor
              font.family: panel.notchRoot.fontFamily
              // Matches the bar's own icon standard (18px) -- was 11,
              // visibly undersized next to the 20px avatar in this
              // same row.
              font.pixelSize: 18

              // Own click target, same pattern as the avatar/bell now
              // that there's no big background MouseArea to compete
              // with -- each interactive element in this row owns its
              // exact hit area independently.
              MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                enabled: panel.notchRoot.hasMedia
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.notchRoot.sendMediaAction("playPause")
              }
            }

            // Fixed 140x20 "now playing" slot -- exactly one of three
            // mutually-exclusive children visible at a time: the
            // seeker (media, mediaVizMode "seeker"), a mini cava
            // visualizer (media, mediaVizMode "cava"), or the active
            // window name (no media at all, unconditional -- see its
            // own comment below for why it has no toggle). Direct
            // request: "since we have the cava visualizer now...
            // click it and it switch between cava and seeker" --
            // scoped to a scroll toggle, and to ONLY the two media-
            // present modes: cava reacts to real audio, so with
            // nothing playing it would just sit at its own flat idle
            // bars, no different from showing nothing at all. Window
            // name already covers that state on its own.
            Item {
              id: nowPlayingSlot
              anchors.verticalCenter: parent.verticalCenter
              width: 140
              height: 20

              MouseArea {
                anchors.fill: parent
                enabled: panel.notchRoot.hasMedia
                cursorShape: panel.notchRoot.hasMedia ? Qt.PointingHandCursor : Qt.ArrowCursor
                // This MouseArea only actually receives input while
                // mediaVizMode is "cava" -- the seeker's own Item
                // (with its own MouseArea) sits on top and shadows
                // this one entirely whenever it's visible. Right
                // click switches back to the seeker, mirroring the
                // seeker's own MouseArea's right click going the
                // other way -- direct follow-up: "right click to go
                // back to the seeker." Wheel no longer toggles mode
                // here (removed) -- right click now owns that switch
                // exclusively in both directions, freeing wheel up to
                // mean "seek" whenever the seeker is the thing
                // showing, not "leave the seeker."
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: function(mouse) {
                  if (mouse.button === Qt.RightButton) {
                    panel.notchRoot.toggleMediaVizMode()
                    return
                  }
                  // Left click cycles bars/wave -- only meaningful
                  // once already in cava mode (nothing to cycle on
                  // the seeker or window name), direct request.
                  if (panel.notchRoot.mediaVizMode === "cava") panel.notchRoot.toggleCavaMiniStyle()
                }
                // Wheel cycles bars/wave here too, mirroring the
                // seeker's own wheel-seeks-instead-of-switches change
                // -- direct follow-up: "on the visualizer when the
                // bars are showing, i cant scroll to the wave
                // anymore... i guess right click and wheel scroll?"
                // Left click keeps doing the same thing too (not
                // replaced) -- both are just different ways to reach
                // the one toggle, same as wheel/click already being
                // two paths to the same seek on the other row.
                onWheel: function(wheel) {
                  if (panel.notchRoot.mediaVizMode === "cava") panel.notchRoot.toggleCavaMiniStyle()
                }
              }

            // Track (full length, dim) + wave (played portion only, up
            // to progressRatio) -- actually reflects position now,
            // instead of a decorative full-width wave. No drag-to-seek
            // yet, position display only.
            Item {
              anchors.fill: parent
              visible: panel.notchRoot.hasMedia && panel.notchRoot.mediaVizMode === "seeker"
            // Grown 12 -> 20 alongside the thickness bump below --
            // WavyLine is a Canvas, and Canvas content outside its
            // own item bounds is simply never drawn (an implicit
            // clip, not a real mask, but reads the same). At
            // lineWidth 4 / amplitudeMultiplier 1.4 the wave's peak
            // extent is +-(amp + lineWidth/2) = +-7.6px from center,
            // needing >=15.2px of height -- the old 12px container
            // was already too short for that, clipping the top/
            // bottom of the wave's crests and troughs.
            height: 20

            // Split point -- where the wave's played portion meets
            // the dim unplayed track, before any gap trim.
            //
            // pressedButtons & LeftButton, not the bare pressed flag --
            // seekerDragArea now also accepts the right button (see its
            // own comment), and pressed goes true for ANY accepted
            // button. A right-click-hold with the bare flag would
            // freeze this at previewRatio's last (possibly stale, e.g.
            // 0 before any left-drag ever happened) value instead of
            // showing the real live position while held.
            readonly property real splitX: width * ((seekerDragArea.pressedButtons & Qt.LeftButton) ? seekerDragArea.previewRatio : panel.notchRoot.progressRatio)
            // Same gap-around-the-tip design as the player ring/
            // dials/brightness bar, ported here too now that it's
            // right on the other components -- per direct request
            // ("bring the design there too"). Computed the same
            // width-aware way that fixed the player ring's real bug
            // (a flat copied constant doesn't clear a custom-sized
            // tip): half the wave's own line width + half the
            // playhead's own width + the desired real clearance.
            // wave lineWidth 4 (half 2) + playhead width 4 (half 2)
            // + 2px desired = 6px, applied as the FULL trim on EACH
            // side independently (not split further) -- matches how
            // the ring's own gapPx already works, not a fresh guess.
            readonly property real gapPx: 6

            // Track/wave/playhead thickened 2px -> 4px together, then
            // wave/playhead alone toned back to 3 (read too thick next
            // to the track). Direct follow-up while music was actually
            // playing: "the wave thickness... kinda too thin now" --
            // back to 4, matching the track again.
            Rectangle {
              // Unplayed remainder, trimmed short of the playhead by
              // gapPx on this side -- starts past the split point,
              // not right at it.
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              width: Math.max(0, parent.width - parent.splitX - parent.gapPx)
              height: 4
              radius: 2
              color: panel.notchRoot.surfaceTint(0.15)
            }

            WavyLine {
              // Trimmed short of the playhead by gapPx on this side
              // too -- the wave's own Canvas bounding width directly
              // controls where its rightmost point sits, so shrinking
              // it here is enough on its own, no separate lineCap
              // handling needed (unlike the circular ring's Canvas
              // arc, this is just a smaller bounding box).
              width: Math.max(0, parent.splitX - parent.gapPx)
              height: parent.height
              anchors.left: parent.left
              anchors.verticalCenter: parent.verticalCenter
              lineColor: panel.notchRoot.hasMedia ? panel.notchRoot.accent : panel.notchRoot.muted
              lineWidth: 4
              // 140/6 preserves the same wave density the old
              // frequency: 6 (cycles across a fixed 140px reference)
              // gave -- expressed directly as a physical wavelength
              // now, so it no longer needs that separate reference
              // length property at all.
              wavelengthPx: 140 / 6
              amplitudeRatio: panel.notchRoot.isPlaying ? 1.4 : 0.15
              running: panel.notchRoot.isPlaying
            }

            // Playhead -- stays centered exactly at the true split
            // point, unchanged -- only the wave/track on either side
            // of it pull back now.
            Rectangle {
              width: 4
              height: parent.height
              radius: width / 2
              anchors.verticalCenter: parent.verticalCenter
              color: panel.notchRoot.textColor
              x: parent.splitX - width / 2
              visible: panel.notchRoot.hasMedia

              Behavior on x {
                enabled: !(seekerDragArea.pressedButtons & Qt.LeftButton)
                NumberAnimation { duration: 450 }
              }
            }

            MouseArea {
              id: seekerDragArea
              anchors.fill: parent
              enabled: panel.notchRoot.hasMedia && panel.notchRoot.canSeek && panel.notchRoot.trackLength > 0
              cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
              // Left drags to seek (this row's whole reason for
              // existing), which collided with left click's prior job
              // of switching between the seeker and the mini cava
              // visualizer. Direct follow-up: "if left click controls
              // the seeker then we cant use left click to switch to
              // visualizer... right click triggers the visualizer
              // instead now." MouseArea only accepts Left by default,
              // so Right is explicitly opted in below and routed to
              // toggleMediaVizMode via onClicked -- onPressed/
              // onPositionChanged/onReleased all stay gated to the
              // left button specifically (mouse.button/pressedButtons
              // checks, not the bare pressed/press-only mouse.button
              // default) so a right click can't also start a seek
              // drag. Wheel already toggled the same viz mode before
              // this PR and still does, unchanged -- this just adds a
              // second, more discoverable way to reach it now that
              // left click itself means something else on this row.
              acceptedButtons: Qt.LeftButton | Qt.RightButton
              property real previewRatio: 0
              function ratioFromMouse(mouse) {
                if (width <= 0) return 0
                return Math.max(0, Math.min(1, mouse.x / width))
              }
              onPressed: function(mouse) {
                if (mouse.button === Qt.LeftButton) previewRatio = ratioFromMouse(mouse)
              }
              onPositionChanged: function(mouse) {
                if (mouse.buttons & Qt.LeftButton) {
                  previewRatio = ratioFromMouse(mouse)
                }
              }
              onReleased: function(mouse) {
                if (mouse.button !== Qt.LeftButton) return
                var ratio = ratioFromMouse(mouse)
                panel.notchRoot.sendMediaSeek(ratio * panel.notchRoot.trackLength)
              }
              onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) panel.notchRoot.toggleMediaVizMode()
              }
              // Wheel now seeks (5s/notch, same flat-step convention
              // Display/Audio's own volume-scroll rows already use)
              // instead of switching to the visualizer -- direct
              // follow-up: "when i [wheel] scroll it is going to the
              // visualizer, we dont want that... lets use the wheel
              // scroll to control the seeker when the seeker is
              // showing." Right click (above) is now the only way to
              // leave the seeker.
              onWheel: function(wheel) {
                var delta = wheel.angleDelta.y > 0 ? 5 : -5
                var target = Math.max(0, Math.min(panel.notchRoot.trackLength, panel.notchRoot.trackPosition + delta))
                panel.notchRoot.sendMediaSeek(target)
              }
            }
            }

            // Mini cava visualizer -- a fresh, smaller CavaFeed
            // instance (kept separate from ruixen.cava's own edge-
            // docked overlay: a different plugin entirely, plugin
            // folders can't share state, and this one only needs to
            // run while actually visible). Fixed horizontal/bottom-
            // grow layout, unlike the full overlay's own configurable
            // orientation -- this slot is always exactly 140x20, so
            // that generality buys nothing here.
            //
            // Mirrored, not a plain 1:1 sweep -- direct request:
            // real bass on both edges, treble in the center, "looks
            // better that way for aesthetic." displayBars is double
            // cavaMirrorBands (root, see its own comment): position i
            // and position (displayBars-1-i) both read the SAME real
            // band, folded around the center. mirrorBandAt(i) is
            // exactly "distance from the nearest edge" -- 0 at either
            // edge (band 0, bass), displayBars/2-1 at the two
            // innermost positions either side of center (the highest
            // analyzed band, treble), by construction of the fold.
            Item {
              id: cavaMiniSlot
              anchors.fill: parent
              visible: panel.notchRoot.hasMedia && panel.notchRoot.mediaVizMode === "cava"

              readonly property int displayBars: panel.notchRoot.compactCavaFeed.bands * 2

              function mirrorBandAt(i) {
                return Math.min(i, cavaMiniSlot.displayBars - 1 - i)
              }

              // Warm center, cool edges -- same formula ruixen.cava/
              // Overlay.qml's own bandColor() already uses, applied
              // to the DISPLAY index/count here (mirroring already
              // makes display-index distance-from-center behave the
              // same way band-index distance-from-center does there).
              function barColor(i, level) {
                var mid = cavaMiniSlot.displayBars / 2
                var dist = cavaMiniSlot.displayBars > 1 ? Math.abs(i - mid + 0.5) / mid : 0
                var c = Qt.rgba(
                  panel.notchRoot.cavaWarmColor.r + (panel.notchRoot.cavaCoolColor.r - panel.notchRoot.cavaWarmColor.r) * dist,
                  panel.notchRoot.cavaWarmColor.g + (panel.notchRoot.cavaCoolColor.g - panel.notchRoot.cavaWarmColor.g) * dist,
                  panel.notchRoot.cavaWarmColor.b + (panel.notchRoot.cavaCoolColor.b - panel.notchRoot.cavaWarmColor.b) * dist,
                  1)
                return Qt.lighter(c, 1 + 0.35 * level)
              }

              // A subtle opacity taper on the outermost couple of
              // positions at EITHER edge -- direct follow-up: "the
              // side of the visualizer edge, its kinda sharp... fade
              // opacity the edges a bit to soften it up." Same idea
              // ruixen.cava/Overlay.qml's own edgeFade already uses,
              // just a much smaller edgeFadeBands -- that file's
              // fixed 6 is tuned against a strip with 32-96 bands;
              // applied unscaled here (displayBars is only 12) it
              // would fade the entire left/right HALVES toward
              // center, not just the last couple of positions at
              // each edge.
              readonly property int edgeFadeBands: 2

              function edgeFade(i) {
                var d = Math.min(i, cavaMiniSlot.displayBars - 1 - i)
                return Math.max(0, Math.min(1, d / cavaMiniSlot.edgeFadeBands))
              }

              // Bars/wave, click-toggled (notchRoot.toggleCavaMiniStyle,
              // nowPlayingSlot's own MouseArea.onClicked) -- no
              // "segments" here, see notchRoot.cavaMiniStyle's own comment
              // for the sub-pixel math that ruled it out at this size.
              Repeater {
                model: panel.notchRoot.cavaMiniStyle === "bars" ? cavaMiniSlot.displayBars : 0
                Rectangle {
                  readonly property real slot: cavaMiniSlot.width / cavaMiniSlot.displayBars
                  readonly property real thick: Math.max(1, slot - 2)
                  readonly property real level: panel.notchRoot.compactCavaFeed.levels[cavaMiniSlot.mirrorBandAt(index)] || 0
                  width: thick
                  height: Math.max(2, level * cavaMiniSlot.height)
                  radius: thick / 2
                  x: index * slot + (slot - thick) / 2
                  y: cavaMiniSlot.height - height
                  color: cavaMiniSlot.barColor(index, level)
                  opacity: cavaMiniSlot.edgeFade(index)

                  Behavior on height { NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
                }
              }

              // Wave -- a filled, smoothed curve through the same
              // mirrored levels the bars use, not just a stroked
              // zigzag -- direct correction: "it wasnt suppose to be
              // a line, our desktop wave has like gradient filled
              // in." Same technique ruixen.cava/Overlay.qml's own
              // wave style already uses: quadratic-through-midpoints
              // for a smooth curve (each segment's endpoint is the
              // midpoint between two real points, the real point
              // itself as the control point, so the curve passes
              // close to every point without sharp corners), filled
              // from that curve down to the bottom edge (bars grow up
              // from there too -- same baseline) with the cool/warm/
              // cool gradient, then a brighter stroke retraced along
              // the same curve on top for definition against the
              // fill.
              Canvas {
                id: cavaMiniWave
                anchors.fill: parent
                visible: panel.notchRoot.cavaMiniStyle === "wave"

                function rgbaStr(c, a) {
                  return "rgba(" + Math.round(c.r * 255) + "," + Math.round(c.g * 255) + "," + Math.round(c.b * 255) + "," + a + ")"
                }

                onVisibleChanged: if (visible) requestPaint()

                Connections {
                  target: panel.notchRoot.compactCavaFeed
                  function onLevelsChanged() { if (cavaMiniWave.visible) cavaMiniWave.requestPaint() }
                }

                onPaint: {
                  var ctx = getContext("2d")
                  ctx.reset()
                  var n = cavaMiniSlot.displayBars
                  if (n < 2) return

                  var pts = []
                  for (var i = 0; i < n; i++) {
                    var level = panel.notchRoot.compactCavaFeed.levels[cavaMiniSlot.mirrorBandAt(i)] || 0
                    var x = (i / (n - 1)) * width
                    var y = height - Math.max(1, level * height)
                    pts.push(Qt.point(x, y))
                  }

                  // 8-step gradient (not just 3 flat stops), each
                  // step's own alpha additionally scaled by
                  // cavaMiniSlot.edgeFade -- same technique
                  // ruixen.cava/Overlay.qml's own wave gradient
                  // already uses. Direct follow-up: "the side of the
                  // visualizer edge, its kinda sharp... fade opacity
                  // the edges a bit to soften it up." Without this,
                  // the fill/stroke hit full alpha right at x=0/x=
                  // width, where the shape's own edge coincides
                  // exactly with the canvas's own edge -- reading as
                  // a hard cutoff rather than easing out.
                  var grad = ctx.createLinearGradient(0, 0, width, 0)
                  var steps = 8
                  for (var s = 0; s <= steps; s++) {
                    var t = s / steps
                    var bandIdx = t * (n - 1)
                    var c = cavaMiniSlot.barColor(bandIdx, 0)
                    var fade = cavaMiniSlot.edgeFade(bandIdx)
                    grad.addColorStop(t, cavaMiniWave.rgbaStr(c, 0.85 * fade))
                  }

                  ctx.beginPath()
                  ctx.moveTo(pts[0].x, height)
                  ctx.lineTo(pts[0].x, pts[0].y)
                  for (var j = 1; j < n - 1; j++) {
                    var mx = (pts[j].x + pts[j + 1].x) / 2
                    var my = (pts[j].y + pts[j + 1].y) / 2
                    ctx.quadraticCurveTo(pts[j].x, pts[j].y, mx, my)
                  }
                  ctx.lineTo(pts[n - 1].x, pts[n - 1].y)
                  ctx.lineTo(pts[n - 1].x, height)
                  ctx.closePath()
                  ctx.fillStyle = grad
                  ctx.fill()

                  ctx.beginPath()
                  ctx.moveTo(pts[0].x, pts[0].y)
                  for (var k = 1; k < n - 1; k++) {
                    var mx2 = (pts[k].x + pts[k + 1].x) / 2
                    var my2 = (pts[k].y + pts[k + 1].y) / 2
                    ctx.quadraticCurveTo(pts[k].x, pts[k].y, mx2, my2)
                  }
                  ctx.lineTo(pts[n - 1].x, pts[n - 1].y)
                  ctx.lineWidth = 2
                  ctx.lineCap = "round"
                  ctx.lineJoin = "round"
                  ctx.strokeStyle = grad
                  ctx.stroke()
                }
              }
            }

            // The "no media" half of this same 140x20 slot -- direct
            // request: "when theres no music it just shows active
            // window". Reads Quickshell.Wayland's own ToplevelManager
            // directly (already imported, already used for
            // fullscreenActive above) rather than depending on the
            // separate omarchy.active-window plugin being installed
            // or pinned at all. Centered + elided, not a marquee --
            // direct follow-up ("is there an effect where it scrolls
            // horizontally, or i guess truncate is fine tbh? center
            // and truncate?") -- simpler, and matches ActiveWindow.qml's
            // own elide: Text.ElideRight treatment of the same title
            // string. "~" is the empty-state fallback for the rare
            // moment nothing is focused at all (just closed
            // everything, say), rather than leaving the pill blank.
            // No toggle of its own -- unconditional whenever there's
            // no media, see nowPlayingSlot's own header comment for why.
            CompactWindowTitle {
              anchors.fill: parent
              visible: !panel.notchRoot.hasMedia
              text: panel.notchRoot.compactWindowTitle !== "" ? panel.notchRoot.compactWindowTitle : "~"
              // Direct follow-up ("are the text a bit muted") -- this
              // is the primary content of the slot now, not a
              // secondary status readout, so it gets the same full
              // textColor a real track title would use, not muted.
              color: panel.notchRoot.textColor
              font.family: panel.notchRoot.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            }
          }
        }

        NotchSeparator { anchors.verticalCenter: parent.verticalCenter }

        Text {
          anchors.verticalCenter: parent.verticalCenter
          text: panel.notchRoot.dnd ? "󰂛" : "󰂚"
          // Matches the dashboard's own bell exactly (see
          // DashboardContent.qml's notification header) -- theme
          // accent when notifications are live, the same fixed red
          // when silenced. Was notchRoot.muted, per direct request to
          // bring the same theme-color/red treatment here too.
          //
          // Glyph now swaps too (md-bell vs md-bell_off), not just
          // color -- real bug caught in DashboardContent.qml's own
          // copy of this same bell: the crossed-bell codepoint was
          // hardcoded for BOTH states, so "notifications are live"
          // was silently showing a slashed bell in accent color
          // instead of the plain one.
          color: panel.notchRoot.dnd ? "#e05252" : panel.notchRoot.accent
          font.family: panel.notchRoot.fontFamily
          font.pixelSize: 18

          Behavior on color { ColorAnimation { duration: 160 } }

          // Real toggle now, not just a state readout -- per direct
          // request ("the notification toggle right"). Goes through
          // the real "notifications" IPC target (confirmed against
          // the real service's own IpcHandler) rather than
          // ruixen.quickactions' own bar.shell.firstPartyServiceFor()
          // call -- this file has no bar capabilities to make that
          // same call with, see the dnd property comment above.
          MouseArea {
            anchors.fill: parent
            anchors.margins: -6
            cursorShape: Qt.PointingHandCursor
            onClicked: panel.notchRoot.sendDndAction("toggleDnd")
          }
        }
      }

      // Expanded: blurred-art thumbnail, title/artist, big wave
      // progress, transport controls.
      // Expanded: dashboard content (player + quick controls/calendar +
      // notifications + volume dials) -- see DashboardContent.qml
      // for the full breakdown. Media data/colors passed through
      // from the same root-level properties the collapsed view
      // already reads.
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
          // 8px -- tightened from 10, a bit looser than this row's
          // own rhythm otherwise.
          spacing: 8

          // Left vertical tab bar: Widgets/Wallpapers/Metrics stacked
          // icon buttons, settings gear pinned at the bottom via a
          // fillHeight spacer above it. All three are real now (see
          // WallpapersContent.qml/MetricsContent.qml) -- Metrics'
          // own right-side stat tiles are still a stub within that
          // file, see its own comments.
          ColumnLayout {
            Layout.preferredWidth: 78
            Layout.maximumWidth: 78
            Layout.fillHeight: true
            spacing: 8

            // Explicitly sets pinnedOpen: true too, even though it's
            // already true by the time a tab is clickable at all
            // (this whole bar only exists inside the pinned-open
            // dashboard now that hover-to-expand is gone) -- cheap
            // safety net, not load-bearing anymore.
            TabButton {
              glyph: "󰕰"
              active: panel.dashboardTab === 0
              onActivated: { panel.notchRoot.dashboardTab = 0; panel.openPinned() }
            }
            TabButton {
              glyph: ""
              active: panel.dashboardTab === 1
              onActivated: { panel.notchRoot.dashboardTab = 1; panel.openPinned() }
            }
            TabButton {
              glyph: ""
              active: panel.dashboardTab === 2
              onActivated: { panel.notchRoot.dashboardTab = 2; panel.openPinned() }
            }
            TabButton {
              glyph: ""
              active: panel.dashboardTab === 3
              onActivated: { panel.notchRoot.dashboardTab = 3; panel.openPinned() }
            }

            Item { Layout.fillHeight: true }

            // The one real action in this tab bar -- opens Omarchy's
            // actual main menu (see mainMenuProc above), the same
            // Super+Space menu, not a notch-local settings page. Was
            // "omarchy-menu summon settings" (straight to the Setup
            // submenu) per direct follow-up asking for the real root
            // menu instead. Mouse-only on purpose -- see notchOuter's
            // Keys.onPressed comment for why Tab deliberately skips
            // this one.
            TabButton {
              glyph: ""
              onActivated: mainMenuProc.running = true
            }
          }

          // Right: active tab's content.
          Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            DashboardContent {
              anchors.fill: parent
              visible: panel.dashboardTab === 0
              shell: panel.notchRoot.shell
              // This whole tab bar + content area (an ancestor of this
              // item) stays visible: true/opacity-based, not behind a
              // Loader -- DashboardContent is alive for the entire
              // session, not just while the dashboard is open. Needed
              // here so its own nightlight status poll (ruixen-shell
              // issue #43) can gate on the same "only while actually
              // visible" condition brightnessStateProc's own Timer
              // above already uses, instead of polling forever.
              panelExpanded: panel.expanded
              textColor: panel.notchRoot.textColor
              muted: panel.notchRoot.muted
              accent: panel.notchRoot.accent
              fontFamily: panel.notchRoot.fontFamily
              themeSurfaceMode: panel.notchRoot.frameColorMode === "theme"
              accentDashboardHeaders: panel.notchRoot.barIconTone === "accent"
              sendMediaAction: panel.notchRoot.sendMediaAction
              sendMediaSeek: panel.notchRoot.sendMediaSeek
              hasMedia: panel.notchRoot.hasMedia
              isPlaying: panel.notchRoot.isPlaying
              canSeek: panel.notchRoot.canSeek
              playIcon: panel.notchRoot.playIcon
              title: panel.notchRoot.title
              artist: panel.notchRoot.artist
              album: panel.notchRoot.album
              artUrl: panel.notchRoot.artUrl
              resolvedWallpaperPath: panel.notchRoot.resolvedWallpaperPath
              progressRatio: panel.notchRoot.progressRatio
              trackPosition: panel.notchRoot.trackPosition
              trackLength: panel.notchRoot.trackLength
              userHost: panel.notchRoot.userHost
              displayedTitle: panel.notchRoot.displayedTitle
              dnd: panel.notchRoot.dnd
              sendDndAction: panel.notchRoot.sendDndAction
              notificationHistory: panel.notchRoot.notificationHistory
              brightnessPercent: panel.notchRoot.brightnessPercent
              brightnessAvailable: panel.notchRoot.brightnessAvailable
              setBrightness: panel.notchRoot.setBrightness
            }

            WallpapersContent {
              id: wallpaperPicker
              anchors.fill: parent
              visible: panel.dashboardTab === 1
              active: panel.dashboardTab === 1 && panel.expanded
              textColor: panel.notchRoot.textColor
              muted: panel.notchRoot.muted
              accent: panel.notchRoot.accent
              secondary: panel.notchRoot.themeSecondaryColor
              dangerColor: panel.notchRoot.kanbanDangerColor
              fontFamily: panel.notchRoot.fontFamily
              // The jump button itself runs the actual launcher
              // IPC call (see its own comment); this only collapses
              // the notch on the way out, same property
              // closeDashboard() above sets -- jumping to the
              // launcher's Wallpaper Shuffle extension with the
              // notch still expanded underneath it would look like
              // two overlays stacked on top of each other.
              onOpenWallpaperShuffleRequested: panel.notchRoot.pinnedOpen = false
              // Same reasoning, for the Wallpapers Effects jump
              // button right next to it.
              onOpenWallpaperEffectsRequested: panel.notchRoot.pinnedOpen = false
              // Same reasoning, for Theme mode's own Bjarneo Themes
              // jump button.
              onOpenThemeBrowserRequested: panel.notchRoot.pinnedOpen = false
            }

            MetricsContent {
              anchors.fill: parent
              visible: panel.dashboardTab === 2
              active: panel.dashboardTab === 2 && panel.expanded
              textColor: panel.notchRoot.textColor
              muted: panel.notchRoot.muted
              accent: panel.notchRoot.accent
              fontFamily: panel.notchRoot.fontFamily
              avatarCacheBust: panel.notchRoot.avatarCacheBust
              avatarAnimated: panel.notchRoot.avatarAnimated
              avatarFrameCount: panel.notchRoot.avatarFrameCount
              avatarFrameDelayMs: panel.notchRoot.avatarFrameDelayMs
              avatarFrameDir: panel.notchRoot.avatarFrameDir
            }

            KanbanContent {
              anchors.fill: parent
              visible: panel.dashboardTab === 3
              textColor: panel.notchRoot.textColor
              muted: panel.notchRoot.muted
              accent: panel.notchRoot.accent
              confirmColor: panel.notchRoot.cavaCoolColor
              successColor: panel.notchRoot.kanbanSuccessColor
              dangerColor: panel.notchRoot.kanbanDangerColor
              warningColor: panel.notchRoot.kanbanWarningColor
              // Per direct request to swap which of the column panel
              // and its nested cards reads darker: cards sit ON TOP
              // of the column's own already-tinted fill (both
              // double-painted -- KanbanContent's own cardBase +
              // cardChrome -- and single-painted alike), so tinting
              // them FURTHER toward textColor only ever pushes darker
              // still when textColor itself is dark (a light theme) --
              // confirmed live, no alpha was low enough to escape
              // that, since it's the wrong tint DIRECTION, not just
              // too strong a magnitude. Tints toward white instead
              // specifically when textColor is dark (surface is
              // light) -- that's the one direction that can actually
              // read lighter than an already-darkened parent. Keeps
              // the original textColor-tint on a dark theme (textColor
              // light there), where that direction already lightens
              // correctly on its own, same as before. 0.65, tuned
              // live against the actual rendered card (not derived on
              // paper): the card's own MultiEffect drop shadow sits
              // BEHIND cardBase at a real, non-trivial opacity
              // (shadowOpacity 0.38) and bleeds through the card's own
              // translucent fill from underneath, darkening the
              // visible result well past what plain double-layer
              // alpha compositing alone predicts -- 0.2 (matched to
              // DashboardContent's own dashboardCardSurface, which
              // has no such shadow-bleed factor) still rendered
              // clearly darker than the column live, 0.4 landed
              // exactly equal to it, 0.65 is what actually reads
              // lighter on screen.
              cardSurface: panel.notchRoot.surfaceLuminance(panel.notchRoot.textColor) < 0.5
                ? Qt.rgba(1, 1, 1, 0.65)
                : Qt.rgba(panel.notchRoot.textColor.r, panel.notchRoot.textColor.g, panel.notchRoot.textColor.b, 0.055)
              cardBorderColor: Qt.rgba(panel.notchRoot.textColor.r, panel.notchRoot.textColor.g, panel.notchRoot.textColor.b, 0.14)
              editorSurface: Qt.rgba(panel.notchRoot.textColor.r, panel.notchRoot.textColor.g, panel.notchRoot.textColor.b, 0.075)
              fontFamily: panel.notchRoot.fontFamily
              kanbanService: panel.notchRoot.kanbanService
            }
          }
        }
      }

      LauncherContent {
        overlayRoot: panel.notchRoot
        panel: panel
        appLibrary: panel.notchRoot.appLibrary
      }
    }
  }
}
