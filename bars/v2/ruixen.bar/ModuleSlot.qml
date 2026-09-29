import QtQuick
import qs.Commons
import qs.Ui

// Single widget slot: resolves a registered widget component or a
// custom-command module, owns click-target/drag/tooltip wiring, and
// instantiates the scoped PluginBarFacade each hosted widget receives
// as its own `bar` property.
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 4) as a pure file
// move: this was previously `component ModuleSlot: Item { ... }`
// declared inline inside Bar.qml's own `Item { id: root }`. barRoot is
// the explicit back-reference every `root.foo` read was rewritten to go
// through, wired at each of this component's instantiation sites
// (ModuleList.qml/CenterModules.qml, both forwarding their own received
// barRoot down). The nested PluginBarFacade instantiation below needs
// TWO-HOP forwarding specifically (`barRoot: slot.barRoot`, not `barRoot:
// root`) -- PluginBarFacade is nested inside THIS component's own body,
// not instantiated directly from Bar.qml, so it has no other way to
// reach the real bar root now that both are separate files. No behavior
// change from this move.
Item {
  id: slot

  required property Item barRoot
  required property var entry
  property string region: ""
  readonly property string moduleName: slot.barRoot.entryId(entry)
  readonly property var moduleSettings: slot.barRoot.entrySettings(entry)
  readonly property string customType: slot.barRoot.customModuleType(entry)
  // Re-evaluate when the registry mutates (Component reference changes,
  // plugin enabled/disabled, etc.). Reading the `widgets` property creates
  // the binding dependency — the wrapped function call alone wouldn't.
  readonly property var registryComponent: {
    var w = slot.barRoot.barWidgetRegistry.widgets
    if (customType) return null
    var registryName = slot.barRoot.canonicalWidgetId(moduleName)
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
  readonly property var pluginBarFacade: PluginBarFacade { barRoot: slot.barRoot; moduleName: slot.moduleName }

  readonly property bool hovered: moduleHover.hovered
  readonly property bool dragSource: slot.barRoot.barDragSource === slot
  readonly property bool panelOpen: slot.barRoot.activePopout === slot.activeItem
  // Modules bigger than the mark they want (a text label in a padded slot,
  // a multi-line stack on a vertical bar) can say how long the open-panel
  // dot should be along the bar, so it tracks what the module paints
  // instead of a fraction of whatever slot it happens to fill.
  readonly property real panelIndicatorExtent: {
    var key = slot.barRoot.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth"
    var hint = activeItem && key in activeItem ? activeItem[key] : undefined
    if (hint !== undefined && hint !== null && hint > 0) return Math.round(hint)
    return Math.max(Style.space(10), Math.round((slot.barRoot.vertical ? slot.height : slot.width) * 0.55))
  }
  implicitWidth: activeItem && activeItem.visible ? (slot.barRoot.vertical ? slot.barRoot.barSize : activeItem.implicitWidth) : 0
  implicitHeight: activeItem && activeItem.visible ? activeItem.implicitHeight : 0
  width: implicitWidth
  height: implicitHeight
  z: modulePointer.dragging ? 100 : 0

  Component.onCompleted: slot.barRoot.registerModuleSlot(slot)
  Component.onDestruction: {
    if (slot.barRoot.barDragSource === slot) slot.barRoot.clearBarDrag()
    slot.barRoot.unregisterModuleSlot(slot)
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
    color: slot.barRoot.transparent ? "transparent" : slot.barRoot.background
    borderSpec: Border.flat(slot.barRoot.barForeground, 1)
    radius: Math.min(Style.cornerRadius, height / 2)
    opacity: slot.barRoot.transparent ? 0.22 : 0.32
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
    source: slot.qmlCustom ? slot.barRoot.customModuleSource(slot.entry) : ""
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
    width: slot.barRoot.vertical ? Style.space(2) : slot.panelIndicatorExtent
    height: slot.barRoot.vertical ? slot.panelIndicatorExtent : Style.space(2)
    // The mark sits on the module's inner edge — the one facing the
    // desktop — so it underlines a top bar, overlines a bottom one, and
    // points inward from a left or right one. It reads as pointing at the
    // panel that opens on that side.
    x: slot.barRoot.vertical
      ? (slot.barRoot.position === "left" ? parent.width - width - inset : inset)
      : Math.round((parent.width - width) / 2)
    y: slot.barRoot.vertical
      ? Math.round((parent.height - height) / 2)
      : (slot.barRoot.position === "top" ? parent.height - height - inset : inset)
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
    readonly property bool canReorder: slot.barRoot.shell && typeof slot.barRoot.shell.mutateShellConfig === "function"
      && slot.barRoot.immovableModuleIds.indexOf(slot.moduleName) === -1
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
    cursorShape: slot.barRoot.moduleClickTargetAt(slot, moduleHover.point.position.x, moduleHover.point.position.y) ? Qt.PointingHandCursor : Qt.ArrowCursor
    // Do not assign drag.target here: ModuleSlot is owned by Row/Column
    // positioners, and mutating slot.x/slot.y can leave stale offsets that
    // make neighboring modules overlap after a small aborted drag.

    onPressed: function(mouse) {
      dragging = false
      suppressClick = false
      pressedX = mouse.x
      pressedY = mouse.y
      slot.barRoot.clearBarDrag()
    }

    onPositionChanged: function(mouse) {
      if (!canReorder || !(mouse.buttons & Qt.LeftButton)) return

      var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
      if (distance >= dragThreshold) {
        if (!dragging) {
          slot.barRoot.barDragWindow = slot.barRoot.targetWindow(slot.activeItem) || slot.barRoot.targetWindow(slot)
          slot.barRoot.barDragScreen = slot.barRoot.barDragWindow ? slot.barRoot.barDragWindow.screen : null
          slot.barRoot.barDragOffsetX = pressedX
          slot.barRoot.barDragOffsetY = pressedY
          slot.barRoot.captureBarDragGhost(slot)
          slot.barRoot.barDragSource = slot
        }
        dragging = true
        slot.barRoot.hideTooltip(slot.activeItem)
      }

      if (dragging) {
        var scenePoint = slot.mapToItem(null, mouse.x, mouse.y)
        var screenPoint = slot.barRoot.barDragScreenPoint(scenePoint)
        slot.barRoot.barDragSceneX = scenePoint.x
        slot.barRoot.barDragSceneY = scenePoint.y
        slot.barRoot.barDragScreenX = screenPoint.x
        slot.barRoot.barDragScreenY = screenPoint.y

        var drop = slot.barRoot.moduleDropAtScene(scenePoint, slot)
        slot.barRoot.barDragTarget = drop ? drop.slot : null
        slot.barRoot.barDragAfter = drop ? drop.after : false
        slot.barRoot.barDragTargetGeometry = drop ? slot.barRoot.dropMarkerRect(drop.slot, drop.after) : null
      }
    }

    onReleased: function(mouse) {
      var wasDragging = dragging
      var targetSlot = slot.barRoot.barDragTarget
      var afterTarget = slot.barRoot.barDragAfter

      if (wasDragging) suppressClick = true

      dragging = false
      slot.barRoot.clearBarDrag()

      if (wasDragging && targetSlot) {
        slot.barRoot.dropBarModuleAtTarget(slot, targetSlot, afterTarget)
        mouse.accepted = true
      } else if (!wasDragging) {
        mouse.accepted = false
      }
    }

    onCanceled: {
      dragging = false
      suppressClick = false
      slot.barRoot.clearBarDrag()
    }

    onClicked: function(mouse) {
      if (suppressClick) {
        suppressClick = false
        mouse.accepted = true
        return
      }

      if (!slot.barRoot.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y)) mouse.accepted = false
    }
  }

  onActiveItemChanged: Qt.callLater(injectProps)
  onModuleSettingsChanged: injectProps()

  // Editing PluginBarFacade or anything it forwards? A qmlcache
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
    CustomCommandModule { entry: slot.entry; barRoot: slot.barRoot }
  }

  // Moved here from Bar.qml's own root scope -- it was only ever
  // referenced by componentLoader above, and a bare Component id lookup
  // like that only resolves within the same document, so it has to live
  // wherever its one consumer does now that ModuleSlot is its own file.
  Component { id: emptyModuleComponent; Item { implicitWidth: 0; implicitHeight: 0; visible: false } }
}
