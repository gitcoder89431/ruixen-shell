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
  // [font] base-size (done to get 18px icons, matching ambxst) scales
  // those theme tokens by the same fontScale, which would balloon this
  // past the 44 target below every time the font scale changes.
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

  // Reserved screen zone for windows -- taller than barSize so
  // ruixen.notch (a separate overlay, reserves nothing on its own) has
  // room for its collapsed height (44, full ambxst parity) without its
  // bottom edge sitting flush against tiled windows.
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

  // Inset to match ruixen.frame-widget's thickness (6px), so the bar sits
  // inside the frame's rounded-rect hole instead of flush against the
  // screen edge when docked -- see BarPanel's own margins for the real
  // consumer. Lives on root (not just inside BarPanel) so widgets can
  // read the bar's own current screen offset too -- see screenMarginTop
  // below for why that matters.
  readonly property int frameInset: 6
  // Floating's own, bigger top margin -- see BarPanel's own margins
  // comment for the full history/tuning. Lives on root for the same
  // reason frameInset does.
  readonly property int topInset: 13
  // The bar WINDOW's own current absolute screen-Y offset (BarPanel's
  // own margins.top, mirrored here) -- NOT the same thing as where bar
  // CONTENT sits (dockedRow's own y is always 0 regardless of mode, see
  // its own anchors). Exists for widgets hosting their own popup via
  // qs.Ui's PopupCard (ruixen.quickactions does): PopupCard is a real
  // xdg-popup anchored to THIS plugin's own bar surface, so its anchor
  // coordinates are relative to that surface's origin -- which itself
  // sits at screenMarginTop on screen, not at screen y=0. KeyboardPanel-
  // based popups (weather/clock/agents) don't have this offset, because
  // they're each a SEPARATE, always-at-origin full-screen window, not
  // attached to the bar's own surface. Direct live report: quickactions'
  // own popup sat noticeably lower than weather/clock's after switching
  // it to centerOnBar -- confirmed live (a temporary debug read of the
  // real window height) that the gap was exactly this value (13 in
  // floating mode on this machine) -- PopupCard's own margin property
  // needs this backed out to land on the same absolute screen Y as a
  // KeyboardPanel-based popup, see ruixen.quickactions/QuickActions.qml's
  // own popup.margin for where that actually happens.
  readonly property int screenMarginTop: docked ? frameInset : topInset

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
  //   3. curatedPill ("SYSTEM") -- an exact, fixed four: system-update,
  //      power, quickactions, settingsbutton ("system is POWER UPDATE
  //      MORE ACTIONS AND SETTING"). Never a catch-all -- nothing else
  //      ever joins this pill, by design.
  //   4. clockPill -- weather + clock, unchanged.
  //
  // curatedRightIds is that exact fixed four. pluginPinsGroupIds is
  // everything that lands in pill 2 -- ruixen.pluginpins itself plus
  // every id NOT in curatedRightIds and NOT ruixen.tray. There's
  // deliberately no third named list: pill 2 is defined as "whatever
  // isn't tray and isn't the fixed system four", so a newly-pinned
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
  // notchGeometryService is Omarchy's own real first-party service
  // registry (shell.firstPartyServiceFor), the same established
  // mechanism ruixen.media's own BarWidget.qml already uses to reach
  // its sibling Service.qml -- reused here for a genuinely NEW thing,
  // one Ruixen plugin (ruixen.bar) reading a constant a DIFFERENT
  // Ruixen plugin (ruixen.notch) owns, so the two can never drift out
  // of sync with each other's real numbers. See
  // ruixen.notch/NotchGeometry.qml's own comment for exactly what this
  // does and doesn't cover (the Notch's COLLAPSED footprint only, not
  // its full live launcher/pinned-expanded width -- a deliberate,
  // named scope limit, not an oversight).
  readonly property var notchGeometryService: root.shell ? root.shell.firstPartyServiceFor("ruixen.notch") : null
  // 340 matches NotchGeometry.qml's own current collapsedBodyWidth (284)
  // + cornerSize (28) * 2 -- only ever used if the service itself is
  // somehow unavailable (ruixen.notch disabled, or not yet loaded),
  // so the bar still reserves a sane default rather than assuming zero.
  readonly property int notchReservedWidth: notchGeometryService && notchGeometryService.reservedWidth ? notchGeometryService.reservedWidth : 340

  // Absolute screen Y of the Notch's own collapsed bottom edge -- see
  // implicitHeight's own comment below for what this is for (giving
  // weather/clock's popup enough window height to clear the Notch
  // without opening underneath it). 48 mirrors NotchGeometry.qml's own
  // current collapsedTopMargin (4) + collapsedHeight (44), same
  // service-unavailable fallback pattern as notchReservedWidth above.
  readonly property int notchCollapsedBottomEdge: notchGeometryService && notchGeometryService.collapsedBottomEdge ? notchGeometryService.collapsedBottomEdge : 48

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

  Component.onCompleted: applyBarConfig()

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

  function rawLayoutSection(config, region) {
    if (!Util.isPlainObject(config.bar)) config.bar = {}
    if (!Util.isPlainObject(config.bar.layout)) config.bar.layout = {}
    if (!Array.isArray(config.bar.layout[region])) config.bar.layout[region] = []

    return config.bar.layout[region]
  }

  function rawEntryIndex(entries, name) {
    for (var i = 0; i < entries.length; i++) {
      if (root.entryId(entries[i]) === name) return i
    }

    return -1
  }

  function moveModuleInConfig(config, fromRegion, fromName, toRegion, beforeName) {
    var fromEntries = rawLayoutSection(config, fromRegion)
    var toEntries = rawLayoutSection(config, toRegion)
    var fromIndex = rawEntryIndex(fromEntries, fromName)
    if (fromIndex < 0) return false

    var toIndex = beforeName ? rawEntryIndex(toEntries, beforeName) : toEntries.length
    if (toIndex < 0) toIndex = toEntries.length

    if (fromRegion === toRegion && fromIndex === toIndex) return false

    var movedEntry = fromEntries[fromIndex]
    fromEntries.splice(fromIndex, 1)

    if (fromRegion === toRegion && fromIndex < toIndex) toIndex -= 1
    if (toIndex < 0) toIndex = 0
    if (toIndex > toEntries.length) toIndex = toEntries.length
    if (fromRegion === toRegion && fromIndex === toIndex) {
      fromEntries.splice(fromIndex, 0, movedEntry)
      return false
    }

    toEntries.splice(toIndex, 0, movedEntry)
    return true
  }

  function dropBarModule(source, toRegion, beforeName) {
    if (!source || !source.region || !source.moduleName || !toRegion) return false
    if (source.region === toRegion && source.moduleName === beforeName) return false
    if (!root.shell || typeof root.shell.mutateShellConfig !== "function") return false

    var changed = false
    root.shell.mutateShellConfig(function(config) {
      changed = moveModuleInConfig(config, source.region, source.moduleName, toRegion, beforeName)
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
    // the bar at all. Ruixen's own protected ids can still freely
    // reorder among each other (e.g. the System pill's own four items),
    // since each of those already has a pill willing to render it --
    // only a genuinely foreign/arbitrary id gets steered away from
    // these slots as a drop target.
    var sourceIsProtected = sourceSlot && root.protectedModuleIds.indexOf(sourceSlot.moduleName) !== -1

    var candidates = []
    for (var i = 0; i < moduleSlots.length; i++) {
      var slot = moduleSlots[i]
      if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0) continue
      if (!sourceIsProtected && root.protectedModuleIds.indexOf(slot.moduleName) !== -1) continue
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
  onPositionChanged: scheduleTransparentForegroundRefresh()
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

  // Ported from ambxst's own modules/corners/RoundCorner.qml -- the small
  // concave wing piece a shape needs ADDED at a corner to flow smoothly
  // into whatever continues past its edge, not a Rectangle corner cut
  // (which recedes into the shape instead). Used for the docked pill
  // groups' open-facing shoulder, same technique ruixen.notch's own two
  // shoulders use, ported the same way there.
  component RoundCorner: Item {
    id: cornerRoot
    // Plain strings, not an enum -- a `component`-local enum's qualified
    // values don't resolve from inside an inline component the way they
    // would in ambxst's own standalone file. One of: "topLeft",
    // "topRight", "bottomLeft", "bottomRight".
    property string corner: "topLeft"
    property int size: 25
    property color color: "#000000"

    onColorChanged: cornerCanvas.requestPaint()
    onCornerChanged: cornerCanvas.requestPaint()
    onSizeChanged: cornerCanvas.requestPaint()
    onVisibleChanged: if (visible) cornerCanvas.requestPaint()

    // implicitWidth/Height alone (ambxst's own original) only sizes this
    // when something else (a Layout, or a wrapper's anchors.fill) reads
    // it -- placed as a bare sibling Item like it is below, that never
    // happens and it silently renders at 0x0. Set the real size directly.
    width: size
    height: size
    implicitWidth: size
    implicitHeight: size

    Canvas {
      id: cornerCanvas
      anchors.fill: parent
      antialiasing: true
      onPaint: {
        var ctx = getContext("2d")
        var r = cornerRoot.size
        ctx.clearRect(0, 0, width, height)
        ctx.beginPath()
        switch (cornerRoot.corner) {
        case "topLeft":
          ctx.arc(r, r, r, Math.PI, 3 * Math.PI / 2)
          ctx.lineTo(0, 0)
          break
        case "topRight":
          ctx.arc(0, r, r, 3 * Math.PI / 2, 2 * Math.PI)
          ctx.lineTo(r, 0)
          break
        case "bottomLeft":
          ctx.arc(r, 0, r, Math.PI / 2, Math.PI)
          ctx.lineTo(0, r)
          break
        case "bottomRight":
          ctx.arc(0, 0, r, 0, Math.PI / 2)
          ctx.lineTo(r, r)
          break
        }
        ctx.closePath()
        ctx.fillStyle = cornerRoot.color
        ctx.fill()
      }
    }
  }

  component BarPanel: PanelWindow {
    id: barWindow

    // Hiding parks the bar just past its screen edge instead of unmapping it.
    // Unmapping frees the layer surface and the whole scene graph, so every
    // reveal has to rebuild them — new surface, re-shaped glyphs, re-uploaded
    // textures — which measures ~150ms against ~20ms to tear down. Parking
    // keeps the surface alive, so showing is only a margin change.
    visible: !remapGuard.remapping
    // Normal (not Auto) + an explicit exclusiveZone bigger than this
    // window's own height -- decouples "how much space windows avoid"
    // from "how tall the bar visually is". Needed so ruixen.notch (a
    // separate overlay, ExclusionMode.Ignore, reserves nothing itself)
    // can be taller than the bar without its collapsed state visually
    // overlapping tiled windows. Auto would only reserve this window's
    // own implicitHeight + margins (26 + 6 frameInset = 32), which is
    // shorter than the notch's own collapsed height.
    exclusionMode: root.barHidden ? ExclusionMode.Ignore : ExclusionMode.Normal
    // Docked mode's own top margin is root.frameInset (6), not
    // root.topInset (13) -- see margins below -- so the total
    // reservation (margin.top + exclusiveZone) needs frameInset backed
    // out here instead of topInset, or it quietly shrinks from 44 to 37
    // and tiled windows creep 7px higher than intended, into the notch's
    // own space.
    //
    // Deliberately NOT also adding root.shoulderWingSize here, even
    // though implicitHeight below grows by that much in both modes now
    // (docked: room for the frame-hem wing graphic; floating: popup
    // clearance below the Notch, see implicitHeight's own comment) --
    // reserving the wing's FULL box left a huge gap between the dock
    // and tiled windows, since the wing's actual painted material is a
    // small curved sliver, not a solid block (per direct report). This
    // window's own bottom edge extends slightly past the reservation as
    // a result, same as ruixen.notch/ruixen.frame-widget already do
    // (ExclusionMode.Ignore, reserve nothing) -- fine here too since
    // that extra room is almost entirely transparent.
    exclusiveZone: root.docked ? (44 - root.frameInset) : root.notchClearance

    ScreenMoveRemap {
      id: remapGuard
      window: barWindow
    }

    // frameInset/topInset live on root now, not here -- ruixen.quickactions'
    // own popup (a real xdg-popup anchored to this window's surface,
    // unlike weather/clock/agents' own separate full-screen popup windows)
    // needs to read the CURRENT one of these two to compensate for this
    // surface's own screen offset, see root.screenMarginTop's own comment.

    margins {
      // Docked mode uses frameInset here too, not topInset -- the merged
      // corner (leftDockedBg/rightDockedBg below) needs to land on
      // exactly the same point ruixen.frame-widget's own rounded corner
      // starts (thickness, thickness), same on all three sides, or its
      // topLeftRadius/topRightRadius arc won't line up with the frame's.
      top: root.barHidden && root.position === "top" ? -root.barSize : (root.position === "top" ? root.screenMarginTop : 0)
      bottom: root.barHidden && root.position === "bottom" ? -root.barSize : 0
      left: root.barHidden && root.position === "left" ? -root.barSize : (root.position === "top" ? root.frameInset : 0)
      right: root.barHidden && root.position === "right" ? -root.barSize : (root.position === "top" ? root.frameInset : 0)
    }

    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.barSize : 0

    // The window's REAL, functional content height -- where the pill row
    // (and, docked only, the frame-hem corner wing graphics) actually
    // live. Used both as implicitHeight's own floor below and, more
    // importantly, as the mask's height (see mask below): this is the
    // ONLY part of the window that should ever accept pointer input,
    // no matter how much taller implicitHeight grows for popup-
    // positioning purposes.
    //
    // Clears the Notch's own collapsed bottom edge (notchCollapsedBottomEdge,
    // from ruixen.notch's own service) -- direct live report: any popup
    // panel anchored off this window (weather's own, and stock Omarchy's
    // clock/agents popups -- all use qs.Ui's KeyboardPanel) opens at
    // `anchorWindow.height + gap` (KeyboardPanel.qml's own cardOrigin, not
    // editable -- it's a stock /usr/share/omarchy file), which had no
    // notion of ruixen.notch and let a popup open right underneath it.
    //
    // Same floor in BOTH modes now, not a per-mode split. Docked needs
    // barSize + shoulderWingSize regardless of the Notch's own numbers:
    // leftFrameHemWing/rightFrameHemWing (the frame-hem corner wing
    // graphics, docked only) are positioned at y: barSize with their own
    // height shoulderWingSize, i.e. they occupy this window's own [34, 58]
    // band; sizing the window any shorter than 58 when docked would clip
    // their bottom edge against the window's own Wayland surface bounds (a
    // real, silent clip -- not a QML clip -- confirmed finding from #29's
    // own investigation). Floating has no such constraint of its own (48,
    // barSize/notchCollapsedBottomEdge's own max, would still clear the
    // Notch on its own) -- but a direct follow-up report pointed out that
    // popups then open at two visibly different heights depending on
    // mode ("it looks kinda sloppy... i think its better they either
    // lower or higher rather than having its own thing"). Docked's own
    // 58 can't safely come down (the wing-clip constraint above), so
    // floating goes up to match instead -- consistent behavior across
    // both modes wins over exactly hugging the window-tiling boundary in
    // floating alone.
    readonly property int visibleBarHeight: root.vertical ? root.barSize : Math.max(root.barSize + root.shoulderWingSize, root.notchCollapsedBottomEdge)

    // Attempted, reverted: growing implicitHeight further so popups
    // anchored off this window (weather, clock, agents, quickactions --
    // all read `anchorWindow.height + gap` for their own Y, see
    // visibleBarHeight's own comment) open closer to screen-center,
    // matching ruixen.settings' own dead-center dialog look ("is it
    // better to make all them show up center and middle like the
    // settings"). `anchorWindow.height` is the only lever this plugin
    // has over a stock/third-party widget's own popup position (their
    // panel code isn't ours to edit), so this was the only way to move
    // theirs at all, not just ruixen's own.
    //
    // Confirmed live this doesn't generalize: a shared target tuned
    // against weather's own real content height (228px) opened it and
    // clock's calendar in a good spot, but pushed omarchy.agents' own
    // popup toward the bottom of the screen instead -- its content can
    // run up to 640px tall (a scrollable dashboard), and centering math
    // sized for a ~228px popup runs a 640px one's bottom edge past the
    // screen edge, so KeyboardPanel's own on-screen clamp shoves the
    // whole thing down. One shared window-height value can't safely
    // serve every popup's own, wildly different content height. Direct
    // live report caught this ("the ai agent popup... showing up at the
    // bottom now"). Back to visibleBarHeight (clears the Notch, doesn't
    // reach for center) until a real per-popup-safe approach exists --
    // if one is built, it'll need an actual `mask` restricting input to
    // visibleBarHeight regardless of implicitHeight (this window is
    // always mapped, unlike a transient popup, so any invisible growth
    // without a mask would permanently swallow clicks meant for windows
    // behind it -- same `Region { x; y; width; height }` technique
    // ruixen.notch/Overlay.qml already uses for exactly that reason).
    implicitHeight: root.vertical ? 0 : visibleBarHeight

    // Always transparent, not root.transparent-gated — the bar-wide solid
    // background is gone entirely now that each module group draws its own
    // floating pill background (see horizontalBar below).
    color: "transparent"
    surfaceFormat.opaque: false
    WlrLayershell.namespace: "omarchy-bar"
    WlrLayershell.layer: WlrLayer.Top

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
          width: settingsPill.x + settingsPill.width
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
          topRightRadius: 0
          // Square, not a plain recede curve -- the actual concave wrap
          // (per direct request: "the smooth curve should face inward")
          // is leftFrameHemWing below, in its own dedicated space
          // (root.shoulderWingSize, added to BarPanel's implicitHeight
          // when docked). Squaring this off keeps it a flush, seamless
          // hand-off into that wing rather than competing with
          // topLeftRadius for room on the same 34px edge.
          bottomLeftRadius: 0
          // The real shoulder. Matches shoulderWingSize (24), not the
          // pill's full height -- the earlier seam/glitch came from this
          // being `height` (34) while the wing was ALSO full-height: two
          // full-height curves with no shared straight edge to align
          // against. Same radius as the wing's own size instead, so
          // there's a real flush edge between them and their curves
          // share a tangent at the join.
          bottomRightRadius: root.shoulderWingSize
        }

        // ambxst's own rightCornerMaskPart, ported: a small square sitting
        // immediately past the body's own right edge, corner: topLeft.
        // Same size as leftDockedBg's own bottomRightRadius above (24),
        // not the full pill height -- their own notch wing is a small
        // square matched to its body's own corner radius, not a
        // full-height piece; that mismatch was the earlier bug.
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
          visible: root.docked
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
          // read as oversized. Pinned back to the pre-bump numbers here;
          // ambxst's own SysTray pill uses a flat 8px inner margin too
          // (modules/bar/systray/SysTray.qml), same ballpark. Trimmed
          // from 16 -- ambxst's own edge-to-icon distance tops out around
          // 18px (frame+outerMargin) and they don't stack a curve-
          // clearance margin on top of that the way we do for the
          // frame's 24px corner.
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
          width: menuContent.width + 8 * 2
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

        Item {
          id: settingsPill
          // Fades out instead of collapsing width/anchors when
          // ruixen.settingsbutton isn't in the "left" layout -- same
          // reasoning as trayPill below: simpler than juggling anchors
          // around a pill that comes and goes, and nothing else anchors
          // off settingsPill's own edges.
          opacity: settingsContent.width > 0 ? 1 : 0
          anchors.left: pinnedappsPill.right
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

    function injectProps() {
      var target = activeItem
      if (!target) return
      if ("bar" in target) target.bar = root
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
