import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// Battery percentage for wireless peripherals (mice/keyboards/headsets/
// controllers) -- one bar icon, showing a real battery-state glyph for
// whichever single device is selected, same interaction language as
// Omarchy's own omarchy.power (its own laptop-battery bar icon: always a
// battery glyph, right-click toggles the percentage, click opens a
// panel). Direct follow-up after shipping a first pass with multi-device
// pin badges + a generic plug trigger: "the pin ability kinda sucks,
// doesnt look good... does omarchy power just show the battery level,
// can we collapse it into this so the main icon shows the battery icon
// always." omarchy.power itself is a stock /usr/share/omarchy file (we
// never edit those) and only ever shows the laptop's own single battery
// -- can't literally merge into it, so this file adopts its pattern
// instead, single-selection (not omarchy.power's own multi-badge idea)
// per direct confirmation: "one icon only, pick a single device."
//
// Detection (Service.qml + helper/status.py) is ported from
// github.com/xgborgeso/omarchy-peripheral-batteries (MIT) -- see
// helper/status.py's own header for why (Quickshell.Bluetooth's own
// battery property and Quickshell.Services.UPower both have real, live-
// confirmed coverage gaps that reading /sys directly doesn't have).
BarWidget {
  id: root
  moduleName: "ruixen.peripherals"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property var peripheralsService: bar?.shell?.firstPartyServiceFor("ruixen.peripherals")
  readonly property var devices: peripheralsService ? peripheralsService.devices : []

  // Direct sibling keys on this widget's OWN shell.json layout entry
  // (id excluded) become `settings` -- see ruixen.bar/BarModel.js's own
  // entrySettings(), same convention omarchy.clock's format/formatAlt
  // already use. No new state file needed.
  readonly property string selectedId: root.setting("selectedId", "")
  readonly property var selectedDevice: root.deviceById(root.selectedId)

  function deviceById(id) {
    if (!id) return null
    for (var i = 0; i < root.devices.length; i++) {
      if (root.devices[i].id === id) return root.devices[i]
    }
    return null
  }

  // Same read-modify-persist primitive ruixen.pluginpins' own setPinSide
  // uses, but writing a single selectedId string on THIS widget's own
  // layout entry instead of moving entries between bar sections.
  // Clicking the already-selected row clears the selection (empty
  // string), same toggle feel as a real radio choice you can turn off.
  function selectDevice(id) {
    if (!bar || !bar.shell || typeof bar.shell.mutateShellConfig !== "function") return
    bar.shell.mutateShellConfig(function(config) {
      if (!config.bar || !config.bar.layout) return
      var sections = ["left", "center", "right"]
      for (var i = 0; i < sections.length; i++) {
        var arr = config.bar.layout[sections[i]]
        if (!Array.isArray(arr)) continue
        for (var j = 0; j < arr.length; j++) {
          var entry = arr[j]
          if (!entry || entry.id !== root.moduleName) continue
          entry.selectedId = (entry.selectedId === id) ? "" : id
          return
        }
      }
    })
  }

  // Font Awesome solid, \u escapes only -- never a pasted glyph, per
  // ruixen.pluginpins' own established reasoning (corrupted-byte issues
  // hit twice already elsewhere in this repo). Used for the dropdown
  // list's own per-row device-kind icon, and reused by the main bar
  // icon's own mainText() for the "no fresh reading" and "nothing
  // selected" cases -- see mainText() below.
  //
  // "mouse" is \uefba, not FA's own standard \uf8cc codepoint for the
  // same computer-mouse icon -- confirmed live by inspecting this
  // machine's actual font file (JetBrainsMonoNerdFont-Regular.ttf) with
  // fontTools: f8cc renders as a missing-glyph box in this font, while
  // efba is the same icon (glyph name "fa-computer_mouse" in the font's
  // own cmap), just remapped to a different Private-Use-Area codepoint
  // by however this particular Nerd Font build was patched.
  function kindGlyph(kind) {
    switch (kind) {
      case "mouse": return "\uefba"
      case "keyboard": return "\uf11c"
      case "headset": return "\uf025"
      case "controller": return "\uf11b"
      default: return "\uf1e6"
    }
  }

  // Direct follow-up after shipping the real battery-glyph icon here:
  // "instead of showing the same battery icon as the laptop power
  // battery, can be confusing, can it just show the % number." Retired
  // the whole battery-glyph icon set (both the 10-level default/
  // charging arrays and the earlier md-battery_unknown fallback) in
  // favor of plain text -- a real number reads unambiguously as "this
  // peripheral," where a battery-shaped icon could be mistaken for
  // omarchy.power's own laptop battery at a glance.
  function mainText(device) {
    // Nothing selected yet -- generic plug, same as ever.
    if (!device) return "\uf1e6"
    // No fresh reading -- the device's own kind icon (see previous
    // commit's own reasoning), unchanged by this pass.
    if (!device.available) return root.kindGlyph(device.kind)
    return root.percentText(device)
  }

  function percentText(device) {
    return device && device.available ? Math.round(device.level) + "%" : "--"
  }

  // Cheap, fixed low-battery cue -- direct scope: "know if it needs to be
  // charged," not a configurable-threshold/notification system (that's
  // the source plugin's own separate feature, not asked for here).
  readonly property int lowBatteryPercent: 20

  function percentColor(device) {
    if (!device || !device.available) return Color.muted
    return device.level < root.lowBatteryPercent ? Color.urgent : root.foreground
  }

  property bool popupOpen: false
  function close() { popupOpen = false }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    bar: root.bar
    text: root.mainText(root.selectedDevice)
    // Fixed width whenever a real percentage is being shown (not
    // dependent on the number's own digit count) -- direct follow-up:
    // "make sure the number dont shift between 2 or 3 digits oldly."
    // The slot's own width only depends on WHETHER a percent is being
    // displayed at all, never on the current value, so it stays put as
    // a real device's battery drains from "100%" down through "9%" --
    // only the icon-vs-percent cases (nothing selected / no reading)
    // ever actually change width, and those are discrete state changes,
    // not a live-updating number.
    slotSize: Style.bar.iconSlot * (root.selectedDevice && root.selectedDevice.available && !vertical ? 2 : 1)
    tooltipText: root.selectedDevice ? root.selectedDevice.name : "Wireless peripherals -- pick one to show here"
    onPressed: function() { root.popupOpen = !root.popupOpen }
  }

  component DeviceRow: Item {
    id: rowRoot
    required property var device
    signal triggered()

    implicitHeight: Style.space(32)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: mouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
    }

    // One slot, not two -- direct follow-up ("the popup is a bit too
    // wide, instead of a column where theres a check that comes in, can
    // we place the pin device with the check instead of the device
    // icon on that row"): the device-kind icon and the "this one's
    // selected" indicator share the same position now. Selected shows
    // a check (U+F00C, accent-colored, same glyph ruixen.pluginpins'
    // own checkGlyph already uses); everything else still shows its
    // own kind icon. Removes the separate right-side check column
    // entirely, narrowing the row by that column's own width.
    readonly property bool isSelected: root.selectedId === rowRoot.device.id
    Text {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      width: Style.space(16)
      horizontalAlignment: Text.AlignHCenter
      text: rowRoot.isSelected ? "\uf00c" : root.kindGlyph(rowRoot.device.kind)
      color: rowRoot.isSelected ? Color.accent : root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: glyph.right
      anchors.right: percent.left
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(6)
      elide: Text.ElideRight
      text: rowRoot.device.name || (rowRoot.device.brand + " " + rowRoot.device.kind)
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      id: percent
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      width: Style.space(28)
      horizontalAlignment: Text.AlignRight
      text: root.percentText(rowRoot.device)
      color: root.percentColor(rowRoot.device)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: rowRoot.triggered()
    }
  }

  PopupCard {
    id: popup
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.popupOpen
    // Narrowed from 240 -- removing the separate check column (merged
    // into the device-kind icon slot, see DeviceRow's own comment)
    // freed up a whole column's worth of width.
    contentWidth: popup.fittedContentWidth(Style.space(210))
    contentHeight: popup.fittedContentHeight(column.implicitHeight, Style.space(360))

    // Escape to dismiss, matching every other PopupCard in this repo.
    Item {
      id: escapeCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()
    }
    onOpenChanged: if (open) Qt.callLater(function() { escapeCatcher.forceActiveFocus() })

    Text {
      visible: root.devices.length === 0
      anchors.centerIn: parent
      width: parent.width
      text: root.peripheralsService && root.peripheralsService.lastError
        ? root.peripheralsService.lastError
        : "No wireless peripherals found"
      color: Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignHCenter
      wrapMode: Text.WordWrap
    }

    Flickable {
      id: flick
      visible: root.devices.length > 0
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
          model: root.devices

          DeviceRow {
            required property var modelData
            width: column.width
            device: modelData
            onTriggered: root.selectDevice(modelData.id)
          }
        }
      }
    }
  }
}
