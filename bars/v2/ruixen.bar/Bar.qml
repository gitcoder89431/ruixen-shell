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
  // Every pill (component GroupPill below) is hardcoded OLED black
  // regardless of theme. Color.bar.text (the theme's body-text color) is
  // fine against that on almost every theme -- checked across Aura Soft,
  // Everforest, Gruvbox, Nord, Catppuccin, Tokyo Night: foreground is
  // already light/off-white on all of them, since that's what "readable
  // body text" means on a dark theme. Two real exceptions: light themes
  // (e.g. "White"), where foreground flips near-black for readability on
  // THAT theme's own light background, and Rose Pine specifically, a
  // dark theme whose foreground (#575279, a muted dark purple) is still
  // too dark against black despite the theme itself being dark-mode.
  // Neither is a light/dark toggle -- it's actual luminance -- so measure
  // it directly and only fall back to a fixed light color when the
  // theme's own foreground genuinely wouldn't read, instead of
  // overriding every theme's icon color wholesale (an earlier pass tried
  // Color.accent for this and lost each theme's actual look for no
  // reason, since accent is a single "pop" hue, not the resting
  // icon/text color stock Omarchy uses).
  readonly property real themeForegroundLuminance: 0.299 * themeForeground.r + 0.587 * themeForeground.g + 0.114 * themeForeground.b
  readonly property color safeForeground: "#e8e8e8"
  // themeForeground itself is left theme-following since it also feeds
  // the legacy transparent-bar wallpaper-contrast script below
  // (omarchy-bar-text-color). Most stock widgets (network, audio,
  // bluetooth, etc.) read bar.foreground directly for their icon/text
  // color, not bar.barForeground (that one only feeds WidgetButton's own
  // default + a few of our pill decorations) -- both need to be pinned,
  // not just one, or half the icons stay theme-black.
  //
  // barForeground is unconditionally pillForeground, NOT gated on
  // useTransparentForeground -- that whole subsystem (requestedTransparent
  // / omarchy-bar-text-color) exists for the *stock* bar's fully
  // see-through mode, picking a contrasting text color against whatever
  // wallpaper shows through. Our GroupPills are always opaque OLED black
  // regardless of shell.json's bar.transparent setting, so that script's
  // answer (frequently black, e.g. against a light wallpaper) has nothing
  // to do with what's actually readable against our pills, and was
  // silently winning over this fix whenever bar.transparent was on.
  readonly property color pillForeground: themeForegroundLuminance > 0.45 ? themeForeground : safeForeground
  property color foreground: pillForeground
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

  // Sharp+docked only: whether leftDockedBg below should span the full
  // window width instead of just the left widget group -- direct
  // request, "make the topbar a full black strip so it runs under the
  // notch too" (a traditional single continuous Waybar-style bar, not
  // two separate left/right groups with a wallpaper gap in the
  // middle). Deliberately NOT used for corner radius -- that stays
  // hardcoded 24 always when docked now (see leftDockedBg/rightDockedBg
  // below), matching ruixen.frame-widget's own corner, which also
  // always stays rounded when docked regardless of curvature (see
  // ruixen.frame-widget/Overlay.qml's own isDocked). Same read-once-at-
  // startup Process pattern as frame-widget's own variant read -- safe
  // because hyprland/ruixen-lookfeel.sh always does a full `omarchy
  // restart shell` on every variant change.
  property bool sharpCorners: false

  Process {
    id: readLookAndFeelVariantForDock
    command: ["bash", "-c", "readlink \"$HOME/.config/hypr/looknfeel.lua\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.sharpCorners = text.indexOf("looknfeel.square.lua") >= 0
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
  // Two independent choices, matching Settings' own Frame category:
  // WHERE the color comes from (frameColorMode: "custom", a user-picked
  // swatch, or "theme", live-tracking the active theme's own Color.background
  // -- see qs.Commons' own Color.qml, already the same singleton
  // themeContrastForeground above reads), and, only when custom, WHICH
  // color that is (frameCustomColor). Kept as two separate properties
  // rather than one resolved-and-cached color so a live theme switch
  // updates frameColor immediately in theme mode without this file
  // needing to re-read anything -- Color.background is already its own
  // live QML binding.
  property string frameColorMode: "custom"
  property color frameCustomColor: "#000000"
  readonly property color frameColor: root.frameColorMode === "theme" ? Color.background : root.frameCustomColor
  // JSON, not the old plain-hex file -- two fields now, same convention
  // every other multi-field ruixen setting in this repo already uses
  // (see ruixen.cava's own cava-visualizer.json). Renamed off the old
  // frame-color path (never actually shipped -- no Settings UI wrote to
  // it, so there is no real user data to migrate) rather than trying to
  // read both formats.
  readonly property string frameColorStatePath: root.stateHome + "/ruixen/frame-appearance.json"

  // Always resets BOTH fields off the parsed result, never leaves either
  // at whatever it happened to be before this call -- direct live bug
  // found testing this: onLoadFailed used to be a bare no-op (fine for
  // the old single-hex-string version, which never changed away from its
  // own declared default without a file existing at all), but once a
  // MODE existed too, deleting the state file after switching to Theme
  // left frameColorMode stuck on "theme" forever instead of reverting --
  // nothing was left to reset it. Same shape as ruixen.cava's own
  // loadCavaState/onLoadFailed pattern, called with "" on failure.
  function loadFrameAppearance(raw) {
    try {
      var p = JSON.parse(String(raw || "").trim() || "{}")
      root.frameColorMode = (p && (p.mode === "theme" || p.mode === "custom")) ? p.mode : "custom"
      var c = p && p.customColor
      root.frameCustomColor = (typeof c === "string" && /^#[0-9a-fA-F]{6,8}$/.test(c)) ? c : "#000000"
    } catch (e) {
      root.frameColorMode = "custom"
      root.frameCustomColor = "#000000"
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
  readonly property var curatedRightIds: ["omarchy.system-update", "omarchy.power", "ruixen.quickactions", "ruixen.settingsbutton"]
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
    var r = BarModel.reservedCenterRect(root.notchReservedWidth, containerWidth, root.barSize)
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
      }
    }
  }

  Variants {
    model: Quickshell.screens

    delegate: Component {
      BarPanel {
        required property var modelData

        screen: modelData
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
      }
    }
  }

  // Tonal floating-pill background shared by each module group — same hue
  // as the theme's bar background (Color.bar.background), just opaque, so
  // each group reads as a "raised" island instead of the bar having one
  // continuous solid background.
  component GroupPill: Rectangle {
    radius: height / 2
    // Solid OLED black, matching ruixen.frame-widget's hardcoded
    // frameColor — was Color.bar.background (theme-linked) at 0.85
    // opacity, read as too close to transparent against the frame.
    color: "#000000"
    // Without this, a full circle (radius === width/2 === height/2, like
    // the solo menu pill) renders as a faceted octagon instead of a
    // smooth curve — much more visible than on a stadium shape (most of
    // that outline is straight, only the two end-caps curve).
    antialiasing: true

    // Direct follow-up after the settings card's own shadow ("try the
    // pill next then") -- every floating pill in the bar shares this
    // one component, so adding it here covers all of them uniformly.
    // Lower risk than ruixen.notch's own attempt (reverted, see that
    // file's own comment): GroupPill is a plain Rectangle with no
    // existing mask/effect stacking to interact with, unlike notchBg's
    // own MultiEffect which was already doing custom silhouette
    // masking before shadow properties were added to it.
    //
    // Tighter and darker than the first pass -- direct correction ("the
    // draw is too far, it looks like faded, gotta closer and darker"):
    // blur 0.3 -> 0.15 and offset 3 -> 1 pull the shadow in close to
    // the pill's own edge instead of spreading/softening it into a
    // faded halo; opacity 0.6 -> 0.8 makes it read as a real shadow
    // rather than a faint tint.
    layer.enabled: true
    layer.effect: MultiEffect {
      shadowEnabled: true
      shadowColor: "#000000"
      shadowOpacity: 0.8
      shadowBlur: 0.15
      shadowVerticalOffset: 1
    }
  }

  // The small concave wing piece a shape needs ADDED at a corner to flow
  // smoothly into whatever continues past its edge, not a Rectangle
  // corner cut (which recedes into the shape instead) -- a standard
  // technique for this (a quarter-circle arc plus a straight line back
  // to the box's own sharp corner) common to plenty of canvas-based UI
  // work, written here as a data table rather than a branch per corner.
  // Used for the docked pill groups' open-facing shoulder, same
  // technique ruixen.notch's own two shoulders use.
  component RoundCorner: Item {
    id: cornerRoot
    // Plain strings, not an enum -- a `component`-local enum's
    // qualified values don't resolve from inside an inline component.
    // One of: "topLeft", "topRight", "bottomLeft", "bottomRight".
    property string corner: "topLeft"
    property int size: 25
    property color color: "#000000"

    onColorChanged: cornerCanvas.requestPaint()
    onCornerChanged: cornerCanvas.requestPaint()
    onSizeChanged: cornerCanvas.requestPaint()
    onVisibleChanged: if (visible) cornerCanvas.requestPaint()

    // implicitWidth/Height alone only sizes this when something else (a
    // Layout, or a wrapper's anchors.fill) reads it -- placed as a bare
    // sibling Item like it is below, that never happens and it
    // silently renders at 0x0. Set the real size directly.
    width: size
    height: size
    implicitWidth: size
    implicitHeight: size

    // Every corner's wedge is the same shape, just rotated 90 degrees
    // at a time: a quarter-circle arc of radius `size`, centered on the
    // box's DIAGONALLY OPPOSITE corner (so the arc passes exactly
    // through the box's other two corners), closed off by a straight
    // line back to this wedge's own sharp corner. centerX/centerY/
    // pointX/pointY below are 0-or-1 multipliers of `size`, not raw
    // pixel values, so the same four numbers describe all four corners
    // without repeating a size-dependent literal per case.
    readonly property var cornerGeometry: ({
      topLeft: { centerX: 1, centerY: 1, startAngle: Math.PI, endAngle: 1.5 * Math.PI, pointX: 0, pointY: 0 },
      topRight: { centerX: 0, centerY: 1, startAngle: 1.5 * Math.PI, endAngle: 2 * Math.PI, pointX: 1, pointY: 0 },
      bottomLeft: { centerX: 1, centerY: 0, startAngle: 0.5 * Math.PI, endAngle: Math.PI, pointX: 0, pointY: 1 },
      bottomRight: { centerX: 0, centerY: 0, startAngle: 0, endAngle: 0.5 * Math.PI, pointX: 1, pointY: 1 }
    })

    Canvas {
      id: cornerCanvas
      anchors.fill: parent
      antialiasing: true
      onPaint: {
        var ctx = getContext("2d")
        var size = cornerRoot.size
        var g = cornerRoot.cornerGeometry[cornerRoot.corner]
        ctx.clearRect(0, 0, width, height)
        if (!g) return

        ctx.beginPath()
        ctx.arc(g.centerX * size, g.centerY * size, size, g.startAngle, g.endAngle)
        ctx.lineTo(g.pointX * size, g.pointY * size)
        ctx.closePath()
        ctx.fillStyle = cornerRoot.color
        ctx.fill()
      }
    }
  }

  // The shell's own decorative border, as its own fullscreen, always-
  // click-through window -- ported from v1 ruixen.frame-widget's own
  // Canvas hole-punch technique (fill, then punch a rounded-rect hole
  // out with destination-out compositing), reading root.frameInset/
  // root.frameColor/root.docked/root.sharpCorners directly instead of
  // re-deriving independent copies of them (v1's frame-widget had to
  // shell out to read shell.json/looknfeel.lua itself; this bar already
  // has all of that live on root). Still ONE authoritative Canvas for
  // all four edges, unlike v1's two-plugin split -- that part of the
  // original fix stands. BarPanel below is what changed back: it tried
  // living in THIS SAME window for one pass (a genuinely fullscreen
  // BarPanel), which fixed the frame/bar seam completely but broke
  // exclusiveZone (see BarPanel's own comment) and broke every stock
  // Omarchy popup on this bar (weather/clock/agents read this window's
  // REAL height for their own positioning -- fullscreen made that the
  // whole screen instead of the bar's real strip, direct live report:
  // "shows up very small on the bottom"). Splitting BarPanel back out
  // fixes both without giving up the frame's own single-Canvas fix --
  // BarPanel's own comment explains how the seam stays covered even
  // though these are two separate surfaces again.
  component FrameWindow: PanelWindow {
    id: frameWindow

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
        target: root
        function onFrameColorChanged() { frameCanvas.requestPaint() }
        function onSharpCornersChanged() { frameCanvas.requestPaint() }
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
      // clipping risk to avoid by going square there).
      readonly property int frameCornerRadius: (!root.docked && root.sharpCorners) ? 0 : 24

      // Neutral black regardless of frameColor, same reasoning a real
      // physical shadow doesn't tint with its caster's own color --
      // direct request, after Themed mode shipped: "the surface looks
      // kinda faded", same depth-cue omacalestria/calestria shell's own
      // frame bezels use. Fixed constants for now, not exposed in
      // Settings -- these need live tuning against an actual affected
      // machine/theme before they're worth turning into a real knob.
      //
      // Qt.rgba(), not an 8-digit hex string -- direct live report ("the
      // shadow looks grey... i was expecting a darker dropshadow like
      // our hyprland windows"), root-caused, not just retuned: QML's own
      // color type parses "#8f000000" alpha-FIRST (Qt convention), but
      // Canvas 2D's own CSS-style color parser expects alpha-LAST
      // (#RRGGBBAA) once that value round-trips through
      // ctx.shadowColor/strokeStyle as a string -- the hex string was
      // being reinterpreted under the wrong convention, landing on a
      // much weaker, greyer result than "black at ~0.56 alpha" ever
      // intended. Qt.rgba(r, g, b, a) is unambiguous regardless of which
      // convention the Canvas string parser assumes, since it's a real
      // color value, never re-parsed as a string at all. Pushed darker
      // at the same time (0.55 -> 0.8 alpha) to actually read as a real
      // drop shadow, closer to Hyprland's own default window shadow
      // weight, not just fixing the parsing bug at the old faint value.
      readonly property color shadowColor: Qt.rgba(0, 0, 0, 0.8)
      readonly property int shadowBlurPx: 18
      readonly property int shadowWidthPx: 10

      onPaint: {
        const ctx = getContext("2d")
        ctx.clearRect(0, 0, width, height)
        ctx.fillStyle = root.frameColor
        ctx.fillRect(0, 0, width, height)
        ctx.globalCompositeOperation = "destination-out"
        roundedRect(ctx, root.frameInset, root.frameInset,
          width - root.frameInset * 2, height - root.frameInset * 2,
          frameCornerRadius)
        ctx.fill()
        ctx.globalCompositeOperation = "source-over"

        // Inner shadow along the hole's own inside edge, giving the
        // frame some depth instead of a flat color band -- standard
        // Canvas inner-shadow technique: clip to the hole itself, then
        // stroke that SAME path with shadowBlur/shadowColor set. The
        // clip means only the half of the stroke (and its blur falloff)
        // that falls inside the hole ever renders, reading as a soft
        // dark band hugging the frame's own inner edge and fading
        // toward whatever's visible through it.
        ctx.save()
        roundedRect(ctx, root.frameInset, root.frameInset,
          width - root.frameInset * 2, height - root.frameInset * 2,
          frameCornerRadius)
        ctx.clip()
        ctx.shadowColor = shadowColor
        ctx.shadowBlur = shadowBlurPx
        ctx.lineWidth = shadowWidthPx
        ctx.strokeStyle = shadowColor
        ctx.stroke()
        ctx.restore()
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

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
    // FrameWindow's edge in docked mode -- is handled by dockedSeamCover
    // below: a plain frameColor-filled Rectangle, deliberately painted
    // a few pixels WIDER than the gap it's covering, sitting on a higher
    // layer than FrameWindow. Two independent surfaces can still round
    // their own edges to slightly different physical pixels under a
    // fractional scale -- that was never fixable by trying harder to
    // agree on a shared number, only by making it not matter. A few
    // pixels of deliberate overlap, painted the same color as the thing
    // underneath, absorbs that disagreement completely: whichever
    // physical pixel FrameWindow's own edge actually lands on, it's
    // already covered by this window's own matching-color paint before
    // it could ever show through as a wallpaper sliver.
    visible: !remapGuard.remapping
    exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Normal
    // + seamOverlap, top position only -- margin.top below only gives up
    // those pixels when position === "top" (see its own comment), so
    // this only needs to pick them back up in that same case. Total
    // real-window reservation (margin.top + exclusiveZone) stays the
    // true v1 value (44) either way -- direct live report, again: the
    // first pass at this overlap trick forgot this compensation and the
    // reserved gap came out seamOverlap px too shallow, same class of
    // miss as the ReservationPanel one before it.
    exclusiveZone: root.docked
      ? (44 - root.frameInset + (root.position === "top" ? root.seamOverlap : 0))
      : root.notchClearance

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    margins {
      top: root.barHidden && root.position === "top" ? -root.barSize : (root.position === "top" ? root.contentTopInset - (root.docked ? root.seamOverlap : 0) : 0)
      bottom: root.barHidden && root.position === "bottom" ? -root.barSize : 0
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
      left: root.barHidden && root.position === "left" ? -root.barSize : (root.position === "top" ? root.frameInset - (root.docked ? root.seamOverlap : 0) : 0)
      right: root.barHidden && root.position === "right" ? -root.barSize : (root.position === "top" ? root.frameInset - (root.docked ? root.seamOverlap : 0) : 0)
    }

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize : 0

    // Clears the Notch's own collapsed bottom edge (notchCollapsedBottomEdge,
    // from ruixen.notch's own service) -- direct live report: any popup
    // panel anchored off this window (weather's own, and stock Omarchy's
    // clock/agents popups -- all use qs.Ui's KeyboardPanel) opens at
    // `anchorWindow.height + gap` (KeyboardPanel.qml's own cardOrigin, not
    // editable -- it's a stock /usr/share/omarchy file), which had no
    // notion of ruixen.notch and let a popup open right underneath it.
    readonly property int visibleBarHeight: root.vertical ? root.barSize : Math.max(root.barSize + root.shoulderWingSize, root.notchCollapsedBottomEdge)
    // + seamOverlap -- this window's own top edge moved up by seamOverlap
    // (margins.top above), so its own height needs to grow by the same
    // amount to keep the BOTTOM edge (and thus anchorWindow.height/
    // visibleBarHeight-dependent popup math, and the real content below)
    // exactly where v1 always had it. contentOffset below is what keeps
    // the actual pill row's own on-screen position unchanged despite the
    // window itself now starting seamOverlap px higher.
    implicitHeight: root.vertical ? 0 : visibleBarHeight + root.seamOverlap

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
    // this -- root.frameInset + root.seamOverlap (9) double-counted
    // frameInset. This window's own top (BarPanel-local y=0) is ALREADY
    // at screen y = root.contentTopInset - root.seamOverlap, which for
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
      visible: root.docked && root.position === "top"
      anchors { top: parent.top; left: parent.left; right: parent.right }
      height: root.seamOverlap + 1
      color: root.frameColor
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
      visible: root.docked && root.position === "top"
      anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
      width: root.seamOverlap + 1
      color: root.frameColor
    }
    Rectangle {
      visible: root.docked && root.position === "top"
      anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
      width: root.seamOverlap + 1
      color: root.frameColor
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
      anchors.topMargin: (!root.vertical && root.docked && root.position === "top") ? root.seamOverlap : 0
      // Mirrors topMargin above, for margins.left/right's own matching
      // overlap reduction -- without this, leftDockedBg/leftShoulderWing/
      // leftFrameHemWing (all positioned off this Item's own x: 0) would
      // visibly shift outward by seamOverlap, past where they're meant to
      // flush against the frame's real rounded corner, into the newly-
      // reclaimed sliver the seam-cover strips above now own instead.
      anchors.leftMargin: (!root.vertical && root.docked && root.position === "top") ? root.seamOverlap : 0
      anchors.rightMargin: (!root.vertical && root.docked && root.position === "top") ? root.seamOverlap : 0

      Loader {
        anchors.fill: parent
        sourceComponent: root.vertical ? verticalBar : horizontalBar

        // A child of the loader, not a sibling of the sections: an ancestor stays
        // hovered while the pointer is over a widget, where a sibling would lose
        // hover to the section the pointer entered.
        HoverHandler {
          onHoveredChanged: root.setBarHovered(hovered)
          // Unplugging a monitor destroys its bar without a leave event, which
          // would strand this surface's tally and hold the peek open for good.
          Component.onDestruction: if (hovered) root.setBarHovered(false)
        }
      }
    }

    PopupWindow {
      id: tooltipWindow

      visible: root.tooltipShown && root.tooltipTarget !== null && root.tooltipText !== "" && root.targetBelongsToWindow(root.tooltipTarget, barWindow)
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
          var target = root.tooltipTarget
          if (!root.targetBelongsToWindow(target, barWindow)) return

          var popupWidth = tooltipWindow.implicitWidth
          var popupHeight = tooltipWindow.implicitHeight
          var localX = target.width / 2 - popupWidth / 2
          var localY = target.height + 6

          if (root.position === "bottom") {
            localY = -popupHeight - 6
          } else if (root.position === "left") {
            localX = target.width + 6
            localY = target.height / 2 - popupHeight / 2
          } else if (root.position === "right") {
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
          text: root.tooltipText
          color: Color.tooltip.text
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }

    Component {
      id: horizontalBar

      Item {
        anchors.fill: parent

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
        Rectangle {
          id: leftDockedBg
          visible: root.docked
          x: 0
          y: 0
          // Rounded mode: just the left group's own width, unchanged.
          // Sharp mode: the FULL window width (see root.sharpCorners'
          // own comment above). rightDockedBg below is hidden in this
          // mode since this one now covers its entire area too.
          // ruixen.notch is a separate overlay window on its own layer,
          // already rendered on top of this one regardless of what's
          // drawn here, so extending underneath it needs no z-order
          // change.
          width: root.sharpCorners ? parent.width : (settingsPill.x + settingsPill.width)
          // root.barSize, not parent.height -- parent (the outer Item,
          // sized to the whole window) is taller than the pill row when
          // docked, to make room for leftFrameTaper below. This piece is
          // just the pill row itself.
          height: root.barSize
          color: "#000000"
          antialiasing: true
          // Matches ruixen.frame-widget's own cornerRadius (24) exactly --
          // this corner sits at the same point the frame's rounded-rect
          // hole starts (see BarPanel's margins above: frameInset used for
          // top too when docked, not topInset, specifically so this lines
          // up).
          topLeftRadius: 24
          // Rounded mode: 0, square -- this edge butts against
          // leftShoulderWing right after it, same as always. Sharp
          // mode: leftDockedBg's own right edge IS the true screen
          // edge now (full width, see width above), so it needs to
          // match frame's own rounded corner there too, same as
          // topLeftRadius does on the left -- direct live report,
          // after the wing-hiding attempt was reverted for being the
          // wrong fix: "the top bar corner is still missing or has a
          // wierd curve on the black full width we added."
          topRightRadius: root.sharpCorners ? root.shoulderWingSize : 0
          // Square, not a plain recede curve -- the actual concave wrap
          // (per direct request: "the smooth curve should face inward")
          // is leftFrameHemWing below, in its own dedicated space
          // (root.shoulderWingSize, added to BarPanel's implicitHeight
          // when docked). Squaring this off keeps it a flush, seamless
          // hand-off into that wing rather than competing with
          // topLeftRadius for room on the same 34px edge.
          bottomLeftRadius: 0
          // Rounded mode: the real shoulder, matches shoulderWingSize
          // (24) -- a flush concave hand-off into leftShoulderWing
          // right after this edge, same as always. Sharp mode:
          // leftShoulderWing sits off-screen now (positioned at
          // leftDockedBg.x + leftDockedBg.width, which is parent.width
          // when full-width -- past the true right edge, effectively
          // moot), so there's nothing left to hand off to; a concave
          // cut here with nothing filling it would just notch a bite
          // of wallpaper out of the strip's own true bottom-right
          // corner. Flat (0) instead, matching the strip's plain
          // bottom edge everywhere else.
          bottomRightRadius: root.sharpCorners ? 0 : root.shoulderWingSize
        }

        // A small square sitting immediately past the body's own right
        // edge, corner: topLeft. Same size as leftDockedBg's own
        // bottomRightRadius above (24), not the full pill height -- a
        // shoulder wing needs to be a small square matched to its
        // body's own corner radius, not a full-height piece; that
        // mismatch was the earlier bug.
        RoundCorner {
          id: leftShoulderWing
          visible: root.docked
          corner: "topLeft"
          size: root.shoulderWingSize
          color: "#000000"
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
        RoundCorner {
          id: leftFrameHemWing
          visible: root.docked
          corner: "topLeft"
          size: root.shoulderWingSize
          color: "#000000"
          x: 0
          y: leftDockedBg.height
        }

        Rectangle {
          id: rightDockedBg
          // Hidden in sharp mode -- leftDockedBg above already spans
          // the full window width there, covering this piece's entire
          // area.
          visible: root.docked && !root.sharpCorners
          x: trayPill.x
          y: 0
          width: parent.width - trayPill.x
          height: root.barSize
          color: "#000000"
          antialiasing: true
          topRightRadius: 24
          topLeftRadius: 0
          // Mirrors leftDockedBg's own bottomLeftRadius -- see its comment.
          bottomRightRadius: 0
          // Mirrors leftDockedBg's own bottomRightRadius -- see its comment.
          bottomLeftRadius: root.shoulderWingSize
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
          visible: root.docked
          corner: "topRight"
          size: root.shoulderWingSize
          color: "#000000"
          x: rightDockedBg.x - size + 1
          y: 0
        }

        // Mirrors leftFrameHemWing -- see its comment.
        RoundCorner {
          id: rightFrameHemWing
          visible: root.docked
          corner: "topRight"
          size: root.shoulderWingSize
          color: "#000000"
          x: rightDockedBg.x + rightDockedBg.width - size
          y: rightDockedBg.height
        }

        // Everything else (every pill's own content).
        Item {
          id: dockedRow
          anchors.top: parent.top
          anchors.left: parent.left
          anchors.right: parent.right
          height: root.barSize

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
          height: root.barSize - Style.space(2)

          // Hidden (not just repositioned) when docked -- the merged
          // leftDockedBg/rightDockedBg below take over the background for
          // every pill in their group, this pill's own icons just sit on
          // top of that shared shape instead of their own floating pill.
          GroupPill { anchors.fill: parent; visible: !root.docked }

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
              entry: root.layoutEntries("center").filter(function(e) { return root.entryId(e) === "ruixen.weather" })[0] || null
              region: "center"
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
              entry: root.layoutEntries("center").filter(function(e) { return root.entryId(e) === "omarchy.clock" })[0] || null
              region: "center"
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
        // root.reservedCenterRect instead, so this content sits in the
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
          readonly property rect reservedRect: root.reservedCenterRect(parent ? parent.width : 0)
          opacity: centerGenericContent.width > 0 ? 1 : 0
          x: reservedRect.x + reservedRect.width + 12
          anchors.verticalCenter: parent.verticalCenter
          width: centerGenericContent.width + 8 * 2
          height: root.barSize - Style.space(2)

          // Hidden (not just repositioned) when docked -- the merged
          // leftDockedBg/rightDockedBg below take over the background for
          // every pill in their group, this pill's own icons just sit on
          // top of that shared shape instead of their own floating pill.
          GroupPill { anchors.fill: parent; visible: !root.docked }

          ModuleList {
            id: centerGenericContent
            anchors.centerIn: parent
            entries: root.layoutEntries("center").filter(function(e) {
              return root.centerSpecialIds.indexOf(root.entryId(e)) === -1
            })
            region: "center"
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
          // GroupPill is hidden (visible: !root.docked below) and
          // replaced by one continuous leftDockedBg shape flush with the
          // frame's corner, so the reasoning that justified trimming
          // this down from 20 doesn't hold there -- direct live report
          // ("the app icons group... too close to the edge... needs to
          // be relaxed") confirmed 12 alone reads as cramped without a
          // pill boundary to lean on. Reverting to the original,
          // already-tuned 20 specifically for docked rather than
          // guessing a new number.
          anchors.leftMargin: root.docked ? 20 : 12
          anchors.verticalCenter: parent.verticalCenter
          // Side padding trimmed from 8 to 4 per direct request ("making
          // the canvas pill thing a bit less wide? more rounded?") --
          // GroupPill's own radius is already height/2 (the max stadium
          // curve), so there was no more roundness to add directly; a
          // single-icon pill this close to square just reads rounder at
          // the same radius as its width shrinks toward its own height.
          width: menuContent.width + 4 * 2
          height: root.barSize - Style.space(2)

          // Hidden (not just repositioned) when docked -- the merged
          // leftDockedBg/rightDockedBg below take over the background for
          // every pill in their group, this pill's own icons just sit on
          // top of that shared shape instead of their own floating pill.
          GroupPill { anchors.fill: parent; visible: !root.docked }

          ModuleList {
            id: menuContent
            anchors.centerIn: parent
            entries: root.layoutEntries("left").filter(function(e) { return root.entryId(e) === "ruixen.applauncher" })
            region: "left"
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
          height: root.barSize - Style.space(2)

          // Hidden (not just repositioned) when docked -- the merged
          // leftDockedBg/rightDockedBg below take over the background for
          // every pill in their group, this pill's own icons just sit on
          // top of that shared shape instead of their own floating pill.
          GroupPill { anchors.fill: parent; visible: !root.docked }

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
            entries: root.layoutEntries("left").filter(function(e) {
              return root.entryId(e) === "ruixen.workspaces"
            })
            region: "left"
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
          height: root.barSize - Style.space(2)

          // Hidden (not just repositioned) when docked -- the merged
          // leftDockedBg/rightDockedBg below take over the background for
          // every pill in their group, this pill's own icons just sit on
          // top of that shared shape instead of their own floating pill.
          GroupPill { anchors.fill: parent; visible: !root.docked }

          ModuleList {
            id: pinnedappsContent
            anchors.centerIn: parent
            entries: root.layoutEntries("left").filter(function(e) {
              return root.entryId(e) === "ruixen.pinnedapps"
            })
            region: "left"
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
          height: root.barSize - Style.space(2)

          GroupPill { anchors.fill: parent; visible: !root.docked }

          ModuleList {
            id: leftPluginPinsContent
            anchors.centerIn: parent
            entries: root.layoutEntries("left").filter(function(e) {
              var id = root.entryId(e)
              return id !== "ruixen.applauncher" && id !== "ruixen.workspaces"
                && id !== "ruixen.pinnedapps" && id !== "ruixen.settingsbutton"
            })
            region: "left"
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
          height: root.barSize - Style.space(2)

          // Hidden (not just repositioned) when docked -- the merged
          // leftDockedBg/rightDockedBg below take over the background for
          // every pill in their group, this pill's own icons just sit on
          // top of that shared shape instead of their own floating pill.
          GroupPill { anchors.fill: parent; visible: !root.docked }

          ModuleList {
            id: settingsContent
            anchors.centerIn: parent
            entries: root.layoutEntries("left").filter(function(e) {
              return root.entryId(e) === "ruixen.settingsbutton"
            })
            region: "left"
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
          height: root.barSize - Style.space(2)

          // Hidden (not just repositioned) when docked -- the merged
          // leftDockedBg/rightDockedBg below take over the background for
          // every pill in their group, this pill's own icons just sit on
          // top of that shared shape instead of their own floating pill.
          GroupPill { anchors.fill: parent; visible: !root.docked }

          ModuleList {
            id: curatedContent
            anchors.centerIn: parent
            entries: root.layoutEntries("right").filter(function(e) {
              return root.curatedRightIds.indexOf(root.entryId(e)) !== -1
            })
            region: "right"
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
          height: root.barSize - Style.space(2)

          GroupPill { anchors.fill: parent; visible: !root.docked }

          ModuleList {
            id: pluginPinsContent
            anchors.right: pluginPinsToggle.left
            anchors.verticalCenter: parent.verticalCenter
            entries: root.layoutEntries("right").filter(function(e) {
              var id = root.entryId(e)
              return id !== "ruixen.tray" && id !== "ruixen.pluginpins" && root.curatedRightIds.indexOf(id) === -1
            })
            region: "right"
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
            entry: root.layoutEntries("right").filter(function(e) { return root.entryId(e) === "ruixen.pluginpins" })[0] || null
            region: "right"
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
          readonly property int leftPad: root.docked ? 20 : 8
          width: trayContent.width + 8 + leftPad
          height: root.barSize - Style.space(2)

          // Hidden (not just repositioned) when docked -- the merged
          // leftDockedBg/rightDockedBg below take over the background for
          // every pill in their group, this pill's own icons just sit on
          // top of that shared shape instead of their own floating pill.
          GroupPill { anchors.fill: parent; visible: !root.docked }

          ModuleList {
            id: trayContent
            anchors.right: parent.right
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            entries: root.layoutEntries("right").filter(function(e) { return root.entryId(e) === "ruixen.tray" })
            region: "right"
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

        CenterModules { anchors.fill: parent }

        LeftModules {
          anchors.top: parent.top
          anchors.topMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }

        RightModules {
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(8)
          anchors.horizontalCenter: parent.horizontalCenter
        }
      }
    }
  }

  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }

  component DragGhostPanel: PanelWindow {
    id: ghostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barDragScreen === ghostScreen ||
      (root.barDragScreen && ghostScreen && root.barDragScreen.name && ghostScreen.name && root.barDragScreen.name === ghostScreen.name)
    readonly property bool active: root.barDragSource && root.barDragScreen && screenMatches
    readonly property var sourceItem: root.barDragSource ? root.barDragSource.activeItem : null
    readonly property int ghostPadding: Style.space(1)
    readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
    readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

    visible: active && sourceItem !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-drag-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only drag feedback. Keep the input region empty so the ghost can
    // sit under the cursor without stealing the MouseArea's active pointer grab.
    mask: Region {}

    Item {
      visible: ghostWindow.visible
      x: Math.round(root.barDragScreenX - root.barDragOffsetX - ghostWindow.ghostPadding)
      y: Math.round(root.barDragScreenY - root.barDragOffsetY - ghostWindow.ghostPadding)
      width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
      height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

      BorderSurface {
        anchors.fill: parent
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        radius: Math.min(Style.cornerRadius, height / 2)
        opacity: root.transparent ? 0.45 : 0.94
      }

      Image {
        anchors.fill: parent
        anchors.margins: ghostWindow.ghostPadding
        source: root.barDragImageUrl
        fillMode: Image.Stretch
        smooth: true
        opacity: 0.84
      }
    }

    Rectangle {
      readonly property var targetRect: root.barDragTargetGeometry

      visible: ghostWindow.active && targetRect !== null
      x: targetRect ? Math.round(targetRect.x) : 0
      y: targetRect ? Math.round(targetRect.y) : 0
      width: targetRect ? targetRect.width : 0
      height: targetRect ? targetRect.height : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
    }
  }

  component BarMoveGhostPanel: PanelWindow {
    id: moveGhostWindow

    required property var ghostScreen
    readonly property bool screenMatches: root.barMoveScreen === ghostScreen ||
      (root.barMoveScreen && ghostScreen && root.barMoveScreen.name && ghostScreen.name && root.barMoveScreen.name === ghostScreen.name)
    visible: root.barMoveActive && screenMatches
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-bar-move-ghost"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    anchors {
      top: true
      bottom: true
      left: true
      right: true
    }

    // Visual-only preview of the candidate edge. Keep the input region empty
    // so the overlay never steals the gesture area's active pointer grab.
    mask: Region {}

    // One fixed-geometry slab per edge, crossfaded on candidate changes.
    // Resizing a single slab between edges repaints mid-transition and
    // flickers; fading between static ones does not.
    Repeater {
      model: ["top", "bottom", "left", "right"]

      BorderSurface {
        id: edgeSlab

        required property string modelData
        readonly property bool edgeVertical: modelData === "left" || modelData === "right"
        readonly property int edgeSize: edgeVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

        x: modelData === "right" ? parent.width - edgeSize : 0
        y: modelData === "bottom" ? parent.height - edgeSize : 0
        width: edgeVertical ? edgeSize : parent.width
        height: edgeVertical ? parent.height : edgeSize
        color: root.transparent ? "transparent" : root.background
        borderSpec: Border.flat(root.barForeground, 1)
        visible: opacity > 0
        opacity: root.barMoveCandidate === modelData ? (root.transparent ? 0.45 : 0.7) : 0

        Behavior on opacity {
          NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
        }
      }
    }
  }

  function findCenterAnchorEntry() {
    var entries = root.layoutEntries("center")
    var idx = root.entryIndex(entries, root.centerAnchor)
    return idx === -1 ? null : entries[idx]
  }

  component LeftModules: ModuleList {
    entries: root.layoutEntries("left")
    region: "left"
  }

  component RightModules: ModuleList {
    entries: root.layoutEntries("right")
    region: "right"
  }

  component CenterModules: Item {
    id: centerRoot

    property var entries: root.layoutEntries("center")
    readonly property bool hasAnchor: root.entryIndex(entries, root.centerAnchor) !== -1
    readonly property var anchorEntry: root.findCenterAnchorEntry()

    Loader {
      anchors.fill: parent
      sourceComponent: root.vertical ? verticalCenterModules : horizontalCenterModules
    }

    Component {
      id: horizontalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.right: centerAnchorModule.left
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.left: centerAnchorModule.right
          anchors.verticalCenter: centerAnchorModule.verticalCenter
        }
      }
    }

    Component {
      id: verticalCenterModules

      Item {
        anchors.fill: parent

        CenterGestureArea { anchors.fill: parent }

        HoverHandler {
          onHoveredChanged: root.setCenterSectionHovered(hovered)
        }

        ModuleList {
          visible: !centerRoot.hasAnchor
          entries: centerRoot.entries
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesBefore(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.bottom: centerAnchorModule.top
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }

        ModuleSlot {
          id: centerAnchorModule
          visible: centerRoot.hasAnchor
          entry: centerRoot.anchorEntry
          region: "center"
          anchors.centerIn: parent
        }

        ModuleList {
          visible: centerRoot.hasAnchor
          entries: root.entriesAfter(centerRoot.entries, root.centerAnchor)
          region: "center"
          anchors.top: centerAnchorModule.bottom
          anchors.horizontalCenter: centerAnchorModule.horizontalCenter
        }
      }
    }
  }

  component CenterGestureArea: MouseArea {
    id: gestureArea

    property bool dragging: false
    property bool suppressClick: false
    property real pressedX: 0
    property real pressedY: 0
    readonly property real dragThreshold: Style.space(4)

    acceptedButtons: Qt.LeftButton
    cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
    pressAndHoldInterval: 200

    function startDrag(x, y) {
      // Disabled: ruixen.bar's inset/padding (frameInset, the extra
      // left/right content padding) is hardcoded for position === "top"
      // to clear ruixen.frame-widget's rounded corners. Dragging to
      // left/right/bottom would look wrong there — no matching insets for
      // those edges. Re-enable once those positions get their own inset
      // handling, if ever needed.
      return
    }

    onPressed: function(mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
    }

    onPressAndHold: function(mouse) {
      startDrag(mouse.x, mouse.y)
    }

    onPositionChanged: function(mouse) {
      if (!(mouse.buttons & Qt.LeftButton)) return

      if (!dragging) {
        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance < dragThreshold) return
        startDrag(mouse.x, mouse.y)
        return
      }

      var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
      root.updateBarMove(root.windowScreenPoint(scenePoint, root.barMoveWindow))
    }

    onReleased: function(mouse) {
      if (!dragging) return
      dragging = false
      suppressClick = true
      root.finishBarMove()
      mouse.accepted = true
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      root.clearBarMove()
    }

    onClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
      }
    }

    onDoubleClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        return
      }
      if (mouse.button === Qt.LeftButton) {
        root.toggleTransparency()
        mouse.accepted = true
      }
    }
  }

  component ModuleList: Loader {
    id: moduleListRoot

    property var entries: []
    property string region: ""

    visible: entries.length > 0
    // A hidden list must not build its modules. The center section declares
    // both an anchored and an unanchored arrangement and shows whichever
    // fits, so leaving the other one loaded mounts every center module
    // twice — two IPC handlers registered for the same target, two clocks
    // ticking, two of every timer and fetch behind them.
    active: visible && entries.length > 0
    sourceComponent: root.vertical ? verticalModuleList : horizontalModuleList
    width: item ? item.implicitWidth : 0
    height: item ? item.implicitHeight : 0

    Component {
      id: horizontalModuleList

      Row {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
          }
        }
      }
    }

    Component {
      id: verticalModuleList

      Column {
        spacing: 0

        Repeater {
          model: moduleListRoot.entries

          ModuleSlot {
            required property var modelData
            entry: modelData
            region: moduleListRoot.region
          }
        }
      }
    }
  }

  // ruixen-shell#67: every hosted widget used to get `bar = root` verbatim
  // -- ruixen.bar's own top-level Item, including its own `shell` (a
  // PluginShellApi scoped to "ruixen.bar"'s identity, not the widget's
  // own). One of these is created per ModuleSlot instead, so each widget
  // sees a facade scoped to ITS OWN moduleName.
  //
  // Every property/method below mirrors something real widgets already
  // read off `bar` today (audited across the repo) -- this is a pure
  // reshaping of the same contract, not a new one, so nothing that works
  // today should regress.
  component PluginBarFacade: QtObject {
    id: facade

    required property string moduleName

    readonly property color foreground: root.foreground
    readonly property string fontFamily: root.fontFamily
    readonly property color barForeground: root.barForeground
    readonly property bool foregroundAnimationEnabled: root.foregroundAnimationEnabled
    readonly property var barWidgetRegistry: root.barWidgetRegistry
    readonly property var barConfig: root.barConfig
    readonly property var layoutConfig: root.layoutConfig
    // The rest of this block: found missing live, after the first version
    // of this facade shipped -- Quickshell's own shared qs.Ui base
    // components (WidgetButton, PopupCard, KeyboardPanel, Panel -- every
    // widget in this repo extends one of these) read all of these off
    // `bar` too, and none of it showed up in a repo-only grep since none
    // of OUR OWN source calls it by name. Confirmed real usage in
    // /usr/share/omarchy/shell/Ui/*.qml, not just this repo.
    readonly property color background: root.background
    readonly property color urgent: root.urgent
    readonly property bool vertical: root.vertical
    readonly property int barSize: root.barSize
    readonly property string position: root.position
    readonly property var clickTargets: root.clickTargets
    // Found missing the same way, this time by actually tracing a real
    // reported bug (ruixen-shell popup-positioning regression) back to
    // its root: this is what ruixen.quickactions'/ruixen.pluginpins' own
    // PopupCard.margin needs to back out of PopupCard's own xdg-popup
    // surface-relative offset -- see either widget's own popup.margin
    // comment (originally added in 61ef0bd) for the full "why".
    readonly property int screenMarginTop: root.screenMarginTop
    readonly property var activePopout: root.activePopout

    // The one writable property in this contract (ruixen.weather/Panel.qml
    // sets it directly) -- kept in sync both ways via plain JS-expression
    // bindings, the same mechanism this whole file already relies on for
    // every other root-tracking property (no property alias used here --
    // untested whether alias resolution reaches into an inline `component`
    // the way plain expression bindings, proven throughout this file, do).
    property bool centerHoverRevealSuppressed: root.centerHoverRevealSuppressed
    onCenterHoverRevealSuppressedChanged: root.centerHoverRevealSuppressed = centerHoverRevealSuppressed

    function run(command) { return root.run(command) }
    function showTooltip(target, text) { return root.showTooltip(target, text) }
    function hideTooltip(target) { return root.hideTooltip(target) }
    function registerClickTarget(target) { return root.registerClickTarget(target) }
    function unregisterClickTarget(target) { return root.unregisterClickTarget(target) }
    function switchPanelFrom(owner, direction) { return root.switchPanelFrom(owner, direction) }
    function requestPopout(owner) { return root.requestPopout(owner) }
    function releasePopout(owner) { return root.releasePopout(owner) }
    function targetBelongsToWindow(target, window) { return root.targetBelongsToWindow(target, window) }
    function moduleWidgets(pluginId) { return root.moduleWidgets(pluginId) }

    // Correct per-widget scoping stops here -- see ruixen-shell#67.
    // pluginShellForBarEntry() is the real, public, host-exposed
    // mechanism for a replacement bar to obtain a facade scoped to a
    // SPECIFIC hosted widget's own id, instead of leaking ruixen.bar's
    // own. summon/hide/toggle/isPluginOpen/updateEntryInline now
    // correctly resolve to THIS widget's own identity through it.
    //
    // firstPartyServiceFor/mutateShellConfig deliberately still route
    // through root.shell (ruixen.bar's own, unchanged) -- confirmed by
    // reading shell.qml that pluginShellForBarEntry()'s own result never
    // wires _firstPartyServiceLookup or _mutateBarConfig, so scoping
    // those here too would silently break ruixen.stayawake/
    // ruixen.quickactions, which already call bar.shell.firstPartyServiceFor
    // successfully today via this exact path.
    //
    // serviceFor() deliberately still returns null: Omarchy has no
    // host-exposed mechanism for a replacement bar to obtain a
    // service-capable facade for a widget it hosts -- confirmed this is
    // an intentional trust boundary (only the trusted built-in bar can
    // call pluginShellForId(), see /usr/share/omarchy/shell/plugins/bar/
    // Bar.qml's own pluginBarApiFor()), not an oversight fixable from
    // here. That's what #11949/PR #11970 (unmerged, blocked on a real
    // security regression) are about.
    // A plain function, not a property binding -- pluginShellForBarEntry()
    // caches and mutates state on the host object as a side effect of
    // being called, and invoking that from inside a declarative binding
    // triggered a real "Binding loop detected" warning (confirmed live).
    // Calling it on demand instead avoids that entirely; the host's own
    // cache keeps repeat calls cheap.
    function _scopedEntry() {
      return (root.shell && typeof root.shell.pluginShellForBarEntry === "function")
        ? root.shell.pluginShellForBarEntry("bar-entry:" + facade.moduleName, facade.moduleName)
        : null
    }

    readonly property var shell: QtObject {
      function serviceFor(id) { return null }
      function firstPartyServiceFor(id) {
        return root.shell ? root.shell.firstPartyServiceFor(id) : null
      }
      function summon(id, payloadJson) {
        var entry = facade._scopedEntry()
        return entry ? entry.summon(id, payloadJson) : false
      }
      function hide(id) {
        var entry = facade._scopedEntry()
        return entry ? entry.hide(id) : false
      }
      function toggle(id, payloadJson) {
        var entry = facade._scopedEntry()
        return entry ? entry.toggle(id, payloadJson) : false
      }
      function isPluginOpen(id) {
        var entry = facade._scopedEntry()
        return entry ? entry.isPluginOpen(id) : false
      }
      function updateEntryInline(id, settings) {
        var entry = facade._scopedEntry()
        return entry ? entry.updateEntryInline(id, settings) : false
      }
      function mutateShellConfig(mutator) {
        return root.shell ? root.shell.mutateShellConfig(mutator) : false
      }
    }
  }

  component ModuleSlot: Item {
    id: slot

    required property var entry
    property string region: ""
    readonly property string moduleName: root.entryId(entry)
    readonly property var moduleSettings: root.entrySettings(entry)
    readonly property string customType: root.customModuleType(entry)
    // Re-evaluate when the registry mutates (Component reference changes,
    // plugin enabled/disabled, etc.). Reading the `widgets` property creates
    // the binding dependency — the wrapped function call alone wouldn't.
    readonly property var registryComponent: {
      var w = root.barWidgetRegistry.widgets
      if (customType) return null
      var registryName = root.canonicalWidgetId(moduleName)
      return w[registryName] ? w[registryName].component : null
    }
    readonly property bool qmlCustom: customType === "qml"
    readonly property bool commandCustom: customType === "command"
    readonly property bool registered: registryComponent !== null
    readonly property var activeItem: {
      if (registered) return registryLoader.item
      if (qmlCustom) return qmlLoader.item
      return componentLoader.item
    }
    readonly property var pluginBarFacade: PluginBarFacade { moduleName: slot.moduleName }

    readonly property bool hovered: moduleHover.hovered
    readonly property bool dragSource: root.barDragSource === slot
    readonly property bool panelOpen: root.activePopout === slot.activeItem
    // Modules bigger than the mark they want (a text label in a padded slot,
    // a multi-line stack on a vertical bar) can say how long the open-panel
    // dot should be along the bar, so it tracks what the module paints
    // instead of a fraction of whatever slot it happens to fill.
    readonly property real panelIndicatorExtent: {
      var key = root.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
      var hint = activeItem && key in activeItem ? activeItem[key] : undefined
      if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
      return Math.max(Style.space(10), Math.round((root.vertical ? slot.height : slot.width) * 0.55))
    }
    implicitWidth: activeItem && activeItem.visible ? (root.vertical ? root.barSize : activeItem.implicitWidth) : 0
    implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
    width: implicitWidth
    height: implicitHeight
    z: modulePointer.dragging ? 100 : 0

    Component.onCompleted: root.registerModuleSlot(slot)
    Component.onDestruction: {
      if (root.barDragSource === slot) root.clearBarDrag()
      root.unregisterModuleSlot(slot)
    }

    // Passive/non-exclusive -- tracks live hover position (point.position)
    // and the plain hovered flag below, without claiming/blocking hover
    // from any MouseArea underneath it (unlike a MouseArea with
    // hoverEnabled: true would). modulePointer's own cursorShape binding
    // below reads point.position from here for exactly that reason.
    HoverHandler { id: moduleHover }

    BorderSurface {
      visible: slot.dragSource
      anchors.fill: parent
      anchors.margins: Style.space(1)
      color: root.transparent ? "transparent" : root.background
      borderSpec: Border.flat(root.barForeground, 1)
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: root.transparent ? 0.22 : 0.32
    }

    Loader {
      id: componentLoader
      active: !slot.qmlCustom && !slot.registered
      sourceComponent: slot.commandCustom ? customCommandModuleComponent : emptyModuleComponent
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: registryLoader
      active: slot.registered
      sourceComponent: slot.registered ? slot.registryComponent : null
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Loader {
      id: qmlLoader
      active: slot.qmlCustom
      source: slot.qmlCustom ? root.customModuleSource(slot.entry) : ""
      anchors.fill: parent
      opacity: slot.dragSource ? 0.22 : 1.0
      onLoaded: {
        slot.injectProps()
        Qt.callLater(slot.injectProps)
      }
    }

    Rectangle {
      id: openPanelIndicator

      readonly property int inset: Style.space(2)

      visible: opacity > 0
      opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
      color: Color.accent
      radius: Math.min(width, height) / 2
      width: root.vertical ? Style.space(2) : slot.panelIndicatorExtent
      height: root.vertical ? slot.panelIndicatorExtent : Style.space(2)
      // The mark sits on the module's inner edge — the one facing the
      // desktop — so it underlines a top bar, overlines a bottom one, and
      // points inward from a left or right one. It reads as pointing at the
      // panel that opens on that side.
      x: root.vertical
        ? (root.position === "left" ? parent.width - width - inset : inset)
        : Math.round((parent.width - width) / 2)
      y: root.vertical
        ? Math.round((parent.height - height) / 2)
        : (root.position === "top" ? parent.height - height - inset : inset)
      z: 50

      Behavior on opacity {
        NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
      }
    }

    MouseArea {
      id: modulePointer

      property bool dragging: false
      property bool suppressClick: false
      property real pressedX: 0
      property real pressedY: 0
      readonly property bool canReorder: root.shell && typeof root.shell.mutateShellConfig === "function"
        && root.immovableModuleIds.indexOf(slot.moduleName) === -1
      readonly property real dragThreshold: Style.space(4)

      anchors.fill: parent
      acceptedButtons: Qt.LeftButton
      enabled: slot.visible && slot.width > 0 && slot.height > 0
      propagateComposedEvents: true
      // Coordinates come from moduleHover (the HoverHandler below), not
      // this MouseArea's own mouseX/mouseY -- those only update live
      // while a button is pressed, or hoverEnabled is true (Qt's own
      // docs), and this MouseArea deliberately does NOT set hoverEnabled
      // (see the comment on moduleHover for why: it would steal
      // entered/exited from every widget's own inner MouseArea sitting
      // underneath it, breaking every hover tooltip in the bar --
      // confirmed live, not assumed, the exact regression "we lost all
      // helpers" after a first attempt set hoverEnabled here directly).
      // moduleHover is a passive, non-exclusive HoverHandler -- it
      // tracks live position without ever claiming/blocking hover from
      // items below it, so it's the one safe source of a genuinely live
      // coordinate for this binding.
      cursorShape: root.moduleClickTargetAt(slot, moduleHover.point.position.x, moduleHover.point.position.y) ? Qt.PointingHandCursor : Qt.ArrowCursor
      // Do not assign drag.target here: ModuleSlot is owned by Row/Column
      // positioners, and mutating slot.x/slot.y can leave stale offsets that
      // make neighboring modules overlap after a small aborted drag.

      onPressed: function(mouse) {
        dragging = false
        suppressClick = false
        pressedX = mouse.x
        pressedY = mouse.y
        root.clearBarDrag()
      }

      onPositionChanged: function(mouse) {
        if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

        var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
        if (distance >= dragThreshold) {
          if (!dragging) {
            root.barDragWindow = root.targetWindow(slot.activeItem) || root.targetWindow(slot)
            root.barDragScreen = root.barDragWindow ? root.barDragWindow.screen : null
            root.barDragOffsetX = pressedX
            root.barDragOffsetY = pressedY
            root.captureBarDragGhost(slot)
            root.barDragSource = slot
          }
          dragging = true
          root.hideTooltip(slot.activeItem)
        }

        if (dragging) {
          var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
          var screenPoint = root.barDragScreenPoint(scenePoint)
          root.barDragSceneX = scenePoint.x
          root.barDragSceneY = scenePoint.y
          root.barDragScreenX = screenPoint.x
          root.barDragScreenY = screenPoint.y

          var drop = root.moduleDropAtScene(scenePoint, slot)
          root.barDragTarget = drop ? drop.slot : null
          root.barDragAfter = drop ? drop.after : false
          root.barDragTargetGeometry = drop ? root.dropMarkerRect(drop.slot, drop.after) : null
        }
      }

      onReleased: function(mouse) {
        var wasDragging = dragging
        var targetSlot = root.barDragTarget
        var afterTarget = root.barDragAfter

        if (wasDragging) suppressClick = true

        dragging = false
        root.clearBarDrag()

        if (wasDragging && targetSlot) {
          root.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
          mouse.accepted = true
        } else if (!wasDragging) {
          mouse.accepted = false
        }
      }

      onCanceled: {
        dragging = false
        suppressClick = false
        root.clearBarDrag()
      }

      onClicked: function(mouse) {
        if (suppressClick) {
          suppressClick = false
          mouse.accepted = true
          return
        }

        if (!root.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
      }
    }

    onActiveItemChanged: Qt.callLater(injectProps)
    onModuleSettingsChanged: injectProps()

    // Editing PluginBarFacade (below) or anything it forwards? A qmlcache
    // clear + hot reload is NOT sufficient to verify the change -- confirmed
    // live that stale PluginBarFacade instances can survive a hot reload,
    // throwing "TypeError: ... is not a function" on methods that plainly
    // exist in the on-disk source (cost hours of debugging a since-fixed
    // popup-positioning bug that looked broken purely because of this).
    // Always do a full `omarchy restart shell` and confirm a new PID via
    // `ps aux | grep quickshell` before trusting a live test of anything
    // touching this facade. See AGENTS.md's own verification checklist.
    function injectProps() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = slot.pluginBarFacade
      if ("moduleName" in target) target.moduleName = moduleName
      if ("settings" in target) target.settings = moduleSettings
    }

    Component {
      id: customCommandModuleComponent
      CustomCommandModule { entry: slot.entry }
    }
  }

  component CustomCommandModule: WidgetButton {
    id: customRoot

    required property var entry
    readonly property string moduleName: root.entryId(entry)
    readonly property var settings: root.entrySettings(entry)
    property string outputText: ""
    property string outputTooltip: ""
    property bool outputActive: false

    function setting(name, fallback) {
      var value = settings ? settings[name] : undefined
      return value === undefined || value === null ? fallback : value
    }

    function update(raw) {
      var data = Util.parseModuleJson(raw)
      var klass = data.class || data.alt || ""

      outputText = data.text || String(raw || "").trim()
      outputTooltip = data.tooltip || String(setting("tooltip", ""))
      outputActive = klass === "active" || (Array.isArray(klass) && klass.indexOf("active") !== -1)
    }

    bar: root
    text: outputText || String(setting("text", ""))
    tooltipText: outputTooltip || String(setting("tooltip", ""))
    active: outputActive
    keepSpace: setting("keepSpace", false) === true
    horizontalMargin: Number(setting("horizontalMargin", 7.5))
    verticalPadding: Number(setting("verticalPadding", 6))
    fontSize: Number(setting("fontSize", 12))

    onPressed: function(button) {
      var command = ""
      if (button === Qt.RightButton)
        command = String(setting("onRightClick", ""))
      else if (button === Qt.MiddleButton)
        command = String(setting("onMiddleClick", ""))
      else
        command = String(setting("onClick", ""))

      if (command) root.run(command)
    }

    Process {
      id: customProc
      command: ["bash", "-lc", String(customRoot.setting("exec", ""))]
      stdout: StdioCollector {
        waitForEnd: true
        onStreamFinished: customRoot.update(text)
      }
    }

    Timer {
      interval: Math.max(1, Number(customRoot.setting("interval", 5))) * 1000
      running: String(customRoot.setting("exec", "")) !== ""
      repeat: true
      triggeredOnStart: true
      onTriggered: root.runProcess(customProc)
    }
  }
}
