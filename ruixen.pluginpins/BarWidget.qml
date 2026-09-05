import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Lets any installed bar-widget plugin be pinned to the bar on demand,
// instead of it needing to live there permanently -- direct request:
// "instead of the AI icon, its a dropdown icon that shows the name of
// the available plugins you have. and then clicking or toggling them
// pins it onto the icons group... left click to open them so they
// remain accessible". A pinned plugin becomes a real, ordinary bar icon
// again (its own native click/tooltip/panel behavior, untouched) --
// this widget only ever adds/removes its shell.json layout entry.
//
// Newly-pinned plugins land in Bar.qml's own existing third-party
// catch-all pill (thirdPartyPill) automatically -- that pill was
// already built generic ("Support arbitrary third-party widgets",
// #27) for exactly this case, so no Bar.qml change was needed for
// this feature at all.
BarWidget {
  id: root
  moduleName: "ruixen.pluginpins"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool popupOpen: false

  // Required -- PopupCard's own close() (fired by its outside-click
  // HyprlandFocusGrab) does `if (owner && "close" in owner)
  // owner.close(); else root.open = false`. Without this, it takes the
  // else branch and assigns directly to ITS OWN open property, which
  // permanently breaks the one-way `open: root.popupOpen` binding below
  // -- popupOpen keeps toggling normally on further clicks, but the
  // popup's own open property is now a dead static false, disconnected
  // from it. Confirmed live: "it worked once but i dismissed it and
  // then clicking on it again doesnt do anything anymore". Matches
  // ruixen.media's own identical close() for the identical reason.
  function close() { popupOpen = false }

  readonly property var pluginRegistry: bar && bar.shell ? bar.shell.pluginRegistry : null

  // Ids structural to THIS bar's own curated layout, not "optional
  // widgets" someone would browse/toggle here -- excluded even though
  // they're technically kind: bar-widget, so this list can't be used to
  // accidentally unpin something load-bearing (the app launcher, the
  // workspace switcher, tray, its own settings/quickactions group).
  // ruixen.media is deliberately kept out of the bar layout on purpose
  // (see its own commit history) -- excluded here too rather than
  // inviting someone to re-pin its oversized badge. The stock omarchy.*
  // counterparts already superseded by one of our own clones are
  // excluded so the list doesn't offer a redundant, worse duplicate.
  //
  // omarchy.clock excluded for a different reason, found live: it
  // shares clockPill with ruixen.weather (a divider between the two,
  // plus clock's own format/formatAlt/verticalFormat settings baked
  // into its shell.json entry -- see Bar.qml's centerSpecialIds). This
  // widget's own setPinSide() only knows how to append a bare {id} to
  // whichever section was clicked, so unpinning clock through here and
  // re-pinning it landed it as a brand new plain icon on the right,
  // stripped of its settings, instead of back in clockPill next to
  // weather. Direct live report: "it hid the clock from our designed
  // pill... when i click to show the clock again its a new one in the
  // new group". Excluded rather than taught this one widget's own
  // special-cased home -- same treatment ruixen.weather already gets
  // for the identical reason.
  //
  // omarchy.system-update and omarchy.power excluded per direct
  // follow-up: both already live in curatedRightIds and render on
  // their own real-world condition (an update being available, running
  // on a laptop) -- offering them here as a separate on/off toggle is
  // pure duplication of something already handled automatically.
  //
  // omarchy.keyboard-layout excluded per direct follow-up ("not showing
  // anything, no new icons on toggle, remove it?") -- confirmed by
  // reading its own source: `visible: layoutLabel !== "" &&
  // multipleLayouts`, deliberately invisible on a single-layout install
  // ("stays out of the way until there are two", its own comment). Not
  // a bug, but pinning it produces zero visible feedback for anyone
  // without a second keyboard layout configured -- most people -- so it
  // reads as broken through this generic dropdown either way.
  //
  // omarchy.network excluded per direct follow-up: pinning it produced
  // a real, ongoing "Handler was registered but will not be used
  // because another handler is registered for target omarchy.network"
  // warning, repeating roughly every second rather than once at
  // startup -- something keeps recreating a competing instance. Not
  // ruixen.settings' own WifiContent.qml (checked directly: it reads
  // Quickshell's own Networking singleton, no IpcHandler of its own,
  // can't be the second registrant). Root cause not found; excluded as
  // the practical fix since the actual collision source is stock
  // Omarchy code we can't edit either way.
  //
  // omarchy.indicators excluded per direct follow-up ("it crashed when
  // i toggled it and now does nothing") -- its own IpcHandler already
  // collides with another instance of the same target at plain shell
  // startup, confirmed in the journal before this widget ever touched
  // it: "Handler was registered but will not be used because another
  // handler is registered for target omarchy.indicators". It also
  // duplicates dictation/screen-recording/reminders/night-light/DND,
  // which ruixen.quickactions already reimplements.
  //
  // omarchy.system-update and omarchy.power ARE excluded -- both live in
  // curatedPill's own fixed, exact four (Bar.qml's own curatedRightIds:
  // "system is POWER UPDATE MORE ACTIONS AND SETTING", never a
  // catch-all), so unpinning either through here would break that fixed
  // set. ruixen.stayawake and omarchy.agents both stay un-excluded on
  // purpose, though -- final answer, after a few false starts: they
  // render in ruixen.pluginpins' OWN pill now (the toggle icon lives
  // together with whatever it toggles -- "microphone network cofee ai
  // [are] toggleable from the plugins pin so they stay pinnable or not
  // in the plugin group"), so pinning/unpinning them through this
  // dropdown is exactly the intended interaction, not something to
  // guard against.
  // omarchy.active-window is also excluded -- ruixen.notch's own
  // collapsed player pill already shows the active window's title when
  // nothing is playing, so offering it here as a separate pinnable bar
  // widget would just be a second, redundant place to turn on the same
  // information.
  readonly property var excludedIds: [
    "ruixen.applauncher", "ruixen.workspaces", "ruixen.pinnedapps",
    "ruixen.tray", "ruixen.quickactions", "ruixen.settingsbutton",
    "ruixen.weather", "ruixen.media", "ruixen.pluginpins",
    "omarchy.clock", "omarchy.system-update", "omarchy.power",
    "omarchy.keyboard-layout", "omarchy.indicators", "omarchy.network",
    "omarchy.bar", "omarchy.menu", "omarchy.spacer", "omarchy.active-window",
    "omarchy.workspaces", "omarchy.tray", "omarchy.weather", "omarchy.media"
  ]

  // Recomputed whenever the registry mutates (a plugin gets installed,
  // enabled/disabled, or moved) -- registryRevision is read here purely
  // to create that binding dependency, same pattern shell.qml's own
  // selectedBarAvailable/activeBarManifest already use.
  // Real per-side lookup, not a hand-rolled region scan -- findBarLocation
  // is the same stock function PluginRegistry.qml's own isEnabled/inBar
  // use internally, called here with shellConfigProvider's own live
  // config so "which side is this id currently on" never drifts from
  // what the registry itself considers true.
  function currentSide(reg, id) {
    if (!reg || typeof reg.shellConfigProvider !== "function" || typeof reg.findBarLocation !== "function") return null
    var config = reg.shellConfigProvider()
    if (!config) return null
    var location = reg.findBarLocation(config, id)
    return location && location.found ? location.section : null
  }

  readonly property var candidates: {
    var reg = pluginRegistry
    if (!reg) return []
    var revision = reg.registryRevision
    var plugins = reg.installedPlugins || {}
    var out = []
    for (var id in plugins) {
      var manifest = plugins[id]
      var kinds = manifest && manifest.kinds ? manifest.kinds : []
      if (kinds.indexOf("bar-widget") === -1) continue
      if (excludedIds.indexOf(id) !== -1) continue
      out.push({ id: id, name: manifest.name || id, side: root.currentSide(reg, id) })
    }
    out.sort(function(a, b) { return String(a.name).localeCompare(String(b.name)) })
    return out
  }

  // Direct request, after drag-and-drop turned out to have no way to
  // populate an initially-empty left-side group ("can we do right
  // click and left click to send it to the new group on the left or
  // right depending on the click"): left-click pins to "right" (the
  // original, unchanged default surface -- pluginPinsPill), right-
  // click pins to "left" (leftPluginPinsPill, Bar.qml). Clicking the
  // side something is ALREADY on unpins it (strips every section,
  // same as the old togglePin's own unpin path); clicking the OTHER
  // side just moves it there directly, no separate unpin-then-repin
  // step needed. mutateShellConfig is the same read-modify-persist
  // primitive the bar's own drag-to-reorder feature already uses (see
  // Bar.qml's modulePointer/canReorder), not a fresh mechanism.
  function setPinSide(id, side) {
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    bar.shell.mutateShellConfig(function(config) {
      if (!config.bar) config.bar = {}
      if (!config.bar.layout) config.bar.layout = {}
      var sections = ["left", "center", "right"]
      var wasOnClickedSide = Array.isArray(config.bar.layout[side])
        && config.bar.layout[side].some(function(e) { return e && e.id === id })
      for (var i = 0; i < sections.length; i++) {
        var name = sections[i]
        if (!Array.isArray(config.bar.layout[name])) continue
        config.bar.layout[name] = config.bar.layout[name].filter(function(e) {
          return !e || e.id !== id
        })
      }
      if (!wasOnClickedSide) {
        if (!Array.isArray(config.bar.layout[side])) config.bar.layout[side] = []
        config.bar.layout[side].push({ id: id })
      }
    })
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Grid ("th"), Font Awesome U+F00A -- \u escape, not a pasted glyph,
    // so there's no risk of the hidden/corrupted-byte issue already hit
    // twice elsewhere in this repo (ruixen.pinnedapps' own fallback
    // glyph, Bar.qml's sidebar label) with directly-typed Nerd Font
    // characters.
    text: "\uf00a"
    tooltipText: "Plugins"
    onPressed: function() { root.popupOpen = !root.popupOpen }
  }

  component PluginRow: Item {
    id: rowRoot
    required property string pluginId
    required property string pluginName
    // "left" | "right" | "" (center never happens here -- this widget
    // only ever writes left/right, see setPinSide) -- "" means unpinned.
    required property string side
    signal triggered(int button)

    implicitHeight: Style.space(32)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: mouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.right: checkGlyph.left
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(6)
      elide: Text.ElideRight
      text: rowRoot.pluginName
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // Check ("check", U+F00C) when pinned right -- the original,
    // unchanged glyph/position for the common case. Long-arrow-left
    // (U+F177) when pinned left instead, same slot -- the glyph itself
    // says which side without needing a separate label. Same \u-escape
    // reasoning as the trigger glyph above.
    Text {
      id: checkGlyph
      visible: rowRoot.side !== ""
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      width: Style.space(16)
      horizontalAlignment: Text.AlignHCenter
      text: rowRoot.side === "left" ? "\uf177" : "\uf00c"
      color: Color.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: function(mouse) { rowRoot.triggered(mouse.button) }
    }
  }

  PopupCard {
    id: popup
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(220))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(360))

    Text {
      visible: root.candidates.length === 0
      anchors.centerIn: parent
      width: parent.width
      text: "No other plugins installed"
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    // Flickable, not a bare Column -- the candidate list can run past
    // the popup's own Style.space(360) cap (13 real plugins already do,
    // on a stock install), same reasoning as ruixen.weather's own
    // weatherScroll.
    Flickable {
      id: flick
      visible: root.candidates.length > 0
      anchors.fill: parent
      contentWidth: width
      contentHeight: column.implicitHeight
      clip: true
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: column
        width: flick.width
        spacing: Style.space(2)

        Repeater {
          model: root.candidates

          PluginRow {
            required property var modelData
            width: column.width
            pluginId: modelData.id
            pluginName: modelData.name
            side: modelData.side || ""
            onTriggered: function(button) {
              root.setPinSide(modelData.id, button === Qt.RightButton ? "left" : "right")
            }
          }
        }
      }
    }
  }
}
