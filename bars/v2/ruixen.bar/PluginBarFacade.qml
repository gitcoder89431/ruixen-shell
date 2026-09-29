import QtQuick

// The per-widget scoped `bar` API object handed to every hosted plugin
// widget (BarWidget.qml across bars/widgets/*), instead of the raw bar
// root Item -- confirmed the widest-blast-radius contract in the repo:
// consumed via bar.*/bar.shell.* by widgets repo-wide, AND by Quickshell's
// own shared qs.Ui base components (WidgetButton, PopupCard,
// KeyboardPanel, Panel -- every widget in this repo extends one of
// these), confirmed real usage in /usr/share/omarchy/shell/Ui/*.qml, not
// just this repo's own source. Every property/method below mirrors
// something real widgets already read off `bar` today (audited across
// the repo) -- this is a pure reshaping of the same contract, not a new
// one, so nothing that works today should regress. ModuleSlot
// instantiates one of these per widget slot, scoped to that slot's own
// moduleName, so each hosted widget only ever sees a facade scoped to
// ITS OWN moduleName.
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 3, its own
// isolated pass given the blast radius) as a pure file move: this was
// previously `component PluginBarFacade: QtObject { ... }` declared
// inline inside Bar.qml's own `Item { id: root }`. barRoot is the
// explicit back-reference every `root.foo` read was rewritten to go
// through, wired at this component's one instantiation site (inside
// ModuleSlot.qml, itself forwarding its own received barRoot down --
// PluginBarFacade is nested inside ModuleSlot's own body, not
// instantiated directly from Bar.qml). This file's own PUBLIC shape
// (every property/function name below) is byte-identical to before --
// only how it reaches bar-root state changed, never what it exposes to
// the widgets that consume it.
QtObject {
  id: facade

  required property Item barRoot
  required property string moduleName

  readonly property color foreground: facade.barRoot.popupForeground
  readonly property color iconForeground: facade.barRoot.iconForeground
  readonly property color semanticGood: facade.barRoot.semanticGood
  readonly property color semanticWarn: facade.barRoot.semanticWarn
  readonly property color semanticBad: facade.barRoot.semanticBad
  readonly property color semanticInfo: facade.barRoot.semanticInfo
  readonly property color semanticNeutral: facade.barRoot.semanticNeutral
  readonly property color themePrimary: facade.barRoot.themePrimary
  readonly property color themeSecondary: facade.barRoot.themeSecondary
  readonly property bool themeMonochrome: facade.barRoot.themeMonochrome
  readonly property string fontFamily: facade.barRoot.fontFamily
  readonly property color barForeground: facade.barRoot.barForeground
  readonly property bool foregroundAnimationEnabled: facade.barRoot.foregroundAnimationEnabled
  readonly property var barWidgetRegistry: facade.barRoot.barWidgetRegistry
  readonly property var barConfig: facade.barRoot.barConfig
  readonly property var layoutConfig: facade.barRoot.layoutConfig
  // The rest of this block: found missing live, after the first version
  // of this facade shipped -- Quickshell's own shared qs.Ui base
  // components (WidgetButton, PopupCard, KeyboardPanel, Panel -- every
  // widget in this repo extends one of these) read all of these off
  // `bar` too, and none of it showed up in a repo-only grep since none
  // of OUR OWN source calls it by name. Confirmed real usage in
  // /usr/share/omarchy/shell/Ui/*.qml, not just this repo.
  readonly property color background: facade.barRoot.background
  readonly property color urgent: facade.barRoot.urgent
  readonly property bool vertical: facade.barRoot.vertical
  readonly property int barSize: facade.barRoot.barSize
  readonly property string position: facade.barRoot.position
  readonly property var clickTargets: facade.barRoot.clickTargets
  // Found missing the same way, this time by actually tracing a real
  // reported bug (ruixen-shell popup-positioning regression) back to
  // its root: this is what ruixen.quickactions'/ruixen.pluginpins' own
  // PopupCard.margin needs to back out of PopupCard's own xdg-popup
  // surface-relative offset -- see either widget's own popup.margin
  // comment (originally added in 61ef0bd) for the full "why".
  readonly property int screenMarginTop: facade.barRoot.screenMarginTop
  readonly property var activePopout: facade.barRoot.activePopout

  // The one writable property in this contract (ruixen.weather/Panel.qml
  // sets it directly) -- kept in sync both ways via plain JS-expression
  // bindings, the same mechanism this whole file already relies on for
  // every other root-tracking property (no property alias used here --
  // untested whether alias resolution reaches into an inline `component`
  // the way plain expression bindings, proven throughout this file, do).
  property bool centerHoverRevealSuppressed: facade.barRoot.centerHoverRevealSuppressed
  onCenterHoverRevealSuppressedChanged: facade.barRoot.centerHoverRevealSuppressed = centerHoverRevealSuppressed

  function run(command) { return facade.barRoot.run(command) }
  function showTooltip(target, text) { return facade.barRoot.showTooltip(target, text) }
  function hideTooltip(target) { return facade.barRoot.hideTooltip(target) }
  function registerClickTarget(target) { return facade.barRoot.registerClickTarget(target) }
  function unregisterClickTarget(target) { return facade.barRoot.unregisterClickTarget(target) }
  function switchPanelFrom(owner, direction) { return facade.barRoot.switchPanelFrom(owner, direction) }
  function requestPopout(owner) { return facade.barRoot.requestPopout(owner) }
  function releasePopout(owner) { return facade.barRoot.releasePopout(owner) }
  function targetBelongsToWindow(target, window) { return facade.barRoot.targetBelongsToWindow(target, window) }
  function moduleWidgets(pluginId) { return facade.barRoot.moduleWidgets(pluginId) }

  // Correct per-widget scoping stops here -- see ruixen-shell#67.
  // pluginShellForBarEntry() is the real, public, host-exposed
  // mechanism for a replacement bar to obtain a facade scoped to a
  // SPECIFIC hosted widget's own id, instead of leaking ruixen.bar's
  // own. summon/hide/toggle/isPluginOpen/updateEntryInline now
  // correctly resolve to THIS widget's own identity through it.
  //
  // firstPartyServiceFor/mutateShellConfig deliberately still route
  // through barRoot.shell (ruixen.bar's own, unchanged) -- confirmed by
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
    return (facade.barRoot.shell && typeof facade.barRoot.shell.pluginShellForBarEntry === "function")
      ? facade.barRoot.shell.pluginShellForBarEntry("bar-entry:" + facade.moduleName, facade.moduleName)
      : null
  }

  readonly property var shell: QtObject {
    function serviceFor(id) { return null }
    function firstPartyServiceFor(id) {
      return facade.barRoot.shell ? facade.barRoot.shell.firstPartyServiceFor(id) : null
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
      return facade.barRoot.shell ? facade.barRoot.shell.mutateShellConfig(mutator) : false
    }
  }
}
