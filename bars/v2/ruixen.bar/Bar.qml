import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import qs.Commons
import qs.Ui
import "BarModel.js" as BarModel

Item {
  id: root

  // The omarchy-shell host injects omarchyPath from OMARCHY_PATH.
  property string omarchyPath: Quickshell.env("OMARCHY_PATH")
  // Injected by the host shell so bar slots can resolve enabled widgets.
  property var barWidgetRegistry: null
  // Injected by the host shell every time shell.json is reloaded. Holds the
  // `bar:` subtree: position, centerAnchor, layout. The host owns file IO;
  // the bar just renders whatever it's handed. The bar font follows the
  // OS-level fontconfig monospace binding — it is not stored in shell.json.
  property var barConfig: ({})
  // Injected by the host shell. Used for shell-wide actions such as opening
  // settings and persisting inline widget state.
  property var shell: null
  // Manifest for the active bar option. Present for custom bars and useful for
  // diagnostics; the built-in bar does not otherwise need it.
  property var manifest: null
  // Mirrors the on-disk `bar-off` flag so the user can hide the bar without
  // killing the entire shell. Hidden panels stay mapped but park off-screen
  // without an exclusion zone; updated by the FileView watcher further down.
  property bool barHidden: false
  property string home: Quickshell.env("HOME")
  property string stateHome: home + "/.local/state"
  property string omarchyConfigDir: home + "/.config/omarchy"
  property var fallbackBarConfig: ({
    position: "top",
    transparent: false,
    style: "notch",
    centerAnchor: "omarchy.clock",
    layout: { left: [], center: [], right: [] }
  })
  property var layoutConfig: fallbackBarConfig.layout
  property string centerAnchor: ""
  property bool requestedTransparent: false
  property bool useTransparentForeground: false
  property bool transparent: false
  // Experimental second look: the outermost left/right pill groups merge
  // into one continuous shape flush with ruixen.frame-widget's corners
  // instead of floating, "growing out of the frame" the way ruixen.notch
  // grows out of the top edge -- one shoulder curve per side instead of
  // the notch's two. Off by default; set bar.docked: true in shell.json
  // to try it. Not the team's favorite mode, kept as an opt-in option.
  property bool docked: false
  // Visual skin, independent from Hyprland window curvature:
  // - notch: current Ruixen island/notch skin, with reserved center space.
  // - fullbar: saved old sharp+docked-style full strip, no notch overlay.
  property string barStyle: "notch"
  readonly property bool fullbarStyle: barStyle === "fullbar"
  // Docked-skin contract (issue #78 Phase 6, stage 5) -- replaces
  // scattered `root.fullbarStyle ? X : Y` branches across BarPanel/
  // FrameWindow with a single selected skin object. Both instances stay
  // alive permanently (cheap plain QtObjects, no visual cost) rather
  // than being Loader-swapped, so a live barStyle change re-selects
  // instantly with no load delay.
  NotchDockedSkin { id: notchDockedSkin }
  FullbarDockedSkin { id: fullbarDockedSkin }
  readonly property QtObject dockedSkin: root.fullbarStyle ? fullbarDockedSkin : notchDockedSkin
  property bool centerSectionHovered: false
  // One bar surface exists per monitor and each reports into this count, so a
  // pointer crossing from one monitor's bar to another's stays counted however
  // the enter and leave interleave. A single shared bool would be left false by
  // whichever event landed last.
  property int barHoverCount: 0
  // True while the pointer is over any bar, widgets included.
  readonly property bool barHovered: barHoverCount > 0
  property bool centerSectionRevealHeld: false
  property bool centerHoverRevealSuppressed: false
  property int barConfigSerial: 0
  property string position: "top"
  // Resolves through fontconfig at paint time (Style.font.family defaults
  // to "monospace"), so changing the system font (via `omarchy-font-set`)
  // updates the bar without a reload.
  property string fontFamily: Style.font.family
  // Bound to the central Color singleton so the bar tracks shell.toml's
  // [bar] section. Property names kept for the rest of this file's bindings.
  property color themeForeground: Color.bar.text
  property color themeContrastForeground: Color.background
  property color transparentForeground: Color.bar.text
  // #78 surface contract: bar surfaces resolve through semantic tokens before
  // any component extraction or visual redesign. Color and material are
  // independent axes; the new bar-surface.json state is authoritative when
  // present, with the older frame-appearance.json kept as color fallback.
  readonly property color surfaceBlack: "#000000"
  readonly property color surfaceSafeLightForeground: "#e8e8e8"
  readonly property color surfaceSafeDarkForeground: "#101010"
  readonly property color surfaceShadow: surfaceBlack
  readonly property string floatingSurfaceColorMode: root.frameColorMode
  readonly property string floatingSurfaceMaterial: root.barSurfaceMaterial
  readonly property color floatingPillSurface: resolveSurfaceColor(floatingSurfaceColorMode)
  readonly property color floatingPillFill: surfaceFillForMaterial(floatingPillSurface, floatingSurfaceMaterial)
  readonly property real floatingPillSurfaceLuminance: surfaceLuminance(floatingPillSurface)
  readonly property real themeForegroundLuminance: surfaceLuminance(themeForeground)
  // Dock chrome refactor bridge: BarPanel owns widget layout, FrameWindow
  // should eventually own the visual chrome. Publish measured geometry per
  // screen first so the frame can consume it without guessing pill widths.
  property var dockChromeMetricsByScreen: ({})
  property int dockChromeMetricsSerial: 0
  readonly property bool frameOwnsDockChrome: true
  readonly property bool integratedTopDockSurface: docked && position === "top"

  function surfaceLuminance(c) {
    return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
  }

  function resolveSurfaceColor(mode) {
    return mode === "theme" ? Color.background : root.surfaceBlack
  }

  function surfaceFillForMaterial(surface, material) {
    var alpha = material === "glass" ? 0.68 : surface.a
    return Qt.rgba(surface.r, surface.g, surface.b, alpha)
  }

  function readableForegroundForSurface(surface, preferred) {
    var surfaceIsLight = root.surfaceLuminance(surface) > 0.5
    var preferredIsLight = root.surfaceLuminance(preferred) > 0.45
    return surfaceIsLight
      ? (preferredIsLight ? root.surfaceSafeDarkForeground : preferred)
      : (preferredIsLight ? preferred : root.surfaceSafeLightForeground)
  }

  function contentSurfaceFor(surface) {
    return root.surfaceLuminance(surface) > 0.5 ? root.surfaceBlack : surface
  }

  function screenNameForWindow(window) {
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  function publishDockChromeMetrics(screenName, metrics) {
    var key = String(screenName || "")
    if (!key || !metrics) return

    var next = {}
    for (var existing in root.dockChromeMetricsByScreen)
      next[existing] = root.dockChromeMetricsByScreen[existing]
    next[key] = {
      screenWidth: Math.max(0, Math.round(metrics.screenWidth || 0)),
      barHeight: Math.max(0, Math.round(metrics.barHeight || 0)),
      leftWidth: Math.max(0, Math.round(metrics.leftWidth || 0)),
      rightX: Math.max(0, Math.round(metrics.rightX || 0)),
      rightWidth: Math.max(0, Math.round(metrics.rightWidth || 0))
    }
    root.dockChromeMetricsByScreen = next
    root.dockChromeMetricsSerial += 1
  }

  function dockChromeMetrics(screenName) {
    var key = String(screenName || "")
    return root.dockChromeMetricsByScreen[key] || {
      screenWidth: 0,
      barHeight: root.barSize,
      leftWidth: 0,
      rightX: 0,
      rightWidth: 0
    }
  }

  // themeForeground itself is left theme-following since it also feeds
  // the legacy transparent-bar wallpaper-contrast script below
  // (omarchy-bar-text-color). Keep bar-row text/icons and popup content
  // separate: WidgetButton/BarIconButton defaults consume barForeground
  // for the bar pill itself, while stock panel bodies often read
  // bar.foreground for popup text. Those popup bodies must follow
  // Color.popups.text, not the bar pill surface, or light/dark surface
  // combinations can collapse into black-on-black or white-on-white.
  //
  // barForeground is unconditionally pillForeground, NOT gated on
  // useTransparentForeground -- that whole subsystem (requestedTransparent
  // / omarchy-bar-text-color) exists for the *stock* bar's fully
  // see-through mode, picking a contrasting text color against whatever
  // wallpaper shows through. Ruixen pills paint their own semantic surface,
  // so that script's answer has nothing to do with what's readable here.
  readonly property color pillForeground: readableForegroundForSurface(floatingPillSurface, themeForeground)
  readonly property color popupForeground: Color.popups.text
  property color foreground: pillForeground
  property string iconTone: "accent"
  readonly property color iconForeground: iconTone === "accent" ? Color.accent : pillForeground
  // Semantic status colors intentionally bypass Icon Tone. Mono/Accent only
  // controls decorative icons; stateful indicators still need readable
  // good/warn/bad colors from the active theme palette.
  readonly property color semanticGood: themeGreen
  readonly property color semanticWarn: themeYellow
  readonly property color semanticBad: themeRed
  readonly property color semanticInfo: Color.accent
  readonly property color semanticNeutral: iconForeground
  // Not readonly -- Behavior on barForeground below needs write access to
  // intercept it, even though nothing assigns it imperatively anymore.
  property color barForeground: pillForeground
  property bool foregroundAnimationEnabled: true
  property color background: Color.bar.background
  property color urgent: Color.bar.active

  // Extra theme-palette roles beyond what Color.qml (qs.Commons) itself
  // exposes -- see ThemeColors.qml's own comment for why this needs its
  // own reader instead of just adding properties to that singleton
  // (Omarchy-owned, wiped on every omarchy-update). Read once here so any
  // widget in this file can reference root.themeGreen/root.themeMagenta/
  // etc directly instead of instantiating its own copy.
  ThemeColors { id: themeColors }
  property color themeRed: themeColors.red
  property color themeYellow: themeColors.yellow
  property color themeOrange: themeColors.orange
  property color themeGreen: themeColors.green
  property color themeCyan: themeColors.cyan
  property color themeBlue: themeColors.blue
  property color themeMagenta: themeColors.magenta
  property color themeBrown: themeColors.brown
  // Semantic vocabulary (see ThemeColors.qml's own comment): primary=
  // green, secondary=blue, mirroring Omarchy's own fastfetch config
  // (its Arch logo is colored "green", its Software block "blue").
  // "accent" isn't repeated here -- it's just Color.accent, already
  // used everywhere else in this file.
  property color themePrimary: themeColors.primary
  property color themeSecondary: themeColors.secondary
  property bool themeMonochrome: themeColors.monochrome

  Behavior on barForeground { enabled: root.foregroundAnimationEnabled; ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on background { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  Behavior on urgent { ColorAnimation { duration: 420; easing.type: Easing.InOutCubic } }
  property var tooltipTarget: null
  property var pendingTooltipTarget: null
  property string tooltipText: ""
  property string pendingTooltipText: ""
  property bool tooltipShown: false
  property int tooltipRequest: 0
  property var activePopout: null
  property var barDragSource: null
  property var barDragTarget: null
  property var barDragTargetGeometry: null
  property bool barDragAfter: false
  property var barDragWindow: null
  property var barDragScreen: null
  property url barDragImageUrl: ""
  property real barDragSceneX: 0
  property real barDragSceneY: 0
  property real barDragScreenX: 0
  property real barDragScreenY: 0
  property real barDragOffsetX: 0
  property real barDragOffsetY: 0
  property bool barMoveActive: false
  property string barMoveCandidate: ""
  property var barMoveWindow: null
  property var barMoveScreen: null
  property var clickTargets: []
  property var moduleSlots: []

  function registerClickTarget(target) {
    if (!target || clickTargets.indexOf(target) !== -1) return
    var next = clickTargets.slice()
    next.push(target)
    clickTargets = next
  }

  function unregisterClickTarget(target) {
    var next = clickTargets.filter(function(item) { return item !== target })
    clickTargets = next
  }

  function registerModuleSlot(slot) {
    if (!slot || moduleSlots.indexOf(slot) !== -1) return
    var next = moduleSlots.slice()
    next.push(slot)
    moduleSlots = next
  }

  function unregisterModuleSlot(slot) {
    var next = moduleSlots.filter(function(item) { return item !== slot })
    moduleSlots = next
  }

  function debugBarGeometry() {
    var out = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      var point = { x: slot.x, y: slot.y }
      try {
        point = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }
      out.push({
        id: slot.moduleName,
        section: slot.region,
        x: Math.round(point.x),
        y: Math.round(point.y),
        width: Math.round(slot.width),
        height: Math.round(slot.height),
        visible: slot.visible === true && slot.width > 0 && slot.height > 0,
        itemVisible: slot.activeItem.visible === true,
        itemWidth: Math.round(slot.activeItem.implicitWidth || 0),
        itemHeight: Math.round(slot.activeItem.implicitHeight || 0)
      })
    }
    return out
  }

  function targetWindow(target) {
    return target && target.QsWindow ? target.QsWindow.window : null
  }

  function targetBelongsToWindow(target, window) {
    return !!target && !!window && targetWindow(target) === window
  }

  function slotWindow(slot) {
    if (!slot) return null
    return targetWindow(slot.activeItem) || targetWindow(slot)
  }

  function sameWindow(left, right) {
    if (!left || !right) return false
    if (left === right) return true
    return !!left.screen && !!right.screen && !!left.screen.name && !!right.screen.name && left.screen.name === right.screen.name
  }

  function targetTooltipHovered(target) {
    return !!target && target.visible !== false && target.opacity !== 0 && target.tooltipHovered === true
  }

  function clearTooltip() {
    tooltipTimer.stop()
    pendingTooltipTarget = null
    pendingTooltipText = ""
    tooltipTarget = null
    tooltipText = ""
    tooltipShown = false
  }

  function clearBarDrag() {
    barDragSource = null
    barDragWindow = null
    barDragScreen = null
    barDragImageUrl = ""
    barDragTarget = null
    barDragTargetGeometry = null
    barDragAfter = false
    barDragSceneX = 0
    barDragSceneY = 0
    barDragScreenX = 0
    barDragScreenY = 0
    barDragOffsetX = 0
    barDragOffsetY = 0
  }

  function windowScreenPoint(scenePoint, window) {
    var x = scenePoint ? scenePoint.x : 0
    var y = scenePoint ? scenePoint.y : 0
    if (!window || !window.screen) return { x: x, y: y }

    if (root.position === "bottom")
      y += Math.max(0, window.screen.height - window.height)
    else if (root.position === "right")
      x += Math.max(0, window.screen.width - window.width)
    else if (root.position === "top")
      // Direct live report: the drag-reorder drop-marker line rendered
      // too high, right at the true screen edge, not aligned with the
      // bar. Root cause: BarPanel's own top margin (margins.top:
      // root.screenMarginTop, see its own comment) is a compositor-level
      // layer-shell margin -- it shifts the WHOLE window down on screen
      // without changing the window's own internal coordinate origin, so
      // mapToItem(null, ...) on a widget inside it returns a point
      // relative to that internal origin, short by screenMarginTop
      // (13px floating / 6px docked) of the widget's real screen
      // position. The bottom/right cases above correct for a DIFFERENT
      // situation entirely (a window anchored to the far edge, narrower/
      // shorter than the full screen, so its own local (0,0) isn't at
      // that far edge) -- a top bar has neither of those (it spans the
      // full width and is anchored only to the top), so it needed its
      // own, different correction: back the real compositor margin out
      // directly, the same root.screenMarginTop the popup-margin fixes
      // elsewhere in this file already use for the identical class of
      // surface-offset bug.
      y += root.screenMarginTop

    return { x: x, y: y }
  }

  function barDragScreenPoint(scenePoint) {
    return windowScreenPoint(scenePoint, barDragWindow)
  }

  function dropMarkerRect(slot, after) {
    if (!slot) return null

    try {
      var slotPoint = slot.mapToItem(null, 0, 0)
      var screenPoint = barDragScreenPoint(slotPoint)
      var thickness = Style.spacing.xs
      if (vertical) {
        return {
          x: screenPoint.x,
          y: screenPoint.y + (after ? slot.height : 0) - thickness / 2,
          width: slot.width,
          height: thickness
        }
      }

      return {
        x: screenPoint.x + (after ? slot.width : 0) - thickness / 2,
        y: screenPoint.y,
        width: thickness,
        height: slot.height
      }
    } catch (e) {
      return null
    }
  }

  // Split the screen along its diagonals (in normalized space, so widescreens
  // don't bias toward left/right): whichever triangle holds the cursor names
  // the candidate edge.
  function nearestScreenEdge(point, screen) {
    var nx = screen.width > 0 ? Util.clamp(point.x / screen.width, 0, 1) : 0.5
    var ny = screen.height > 0 ? Util.clamp(point.y / screen.height, 0, 1) : 0.5

    var edge = "top"
    var best = ny
    if (1 - ny < best) { edge = "bottom"; best = 1 - ny }
    if (nx < best) { edge = "left"; best = nx }
    if (1 - nx < best) { edge = "right"; best = 1 - nx }
    return edge
  }

  function beginBarMove(window) {
    barMoveWindow = window
    barMoveScreen = window ? window.screen : null
    barMoveCandidate = position
    barMoveActive = true
  }

  function updateBarMove(screenPoint) {
    if (!barMoveActive || !barMoveScreen) return
    barMoveCandidate = nearestScreenEdge(screenPoint, barMoveScreen)
  }

  function clearBarMove() {
    barMoveActive = false
    barMoveCandidate = ""
    barMoveWindow = null
    barMoveScreen = null
  }

  function finishBarMove() {
    var edge = barMoveCandidate
    if (!barMoveActive || !edge || edge === position) {
      clearBarMove()
      return
    }

    clearBarMove()
    setBarPosition(edge)
  }

  function setBarPosition(value) {
    var next = normalizePosition(value)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.position = next
      })
    } else {
      root.position = next
    }
  }

  function captureBarDragGhost(slot) {
    var item = slot && slot.activeItem ? slot.activeItem : null
    barDragImageUrl = ""
    if (!item || typeof item.grabToImage !== "function") return

    var grabWidth = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1))
    var grabHeight = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1))
    item.grabToImage(function(result) {
      if (root.barDragSource !== slot || !result || !result.url) return
      root.barDragImageUrl = result.url
    }, Qt.size(grabWidth, grabHeight))
  }

  function requestPopout(owner) {
    if (activePopout === owner) return
    if (activePopout) {
      if ("closeForPopoutSwitch" in activePopout) activePopout.closeForPopoutSwitch()
      else if ("close" in activePopout) activePopout.close()
    }
    activePopout = owner
  }

  function releasePopout(owner) {
    if (activePopout === owner) activePopout = null
  }

  readonly property bool vertical: position === "left" || position === "right"
  // A flat absolute now, NOT theme-relative -- used to derive from
  // Style.bar.sizeHorizontal/sizeVertical + a flat offset, but bumping
  // [font] base-size (done to get 18px icons) scales those theme
  // tokens by the same fontScale, which would balloon this past the
  // 44 target below every time the font scale changes.
  // BarIconButton only fixes *width* to Style.bar.iconSlot on a
  // horizontal bar (see qs.Ui BarIconButton.qml's fixedWidth/
  // fixedHeight split) -- height just fills whatever this pill provides,
  // so growing iconSlot/iconFont doesn't force a taller pill; 34 has
  // plenty of headroom for an 18px glyph.
  //
  // NOT paired 1:1 with topInset anymore (was topInset(10) + barSize(34)
  // = 44 == notchClearance's own target, a coincidence of both being 34,
  // not a real requirement). The actual invariant that matters is
  // topInset + notchClearance = 44 (see notchClearance below) -- barSize
  // itself is just this pill's own visual height, unrelated to where
  // Hyprland's reservation ends.
  readonly property int barSize: 34

  // Docked mode's open-facing shoulder: shared between the docked pill's
  // OWN corner radius and its RoundCorner wing's size, so they meet with
  // a matching straight edge and tangent instead of a visible seam (see
  // leftDockedBg/leftShoulderWing).
  readonly property int shoulderWingSize: 24

  // Hyprland/window curvature variant. This still controls the full-screen
  // frame hole in floating mode, but docked bar chrome intentionally ignores
  // it: sharp+docked should keep sharp windows below while the bar/notch skin
  // behaves exactly like rounded+docked. The older sharp+docked full-strip bar
  // is a separate future "classic/statusline" mode, not this curvature toggle.
  // Same read-once-at-startup Process pattern as the rest of lookfeel -- safe
  // because hyprland/ruixen-lookfeel.sh always does a full `omarchy restart
  // shell` on every variant change. "half" is the third Window Curvature
  // option (looknfeel.half.lua, half the full curve's own 24 -> 12; direct
  // request: "add a 3rd option that'd be half the size of the border's curve
  // on the windows") -- the frame's own hole follows it so the mask keeps
  // matching the real window corners.
  property string lookFeelVariant: "rounded"

  Process {
    id: readLookAndFeelVariantForDock
    command: ["bash", "-c", "readlink \"$HOME/.config/hypr/looknfeel.lua\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text.indexOf("looknfeel.square.lua") >= 0)
          root.lookFeelVariant = "sharp"
        else if (text.indexOf("looknfeel.half.lua") >= 0)
          root.lookFeelVariant = "half"
        else
          root.lookFeelVariant = "rounded"
      }
    }
  }

  // Reserved screen zone for windows -- taller than barSize so
  // ruixen.notch (a separate overlay, reserves nothing on its own) has
  // room for its collapsed height (44) without its bottom edge sitting
  // flush against tiled windows.
  //
  // ExclusionMode.Normal's exclusiveZone turned out additive to
  // BarPanel's own top margin (topInset -- see BarPanel), not a full
  // replacement -- this value has that margin already backed out,
  // targeting an actual reserved zone matching the notch's own 44px
  // height. Keep this in sync if topInset ever changes again -- it must
  // always equal 44 - topInset.
  //
  // 34 -> 31 alongside topInset 10 -> 13 (see BarPanel) -- per direct
  // report of unequal top/bottom spacing around the pills (measured:
  // ~5.5px above vs ~11.5px below, a real 6px imbalance, not a
  // perception issue -- confirmed against this machine's actual live
  // config: frame border thickness 6, Style.space(2) == 3 at this
  // machine's [font] base-size 17, Hyprland gaps_out 10). Moving
  // topInset down 3px and notchClearance down 3px in lockstep keeps
  // topInset + notchClearance = 44 (the reservation itself, and
  // therefore the tiled-window gap, is unchanged) while shifting the
  // pills themselves down 3px, splitting the old 6px imbalance evenly:
  // new spacing is ~8.5px on both sides instead of 5.5/11.5.
  //
  // #29 briefly retired this split (unified floating's own top margin
  // onto frameInset, to match docked's widget baseline exactly) --
  // reverted per direct live report: the actual complaint was never
  // this padding, it was weather/clock's own POPUP overlapping the
  // Notch (fixed separately, see BarPanel's implicitHeight comment),
  // and unifying the margin made floating's own spacing look
  // unbalanced for no real benefit. Back to the split tuned here.
  readonly property int notchClearance: 31

  // Inset so the bar's own content sits inside the frame's rounded-rect
  // hole instead of flush against the screen edge when docked. v1 had
  // to publish this to a shared state file so a SEPARATE ruixen.frame-
  // widget plugin/surface could read a matching copy -- the entire
  // reason v2 exists is that this bar now draws its own frame directly
  // (frameCanvas, inside BarPanel below), in the exact same window, so
  // there is no longer a second surface to keep in sync with at all.
  // One number, one scene, pixel-identical by construction.
  readonly property int frameInset: 6

  // Was hardcoded "#000000" (OLED black) in v1's ruixen.frame-widget,
  // unconditionally -- direct request: "make the surface for the frame
  // and floating pills not oled black this time too but changeable".
  // Just one choice now: "theme" (live-tracking the active theme's own
  // Color.background -- see qs.Commons' own Color.qml, already the same
  // singleton themeContrastForeground above reads) or "black" (plain
  // fixed OLED black). Was a Themed/Custom split with a 3-swatch color
  // picker (OLED Black/Charcoal/White) -- direct correction after live
  // testing surfaced a real problem White couldn't be patched around:
  // "some themes uses white like lupine and few other light theme, this
  // would make the notch unusable" (ruixen.notch shares this exact
  // frameColorMode/frameColor resolution off the same state file --
  // Theme mode on an actual light theme hits the identical failure any
  // light custom swatch would). Simplified down to the two colors this
  // repo's own downstream consumers (this frame, and the notch) can
  // actually support without a much bigger light-background rework:
  // "remove white from the setting as an option then and just leave
  // Black and Theme."
  property string frameColorMode: "black"
  property string barSurfaceMaterial: "glass"
  readonly property color frameColor: resolveSurfaceColor(root.frameColorMode)
  // Docked mode's merged shoulder strip (leftDockedBg/rightDockedBg and
  // their wing pieces below) hides every individual pill's own
  // background (GroupPill { visible: !root.docked }) and renders icons
  // directly against this fill -- same situation ruixen.notch's own
  // notchColor is in, and for the same reason it needs the same clamp:
  // docked foreground resolves against the floating pill surface for
  // Phase 1, so a light frameColor (Theme mode on an actual light theme)
  // would make every docked icon unreadable, not just look "off".
  // Falls back to plain black instead of frameColor whenever
  // frameColor itself reads too light -- mirrors ruixen.notch/Overlay.qml's
  // own resolvedFrameColorLuminance/notchColor pair exactly.
  readonly property real frameColorLuminance: surfaceLuminance(root.frameColor)
  readonly property color dockedBarColor: contentSurfaceFor(root.frameColor)

  readonly property string barIconToneStatePath: root.stateHome + "/ruixen/bar-icon-tone.json"

  function normalizeIconTone(tone) {
    return tone === "accent" ? "accent" : "mono"
  }

  function loadBarIconTone(raw) {
    try {
      var p = JSON.parse(String(raw || "").trim() || "{}")
      root.iconTone = normalizeIconTone(p && p.tone)
    } catch (e) {
      root.iconTone = "accent"
    }
  }

  FileView {
    id: barIconToneFile
    path: root.barIconToneStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadBarIconTone(text())
    onLoadFailed: root.iconTone = "accent"
  }

  // bar-surface.json is the new #78 state for independent color/material
  // axes. frame-appearance.json remains as a compatibility fallback and
  // notch mirror until the coupled notch/frame surface is migrated too.
  readonly property string barSurfaceStatePath: root.stateHome + "/ruixen/bar-surface.json"
  property bool barSurfaceStateLoaded: false

  function normalizeSurfaceColorMode(mode) {
    return mode === "theme" ? "theme" : "black"
  }

  function normalizeSurfaceMaterial(material) {
    return material === "glass" ? "glass" : "solid"
  }

  function applyBarSurfaceState(colorMode, material) {
    root.frameColorMode = normalizeSurfaceColorMode(colorMode)
    root.barSurfaceMaterial = normalizeSurfaceMaterial(material)
  }

  function loadBarSurfaceState(raw) {
    try {
      var p = JSON.parse(String(raw || "").trim() || "{}")
      root.applyBarSurfaceState(p && p.color, p && p.material)
      root.barSurfaceStateLoaded = true
    } catch (e) {
      root.barSurfaceStateLoaded = false
      frameColorFile.reload()
    }
  }

  FileView {
    id: barSurfaceFile
    path: root.barSurfaceStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadBarSurfaceState(text())
    onLoadFailed: {
      root.barSurfaceStateLoaded = false
      frameColorFile.reload()
    }
  }

  // JSON, not a plain string -- kept the shape (an object with a "mode"
  // key) even though customColor is gone, so an old file from before
  // this simplification (mode: "custom", customColor: "#...") degrades
  // safely: "custom" is no longer a recognized mode string, so
  // loadFrameAppearance's own fallback below just treats it as unknown
  // and lands on the new "black" default -- never a crash, never a
  // stale color stuck from the old 3-swatch picker.
  readonly property string frameColorStatePath: root.stateHome + "/ruixen/frame-appearance.json"

  // Always resets the mode off the parsed result, never leaves it at
  // whatever it happened to be before this call -- direct live bug found
  // testing the ORIGINAL (Themed/Custom) version of this: onLoadFailed
  // used to be a bare no-op (fine for the very first single-hex-string
  // version, which never changed away from its own declared default
  // without a file existing at all), but once a mode existed too,
  // deleting the state file left frameColorMode stuck on "theme" forever
  // instead of reverting -- nothing was left to reset it. Same shape as
  // ruixen.cava's own loadCavaState/onLoadFailed pattern, called with ""
  // on failure.
  function loadFrameAppearance(raw) {
    if (root.barSurfaceStateLoaded) return
    try {
      var p = JSON.parse(String(raw || "").trim() || "{}")
      root.frameColorMode = normalizeSurfaceColorMode(p && p.mode)
      root.barSurfaceMaterial = "glass"
    } catch (e) {
      root.frameColorMode = "black"
      root.barSurfaceMaterial = "glass"
    }
  }

  FileView {
    id: frameColorFile
    path: root.frameColorStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadFrameAppearance(text())
    onLoadFailed: root.loadFrameAppearance("")
  }
  // Floating's own, bigger top margin -- see BarPanel's own margins
  // comment for the full history/tuning. Lives on root for the same
  // reason frameInset does.
  readonly property int topInset: 13

  // BarPanel's own baseline top margin, before the seam-overlap
  // reduction below -- exactly what v1's own screenMarginTop always was.
  readonly property int contentTopInset: docked ? frameInset : topInset

  // A few pixels of deliberate insurance overlap BarPanel paints into
  // where FrameWindow's own edge is, so the two surfaces' own edges
  // never need to agree on the exact same physical pixel to avoid a
  // visible seam -- see BarPanel's own comment for the full mechanism.
  //
  // A plain constant now, NOT docked/position-conditional -- direct live
  // report: BarPanel's own real height came out different between docked
  // (61) and floating (58) modes, breaking v1's own explicit "same floor
  // in both modes" design (see visibleBarHeight's own comment) and
  // visibly affecting spacing around the Notch. Root cause: implicitHeight
  // below added this value unconditionally, but the OLD conditional
  // property evaluated to 0 in floating mode -- so only docked grew.
  // Every actual USE of the overlap (margins.top, exclusiveZone,
  // contentOffset's own topMargin) now carries its own explicit
  // docked-and-top-position gate at the call site instead of relying on
  // this property doing that gating internally, specifically so
  // implicitHeight CAN apply the fixed 3px in both modes uniformly
  // without needing a separate, second constant.
  readonly property int seamOverlap: 3

  // BarPanel's own current REAL on-screen margin -- contentTopInset
  // minus whatever seam-overlap it's currently painting. Backs this out
  // for anything anchored to BarPanel's own surface coordinate space
  // (PopupCard xdg-popups, the drag-ghost screen-point correction) --
  // same role this property has always had, just now also accounting
  // for the overlap trick on top of the older docked-vs-floating split.
  readonly property int screenMarginTop: position === "top" ? contentTopInset - seamOverlap : contentTopInset

  function normalizePosition(value) {
    return BarModel.normalizePosition(value)
  }

  // Apply tray-pinning on top of the shared layout normalization so the
  // bar host and scriptable config helpers can't drift on entry shape.
  function normalizeLayout(layout) {
    var normalized = Util.normalizeLayout(Util.isPlainObject(layout) ? layout : fallbackBarConfig.layout)
    return {
      left:   pinTrayToInner(normalized.left,   "left"),
      center: pinTrayToInner(normalized.center, "center"),
      right:  pinTrayToInner(normalized.right,  "right")
    }
  }

  // The tray drawer reveals inward (away from the bar edge). Place it at the
  // section's inner edge: start of the right section, end of the left/center
  // sections. The drawer's reserved space then sits next to the bar center,
  // not stranded mid-section.
  function pinTrayToInner(entries, section) {
    return BarModel.pinTrayToInner(entries, section)
  }

  function applyBarConfig() {
    var config = Util.isPlainObject(barConfig) ? barConfig : fallbackBarConfig

    position = normalizePosition(config.position)
    setRequestedTransparency(config.transparent === true)
    docked = config.docked === true
    barStyle = config.style === "fullbar" ? "fullbar" : "notch"
    centerAnchor = Util.canonicalWidgetId(config.centerAnchor || "")

    // layoutEntries feeds plain JS arrays to the module Repeaters, and QML
    // cannot diff those: reassigning layoutConfig rebuilds every widget on
    // every monitor. When a shell.json write only changed inline widget
    // settings, patch the live layout and running widgets in place instead.
    var next = normalizeLayout(config.layout)
    var delta = BarModel.inlineSettingsDelta(layoutConfig, next)
    if (delta) {
      applySettingsDelta(delta)
      return
    }
    layoutConfig = next
    barConfigSerial++
  }

  function applySettingsDelta(delta) {
    for (var i = 0; i < delta.length; i++) {
      var change = delta[i]
      layoutConfig[change.region][change.index] = change.entry
      var settings = entrySettings(change.entry)
      for (var s = 0; s < moduleSlots.length; s++) {
        var slot = moduleSlots[s]
        if (!slot || slot.region !== change.region || slot.moduleName !== entryId(change.entry)) continue
        var item = slot.activeItem
        if (item && "settings" in item) item.settings = settings
      }
    }
  }

  onBarConfigChanged: applyBarConfig()

  function layoutEntries(region) {
    var serial = barConfigSerial
    var entries = layoutConfig ? layoutConfig[region] : null
    return Array.isArray(entries) ? entries : []
  }

  // Tab order for the panels in one bar region. Scoped to a single bar surface
  // so tabbing walks the bar the open panel belongs to instead of hopping the
  // panel to another monitor's copy of the same widget.
  function panelNavigationSlots(region, window) {
    var entries = layoutEntries(region)
    var slots = []
    for (var i = 0; i < entries.length; i++) {
      var id = entryId(entries[i])
      for (var j = 0; j < moduleSlots.length; j++) {
        var slot = moduleSlots[j]
        if (!slot || slot.region !== region || slot.moduleName !== id) continue
        if (window && !sameWindow(slotWindow(slot), window)) continue
        var item = slot.activeItem
        if (!item || item.visible !== true || slot.visible !== true || slot.width <= 0 || slot.height <= 0) continue
        if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
        slots.push(slot)
        break
      }
    }
    return slots
  }

  // The Nth panel in a bar region, counted the way the bar reads: layout order,
  // and only the panels actually on screen. A widget with no panel (the tray)
  // and one that is hiding itself are passed over, so the number lands on the
  // Nth panel icon the user can see rather than the Nth layout entry.
  // One-based, because it exists for hotkeys; anything else lands on no slot.
  //
  // Counting any bar surface is enough: every monitor lays its bar out from the
  // one layout, and summoning the id routes through pickPanelSlot, which opens
  // the focused monitor's copy whichever surface was counted.
  function panelWidgetIdAt(region, index) {
    var slots = panelNavigationSlots(String(region || ""), null)
    var slot = slots[Math.round(Number(index)) - 1]
    return slot ? String(slot.moduleName || "") : ""
  }

  function switchPanelFrom(owner, direction) {
    if (!owner) return false

    var currentSlot = null
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (slot && slot.activeItem === owner) {
        currentSlot = slot
        break
      }
    }
    if (!currentSlot) return false

    var slots = panelNavigationSlots(currentSlot.region, slotWindow(currentSlot))
    if (slots.length < 2) return false

    var currentIndex = -1
    for (var j = 0; j < slots.length; j++) {
      if (slots[j] === currentSlot) {
        currentIndex = j
        break
      }
    }
    if (currentIndex < 0) return false

    var step = direction < 0 ? -1 : 1
    var nextSlot = slots[(currentIndex + step + slots.length) % slots.length]
    if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner) return false

    nextSlot.activeItem.open()
    return true
  }

  // Every live instance of a widget id. A bar surface is built per monitor, so
  // a widget that appears once in the layout is still live once per screen.
  function moduleWidgets(pluginId) {
    var id = String(pluginId || "")
    var items = []
    if (!id) return items
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem || slot.moduleName !== id) continue
      items.push(slot.activeItem)
    }
    return items
  }

  function slotScreenName(slot) {
    var window = slotWindow(slot)
    return window && window.screen ? String(window.screen.name || "") : ""
  }

  // The output Hyprland has focused, which is where a keyboard-summoned panel
  // belongs. Empty until Hyprland reports one, which leaves panel routing on
  // its per-monitor fallback rather than guessing at an output.
  function focusedScreenName() {
    var monitor = Hyprland.focusedMonitor
    return monitor ? String(monitor.name || "") : ""
  }

  // Resolve the live bar-widget instance for a plugin id (e.g. "omarchy.bluetooth").
  // Only widgets that expose popup open/close methods count; plain indicators
  // (clock, workspaces, tray) return null. Used by shell.summon/toggle so
  // panel hotkeys route through the bar instead of a per-target IPC handler
  // that only reaches whichever per-monitor instance claimed the target.
  function findPanelWidget(pluginId) {
    var id = String(pluginId || "")
    if (!id) return null
    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || !slot.activeItem) continue
      if (slot.moduleName !== id) continue
      var item = slot.activeItem
      if (typeof item.open !== "function" || typeof item.close !== "function" || item.opened === undefined) continue
      candidates.push({ slot: slot, screenName: slotScreenName(slot), opened: item.opened === true })
    }
    // One copy per monitor, plus a zero-size placeholder for anchored center
    // modules. See BarModel.pickPanelSlot for which one a hotkey acts on.
    var chosen = BarModel.pickPanelSlot(candidates, focusedScreenName())
    return chosen ? chosen.activeItem : null
  }

  function summonBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.open !== "function") return false
    item.open()
    return true
  }

  function hideBarWidget(pluginId) {
    var item = findPanelWidget(pluginId)
    if (!item || typeof item.close !== "function") return false
    item.close()
    return true
  }

  function isBarWidgetOpen(pluginId) {
    var item = findPanelWidget(pluginId)
    return !!item && item.opened === true
  }

  function entrySettings(entry) {
    return BarModel.entrySettings(entry)
  }

  function entryId(entry) {
    return BarModel.entryId(entry)
  }

  // Widgets pulled out of the main catch-all pill into their own small pills —
  // see horizontalBar below. ruixen.dnd removed -- no longer in the bar
  // layout (its toggle now lives in ruixen.notch's own bell + as a row in
  // ruixen.quickactions' popup instead of a standalone pill).
  //
  // Right side redrawn into four groups, left to right, per direct
  // request ("your blowing up the icon groups, this doesnt make any
  // sense. so starting from the first left icon group, the onepassword
  // and open app pill group, next pill group is the PLUGSINSPIN and the
  // popup plugin widget pin icon. then the next group is more actions
  // and setting. then the last pill group is weather and time"):
  //
  //   1. trayPill -- ruixen.tray ONLY. Literal open apps (1Password,
  //      etc.), nothing else -- not a catch-all. Direct correction,
  //      three times over: first attempts routed stayawake/agents,
  //      then system-update/power, then microphone/network here too;
  //      final answer is "OPEN APPS GROUP" means exactly that, tray and
  //      only tray.
  //   2. pluginPinsPill -- ruixen.pluginpins itself PLUS everything
  //      pinned through it (stayawake, agents, microphone, network, any
  //      third-party widget someone pins) -- direct correction: "the
  //      plugs in toggle inside the pill it toggles... microphone
  //      network cofee ai [are] toggleable from the plugins pin so they
  //      stay pinnable or not in the plugin group". The toggle icon
  //      lives together with whatever it toggles, not off on its own.
  //   3. curatedPill ("SYSTEM") -- system-update, power, quickactions,
  //      settingsbutton ("system is POWER UPDATE MORE ACTIONS AND
  //      SETTING"). Never a real catch-all -- an exact id-match list
  //      below, not a default landing zone.
  //   4. clockPill -- weather + clock, unchanged.
  //
  // curatedRightIds is that exact fixed list. pluginPinsGroupIds is
  // everything that lands in pill 2 -- ruixen.pluginpins itself plus
  // every id NOT in curatedRightIds and NOT ruixen.tray. There's
  // deliberately no third named list: pill 2 is defined as "whatever
  // isn't tray and isn't the fixed system list", so a newly-pinned
  // third-party widget lands there automatically without needing its
  // id added anywhere.
  //
  // Omarchy's own bar-widget placement (PluginRegistry.qml's
  // defaultBarWidgetSection/barTarget, what `omarchy plugin enable <id>`
  // with no explicit --section runs) inserts a widget with no placement
  // right after the section's own anchor id, hardcoded to ruixen.tray
  // for "right" -- landing a newly-enabled widget's default insertion
  // point right after tray in shell.json's own array. That still lands
  // it in pill 2 (not curated, not tray itself), matching "third-party
  // lands left of the coffee" from the original design intent -- the
  // coffee (stayawake) itself lives in pill 2 now too.
  //
  // ruixen.peripherals passed through here once (direct ask: "its kinda
  // crowding to put it in the pinplugins group, can we move this so it
  // works inside the setting more actions group instead"), then back out
  // again (direct follow-up, to reduce clutter: "its not that important
  // for me to always see it right now" -- pill 2, pinned on demand
  // through ruixen.pluginpins, same as stayawake/agents, rather than a
  // permanent fixture here).
  readonly property var curatedRightIds: ["omarchy.system-update", "ruixen.power", "ruixen.quickactions", "ruixen.settingsbutton"]
  // The two ids clockPill gives its own special pill+divider treatment
  // (see clockPill's own comment) -- direct review finding ("Support
  // arbitrary third-party widgets in the horizontal center region",
  // #27): everything else ever placed in shell.json's "center" region
  // was silently dropped by the horizontal bar, since clockPill was
  // the ONLY thing that ever read from "center" there. Same shape as
  // curatedRightIds above -- the ids with their own dedicated pill, so a
  // generic catch-all elsewhere can exclude them and host everything
  // remaining.
  readonly property var centerSpecialIds: ["ruixen.weather", "omarchy.clock"]

  // Every id with its own dedicated, exact-match pill (curatedRightIds
  // and centerSpecialIds above, plus the left-side ones: menuPill/
  // workspacesPill/pinnedappsPill/settingsPill each render exactly one
  // named id, never a catch-all) and ruixen.tray/ruixen.pluginpins
  // themselves. Mirrors lib/build-shell-json.sh's own protected_bar_ids
  // -- keep both in sync if either changes.
  //
  // Direct follow-up after #36 ("can you make sure we just disable
  // people from dragging icons into the workspace group blowing it up
  // again"): dropping any OTHER id onto one of these pills does not
  // just fail to look reordered -- the pill's own filter is an exact
  // id match, not a catch-all, so the dropped widget stops rendering
  // anywhere on the bar at all, silently, with no feedback. Used below
  // to keep these slots out of the drop-target search entirely, not
  // just workspacesPill -- every exact-match pill has the identical
  // failure mode.
  readonly property var protectedModuleIds: root.curatedRightIds.concat(root.centerSpecialIds).concat([
    "ruixen.applauncher", "ruixen.workspaces", "ruixen.pinnedapps",
    "ruixen.tray", "ruixen.pluginpins"
  ])

  // Solo pills -- each renders exactly one fixed id, with no second
  // legitimate home anywhere else on the bar. ruixen.settingsbutton is
  // NOT in this list -- it still needs to reorder among the other
  // three curatedRightIds items -- but it no longer gets a second home
  // either; moduleDropAtScene's own sourceIsCurated scoping keeps it
  // (and the rest of curatedRightIds) confined to curatedPill only, a
  // direct correction after an earlier pass let it pop out to its own
  // left-side settingsPill fallback ("no i dont want the settings and
  // more options and power etc to have that option, keep that pill
  // rearrange within its group only").
  //
  // Direct follow-up after the broader protectedModuleIds fix ("we
  // either want to move the whole workspace or app launcher as a
  // plugin by itself, dont allow stuff in there... on other pills that
  // are solo buttons dont allow move out of the pill or other stuff
  // into the pill"): these ids cannot be dragged AT ALL, in either
  // direction -- protectedModuleIds alone only blocked foreign ids
  // from landing here, a drag whose SOURCE is itself protected
  // (ruixen.tray dragged near workspacesPill, say) could still land on
  // another solo pill's slot and vanish just the same way. Blocking
  // the drag from ever starting for these ids is simpler and more
  // complete than trying to validate every possible destination.
  readonly property var immovableModuleIds: [
    "ruixen.applauncher", "ruixen.workspaces", "ruixen.pinnedapps",
    "ruixen.tray", "ruixen.pluginpins"
  ]

  // Direct review finding ("Reserve horizontal space for the Notch so
  // bar widgets cannot render underneath it", #28): ruixen.notch's own
  // overlay window sits on WlrLayer.Overlay, a compositor layer ABOVE
  // this bar's own -- confirmed live during #27's own work (a
  // hardcoded, unconditional, opaque, z:999 test rectangle placed
  // dead-center still never appeared on screen, until ruixen.notch was
  // disabled). That already means anything the bar draws underneath
  // the Notch is invisible for free, with no masking needed here --
  // but a bar widget positioned there is also UNCLICKABLE and
  // functionally useless sitting in a spot the user can never
  // interact with, which is the real problem this issue is about:
  // not visual bleed-through, but wasted layout space a widget could
  // otherwise occupy somewhere actually visible.
  //
  // Used to read these live from ruixen.notch's own NotchGeometry.qml
  // service via Omarchy's own shell.firstPartyServiceFor("ruixen.notch")
  // -- one Ruixen plugin reading a constant a DIFFERENT Ruixen plugin
  // owns, so the two could never drift out of sync with each other's
  // real numbers. Omarchy v4.0.3 restricts that call to a fixed 4-item
  // allowlist of Omarchy's own services, which "ruixen.notch" was never
  // going to be in (ruixen-shell issue #41/#38), so these are now plain
  // constants, manually kept in sync with ruixen.notch/Overlay.qml's own
  // current values instead -- the exact same convention this file's own
  // ModuleSlot/cornerSize already uses for a different pair of plugins'
  // shared numbers. NotchGeometry.qml itself was deleted entirely once
  // this file became its only remaining reader and stopped reading it
  // live (ruixen-shell issue #38's own cleanup pass) -- Overlay.qml was
  // always the real source of truth those numbers mirrored anyway. These
  // two are the Notch's COLLAPSED footprint only, not its full live
  // launcher/pinned-expanded width -- a deliberate, named scope limit,
  // not an oversight. If Overlay.qml's own bodyWidth/cornerSize/
  // margins.top/notchOuter height ever change, these two must change
  // with them.
  //
  // 340 matches Overlay.qml's own current collapsed bodyWidth (284) +
  // cornerSize (28) * 2.
  readonly property int notchReservedWidth: 340

  // Absolute screen Y of the Notch's own collapsed bottom edge -- see
  // implicitHeight's own comment below for what this is for (giving
  // weather/clock's popup enough window height to clear the Notch
  // without opening underneath it). 48 mirrors Overlay.qml's own current
  // collapsed margins.top (4) + notchOuter height (44).
  readonly property int notchCollapsedBottomEdge: 48

  // Screen-space rect the Notch's collapsed footprint occupies, centered
  // in a region of the given width -- per-output correct for free
  // (called with THIS bar surface's own dockedRow.width, which is
  // already sized to whichever screen that surface belongs to, same as
  // every other per-monitor bar geometry in this file). y/height cover
  // this bar's own row specifically, not the Notch's real screen
  // position -- the only thing that matters for keeping bar CONTENT
  // out of the way is the horizontal span, since this bar and the
  // Notch already occupy the same horizontal band by construction (both
  // live at the top of the screen, centered).
  function reservedCenterRect(containerWidth) {
    var r = BarModel.reservedCenterRect(root.dockedSkin.dockSpansFullWidth ? 0 : root.notchReservedWidth, containerWidth, root.barSize)
    return Qt.rect(r.x, r.y, r.width, r.height)
  }

  function moduleString(entry, key, fallback) {
    return BarModel.moduleString(entry, key, fallback)
  }

  function entryIndex(entries, name) {
    return BarModel.entryIndex(entries, name)
  }

  function entriesBefore(entries, name) {
    return BarModel.entriesBefore(entries, name)
  }

  function entriesAfter(entries, name) {
    return BarModel.entriesAfter(entries, name)
  }

  function canonicalWidgetId(name) {
    return Util.canonicalWidgetId(name)
  }

  function expandPath(path) {
    return BarModel.expandPath(path, home)
  }

  function customModuleSafeName(name) {
    return BarModel.customModuleSafeName(name)
  }

  function customModuleType(entry) {
    return BarModel.customModuleType(entry)
  }

  function customModuleSource(entry) {
    var source = BarModel.customModulePath(entry, home, omarchyConfigDir)
    return source ? Util.fileUrl(source) : ""
  }

  Component.onCompleted: {
    applyBarConfig()
    readLookAndFeelVariantForDock.running = true
  }

  // Revealing the indicators widens their section, which can slide a neighbour
  // under a stationary pointer. Collapsing on that un-hover would move it back
  // out and re-open the peek, so hold until the pointer leaves the bar.
  function setCenterSectionHovered(hovered) {
    centerSectionHovered = hovered
    if (hovered) {
      centerSectionRevealTimer.stop()
      centerSectionRevealHeld = true
    } else {
      centerSectionRevealTimer.restart()
    }
  }

  function setBarHovered(hovered) {
    barHoverCount = Math.max(0, barHoverCount + (hovered ? 1 : -1))
    if (barHoverCount === 0) centerSectionRevealTimer.restart()
  }

  Timer {
    id: centerSectionRevealTimer
    interval: 120
    // Collapse only. Opening the peek is the center section's own gesture, done
    // in setCenterSectionHovered, so a timer left pending by a pointer that dipped
    // off the bar and came back cannot reveal indicators it never pointed at.
    onTriggered: if (!root.centerSectionHovered && !root.barHovered) root.centerSectionRevealHeld = false
  }

  function run(command) {
    if (!command) return

    Util.execDetached(command)
  }

  function toggleTransparency() {
    var nextTransparent = !(root.requestedTransparent === true)
    if (root.shell && typeof root.shell.mutateShellConfig === "function") {
      root.shell.mutateShellConfig(function(config) {
        if (!Util.isPlainObject(config.bar)) config.bar = {}
        config.bar.transparent = nextTransparent
      })
    } else {
      root.setRequestedTransparency(nextTransparent)
    }
  }

  // Issue #7: the actual config-mutation math (find the entry, splice
  // it out, splice it back in at the target index) has no QML/Item
  // dependency at all -- moved to BarModel.js's own moveModuleInConfig,
  // unit-testable without a live Quickshell instance. This wrapper is
  // the only part that genuinely needs to be here: root.shell itself.
  function dropBarModule(source, toRegion, beforeName) {
    if (!source || !source.region || !source.moduleName || !toRegion) return false
    if (source.region === toRegion && source.moduleName === beforeName) return false
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return false

    var changed = false
    root.shell.mutateShellConfig(function(config) {
      changed = BarModel.moveModuleInConfig(config, source.region, source.moduleName, toRegion, beforeName)
    })
    return changed
  }

  function moduleDropAtScene(scenePoint, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    if (sourceWindow && sourceWindow.contentItem) {
      var barPoint = sourceWindow.contentItem.mapFromItem(null, scenePoint.x, scenePoint.y)
      if (barPoint.x < 0 || barPoint.x > sourceWindow.contentItem.width ||
          barPoint.y < 0 || barPoint.y > sourceWindow.contentItem.height)
        return null
    }

    // A protected slot (workspacesPill, applauncher, tray, the curated
    // system four, ...) only ever renders its own exact id -- dropping
    // some OTHER, non-protected widget there does not reorder anything
    // visible, it just makes that widget stop rendering anywhere on
    // the bar at all, so a non-protected source can only ever target a
    // non-protected slot (pluginPinsPill's own catch-all).
    //
    // curatedRightIds (the "settings and more options and power"
    // group) is a SEPARATE case from the rest of protectedModuleIds --
    // direct correction after an earlier pass wrongly let it reorder
    // onto ANY protected slot, including ruixen.settingsbutton's own
    // left-side settingsPill fallback ("no i dont want the settings
    // and more options and power etc to have that option, keep that
    // pill rearrange within its group only"): these four may only
    // reorder among each other, never leave curatedPill via drag.
    var sourceIsCurated = sourceSlot && root.curatedRightIds.indexOf(sourceSlot.moduleName) !== -1
    // Direct report: centerSpecialIds (weather/clock's own clockPill)
    // never got curatedRightIds' own "only reorder among its own group"
    // treatment -- it was only ever protected in the general
    // (sourceIsProtected) sense, which just stops FOREIGN widgets from
    // landing there. That sense does nothing to constrain WHERE weather/
    // clock themselves can be dragged TO, since being protected also
    // exempts a source from the foreign-widget block below -- so either
    // one could freely land on any other protected slot (workspacesPill,
    // applauncher, tray, curatedPill, ...), scattering clockPill and
    // leaving no ordinary way to drag anything back into the gap.
    // Confirmed as a real, live-reported bug, not a hypothetical --
    // identical shape to the curatedRightIds fix above, just never
    // extended to this second group.
    var sourceIsCenterSpecial = sourceSlot && root.centerSpecialIds.indexOf(sourceSlot.moduleName) !== -1
    var sourceIsProtected = sourceSlot && root.protectedModuleIds.indexOf(sourceSlot.moduleName) !== -1

    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceIsCurated) {
        if (root.curatedRightIds.indexOf(slot.moduleName) === -1) continue
      } else if (sourceIsCenterSpecial) {
        if (root.centerSpecialIds.indexOf(slot.moduleName) === -1) continue
      } else if (!sourceIsProtected && root.protectedModuleIds.indexOf(slot.moduleName) !== -1) {
        continue
      }
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue

      var slotPoint = { x: slot.x, y: slot.y }
      try {
        slotPoint = slot.mapToItem(null, 0, 0)
      } catch (e) {
      }

      candidates.push({
        slot: slot,
        x: slotPoint.x,
        y: slotPoint.y,
        width: slot.width,
        height: slot.height
      })
    }

    return BarModel.nearestDropTarget(candidates, scenePoint, root.vertical)
  }

  function visibleModuleSlot(region, name, sourceSlot) {
    var sourceWindow = root.slotWindow(sourceSlot) || root.barDragWindow
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || slot.region !== region || slot.moduleName !== name ||
          !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (sourceWindow && !root.sameWindow(root.slotWindow(slot), sourceWindow)) continue
      return slot
    }

    return null
  }

  function nextVisibleModuleName(region, afterName, sourceSlot) {
    var entries = layoutEntries(region)
    var found = false
    for (var i = 0; i < entries.length; i++) {
      var name = entryId(entries[i])
      if (!found) {
        found = name === afterName
        continue
      }

      if (visibleModuleSlot(region, name, sourceSlot)) return name
    }

    return ""
  }

  function dropBarModuleAtTarget(sourceSlot, targetSlot, afterTarget) {
    if (!sourceSlot || !targetSlot) return false

    var beforeName = afterTarget ? nextVisibleModuleName(targetSlot.region, targetSlot.moduleName, sourceSlot) : targetSlot.moduleName
    return dropBarModule(sourceSlot, targetSlot.region, beforeName)
  }

  function moduleTargetClickable(target) {
    return target
      && target.visible !== false
      && target.opacity !== 0
      && target.interactive !== false
      && target.pressable !== false
      && target.concealed !== true
      && typeof target.triggerPress === "function"
  }

  function moduleClickTargetAt(slot, localX, localY) {
    for (var i = clickTargets.length - 1; i >= 0; i--) {
      var target = clickTargets[i]
      if (!moduleTargetClickable(target)) continue

      var targetPoint = { x: localX, y: localY }
      try {
        targetPoint = slot.mapToItem(target, localX, localY)
      } catch (e) {
        continue
      }

      if (targetPoint.x >= 0 && targetPoint.x <= target.width &&
          targetPoint.y >= 0 && targetPoint.y <= target.height) {
        return target
      }
    }

    if (moduleTargetClickable(slot.activeItem)) return slot.activeItem
    return null
  }

  function pressModuleClickTarget(slot, button, localX, localY) {
    var target = moduleClickTargetAt(slot, localX, localY)
    if (!target) return false

    target.triggerPress(button)
    return true
  }

  function colorHex(colorValue) {
    var c = colorValue
    if (typeof c === "string") c = Qt.color(c)
    function hexChannel(value) {
      var s = Math.round(Util.clamp(value, 0, 1) * 255).toString(16)
      return s.length < 2 ? "0" + s : s
    }
    return "#" + hexChannel(c.r) + hexChannel(c.g) + hexChannel(c.b)
  }

  function setRequestedTransparency(value) {
    var nextTransparent = value === true
    requestedTransparent = nextTransparent
    if (!nextTransparent) {
      foregroundAnimationEnabled = false
      useTransparentForeground = false
      transparent = false
      transparentForeground = themeForeground
      restoreForegroundAnimation()
      return
    }
    scheduleTransparentForegroundRefresh()
  }

  function restoreForegroundAnimation() {
    Qt.callLater(function() {
      Qt.callLater(function() { root.foregroundAnimationEnabled = true })
    })
  }

  function scheduleTransparentForegroundRefresh() {
    if (!requestedTransparent) {
      transparentForeground = themeForeground
      return
    }
    transparentForegroundTimer.restart()
  }

  function refreshTransparentForeground() {
    if (!requestedTransparent || transparentForegroundProc.running) return

    transparentForegroundProc.command = [
      "omarchy-bar-text-color",
      root.position,
      String(root.barSize),
      colorHex(root.themeForeground),
      colorHex(root.themeContrastForeground)
    ]
    transparentForegroundProc.running = true
  }

  onRequestedTransparentChanged: scheduleTransparentForegroundRefresh()
  // Also re-syncs gaps_out.top (see that function's own comment) --
  // QML only allows one onPositionChanged handler per Item, so this
  // rides along with the pre-existing one rather than declaring a
  // second (confirmed live: a second onPositionChanged elsewhere in
  // this same file failed the whole plugin to load with "Property
  // value set multiple times").
  onPositionChanged: { scheduleTransparentForegroundRefresh(); root.syncGapsOutForTopBarVisibility() }
  onThemeForegroundChanged: scheduleTransparentForegroundRefresh()
  onThemeContrastForegroundChanged: scheduleTransparentForegroundRefresh()

  Timer {
    id: transparentForegroundTimer
    interval: 120
    repeat: false
    onTriggered: root.refreshTransparentForeground()
  }

  Process {
    id: transparentForegroundProc
    stdout: SplitParser {
      onRead: function(line) {
        var value = String(line || "").trim()
        if (!/^#[0-9A-Fa-f]{6}$/.test(value)) return

        root.foregroundAnimationEnabled = false
        root.transparentForeground = value
        if (root.requestedTransparent) {
          root.useTransparentForeground = true
          root.transparent = true
        }
        root.restoreForegroundAnimation()
      }
    }
  }

  FileView {
    path: root.stateHome + "/omarchy/current"
    watchChanges: true
    printErrors: false
    onFileChanged: root.scheduleTransparentForegroundRefresh()
  }

  function runProcess(process) {
    if (!process.running)
      process.running = true
  }

  function showTooltip(target, text) {
    clearTooltip()

    if (!targetTooltipHovered(target) || !text) {
      tooltipRequest += 1
      return
    }

    var request = tooltipRequest + 1
    tooltipRequest = request
    pendingTooltipTarget = target
    pendingTooltipText = text

    Qt.callLater(function() {
      if (request !== tooltipRequest) return
      if (!targetTooltipHovered(pendingTooltipTarget)) {
        clearTooltip()
        return
      }
      tooltipTarget = pendingTooltipTarget
      tooltipText = pendingTooltipText
      pendingTooltipTarget = null
      pendingTooltipText = ""
      tooltipTimer.restart()
    })
  }

  function hideTooltip(target) {
    if (tooltipTarget !== target && pendingTooltipTarget !== target) return

    tooltipRequest += 1
    clearTooltip()
  }

  Timer {
    id: tooltipTimer
    interval: 400
    onTriggered: {
      if (root.targetTooltipHovered(root.tooltipTarget)) root.tooltipShown = true
      else root.clearTooltip()
    }
  }

  Timer {
    interval: 100
    running: root.tooltipShown
    repeat: true
    onTriggered: if (!root.targetTooltipHovered(root.tooltipTarget)) root.hideTooltip(root.tooltipTarget)
  }

  // Presence of the `bar-off` flag = bar hidden. Watching the parent toggles
  // directory because FileView can't observe a file that doesn't exist yet,
  // and the flag is created/removed by `omarchy-toggle-bar`.
  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }
  FileView {
    path: root.home + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  // Direct follow-up chain: hyprland/looknfeel.ruixen.lua's own
  // gaps_out.top (10, both round/square variants) is deliberately
  // smaller than the other three (20) on the assumption that the bar's
  // own exclusiveZone reservation already provides real top clearance
  // independent of gaps -- true only while the bar is actually VISIBLE.
  // Hiding it (Super+Shift+Space, ExclusionMode.Ignore) drops that
  // reservation, leaving the bare 10 read as visibly tighter than the
  // bottom's 20 ("it gets too close to the top edge compare to bottom
  // edge"). A static bump to 20 fixed that but overcorrected the far
  // more common bar-visible case instead ("that kinda messed up...
  // extra padding now the top is more than the bottom") -- no single
  // static value gets both right, since gaps_out.top sits BELOW the
  // reservation, not instead of it. This pushes a live override
  // instead: `hyprctl eval` (not `hyprctl keyword`, confirmed live --
  // this Hyprland config uses the Lua-based `hl.config` API, and
  // `keyword` refuses to touch it: "keyword can't work with non-legacy
  // parsers. Use eval") sets gaps_out.top to 20 for exactly as long as
  // the bar is actually hidden, and back to 10 the moment it's shown
  // again. The other three positions never had this asymmetry to begin
  // with (their own edge's gap was already 20 in the static config,
  // un-offset by any exclusiveZone reservation) -- top only needs the
  // override while BOTH root.position === "top" AND root.barHidden are
  // true, computed as one explicit expression rather than an early
  // return so this stays correct even if position changes while hidden
  // (moving the bar away from top while it's toggled off correctly
  // reverts gaps_out.top to 10, not left stuck at 20 for an edge the
  // bar no longer occupies).
  function syncGapsOutForTopBarVisibility() {
    var top = (root.position === "top" && root.barHidden) ? 20 : 10
    gapsOutSyncProc.exec(["hyprctl", "eval",
      "hl.config({general = {gaps_out = {top = " + top + ", right = 20, bottom = 20, left = 20}}})"])
  }
  Process { id: gapsOutSyncProc }
  onBarHiddenChanged: root.syncGapsOutForTopBarVisibility()

  Variants {
    model: Quickshell.screens

    delegate: Component {
      FrameWindow {
        required property var modelData

        screen: modelData
        barRoot: root
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData

        screen: modelData
        barRoot: root
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      DragGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
        barRoot: root
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarMoveGhostPanel {
        required property var modelData

        screen: modelData
        ghostScreen: modelData
        barRoot: root
      }
    }
  }

  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

}
