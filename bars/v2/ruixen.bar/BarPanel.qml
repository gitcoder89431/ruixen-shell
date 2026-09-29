import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import qs.Commons
import qs.Ui

// The real bar content window -- margins/anchors/exclusiveZone math,
// tooltip popup, and the entire horizontal/vertical pill layout. See
// FrameWindow.qml's own header comment for why this is a separate
// window from the screen-border frame (exclusiveZone/popup-positioning
// history), and AGENTS.md's own coupled-surfaces section for how this
// window's docked-mode chrome relates to FrameWindow's own.
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 7, the last and
// heaviest stage) as a pure file move: this was previously
// `component BarPanel: PanelWindow { ... }` declared inline inside
// Bar.qml's own `Item { id: root }`. barRoot is the explicit
// back-reference every `root.foo` read was rewritten to go through
// (barWindow.barRoot.foo, using this window's own existing `id:
// barWindow`), wired at this component's one instantiation site
// (Bar.qml's own Variants block, `barRoot: root`). Every nested
// GroupPill/RoundCorner/ModuleList/ModuleSlot/CenterModules/
// LeftModules/RightModules instantiation below forwards
// `barRoot: barWindow.barRoot` -- a two-hop change from the
// `barRoot: root` those call sites had before this stage, back when
// BarPanel itself was still nested in the same document as root. No
// behavior change from this move; only how nested state is reached.
PanelWindow {
  id: barWindow

  required property Item barRoot

  // Back to a real small window (v1's own anchors/margins, byte-for-
  // byte) -- NOT fullscreen anymore. Two things forced this back:
  // exclusiveZone has no well-defined meaning on a surface anchored to
  // all four edges (direct live report at 1.25x scale: real windows
  // rendered UNDER the bar), and every stock Omarchy popup on this bar
  // reads THIS window's real height for its own position (direct live
  // report: popups clamped to the bottom of the screen, tiny, once
  // this window's real height became the whole screen instead of the
  // bar's own strip). Both need this window's real size to be the
  // bar's own small footprint again, no way around it.
  //
  // What's DIFFERENT from v1, and still the actual fix: FrameWindow
  // above is one single Canvas covering the whole screen, not two
  // independently-hardcoded plugins each guessing the other's number.
  // The one remaining seam risk -- this window's own edge meeting
  // FrameWindow's edge in docked mode -- is handled by
  // leftFrameHemWing/rightFrameHemWing below (renamed from this
  // comment's own original "dockedSeamCover" at some point -- if you're
  // grepping for that name and finding nothing, this is why): a plain
  // frameColor-filled RoundCorner, deliberately painted a few pixels
  // WIDER than the gap it's covering, sitting on a higher layer than
  // FrameWindow. Two independent surfaces can still round
  // their own edges to slightly different physical pixels under a
  // fractional scale -- that was never fixable by trying harder to
  // agree on a shared number, only by making it not matter. A few
  // pixels of deliberate overlap, painted the same color as the thing
  // underneath, absorbs that disagreement completely: whichever
  // physical pixel FrameWindow's own edge actually lands on, it's
  // already covered by this window's own matching-color paint before
  // it could ever show through as a wallpaper sliver.
  visible: !remapGuard.remapping
  exclusionMode: barWindow.barRoot.barHidden ? ExclusionMode.Ignore : ExclusionMode.Normal
  // + seamOverlap, top position only -- margin.top below only gives up
  // those pixels when position === "top" (see its own comment), so
  // this only needs to pick them back up in that same case. Total
  // real-window reservation (margin.top + exclusiveZone) stays the
  // true v1 value (44) either way -- direct live report, again: the
  // first pass at this overlap trick forgot this compensation and the
  // reserved gap came out seamOverlap px too shallow, same class of
  // miss as the ReservationPanel one before it.
  exclusiveZone: barWindow.barRoot.docked
    ? (44 - barWindow.barRoot.frameInset + (barWindow.barRoot.position === "top" ? barWindow.barRoot.seamOverlap : 0))
    : barWindow.barRoot.notchClearance

  ScreenMoveRemap {
    id: remapGuard
    window: barWindow
  }

  margins {
    top: barWindow.barRoot.barHidden && barWindow.barRoot.position === "top" ? -barWindow.barRoot.barSize : (barWindow.barRoot.position === "top" ? barWindow.barRoot.contentTopInset - (barWindow.barRoot.docked ? barWindow.barRoot.seamOverlap : 0) : 0)
    bottom: barWindow.barRoot.barHidden && barWindow.barRoot.position === "bottom" ? -barWindow.barRoot.barSize : 0
    // - (docked ? seamOverlap : 0), same reasoning/same constant as
    // margins.top just above: docked mode's leftDockedBg/leftFrameHemWing
    // (and their right-side mirrors) paint flush against this window's
    // own left/right edge specifically to visually merge with
    // FrameWindow's own rounded corner there (see their own comments,
    // "growing out of the frame") -- the exact same cross-surface
    // rounding risk as the top seam, just on a different axis. Direct
    // live report on another machine only (never reproduced on this
    // dev machine, matching how the original top-seam bug only showed
    // up under a fractional Hyprland scale this machine doesn't use):
    // a hairline gap between the left wing and the real frame border in
    // docked mode. No exclusiveZone compensation needed here unlike
    // margins.top's own -- a horizontal top bar's exclusiveZone reserves
    // vertical space only, left/right margins are pure positioning, not
    // reservation.
    left: barWindow.barRoot.barHidden && barWindow.barRoot.position === "left" ? -barWindow.barRoot.barSize : (barWindow.barRoot.position === "top" ? barWindow.barRoot.frameInset - (barWindow.barRoot.docked ? barWindow.barRoot.seamOverlap : 0) : 0)
    right: barWindow.barRoot.barHidden && barWindow.barRoot.position === "right" ? -barWindow.barRoot.barSize : (barWindow.barRoot.position === "top" ? barWindow.barRoot.frameInset - (barWindow.barRoot.docked ? barWindow.barRoot.seamOverlap : 0) : 0)
  }

  anchors {
    top: barWindow.barRoot.position === "top" || barWindow.barRoot.vertical
    bottom: barWindow.barRoot.position === "bottom" || barWindow.barRoot.vertical
    left: barWindow.barRoot.position === "left" || !barWindow.barRoot.vertical
    right: barWindow.barRoot.position === "right" || !barWindow.barRoot.vertical
  }

  implicitWidth: barWindow.barRoot.vertical ? barWindow.barRoot.barSize : 0

  // Clears the Notch's own collapsed bottom edge (notchCollapsedBottomEdge,
  // from ruixen.notch's own service) -- direct live report: any popup
  // panel anchored off this window (weather's own, and stock Omarchy's
  // clock/agents popups -- all use qs.Ui's KeyboardPanel) opens at
  // `anchorWindow.height + gap` (KeyboardPanel.qml's own cardOrigin, not
  // editable -- it's a stock /usr/share/omarchy file), which had no
  // notion of ruixen.notch and let a popup open right underneath it.
  readonly property int floatingVisibleBarHeight: Math.max(barWindow.barRoot.barSize, barWindow.barRoot.notchCollapsedBottomEdge)
  readonly property int dockedVisibleBarHeight: Math.max(barWindow.barRoot.barSize + barWindow.barRoot.shoulderWingSize, barWindow.barRoot.notchCollapsedBottomEdge)
  readonly property int visibleBarHeight: barWindow.barRoot.vertical ? barWindow.barRoot.barSize : (barWindow.barRoot.docked ? dockedVisibleBarHeight : floatingVisibleBarHeight)
  // + seamOverlap -- this window's own top edge moved up by seamOverlap
  // (margins.top above), so its own height needs to grow by the same
  // amount to keep the BOTTOM edge (and thus anchorWindow.height/
  // visibleBarHeight-dependent popup math, and the real content below)
  // exactly where v1 always had it. contentOffset below is what keeps
  // the actual pill row's own on-screen position unchanged despite the
  // window itself now starting seamOverlap px higher.
  implicitHeight: barWindow.barRoot.vertical ? 0 : visibleBarHeight + barWindow.barRoot.seamOverlap

  color: "transparent"
  surfaceFormat.opaque: false
  WlrLayershell.namespace: "omarchy-bar"
  // Above FrameWindow (Bottom) -- needed for the seam-cover Rectangle
  // below to actually be capable of covering FrameWindow's own edge.
  WlrLayershell.layer: WlrLayer.Top

  // The actual seam-covering paint -- see this component's own comment
  // above for the full mechanism. Only present in docked+top (the only
  // configuration where this window's own edge is meant to visually
  // merge with FrameWindow's rounded corner at all; floating pills
  // stay clear of the frame with a real gap, no seam risk there).
  //
  // A THIN band at the top only, not anchors.fill: parent -- direct
  // live report: filling this window's own full height painted the
  // WHOLE bar strip solid, including the real overflow room below the
  // pill row (popup-clearance/hem-wing space, this window's own
  // implicitHeight is deliberately taller than the actual reserved
  // exclusiveZone -- see visibleBarHeight's own comment). That overflow
  // band is supposed to stay transparent, same as v1 always had it
  // ("almost entirely transparent") -- painting it solid turned it
  // into a real, visible black block sitting on top of wherever a
  // tiled window is supposed to start.
  //
  // height, corrected: a second direct live report ("i definitely
  // notice a difference, just cant pinpoint what") turned out to be
  // this -- barWindow.barRoot.frameInset + barWindow.barRoot.seamOverlap (9) double-counted
  // frameInset. This window's own top (BarPanel-local y=0) is ALREADY
  // at screen y = barWindow.barRoot.contentTopInset - barWindow.barRoot.seamOverlap, which for
  // docked mode (contentTopInset === frameInset) is frameInset -
  // seamOverlap = 3, not 0 -- the seam-cover only needs to reach a
  // little PAST FrameWindow's real edge (screen y = frameInset) from
  // THAT starting point, i.e. seamOverlap px plus a couple more for
  // safety margin, not frameInset's own full value added on top again.
  // The old (wrong) height of 9 made the real visible top border
  // roughly twice as thick on screen (~12px) as v1's own plain 6px --
  // exactly the "something's different, can't place it" report.
  //
  // +1, not +2 -- the only real uncertainty this buffer needs to cover
  // is BarPanel's OWN margin.top possibly rounding to a physical pixel
  // slightly different from intended (the same class of cross-surface
  // rounding this whole v2 effort exists to route around). FrameWindow's
  // own edge is a fixed integer value rendered with antialiasing:false
  // in a single Canvas pass, not independently uncertain on its own --
  // there's nothing on that side for a bigger buffer to protect against.
  // A 1px margin is already more than that rounding could plausibly
  // need, measured live: this puts the real on-screen border at 7px
  // total (was 6 in v1, was a broken ~12-13 before this fix) --
  // negligible rather than "definitely something different".
  Rectangle {
    visible: barWindow.barRoot.docked && barWindow.barRoot.position === "top" && !barWindow.barRoot.frameOwnsDockChrome
    anchors { top: parent.top; left: parent.left; right: parent.right }
    height: barWindow.barRoot.seamOverlap + 1
    color: barWindow.barRoot.frameColor
  }

  // Mirrors the top seam-cover immediately above, for margins.left/
  // right's own identical overlap reduction just above THAT. Full
  // window height (not a thin band like the top cover) is deliberate,
  // not an oversight -- unlike the top cover, which had to avoid
  // painting over the transparent popup-clearance area below the pill
  // row, this sliver never overlaps that area horizontally at all: it
  // only occupies the seamOverlap-px-wide strip contentOffset's own
  // leftMargin/rightMargin (below) pushes the real content clear of, so
  // there's nothing real underneath it to hide -- just true screen
  // pixels that already show FrameWindow's own continuing border there
  // regardless, same color, at every height.
  Rectangle {
    visible: barWindow.barRoot.docked && barWindow.barRoot.position === "top" && !barWindow.barRoot.frameOwnsDockChrome
    anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
    width: barWindow.barRoot.seamOverlap + 1
    color: barWindow.barRoot.frameColor
  }
  Rectangle {
    visible: barWindow.barRoot.docked && barWindow.barRoot.position === "top" && !barWindow.barRoot.frameOwnsDockChrome
    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
    width: barWindow.barRoot.seamOverlap + 1
    color: barWindow.barRoot.frameColor
  }

  // Keeps the real content (the Loader, and everything inside it) at
  // EXACTLY the same on-screen position it always had, despite this
  // window's own top edge now starting seamOverlap px higher for the
  // insurance-overlap trick above -- without this, the whole pill row
  // would visibly shift up by seamOverlap too, since horizontalBar's
  // own Item positions everything relative to its own (0,0), which is
  // this window's own top-left corner.
  Item {
    id: contentOffset
    anchors.fill: parent
    anchors.topMargin: (!barWindow.barRoot.vertical && barWindow.barRoot.docked && barWindow.barRoot.position === "top") ? barWindow.barRoot.seamOverlap : 0
    // Mirrors topMargin above, for margins.left/right's own matching
    // overlap reduction -- without this, leftDockedBg/leftShoulderWing/
    // leftFrameHemWing (all positioned off this Item's own x: 0) would
    // visibly shift outward by seamOverlap, past where they're meant to
    // flush against the frame's real rounded corner, into the newly-
    // reclaimed sliver the seam-cover strips above now own instead.
    anchors.leftMargin: (!barWindow.barRoot.vertical && barWindow.barRoot.docked && barWindow.barRoot.position === "top") ? barWindow.barRoot.seamOverlap : 0
    anchors.rightMargin: (!barWindow.barRoot.vertical && barWindow.barRoot.docked && barWindow.barRoot.position === "top") ? barWindow.barRoot.seamOverlap : 0

    Loader {
      anchors.fill: parent
      sourceComponent: barWindow.barRoot.vertical ? verticalBar : horizontalBar

      // A child of the loader, not a sibling of the sections: an ancestor stays
      // hovered while the pointer is over a widget, where a sibling would lose
      // hover to the section the pointer entered.
      HoverHandler {
        onHoveredChanged: barWindow.barRoot.setBarHovered(hovered)
        // Unplugging a monitor destroys its bar without a leave event, which
        // would strand this surface's tally and hold the peek open for good.
        Component.onDestruction: if (hovered) barWindow.barRoot.setBarHovered(false)
      }
    }
  }

  PopupWindow {
    id: tooltipWindow

    visible: barWindow.barRoot.tooltipShown && barWindow.barRoot.tooltipTarget !== null && barWindow.barRoot.tooltipText !== "" && barWindow.barRoot.targetBelongsToWindow(barWindow.barRoot.tooltipTarget, barWindow)
    color: "transparent"
    implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
    implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

    anchor {
      id: tooltipAnchor
      window: barWindow
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: Edges.Bottom | Edges.Right
      rect.width: 1
      rect.height: 1

      onAnchoring: {
        var target = barWindow.barRoot.tooltipTarget
        if (!barWindow.barRoot.targetBelongsToWindow(target, barWindow)) return

        var popupWidth = tooltipWindow.implicitWidth
        var popupHeight = tooltipWindow.implicitHeight
        var localX = target.width / 2 - popupWidth / 2
        var localY = target.height + 6

        if (barWindow.barRoot.position === "bottom") {
          localY = -popupHeight - 6
        } else if (barWindow.barRoot.position === "left") {
          localX = target.width + 6
          localY = target.height / 2 - popupHeight / 2
        } else if (barWindow.barRoot.position === "right") {
          localX = -popupWidth - 6
          localY = target.height / 2 - popupHeight / 2
        }

        var point = barWindow.contentItem.mapFromItem(target, localX, localY)
        tooltipAnchor.rect.x = Math.round(point.x)
        tooltipAnchor.rect.y = Math.round(point.y)
      }
    }

    BorderSurface {
      id: tooltipBubble
      implicitWidth: tooltipLabel.implicitWidth + 20
      implicitHeight: tooltipLabel.implicitHeight + 14
      color: Color.tooltip.background
      borderSpec: Border.surfaceSpec("tooltip", "border", Color.tooltip.border, 1)
      radius: Style.cornerRadius

      Text {
        id: tooltipLabel
        anchors.centerIn: parent
        text: barWindow.barRoot.tooltipText
        color: Color.tooltip.text
        font.family: barWindow.barRoot.fontFamily
        font.pixelSize: Style.font.body
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }
  }

  Component {
    id: horizontalBar

    Item {
      id: horizontalBarRoot
      anchors.fill: parent
      onWidthChanged: publishDockChromeMetrics()
      onHeightChanged: publishDockChromeMetrics()
      Component.onCompleted: Qt.callLater(publishDockChromeMetrics)
      // settleTimer is parented to this Item and torn down along with
      // it normally, but a live shell.json reload (pinning/unpinning a
      // widget, not a restart) destroys and rebuilds this whole Item,
      // and a Timer mid-flight at that exact moment can still fire its
      // onTriggered a beat into the teardown, calling back into an
      // object whose QML context is already gone -- confirmed live
      // (rapid-fire repeated edits): "QQmlVMEMetaObject: Internal
      // error - attempted to evaluate a function in an invalid
      // context", over and over, taking the whole bar down. Explicitly
      // stopping it here closes that window -- Component.onDestruction
      // runs before teardown actually happens, so this always wins the
      // race against the timer's own onTriggered.
      Component.onDestruction: settleTimer.stop()

      function currentDockChromeMetrics() {
        return {
          screenWidth: horizontalBarRoot.width,
          barHeight: barWindow.barRoot.barSize,
          leftWidth: settingsPill.x + settingsPill.width,
          rightX: rightDockedBg.x,
          rightWidth: horizontalBarRoot.width - rightDockedBg.x
        }
      }

      function publishDockChromeMetricsNow() {
        if (!barWindow.barRoot.docked || barWindow.barRoot.position !== "top") return
        barWindow.barRoot.publishDockChromeMetrics(barWindow.barRoot.screenNameForWindow(barWindow), horizontalBarRoot.currentDockChromeMetrics())
      }

      // Safety net for a real live-reload race, root-caused with a
      // debug trace: settingsPill/rightDockedBg's own onXChanged/
      // onWidthChanged handlers (below) DO fire and DO call this
      // function correctly on every layout change -- but if a newly-
      // added widget's own icon/content finishes loading and resizing
      // slightly AFTER the last of those signals fires (an async
      // image/glyph load, or the next Repeater delta landing a beat
      // later), nothing re-measures after that: the chrome silently
      // freezes one step short of the real final width, exactly
      // matching the direct live report ("as i add more stuff to the
      // pin plugin... the dock size isnt like moving or getting larger
      // anymore"). Re-checking once, a beat after the last width-
      // changing signal, catches that gap without needing to chase
      // down every possible async widget content source individually.
      // settleTimer.restart() (not start()) makes this a debounce -- a
      // burst of changes during layout settling collapses to exactly
      // one recheck, not one per signal.
      property Timer settleTimer: Timer {
        interval: 250
        onTriggered: horizontalBarRoot.publishDockChromeMetricsNow()
      }

      function publishDockChromeMetrics() {
        horizontalBarRoot.publishDockChromeMetricsNow()
        horizontalBarRoot.settleTimer.restart()
      }

      // Docked mode: the left group (menuPill/workspacesPill/
      // settingsPill) and right group (trayPill/pluginPinsPill/
      // curatedPill/clockPill) merge into one
      // continuous shape each, flush with
      // ruixen.frame-widget's own rounded corner instead of floating
      // inset from it -- "growing out of the frame" the same way
      // ruixen.notch grows out of the top edge, just one shoulder per
      // side instead of the notch's two (see ruixen.notch/Overlay.qml's
      // own bottomLeftRadius/bottomRightRadius treatment -- same simple
      // per-corner-radius technique, not a custom Shape/Canvas). Declared
      // first (behind every pill below) since they're all siblings, not
      // nested -- QML paints siblings in document order.
      //
      // Positioned/sized off the existing pills' own x/width rather than
      // duplicating their layout math: settingsPill.x + settingsPill.width
      // is wherever the left group actually ends (0 width when
      // settingsPill's empty, same as its own fade-out), and
      // parent.width - trayPill.x is the mirror for the right group.
      //
      // leftShoulderShadowClip/rightShoulderShadowClip: hidden, solid-
      // black duplicates of ALL THREE real pieces per side (DockedBg +
      // ShoulderWing + FrameHemWing), shadowed and clipped, sitting
      // behind the real pieces. First tried excluding FrameHemWing
      // from the duplicate entirely, reasoning "it touches the frame,
      // so it shouldn't shadow" -- wrong: FrameHemWing has ONE edge
      // touching the frame (its straight left edge, x:0) but its own
      // CURVE faces the open window content below, exactly like
      // ShoulderWing's curve does, and that curve legitimately wants a
      // shadow. Direct live correction: "you took out the correct
      // shadow between the lower dock filler curve and the window
      // instead, now it looks missing." The excluded-PIECE model was
      // wrong; what actually matters is excluded-DIRECTION -- which
      // the clip below already does correctly on its own (trimming
      // anything past the true screen top/left edge) as long as the
      // full, real 3-piece shape is what's being clipped, not a
      // partial stand-in for it. Duplicating the full shape also
      // removes the earlier seam artifact where a shadowed DockedBg
      // bottom edge sat directly above an unshadowed FrameHemWing --
      // this was seen live as a stray triangular patch right at that
      // hand-off ("the triangle corner is still there between frame
      // and the dock filler").
      //
      // A hidden duplicate (not shadowEnabled directly on the real
      // pieces, unlike GroupPill) is what makes excluding the frame-
      // touching DIRECTIONS possible without also clipping the real,
      // visible fill -- exactly ruixen.notch/Overlay.qml's own
      // notchShadowClip technique, just with two frame-touching sides
      // to flatten instead of one: each clip is flush (no margin) on
      // its own corner's two frame-touching sides (top+left for the
      // left cluster, top+right for the right one) and expanded -40 on
      // the two open sides, so shadow can't render past the frame-
      // touching edges but still shows fully everywhere else. Geometry
      // bound directly to the real pieces' own properties, not re-
      // derived, so it can never drift out of sync with them.
      //
      // leftShoulderShadowClip's own flush corner (top-left) happens to
      // coincide with this whole Item's own (0,0) origin, so the real
      // pieces' x/y bind straight through with no compensation needed.
      // rightShoulderShadowClip does NOT have that luxury (see its own
      // comment below) -- expanding its clip LEFTWARD while staying
      // flush on the RIGHT necessarily shifts ITS OWN local origin away
      // from this Item's origin, and forgetting that shift the first
      // time around left the right cluster's whole duplicate rendered
      // 40px too far left -- its own solid, un-blurred core spilling out
      // past the real (correctly-positioned) content instead of staying
      // hidden under it. Direct live report: "the right side of the
      // dock has like black sticking out from the curve's wing, looks
      // like an extended shadow or just something else entirely
      // layering there as pure black."
      Item {
        id: leftShoulderShadowClip
        visible: !barWindow.barRoot.frameOwnsDockChrome
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.rightMargin: -40
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -40
        clip: true

        Item {
          anchors.fill: parent
          // opacity/blurMax/blur: byte-for-byte the same recipe as
          // ruixen.notch/Overlay.qml's own notchShadowBlur -- direct
          // live correction after this used GroupPill's own tighter
          // pill-lift shadow instead (shadowEnabled/shadowBlur:0.15/
          // shadowVerticalOffset), copied for convenience (also mask-
          // safe) rather than actually matched to what frame/notch
          // already agreed on: "why does it need to be different at
          // all? why cant they act as one continuous shadow?" It
          // didn't need to be -- a plain blur, not a directional
          // shadowEnabled effect, is what the notch's own reach/
          // softness comes from; no shadowVerticalOffset either, so
          // it doesn't bias toward one edge the way a pill-lift shadow
          // deliberately does.
          opacity: 1.0

          Rectangle {
            x: leftDockedBg.x
            y: leftDockedBg.y
            width: leftDockedBg.width
            height: leftDockedBg.height
            visible: leftDockedBg.visible
            topLeftRadius: leftDockedBg.topLeftRadius
            topRightRadius: leftDockedBg.topRightRadius
            bottomLeftRadius: leftDockedBg.bottomLeftRadius
            bottomRightRadius: leftDockedBg.bottomRightRadius
            color: "#000000"
          }

          RoundCorner {
            x: leftShoulderWing.x
            y: leftShoulderWing.y
            corner: leftShoulderWing.corner
            size: leftShoulderWing.size
            visible: leftShoulderWing.visible
            color: "#000000"
          }

          RoundCorner {
            x: leftFrameHemWing.x
            y: leftFrameHemWing.y
            corner: leftFrameHemWing.corner
            size: leftFrameHemWing.size
            visible: leftFrameHemWing.visible
            color: "#000000"
          }

          layer.enabled: true
          layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: 0.6
          }
        }
      }

      // Mirrors leftShoulderShadowClip -- see its comment. Flush
      // top+right (rightDockedBg's own corner touches the frame there
      // instead of on the left), expanded left+bottom.
      //
      // Expanding LEFTWARD while staying flush-right unavoidably moves
      // THIS ITEM'S OWN x to (parent.x - 40) -- x = right edge - width,
      // and a wider box with a fixed right edge must start further
      // left. The inner Item below inherits that same shifted origin
      // via anchors.fill, so a child placed at a real piece's own x
      // (e.g. rightDockedBg.x, expressed in the outer, UNshifted
      // horizontalBar coordinate frame) would land 40px further left
      // on screen than the real piece actually is. Subtracting this
      // Item's own x (itself expressed in that same outer frame, as a
      // sibling of rightDockedBg) cancels exactly that shift, however
      // large the margin actually is -- not a hardcoded "+40".
      Item {
        id: rightShoulderShadowClip
        visible: !barWindow.barRoot.frameOwnsDockChrome
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.left: parent.left
        anchors.leftMargin: -40
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -40
        clip: true

        Item {
          anchors.fill: parent
          // Mirrors leftShoulderShadowClip's own inner Item -- see its
          // comment (same notchShadowBlur recipe, not GroupPill's).
          opacity: 1.0

          Rectangle {
            x: rightDockedBg.x - rightShoulderShadowClip.x
            y: rightDockedBg.y
            width: rightDockedBg.width
            height: rightDockedBg.height
            visible: rightDockedBg.visible
            topLeftRadius: rightDockedBg.topLeftRadius
            topRightRadius: rightDockedBg.topRightRadius
            bottomLeftRadius: rightDockedBg.bottomLeftRadius
            bottomRightRadius: rightDockedBg.bottomRightRadius
            color: "#000000"
          }

          RoundCorner {
            x: rightShoulderWing.x - rightShoulderShadowClip.x
            y: rightShoulderWing.y
            corner: rightShoulderWing.corner
            size: rightShoulderWing.size
            visible: rightShoulderWing.visible
            color: "#000000"
          }

          RoundCorner {
            x: rightFrameHemWing.x - rightShoulderShadowClip.x
            y: rightFrameHemWing.y
            corner: rightFrameHemWing.corner
            size: rightFrameHemWing.size
            visible: rightFrameHemWing.visible
            color: "#000000"
          }

          layer.enabled: true
          layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: 0.6
          }
        }
      }

      // Grouping only, no shadow of its own -- see
      // leftShoulderShadowClip/rightShoulderShadowClip above for that.
      Item {
        id: dockedShoulderShadow
        visible: !barWindow.barRoot.frameOwnsDockChrome
        anchors.fill: parent

      // Square (no radius) corner fills sitting BEHIND leftDockedBg/
      // rightDockedBg's own rounded corners, exactly at the true
      // screen corner. Direct live report, tracked down with a red/
      // orange debug pass: a small dark wedge visible right at the
      // true top-left/top-right screen corner, between the docked
      // strip's own rounded curve and the corner itself -- ruixen.bar's
      // own frameShadowCanvas deliberately SQUARES OFF its top corners
      // in docked mode (topRadius: 0 above, see its own comment: "the
      // docked wing pieces already cover that exact corner"), but a
      // ROUNDED corner piece like leftDockedBg only covers the
      // INSCRIBED disk, not the full square bounding box -- it never
      // actually reaches into the small triangular sliver right at the
      // box's own sharp corner, which is exactly where the frame's own
      // squared-off shadow still paints. leftDockedBg's rounded shape
      // was never going to cover that sliver no matter how precisely
      // it's positioned; it needs a plain square patch behind it, sized
      // to the same radius, so nothing frame-shadow-colored is left
      // exposed there. Same "paint over the disagreement" philosophy as
      // BarPanel's own dockedSeamCover/HemWing pieces above, just for a
      // corner instead of an edge.
      Rectangle {
        visible: barWindow.barRoot.docked
        x: 0
        y: 0
        width: barWindow.barRoot.shoulderWingSize
        height: barWindow.barRoot.shoulderWingSize
        color: barWindow.barRoot.dockedBarColor
      }

      // Historical sharp+docked full-strip corner patch, revived behind
      // bar.style="fullbar" only. Curvature alone must not select it.
      Rectangle {
        visible: barWindow.barRoot.docked && barWindow.barRoot.dockedSkin.dockSpansFullWidth
        x: leftDockedBg.width - barWindow.barRoot.shoulderWingSize
        y: 0
        width: barWindow.barRoot.shoulderWingSize
        height: barWindow.barRoot.shoulderWingSize
        color: barWindow.barRoot.dockedBarColor
      }

      // Covers rightDockedBg's own top-right corner in the normal notch skin.
      // In fullbar mode leftDockedBg spans the whole surface and owns this
      // corner instead.
      Rectangle {
        visible: barWindow.barRoot.docked && !barWindow.barRoot.dockedSkin.dockSpansFullWidth
        x: parent.width - barWindow.barRoot.shoulderWingSize
        y: 0
        width: barWindow.barRoot.shoulderWingSize
        height: barWindow.barRoot.shoulderWingSize
        color: barWindow.barRoot.dockedBarColor
      }

      Rectangle {
        id: leftDockedBg
        visible: barWindow.barRoot.docked && !barWindow.barRoot.frameOwnsDockChrome
        x: 0
        y: 0
        onWidthChanged: horizontalBarRoot.publishDockChromeMetrics()
        // Normal notch skin: just the left group's own width. Fullbar skin:
        // stretch across the whole surface for the saved statusline strip.
        width: barWindow.barRoot.dockedSkin.dockSpansFullWidth ? parent.width : (settingsPill.x + settingsPill.width)
        // barWindow.barRoot.barSize, not parent.height -- parent (the outer Item,
        // sized to the whole window) is taller than the pill row when
        // docked, to make room for leftFrameHemWing below (renamed from
        // this comment's own original "leftFrameTaper" at some point).
        // This piece is just the pill row itself.
        height: barWindow.barRoot.barSize
        color: barWindow.barRoot.dockedBarColor
        antialiasing: true
        // Matches ruixen.frame-widget's own cornerRadius (24) exactly --
        // this corner sits at the same point the frame's rounded-rect
        // hole starts (see BarPanel's margins above: frameInset used for
        // top too when docked, not topInset, specifically so this lines
        // up).
        topLeftRadius: 24
        // In fullbar mode this is the true screen edge, so it gets the
        // same rounded frame-touching corner as topLeftRadius.
        topRightRadius: barWindow.barRoot.dockedSkin.dockSpansFullWidth ? barWindow.barRoot.shoulderWingSize : 0
        // Square, not a plain recede curve -- the actual concave wrap
        // (per direct request: "the smooth curve should face inward")
        // is leftFrameHemWing below, in its own dedicated space
        // (barWindow.barRoot.shoulderWingSize, added to BarPanel's implicitHeight
        // when docked). Squaring this off keeps it a flush, seamless
        // hand-off into that wing rather than competing with
        // topLeftRadius for room on the same 34px edge.
        bottomLeftRadius: 0
        // Normal notch skin hands off into leftShoulderWing. Fullbar has no
        // open-facing shoulder at the right edge, so keep its bottom flat.
        bottomRightRadius: barWindow.barRoot.dockedSkin.dockSpansFullWidth ? 0 : barWindow.barRoot.shoulderWingSize
      }

      // A small square sitting immediately past the body's own right
      // edge, corner: topLeft. Same size as leftDockedBg's own
      // bottomRightRadius above (24), not the full pill height -- a
      // shoulder wing needs to be a small square matched to its
      // body's own corner radius, not a full-height piece; that
      // mismatch was the earlier bug.
      RoundCorner {
        id: leftShoulderWing
        visible: barWindow.barRoot.docked && !barWindow.barRoot.frameOwnsDockChrome
        corner: "topLeft"
        size: barWindow.barRoot.shoulderWingSize
        color: barWindow.barRoot.dockedBarColor
        x: leftDockedBg.x + leftDockedBg.width
        y: 0
      }

      // The frame-hem corner's own wing -- concave, curving inward,
      // not the plain recede curve a Rectangle radius gives. Flush
      // against leftDockedBg's own square bottom edge at its own top
      // (y: leftDockedBg.height, no seam -- both are simply square
      // there) and flush against the true screen edge on its own left
      // (x: 0, matching ruixen.frame-widget's continuing border strip),
      // with the curve itself down at its far corner, closer to where
      // this hands off to frame's plain strip continuing further down.
      //
      // barWindow.barRoot.frameColor, NOT dockedBarColor -- this piece hosts no
      // icon content, its entire job is disappearing into FrameWindow's
      // own real border (BarPanel's own comment above: "a plain
      // frameColor-filled Rectangle... painted the same color as the
      // thing underneath... absorbs that disagreement completely").
      // dockedBarColor can differ from frameColor (it clamps to black
      // whenever frameColor itself reads too light, since leftDockedBg/
      // leftShoulderWing DO host icons) -- direct live report of
      // exactly that: "this black thing we added to cover up a
      // triangle gap... its currently possibly leaking through." Once
      // this wedge's own color no longer matches the frame's real
      // color underneath, the deliberate few-px overlap that's
      // supposed to be an invisible seam-fill instead shows up as its
      // own visibly wrong-colored triangle.
      RoundCorner {
        id: leftFrameHemWing
        visible: barWindow.barRoot.docked && !barWindow.barRoot.frameOwnsDockChrome
        corner: "topLeft"
        size: barWindow.barRoot.shoulderWingSize
        color: barWindow.barRoot.frameColor
        x: 0
        y: leftDockedBg.height
      }

      Rectangle {
        id: rightDockedBg
        visible: barWindow.barRoot.docked && !barWindow.barRoot.dockedSkin.dockSpansFullWidth && !barWindow.barRoot.frameOwnsDockChrome
        x: trayPill.x
        y: 0
        onXChanged: horizontalBarRoot.publishDockChromeMetrics()
        onWidthChanged: horizontalBarRoot.publishDockChromeMetrics()
        width: parent.width - trayPill.x
        height: barWindow.barRoot.barSize
        color: barWindow.barRoot.dockedBarColor
        antialiasing: true
        topRightRadius: 24
        topLeftRadius: 0
        // Mirrors leftDockedBg's own bottomLeftRadius -- see its comment.
        bottomRightRadius: 0
        // Mirrors leftDockedBg's own bottomRightRadius -- see its comment.
        bottomLeftRadius: barWindow.barRoot.shoulderWingSize
      }

      // Mirrors leftShoulderWing -- see its comment.
      //
      // x is 1px INTO rightDockedBg's own territory (- size + 1, not
      // - size), not flush against it -- direct live report of a thin
      // vertical seam right at this exact boundary in docked mode,
      // more visible after ruixen.stayawake/omarchy.agents' own icons
      // moved closer to it in a recent reorg. Both this Canvas
      // (antialiasing: true) and rightDockedBg (also antialiasing:
      // true) independently soften their own edge where they meet,
      // and two separately-antialiased shapes landing on the exact
      // same coordinate can each erode inward by a sub-pixel amount,
      // leaving a hairline of whatever's behind them (the wallpaper)
      // showing through. A deliberate 1px overlap guarantees full
      // coverage from at least one shape regardless of which side
      // eroded more -- both are the same solid black, so the extra
      // shared pixel is invisible either way.
      RoundCorner {
        id: rightShoulderWing
        visible: barWindow.barRoot.docked && !barWindow.barRoot.frameOwnsDockChrome
        corner: "topRight"
        size: barWindow.barRoot.shoulderWingSize
        color: barWindow.barRoot.dockedBarColor
        x: rightDockedBg.x - size + 1
        y: 0
      }

      // Mirrors leftFrameHemWing -- see its comment (barWindow.barRoot.frameColor,
      // not dockedBarColor).
      RoundCorner {
        id: rightFrameHemWing
        visible: barWindow.barRoot.docked && !barWindow.barRoot.frameOwnsDockChrome
        corner: "topRight"
        size: barWindow.barRoot.shoulderWingSize
        color: barWindow.barRoot.frameColor
        x: rightDockedBg.x + rightDockedBg.width - size
        y: rightDockedBg.height
      }
      }

      // Everything else (every pill's own content).
      Item {
        id: dockedRow
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: barWindow.barRoot.barSize

      // Media used to have its own bar-center pill here. Replaced by
      // ruixen.notch (a standalone overlay, not part of this window) --
      // see that plugin's README for why: it needed to grow downward
      // on hover without touching this bar's own reserved screen zone
      // or every other pill's vertical anchor.

      // Solo pill, not CenterModules -- that component's hover-reveal/
      // drag-anchor machinery was built for the old indicators cluster
      // sharing this region (removed). Weather + a divider + clock,
      // instead of a plain ModuleList Row, so there's a visible split
      // between the two instead of just spacing -- direct ModuleSlots,
      // not ModuleList, since ModuleList has no separator support.
      Item {
        id: clockPill
        anchors.right: parent.right
        // Flat px, not Style.space() -- that scales with [font]
        // base-size (bumped for bigger bar icons), which was inflating
        // every pill's padding/gaps right along with it and made pills
        // read as oversized. Pinned back to the pre-bump numbers here:
        // a flat 8px inner margin. Trimmed from 16 -- an 18px edge-to-
        // icon distance (frame+outerMargin) is plenty on its own
        // without also stacking a curve-clearance margin on top of it
        // for the frame's 24px corner.
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        width: clockRow.implicitWidth + 8 * 2
        height: barWindow.barRoot.barSize - Style.space(2)

        // Hidden (not just repositioned) when docked -- the merged
        // leftDockedBg/rightDockedBg below take over the background for
        // every pill in their group, this pill's own icons just sit on
        // top of that shared shape instead of their own floating pill.
        GroupPill { anchors.fill: parent; visible: !barWindow.barRoot.docked; barRoot: barWindow.barRoot }

        Row {
          id: clockRow
          anchors.centerIn: parent
          // Flat px, not Style.space() -- see clockPill's own margin
          // comment for why. Trimmed from Style.space(8) (~11px at
          // current font scale) to tighten the weather<->divider and
          // divider<->clock gaps as the bar got busier.
          spacing: 6

          ModuleSlot {
            anchors.verticalCenter: parent.verticalCenter
            entry: barWindow.barRoot.layoutEntries("center").filter(function(e) { return barWindow.barRoot.entryId(e) === "ruixen.weather" })[0] || null
            region: "center"
            barRoot: barWindow.barRoot
          }

          Rectangle {
            width: 3
            height: Style.space(14)
            radius: width / 2
            anchors.verticalCenter: parent.verticalCenter
            // Color.accent -- direct correction: Color.muted read as
            // flat grey, not the theme's actual color. Color.accent is
            // the theme's primary/focus token (same one
            // ruixen.workspaces uses for its own focused dot).
            color: Color.accent
          }

          ModuleSlot {
            anchors.verticalCenter: parent.verticalCenter
            entry: barWindow.barRoot.layoutEntries("center").filter(function(e) { return barWindow.barRoot.entryId(e) === "omarchy.clock" })[0] || null
            region: "center"
            barRoot: barWindow.barRoot
          }
        }
      }

      // Generic catch-all for everything else in "center" -- direct
      // review finding ("Support arbitrary third-party widgets in
      // the horizontal center region", #27): clockPill above is the
      // only thing that ever read from "center" here, so any OTHER
      // entry placed there (a third-party bar-widget, or even one of
      // Ruixen's own -- ruixen.media had this exact problem) was
      // silently dropped in horizontal mode. Same "special pill(s)
      // for a few ids, generic ModuleList for the rest" shape
      // workspacesPill/trayPill already use for left/right -- no
      // allowlist of known third-party ids, anything not in
      // centerSpecialIds just flows through here regardless of
      // plugin identity, the same generic registry/ModuleSlot path
      // every other hosted widget already goes through.
      //
      // Adjacent to the Notch's reserved zone, not dead-center on it
      // (#28) -- direct review finding ("Reserve horizontal space
      // for the Notch so bar widgets cannot render underneath it"):
      // "center" here originally meant the screen's own true center,
      // matching centerAnchor's own intent, but that's exactly where
      // ruixen.notch's own always-on-top overlay sits. A widget
      // positioned there isn't just visually hidden (the compositor
      // already does that for free, confirmed live during #27's own
      // work) -- it's UNCLICKABLE and functionally useless sitting
      // somewhere the user can never interact with, which is the
      // real problem worth fixing: wasted layout space, not visual
      // bleed-through. Anchored to the right edge of
      // barWindow.barRoot.reservedCenterRect instead, so this content sits in the
      // real, visible, clickable part of the bar.
      //
      // Left/right pill groups (menuPill/workspacesPill/... and
      // trayPill/pluginPinsPill/curatedPill/
      // clockPill) are NOT similarly
      // constrained yet -- a genuinely busy bar with enough widgets
      // on either side could still grow into this same reserved
      // zone. Deliberately left as a named follow-up rather than
      // restructuring their existing, working anchor chains in this
      // same pass -- matches the issue's own explicit allowance
      // ("if full overflow UX is out of scope, at minimum clip/
      // constrain at the reserved boundary and leave a follow-up
      // hook for a future collapse/overflow treatment"). Nothing in
      // this repo's own shipped default layout comes remotely close
      // to that many widgets today.
      Item {
        id: centerGenericPill
        readonly property rect reservedRect: barWindow.barRoot.reservedCenterRect(parent ? parent.width : 0)
        opacity: centerGenericContent.width > 0 ? 1 : 0
        x: reservedRect.x + reservedRect.width + 12
        anchors.verticalCenter: parent.verticalCenter
        width: centerGenericContent.width + 8 * 2
        height: barWindow.barRoot.barSize - Style.space(2)

        // Hidden (not just repositioned) when docked -- the merged
        // leftDockedBg/rightDockedBg below take over the background for
        // every pill in their group, this pill's own icons just sit on
        // top of that shared shape instead of their own floating pill.
        GroupPill { anchors.fill: parent; visible: !barWindow.barRoot.docked; barRoot: barWindow.barRoot }

        ModuleList {
          id: centerGenericContent
          anchors.centerIn: parent
          entries: barWindow.barRoot.layoutEntries("center").filter(function(e) {
            return barWindow.barRoot.centerSpecialIds.indexOf(barWindow.barRoot.entryId(e)) === -1
          })
          region: "center"
          barRoot: barWindow.barRoot
          // ModuleList's own default `active: visible && entries.length
          // > 0` never fired for this specific late-filled entries
          // value -- same exact bug trayContent's own comment already
          // documents and works around further down this file (see
          // trayPill). Confirmed live, not assumed: debugBarGeometry()
          // reported correct, non-zero widths/positions for real
          // third-party fixture widgets placed here, yet nothing
          // actually painted on screen -- the geometry math runs off
          // the raw entries data regardless of active, only the
          // Loader's actual visual content depends on it. This region
          // always has exactly this one layout slot structurally, so
          // there's nothing meaningful to gate active on anyway.
          active: true
        }
      }

      // Was omarchy.menu (the Omarchy logo) -- removed from the bar
      // layout entirely per direct request, replaced with
      // ruixen.applauncher in the same leftmost slot. Super+Space
      // keeps working regardless -- that goes through omarchy.menu's
      // own "menu" kind via the stock omarchy-menu CLI, unrelated to
      // whether it has a bar button (the shell's own inBar() comment
      // confirms this exact case: a plugin that's both a menu and a
      // bar-widget can't be locked out of the shell by taking its
      // button off the bar).
      Item {
        id: menuPill
        anchors.left: parent.left
        // Extra space on top of the usual 8px so content clears
        // ruixen.frame-widget's rounded corner (cornerRadius: 24)
        // instead of starting right at the edge. Smaller than the +20
        // this started at when floating — the pill's own background
        // provides visual separation from the curve on its own there,
        // bare icons needed more raw clearance than a pill shape does.
        // Flat px, not Style.space() -- see clockPill's comment on why.
        //
        // Docked mode doesn't get that cushion, though: its own
        // GroupPill is hidden (visible: !barWindow.barRoot.docked below) and
        // replaced by one continuous leftDockedBg shape flush with the
        // frame's corner, so the reasoning that justified trimming
        // this down from 20 doesn't hold there -- direct live report
        // ("the app icons group... too close to the edge... needs to
        // be relaxed") confirmed 12 alone reads as cramped without a
        // pill boundary to lean on. Reverting to the original,
        // already-tuned 20 specifically for docked rather than
        // guessing a new number.
        anchors.leftMargin: barWindow.barRoot.docked ? 20 : 12
        anchors.verticalCenter: parent.verticalCenter
        // Side padding trimmed from 8 to 4 per direct request ("making
        // the canvas pill thing a bit less wide? more rounded?") --
        // GroupPill's own radius is already height/2 (the max stadium
        // curve), so there was no more roundness to add directly; a
        // single-icon pill this close to square just reads rounder at
        // the same radius as its width shrinks toward its own height.
        width: menuContent.width + 4 * 2
        height: barWindow.barRoot.barSize - Style.space(2)

        // Hidden (not just repositioned) when docked -- the merged
        // leftDockedBg/rightDockedBg below take over the background for
        // every pill in their group, this pill's own icons just sit on
        // top of that shared shape instead of their own floating pill.
        GroupPill { anchors.fill: parent; visible: !barWindow.barRoot.docked; barRoot: barWindow.barRoot }

        ModuleList {
          id: menuContent
          anchors.centerIn: parent
          entries: barWindow.barRoot.layoutEntries("left").filter(function(e) { return barWindow.barRoot.entryId(e) === "ruixen.applauncher" })
          region: "left"
          barRoot: barWindow.barRoot
        }
      }

      Item {
        id: workspacesPill
        anchors.left: menuPill.right
        // Flat px, not Style.space() -- see clockPill's comment.
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        // Reverted a zero-padding trim here (tried matching menuPill's
        // fix, since omarchy.workspaces also has its own
        // horizontalMargin: 6 baked in) -- looked worse for this one,
        // user preferred the original +8 each side.
        width: workspacesContent.width + 8 * 2
        height: barWindow.barRoot.barSize - Style.space(2)

        // Hidden (not just repositioned) when docked -- the merged
        // leftDockedBg/rightDockedBg below take over the background for
        // every pill in their group, this pill's own icons just sit on
        // top of that shared shape instead of their own floating pill.
        GroupPill { anchors.fill: parent; visible: !barWindow.barRoot.docked; barRoot: barWindow.barRoot }

        ModuleList {
          id: workspacesContent
          anchors.centerIn: parent
          // Strict single-id match, not an exclusion list (issue #36):
          // an exclusion filter is an accidental catch-all for
          // anything else in "left" -- a stale/foreign entry left
          // over from before ruixen.pluginpins existed (or dragged
          // there by hand) would render sharing this Row with the
          // workspace dots, which is exactly what a direct report
          // described as the dots looking "floating/misaligned"
          // inside the pill: a real ~11px-tall dot next to a much
          // taller foreign widget in the same Row. The real fix is
          // this pill staying workspace-only; migrating any such
          // stale entry into ruixen.pluginpins' own group instead
          // lives in lib/build-shell-json.sh (runs on every
          // install/update, not just fresh installs).
          entries: barWindow.barRoot.layoutEntries("left").filter(function(e) {
            return barWindow.barRoot.entryId(e) === "ruixen.workspaces"
          })
          region: "left"
          barRoot: barWindow.barRoot
        }
      }

      // Pinned-apps quick-launch row -- moved here from the right side
      // (direct request: "move it to the left side... right next after
      // the window switcher"). Zero-collapse pattern, not just fade:
      // this pill is legitimately, routinely empty until the user has
      // pinned something in the launcher, so it must not hold open a
      // dead gap between the workspace icons and settings the rest of
      // the time.
      Item {
        id: pinnedappsPill
        anchors.left: workspacesPill.right
        anchors.leftMargin: pinnedappsContent.width > 0 ? 6 : 0
        anchors.verticalCenter: parent.verticalCenter
        width: pinnedappsContent.width > 0 ? pinnedappsContent.width + 8 * 2 : 0
        height: barWindow.barRoot.barSize - Style.space(2)

        // Hidden (not just repositioned) when docked -- the merged
        // leftDockedBg/rightDockedBg below take over the background for
        // every pill in their group, this pill's own icons just sit on
        // top of that shared shape instead of their own floating pill.
        GroupPill { anchors.fill: parent; visible: !barWindow.barRoot.docked; barRoot: barWindow.barRoot }

        ModuleList {
          id: pinnedappsContent
          anchors.centerIn: parent
          entries: barWindow.barRoot.layoutEntries("left").filter(function(e) {
            return barWindow.barRoot.entryId(e) === "ruixen.pinnedapps"
          })
          region: "left"
          barRoot: barWindow.barRoot
        }
      }

      // Left-side twin of pluginPinsPill (right side) -- direct
      // request: "the plugs in can rearrange within group or create
      // one more group on the left side after the pin apps group".
      // No toggle icon of its own: ruixen.pluginpins' own dropdown
      // stays the single control surface for browsing/pinning every
      // installed widget (always defaults new pins to "right", via
      // togglePin -- unchanged); this pill only ever gains an entry
      // when someone drags an already-pinned widget over from the
      // right pluginPinsPill, using the bar's existing generic
      // drag-to-reorder (dropBarModule already moves an entry
      // between regions, no region-specific change needed there).
      // Zero-collapse pattern, same as pinnedappsPill -- empty for
      // every user who never drags anything here.
      Item {
        id: leftPluginPinsPill
        anchors.left: pinnedappsPill.right
        anchors.leftMargin: leftPluginPinsContent.width > 0 ? 6 : 0
        anchors.verticalCenter: parent.verticalCenter
        width: leftPluginPinsContent.width > 0 ? leftPluginPinsContent.width + 8 * 2 : 0
        height: barWindow.barRoot.barSize - Style.space(2)

        GroupPill { anchors.fill: parent; visible: !barWindow.barRoot.docked; barRoot: barWindow.barRoot }

        ModuleList {
          id: leftPluginPinsContent
          anchors.centerIn: parent
          entries: barWindow.barRoot.layoutEntries("left").filter(function(e) {
            var id = barWindow.barRoot.entryId(e)
            return id !== "ruixen.applauncher" && id !== "ruixen.workspaces"
              && id !== "ruixen.pinnedapps" && id !== "ruixen.settingsbutton"
          })
          region: "left"
          barRoot: barWindow.barRoot
        }
      }

      Item {
        id: settingsPill
        // Fades out instead of collapsing width/anchors when
        // ruixen.settingsbutton isn't in the "left" layout -- same
        // reasoning as trayPill below: simpler than juggling anchors
        // around a pill that comes and goes, and nothing else anchors
        // off settingsPill's own edges.
        opacity: settingsContent.width > 0 ? 1 : 0
        anchors.left: leftPluginPinsPill.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: settingsContent.width + 8 * 2
        onXChanged: horizontalBarRoot.publishDockChromeMetrics()
        onWidthChanged: horizontalBarRoot.publishDockChromeMetrics()
        height: barWindow.barRoot.barSize - Style.space(2)

        // Hidden (not just repositioned) when docked -- the merged
        // leftDockedBg/rightDockedBg below take over the background for
        // every pill in their group, this pill's own icons just sit on
        // top of that shared shape instead of their own floating pill.
        GroupPill { anchors.fill: parent; visible: !barWindow.barRoot.docked; barRoot: barWindow.barRoot }

        ModuleList {
          id: settingsContent
          anchors.centerIn: parent
          entries: barWindow.barRoot.layoutEntries("left").filter(function(e) {
            return barWindow.barRoot.entryId(e) === "ruixen.settingsbutton"
          })
          region: "left"
          barRoot: barWindow.barRoot
        }
      }

      // "SYSTEM" -- an exact, fixed four (system-update, power,
      // quickactions, settingsbutton), never a catch-all. See
      // curatedRightIds' own comment for the full history of what's
      // moved in and out of this pill tonight; this is the final
      // answer ("system is POWER UPDATE MORE ACTIONS AND SETTING").
      // Anchored off clockPill, taking over the screen position the
      // old catch-all rightPill used to occupy.
      Item {
        id: curatedPill
        anchors.right: clockPill.left
        // Flat px, not Style.space() -- see clockPill's comment. Was
        // Style.space(16), an intentional outlier for holding 6 icons;
        // standardized down to the same 8px every other pill uses now
        // that the icons themselves already read bigger/bolder (18px).
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        width: curatedContent.width + 8 * 2
        height: barWindow.barRoot.barSize - Style.space(2)

        // Hidden (not just repositioned) when docked -- the merged
        // leftDockedBg/rightDockedBg below take over the background for
        // every pill in their group, this pill's own icons just sit on
        // top of that shared shape instead of their own floating pill.
        GroupPill { anchors.fill: parent; visible: !barWindow.barRoot.docked; barRoot: barWindow.barRoot }

        ModuleList {
          id: curatedContent
          anchors.centerIn: parent
          entries: barWindow.barRoot.layoutEntries("right").filter(function(e) {
            return barWindow.barRoot.curatedRightIds.indexOf(barWindow.barRoot.entryId(e)) !== -1
          })
          region: "right"
          barRoot: barWindow.barRoot
        }
      }

      // ruixen.pluginpins itself PLUS everything pinned through it
      // (stayawake, agents, microphone, network, any third-party
      // widget) -- direct correction: "the plugs in toggle inside the
      // pill it toggles... microphone network cofee ai [are]
      // toggleable from the plugins pin so they stay pinnable or not
      // in the plugin group". The toggle lives together with whatever
      // it toggles, not off on its own -- this is the catch-all pill
      // now (everything in "right" that's neither tray nor the fixed
      // system four), which is also what makes a newly-enabled
      // third-party widget land here automatically with no id list to
      // maintain.
      //
      // The toggle icon itself (ruixen.pluginpins) is pulled out of
      // that catch-all ModuleList and anchored to this pill's own
      // right edge directly, via its own ModuleSlot -- direct request:
      // "can you make it right of the pill group, so its like thing
      // that stays fix at the first right position of the pill
      // group". A ModuleList's render order otherwise just follows
      // shell.json's own array order, which drifts every time
      // something gets pinned/unpinned through it (see togglePin,
      // ruixen.pluginpins/BarWidget.qml) -- pulling it out is what
      // makes its own position a real, structural guarantee instead
      // of a data-order coincidence.
      Item {
        id: pluginPinsPill
        anchors.right: curatedPill.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        // pluginPinsContent.width, not .implicitWidth -- ModuleList (a
        // Loader) only computes the former explicitly for a
        // late-filled entries value; see stayawakeGroupPill's own old
        // comment (git history) for the identical bug this caused
        // there. Confirmed live: "it doesnt shrink or expand anymore"
        // and a lopsided pill the moment this pill's content stopped
        // being empty -- both symptoms of this exact stale-width bug.
        width: pluginPinsContent.width + pluginPinsToggle.implicitWidth + 8 * 2
        height: barWindow.barRoot.barSize - Style.space(2)

        GroupPill { anchors.fill: parent; visible: !barWindow.barRoot.docked; barRoot: barWindow.barRoot }

        ModuleList {
          id: pluginPinsContent
          anchors.right: pluginPinsToggle.left
          anchors.verticalCenter: parent.verticalCenter
          entries: barWindow.barRoot.layoutEntries("right").filter(function(e) {
            var id = barWindow.barRoot.entryId(e)
            return id !== "ruixen.tray" && id !== "ruixen.pluginpins" && barWindow.barRoot.curatedRightIds.indexOf(id) === -1
          })
          region: "right"
          barRoot: barWindow.barRoot
        }

        ModuleSlot {
          id: pluginPinsToggle
          anchors.right: parent.right
          // Was missing entirely -- with pluginPinsContent sitting
          // flush against this slot's own left edge (0 margin, same
          // 0-gap convention every other multi-icon pill already
          // uses), the pill's own width formula (content.width +
          // toggle.implicitWidth + 8*2) only reads as a symmetric 8px
          // each side if THIS edge also reserves its own 8px. Without
          // it, the missing 8 silently doubled onto the LEFT side
          // instead (content's own left edge floated out to 16px, not
          // 8) -- confirmed live: "the pill is lop sided now".
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          entry: barWindow.barRoot.layoutEntries("right").filter(function(e) { return barWindow.barRoot.entryId(e) === "ruixen.pluginpins" })[0] || null
          region: "right"
          barRoot: barWindow.barRoot
        }
      }

      // Tray ONLY -- direct correction, after three earlier attempts
      // widened this pill's own filter to also catch stayawake/agents,
      // then system-update/power, then microphone/network: "OPEN APPS
      // GROUP" means exactly tray, nothing else. Used to also host a
      // separate thirdPartyPill/catch-all filter of its own (both the
      // catch-all role and the id thirdPartyPill are gone now --
      // pluginPinsPill owns the catch-all instead). Keeps the id
      // trayPill regardless -- rightDockedBg/rightShoulderWing's own x
      // formulas (below) anchor half the docked-mode frame to THIS
      // pill's own left edge.
      Item {
        id: trayPill
        opacity: trayContent.width > 0 ? 1 : 0
        anchors.right: pluginPinsPill.left
        // Flat px, not Style.space() -- see clockPill's comment.
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        // Left padding alone is mode-aware -- direct report after the
        // itemExtent tightening above: docked mode has no per-pill
        // GroupPill of its own (hidden below) to cushion the icon from
        // rightShoulderWing's curve, since rightDockedBg.x/the wing's
        // own x both derive directly from THIS pill's own left edge
        // (see rightDockedBg's comment) -- same "no cushion in docked
        // mode" reasoning as menuPill's own left inset fix, mirrored
        // for this side's open-facing edge instead of the screen edge.
        // Right padding (trayContent's own anchors.rightMargin below)
        // stays flat 8 in both modes -- unaffected either way.
        readonly property int leftPad: barWindow.barRoot.docked ? 20 : 8
        width: trayContent.width + 8 + leftPad
        onXChanged: horizontalBarRoot.publishDockChromeMetrics()
        onWidthChanged: horizontalBarRoot.publishDockChromeMetrics()
        height: barWindow.barRoot.barSize - Style.space(2)

        // Hidden (not just repositioned) when docked -- the merged
        // leftDockedBg/rightDockedBg below take over the background for
        // every pill in their group, this pill's own icons just sit on
        // top of that shared shape instead of their own floating pill.
        GroupPill { anchors.fill: parent; visible: !barWindow.barRoot.docked; barRoot: barWindow.barRoot }

        ModuleList {
          id: trayContent
          anchors.right: parent.right
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          entries: barWindow.barRoot.layoutEntries("right").filter(function(e) { return barWindow.barRoot.entryId(e) === "ruixen.tray" })
          region: "right"
          barRoot: barWindow.barRoot
          // ModuleList's own visible/active binding (entries.length > 0)
          // never fired for this specific late-filled entries value --
          // stayed permanently inactive even once entries had 1 item.
          // Sidestep it: this region always has exactly this one layout
          // slot structurally, so there's nothing to gate on -- always
          // active, unconditionally.
          active: true
        }
      }
      } // dockedRow
    }
  }

  Component {
    id: verticalBar

    Item {
      anchors.fill: parent

      CenterModules { anchors.fill: parent; barRoot: barWindow.barRoot }

      LeftModules {
        anchors.top: parent.top
        anchors.topMargin: Style.space(8)
        anchors.horizontalCenter: parent.horizontalCenter
        barRoot: barWindow.barRoot
      }

      RightModules {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: Style.space(8)
        anchors.horizontalCenter: parent.horizontalCenter
        barRoot: barWindow.barRoot
      }
    }
  }
}
