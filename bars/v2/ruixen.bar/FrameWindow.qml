import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

// The shell's own decorative border, as its own fullscreen, always-
// click-through window -- ported from v1 ruixen.frame-widget's own
// Canvas hole-punch technique (fill, then punch a rounded-rect hole
// out with destination-out compositing), reading barRoot.frameInset/
// barRoot.frameColor/barRoot.docked/barRoot.lookFeelVariant directly
// instead of re-deriving independent copies of them (v1's frame-widget
// had to shell out to read shell.json/looknfeel.lua itself; this bar
// already has all of that live on barRoot). Still ONE authoritative
// Canvas for all four edges, unlike v1's two-plugin split -- that part
// of the original fix stands. BarPanel.qml (its own sibling file) is
// what changed back: it tried living in THIS SAME window for one pass
// (a genuinely fullscreen BarPanel), which fixed the frame/bar seam
// completely but broke exclusiveZone (see BarPanel's own comment) and
// broke every stock Omarchy popup on this bar (weather/clock/agents
// read this window's REAL height for their own positioning --
// fullscreen made that the whole screen instead of the bar's real
// strip, direct live report: "shows up very small on the bottom").
// Splitting BarPanel back out fixes both without giving up the frame's
// own single-Canvas fix -- BarPanel's own comment explains how the
// seam stays covered even though these are two separate surfaces
// again.
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 1) as a pure file
// move: this was previously `component FrameWindow: PanelWindow { ... }`
// declared inline inside Bar.qml's own `Item { id: root }`, which gave it
// free access to `root`'s properties/functions since it was a nested type
// in the SAME document. A standalone file gets none of that for free --
// `barRoot` below is the explicit back-reference every `root.foo` read in
// this file was rewritten to go through (`barRoot.foo`), wired at the one
// instantiation site in Bar.qml's own Variants block (`barRoot: root`).
// No behavior change from this move -- every property/function/Connections
// target below is byte-identical to before, just resolved through
// `barRoot` instead of the free `root` a nested type used to get.
PanelWindow {
  id: frameWindow

  required property Item barRoot

  readonly property string dockChromeScreenName: barRoot.screenNameForWindow(frameWindow)
  readonly property int dockChromeSerial: barRoot.dockChromeMetricsSerial
  readonly property var dockChromeMetrics: {
    dockChromeSerial
    return barRoot.dockChromeMetrics(dockChromeScreenName)
  }

  visible: true
  exclusionMode: ExclusionMode.Ignore
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  surfaceFormat.opaque: false
  WlrLayershell.namespace: "omarchy-shell-frame"
  // Bottom, not Top -- BarPanel (real content, and its own insurance-
  // overlap trim, see its own comment) needs to render ON TOP of this
  // wherever the two would otherwise meet.
  WlrLayershell.layer: WlrLayer.Bottom
  // Zero interactive purpose ever -- matches v1 ruixen.frame-widget's
  // own `mask: Region {}` exactly.
  mask: Region {}

  Canvas {
    id: frameCanvas
    anchors.fill: parent
    // A hard edge has no fractional coverage to leak on a fractional
    // Hyprland monitor scale -- same fix v1's own frame-widget already
    // needed for this exact Canvas technique, ported unchanged.
    antialiasing: false

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Connections {
      target: frameWindow.barRoot
      function onFrameColorChanged() { frameCanvas.requestPaint() }
      function onLookFeelVariantChanged() { frameCanvas.requestPaint() }
      function onDockedChanged() { frameCanvas.requestPaint() }
    }

    function roundedRect(ctx, x, y, w, h, r) {
      const rr = Math.max(0, Math.min(r, w / 2, h / 2))
      ctx.beginPath()
      ctx.moveTo(x + rr, y)
      ctx.lineTo(x + w - rr, y)
      ctx.quadraticCurveTo(x + w, y, x + w, y + rr)
      ctx.lineTo(x + w, y + h - rr)
      ctx.quadraticCurveTo(x + w, y + h, x + w - rr, y + h)
      ctx.lineTo(x + rr, y + h)
      ctx.quadraticCurveTo(x, y + h, x, y + h - rr)
      ctx.lineTo(x, y + rr)
      ctx.quadraticCurveTo(x, y, x + rr, y)
      ctx.closePath()
    }

    // Matches v1 ruixen.frame-widget's own cornerRadius exactly:
    // square only when BOTH floating AND sharp -- docked mode stays
    // curved regardless of curvature (docked's own bigger gaps already
    // keep a real window's corner clear of this curve, so there's no
    // clipping risk to avoid by going square there). "half" follows
    // the window's own half step (12) for the same match-the-real-
    // corners reason.
    readonly property int frameCornerRadius: !frameWindow.barRoot.docked
      ? (frameWindow.barRoot.lookFeelVariant === "sharp" ? 0
        : frameWindow.barRoot.lookFeelVariant === "half" ? 12
        : 24)
      : 24

    onPaint: {
      const ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      ctx.fillStyle = frameWindow.barRoot.frameColor
      ctx.fillRect(0, 0, width, height)
      ctx.globalCompositeOperation = "destination-out"
      const holeY = frameWindow.barRoot.frameInset
      roundedRect(ctx, frameWindow.barRoot.frameInset, holeY,
        width - frameWindow.barRoot.frameInset * 2, height - holeY - frameWindow.barRoot.frameInset,
        frameCornerRadius)
      // Old, since-reverted: a second notch-shaped hole punched here
      // too, so this canvas's own paint would show through ruixen.notch's
      // own window wherever it left itself transparent. Direct live
      // regression that reverting caused: "the notch bg is stuck on
      // black, its not theme changing anymore" -- ruixen.notch's own
      // window stacks ABOVE this one in the compositor, so once its own
      // notchShadowBlur (a SOLID filled shape, not a thin ring) had
      // nothing opaque left in front of it to hide its own interior
      // behind, that solid black sat on top of whatever this hole
      // showed through, regardless of this hole's own color. Restoring
      // ruixen.notch's own always-real notchBg fill (see its own
      // comment) fixed that regression directly and made this hole
      // redundant at the same time -- ruixen.notch's own opaque layer
      // covers this exact footprint either way now, hole or not, so
      // there's nothing left for a hole here to actually reveal. Removing
      // it is a clean simplification, not a functional loss -- and it
      // incidentally fixes the one real limitation the hole always had:
      // "hover"/"hidden" notch visibility modes previously left an
      // always-open gap here even while the notch itself was hidden;
      // with no hole punched at all, that footprint is just the frame's
      // own ordinary top edge now, matching every other point along it.
      ctx.fill()
      ctx.globalCompositeOperation = "source-over"
    }
  }

  // Inner shadow along the hole's own inside edge, giving the frame
  // some depth instead of a flat color band -- a SEPARATE Canvas from
  // frameCanvas above, not more drawing inside it. Direct live report,
  // corners only: "theres dots artifact kinda stuff, looks like an
  // anti alias... issue". Root cause: frameCanvas has antialiasing:
  // false, deliberately, so the hole-punch's own hard edge has no
  // fractional coverage to leak on a fractional Hyprland scale (see
  // its own comment) -- but that setting applies to the WHOLE canvas
  // for a given paint, and this shadow draws many thin CURVED strokes
  // (see the loop below), which rasterize as a jagged dotted mess
  // without antialiasing, especially stacked at a rounded corner. The
  // shadow has none of the cross-surface alignment risk the hole-punch
  // edge does -- it never has to agree pixel-for-pixel with anything
  // outside this one window -- so it can just be antialiased properly
  // on its own canvas instead.
  Canvas {
    id: frameShadowCanvas
    anchors.fill: parent
    antialiasing: true

    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()
    Connections {
      target: frameWindow.barRoot
      function onFrameColorChanged() { frameShadowCanvas.requestPaint() }
      function onLookFeelVariantChanged() { frameShadowCanvas.requestPaint() }
      function onDockedChanged() { frameShadowCanvas.requestPaint() }
    }

    // Independent per-corner radii, not one uniform r like frameCanvas's
    // own helper -- needed so the top-left/top-right corners can be
    // squared off in THIS canvas specifically (see shadow-corner
    // exclusion comment in onPaint below) without touching frameCanvas's
    // own hole-punch geometry, which stays uniformly rounded and has
    // never needed this.
    function roundedRectCorners(ctx, x, y, w, h, rTop, rBottom) {
      const rt = Math.max(0, Math.min(rTop, w / 2, h / 2))
      const rb = Math.max(0, Math.min(rBottom, w / 2, h / 2))
      ctx.beginPath()
      ctx.moveTo(x + rt, y)
      ctx.lineTo(x + w - rt, y)
      ctx.quadraticCurveTo(x + w, y, x + w, y + rt)
      ctx.lineTo(x + w, y + h - rb)
      ctx.quadraticCurveTo(x + w, y + h, x + w - rb, y + h)
      ctx.lineTo(x + rb, y + h)
      ctx.quadraticCurveTo(x, y + h, x, y + h - rb)
      ctx.lineTo(x, y + rt)
      ctx.quadraticCurveTo(x, y, x + rt, y)
      ctx.closePath()
    }

    // How many pixels the shadow reaches into the hole before fading
    // out completely. 16 -> 8 -- direct live follow-up right after the
    // antialiasing fix: "the shadow distance is soft now but a bit too
    // much distance now, it looks more like a fade lol". Halved so the
    // darkness concentrates closer to the edge and reads as a defined
    // shadow again, not a broad wash.
    readonly property int shadowReachPx: 8

    onPaint: {
      const ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      const frameCornerRadius = !frameWindow.barRoot.docked
        ? (frameWindow.barRoot.lookFeelVariant === "sharp" ? 0
          : frameWindow.barRoot.lookFeelVariant === "half" ? 12
          : 24)
        : 24
      // Direct live follow-up, top corners only, bottom confirmed
      // clean: "theres still some specs of dots left on the top right
      // and left corner". Root cause isn't this canvas's own
      // antialiasing (already fixed) -- it's that BarPanel's own
      // docked wing pieces (leftShoulderWing/leftFrameHemWing and
      // their right-side mirrors, a SEPARATE window layered on top)
      // already fully cover this exact corner when docked, and only
      // rightShoulderWing ever got the small sibling-overlap insurance
      // this repo already uses elsewhere for exactly this class of
      // gap (#36-era fix) -- leftShoulderWing/both hem-wings never
      // did. That pre-existing sub-pixel seam was harmless before
      // (flat frame color peeking through matched the wing's own flat
      // black almost exactly) but this shadow's own gradient now gives
      // it something to visibly leak as a fleck. Rather than touch
      // BarPanel's own wing geometry (a different, more fragile fix,
      // deliberately deferred earlier this same session pending an
      // actual report), squaring off just THIS canvas's own top
      // corners when docked removes the shadow from the only place it
      // could ever leak into that seam -- the open middle of the top
      // edge (unclaimed by any wing) keeps its shadow exactly as
      // before, and bottom corners (nothing overlapping them ever)
      // are untouched.
      const topRadius = (frameWindow.barRoot.docked && frameWindow.barRoot.position === "top") ? 0 : frameCornerRadius
      ctx.save()
      const holeY = frameWindow.barRoot.frameInset
      roundedRectCorners(ctx, frameWindow.barRoot.frameInset, holeY,
        width - frameWindow.barRoot.frameInset * 2, height - holeY - frameWindow.barRoot.frameInset,
        topRadius, frameCornerRadius)
      ctx.clip()
      ctx.lineWidth = 1
      // 0.8 -> 0.95 peak -- direct live report comparing corners
      // against different wallpaper brightness (top-right, a lighter
      // patch, looked "blurred"; bottom-right, over a darker area, read
      // clean): 20% of whatever's underneath still showing through even
      // at the shadow's own darkest point is negligible against a dark
      // background but reads as a visible bright haze against a light
      // one -- not a bug in the falloff shape (still the same smooth
      // quadratic curve, still "soft"), just not dark enough at the
      // peak to look like a solid edge regardless of what's behind it.
      // "the shadow to like appear like the frame is on top" -- the
      // peak needs to nearly fully override the wallpaper's own
      // brightness, then fade, not stay semi-transparent throughout.
      for (var i = 0; i < shadowReachPx; i++) {
        var t = 1 - (i / shadowReachPx)
        var alpha = 1.0 * t * t
        if (alpha < 0.004) continue
        if (frameWindow.barRoot.integratedTopDockSurface) {
          ctx.save()
          ctx.beginPath()
          ctx.rect(0, frameWindow.barRoot.frameInset + frameWindow.barRoot.barSize, width, height - frameWindow.barRoot.frameInset - frameWindow.barRoot.barSize)
          ctx.clip()
        }
        ctx.strokeStyle = Qt.rgba(0, 0, 0, alpha)
        roundedRectCorners(ctx, frameWindow.barRoot.frameInset + i, holeY + i,
          width - (frameWindow.barRoot.frameInset + i) * 2, height - holeY - frameWindow.barRoot.frameInset - i * 2,
          Math.max(0, topRadius - i), Math.max(0, frameCornerRadius - i))
        ctx.stroke()
        if (frameWindow.barRoot.integratedTopDockSurface) ctx.restore()
      }
      ctx.restore()
      // Notch's own shadow used to live here too (a hand-rolled Canvas
      // ring system, ported from ruixen.notch's own now-abandoned
      // version) -- direct live correction after it kept getting the
      // curve/radius wrong every tuning pass: "cant the notch edges
      // just produce its own shadow?" Moved to a real blur effect on a
      // plain, unmasked duplicate of the notch's own shape instead
      // (ruixen.notch/Overlay.qml's own notchShadowBlur) -- guaranteed
      // to match the true silhouette since it directly reuses that
      // geometry, no hand-derived arc math to get wrong. This canvas
      // keeps its own hole-punch (frameCanvas above) since that part
      // was correct; only the shadow moved back.
    }
  }

  // Frame-owned dock skin. BarPanel still owns widget layout/content and
  // publishes the measured left/right extents, but the visual surface now
  // lives beside the frame so dock corners and frame corners share one
  // layer-surface coordinate space.
  Item {
    id: dockChrome
    visible: frameWindow.barRoot.docked && frameWindow.barRoot.position === "top" && frameWindow.dockChromeMetrics.screenWidth > 0
    x: frameWindow.barRoot.frameInset - frameWindow.barRoot.seamOverlap
    y: frameWindow.barRoot.frameInset
    width: frameWindow.dockChromeMetrics.screenWidth + frameWindow.barRoot.seamOverlap * 2
    height: frameWindow.barRoot.barSize + frameWindow.barRoot.shoulderWingSize
    readonly property int leftWidth: frameWindow.dockChromeMetrics.leftWidth + dockChrome.overlap
    readonly property int rightX: frameWindow.dockChromeMetrics.rightX + dockChrome.overlap
    readonly property int rightWidth: frameWindow.dockChromeMetrics.rightWidth
    readonly property int overlap: frameWindow.barRoot.seamOverlap

    function dockPath(ctx, dockColor, hemColor) {
      var frameHemColor = hemColor || dockColor
      var r = frameWindow.barRoot.shoulderWingSize
      function wingPath(x, y, corner) {
        var centerX = corner === "topLeft" || corner === "bottomLeft" ? x + r : x
        var centerY = corner === "topLeft" || corner === "topRight" ? y + r : y
        var start = corner === "topLeft" ? Math.PI
          : corner === "topRight" ? 1.5 * Math.PI
          : corner === "bottomRight" ? 0
          : 0.5 * Math.PI
        var end = corner === "topLeft" ? 1.5 * Math.PI
          : corner === "topRight" ? 2 * Math.PI
          : corner === "bottomRight" ? 0.5 * Math.PI
          : Math.PI
        var pointX = corner === "topLeft" || corner === "bottomLeft" ? x : x + r
        var pointY = corner === "topLeft" || corner === "topRight" ? y : y + r
        ctx.moveTo(pointX, pointY)
        ctx.arc(centerX, centerY, r, start, end)
        ctx.lineTo(pointX, pointY)
        ctx.closePath()
      }

      ctx.beginPath()
      var y0 = -dockChrome.overlap
      var y1 = frameWindow.barRoot.barSize + dockChrome.overlap
      var x0 = -dockChrome.overlap
      var leftEnd = frameWindow.barRoot.dockedSkin.dockSpansFullWidth ? dockChrome.width + dockChrome.overlap : dockChrome.leftWidth
      ctx.moveTo(x0, y0)
      ctx.lineTo(frameWindow.barRoot.dockedSkin.dockSpansFullWidth ? leftEnd : leftEnd, y0)
      if (!frameWindow.barRoot.dockedSkin.dockSpansFullWidth) {
        ctx.lineTo(leftEnd + r, y0)
        ctx.arc(leftEnd + r, y0 + r, r, 1.5 * Math.PI, Math.PI, true)
        ctx.lineTo(leftEnd, y1 - r)
        ctx.quadraticCurveTo(leftEnd, y1, leftEnd - r, y1)
      } else {
        ctx.lineTo(leftEnd, y1)
      }
      ctx.lineTo(x0, y1)
      ctx.closePath()

      if (!frameWindow.barRoot.dockedSkin.dockSpansFullWidth) {
        var rightStart = dockChrome.rightX
        var rightEnd = dockChrome.rightX + dockChrome.rightWidth + dockChrome.overlap
        ctx.moveTo(rightEnd, y0)
        ctx.lineTo(rightStart - r, y0)
        ctx.arc(rightStart - r, y0 + r, r, 1.5 * Math.PI, 0, false)
        ctx.lineTo(rightStart, y1 - r)
        ctx.quadraticCurveTo(rightStart, y1, rightStart + r, y1)
        ctx.lineTo(rightEnd, y1)
        ctx.closePath()
      }
      ctx.fillStyle = dockColor
      ctx.fill()

      ctx.beginPath()
      wingPath(0, frameWindow.barRoot.barSize, "topLeft")
      if (!frameWindow.barRoot.dockedSkin.dockSpansFullWidth)
        wingPath(dockChrome.rightX + dockChrome.rightWidth - r, frameWindow.barRoot.barSize, "topRight")
      ctx.fillStyle = frameHemColor
      ctx.fill()
    }

    Canvas {
      id: dockChromeShadowCanvas
      visible: true
      anchors.fill: parent
      // Was visible: false outright -- ruixen-shell#89's own follow-up,
      // direct request: "i so wish we can add dropshadow to the dock
      // mode so it continues from the frame". tests/chrome-surface-
      // refactor.sh's own name for the old pinned state said why it was
      // off: "disables frame-touching dock shadow". Confirmed live
      // exactly what that meant before touching anything further: with
      // symmetric -40 margins on every side (room for the blur to
      // spread outward), the TOP side has nowhere real to spread into
      // when docked at the top -- the dock's own top edge already sits
      // right at the literal screen edge, so that "outward" blur
      // immediately hits the window's own bounds and gets truncated,
      // collapsing into a dark smudge sitting right on top of the
      // frame's own clean 6px border strip (frameInset) instead of
      // fading into open wallpaper the way the bottom/side shadows do.
      // A first pass just zeroed the top margin (no canvas room above
      // the dock's own real edge) -- measurably softer live, but still
      // visibly darkened that same 6px strip, since the shadow's own
      // silhouette edge sits at that same real y=0 and blur is darkest
      // right next to its own source regardless of how much room it
      // has to fade into.
      //
      // Real fix: shrink the canvas's own top edge down PAST the
      // border entirely, to frameInset (6px) instead of 0 -- the exact
      // depth of the frame's own clean border strip (frameCanvas's own
      // holeY above). Below that line, dockChromeFillCanvas's own
      // OPAQUE frameColor fill (declared after this canvas, so it
      // paints on top) already fully covers this shadow regardless of
      // how dark it is -- an opaque layer on top always wins. Above
      // that line is exactly, and only, the strip that ISN'T covered by
      // anything opaque, so that's the one region this shadow actually
      // needs to stay out of.
      //
      // Direct live follow-up right after: "on the top and straight
      // side of the dock edge, it seems like its bleeding some shadow
      // into it, its doesnt look connected to frame anymore" -- the
      // left/right vertical sides have the exact same problem the top
      // did, for the exact same reason: leftDockedBg/rightDockedBg
      // (BarPanel's own dock-fill rectangles this frame surface
      // mirrors) both run flush to the true screen edge (x: 0 on the
      // left, parent.width on the right -- see their own comments),
      // same as the top ran flush to y: 0, so the same -40 margin had
      // nowhere real to spread into on those two sides either. Same
      // fix, same frameInset depth, same condition -- dockChrome's own
      // parent Item (above) is already gated to exactly
      // integratedTopDockSurface's own condition (docked && position
      // === "top"), so every side of this canvas only ever needs to
      // choose between "open wallpaper, keep the -40 room" and "a real
      // screen edge, clip to frameInset" under that one state anyway.
      // Bottom is untouched -- the dock's own bottom edge is never
      // flush against any screen edge, it always has real open
      // wallpaper below it to shadow onto.
      anchors.leftMargin: frameWindow.barRoot.integratedTopDockSurface ? frameWindow.barRoot.frameInset : -40
      anchors.rightMargin: frameWindow.barRoot.integratedTopDockSurface ? frameWindow.barRoot.frameInset : -40
      anchors.bottomMargin: -40
      anchors.topMargin: frameWindow.barRoot.integratedTopDockSurface ? frameWindow.barRoot.frameInset : -40
      antialiasing: true
      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.save()
        ctx.translate(
          frameWindow.barRoot.integratedTopDockSurface ? -frameWindow.barRoot.frameInset : 40,
          frameWindow.barRoot.integratedTopDockSurface ? -frameWindow.barRoot.frameInset : 40
        )
        dockChrome.dockPath(ctx, frameWindow.barRoot.surfaceShadow)
        ctx.restore()
      }
      // target: frameWindow's own dockChromeMetrics property, not
      // dockChrome's own derived leftWidth/rightX/rightWidth ints --
      // direct live report of a real bug this masked: as more pinned
      // widgets/launcher icons grew the bar's own content, "the dock
      // size isnt like moving or getting larger anymore, its like
      // static bar", overflowing content onto bare wallpaper past the
      // chrome's own edge. Root cause, found with a live debug trace:
      // the per-property Connections below (onLeftWidthChanged etc.)
      // only ever fired ONCE, for the initial visible:false->true
      // transition -- every metrics update afterward (confirmed via
      // the same trace to be reaching frameWindow.dockChromeMetrics
      // correctly, settling on the real, grown width) never triggered
      // a single further repaint. dockChromeMetricsChanged is the one
      // signal already proven reliable (by the same trace) across
      // every single update, not just the first -- binding repaint
      // directly to it removes whatever reactivity gap existed in the
      // extra layer of derived int properties in between. Still
      // `target: frameWindow` (not barRoot) after this file's own
      // extraction -- frameWindow is this file's own root id, still in
      // the same document, so this specific binding was never at risk
      // from the extraction the way root.* reads were.
      Connections {
        target: frameWindow
        function onDockChromeMetricsChanged() { dockChromeShadowCanvas.requestPaint() }
      }
      Connections {
        target: frameWindow.barRoot
        function onDockedChanged() { dockChromeShadowCanvas.requestPaint() }
        function onFullbarStyleChanged() { dockChromeShadowCanvas.requestPaint() }
        function onDockedBarColorChanged() { dockChromeShadowCanvas.requestPaint() }
      }
      layer.enabled: true
      layer.effect: MultiEffect {
        blurEnabled: true
        blurMax: 32
        blur: 0.72
      }
    }

    Canvas {
      id: dockChromeFillCanvas
      anchors.fill: parent
      antialiasing: true
      onPaint: {
        var ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        dockChrome.dockPath(ctx, frameWindow.barRoot.frameColor, frameWindow.barRoot.frameColor)
      }
      // Mirrors dockChromeShadowCanvas's own Connections -- see its
      // comment for the real bug this fixes.
      Connections {
        target: frameWindow
        function onDockChromeMetricsChanged() { dockChromeFillCanvas.requestPaint() }
      }
      Connections {
        target: frameWindow.barRoot
        function onDockedChanged() { dockChromeFillCanvas.requestPaint() }
        function onFullbarStyleChanged() { dockChromeFillCanvas.requestPaint() }
        function onDockedBarColorChanged() { dockChromeFillCanvas.requestPaint() }
      }
    }
  }
}
