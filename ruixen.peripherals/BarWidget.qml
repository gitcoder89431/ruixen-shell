import QtQuick
import QtQuick.Layouts
import Quickshell
import qs.Commons
import qs.Ui

// Battery percentage for wireless peripherals (mice/keyboards/headsets/
// controllers), pinned to the bar the same way ruixen.pluginpins pins
// other plugins -- direct request: "displayed as icons on our topbar so
// they can see the battery level and pin it, kinda like the pinplugins."
//
// Detection (Service.qml + helper/status.py) is ported from
// github.com/xgborgeso/omarchy-peripheral-batteries (MIT) -- see
// helper/status.py's own header for why (Quickshell.Bluetooth's own
// battery property and Quickshell.Services.UPower both have real, live-
// confirmed coverage gaps that reading /sys directly doesn't have). This
// file is new: their own UI is a single dropdown-only bar icon: this one
// additionally renders a small icon+percentage per PINNED device inline
// in the bar, and drives pinning off this widget's own shell.json layout
// entry instead of a settings-schema panel.
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
  readonly property var pinnedIds: root.setting("pinnedIds", [])

  function isPinned(id) { return root.pinnedIds.indexOf(id) !== -1 }

  function deviceById(id) {
    for (var i = 0; i < root.devices.length; i++) {
      if (root.devices[i].id === id) return root.devices[i]
    }
    return null
  }

  // Same read-modify-persist primitive ruixen.pluginpins' own setPinSide
  // uses, but mutating THIS widget's own layout entry's pinnedIds array
  // directly instead of moving entries between bar sections.
  function togglePin(id) {
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
          var ids = Array.isArray(entry.pinnedIds) ? entry.pinnedIds.slice() : []
          var idx = ids.indexOf(id)
          if (idx >= 0) ids.splice(idx, 1)
          else ids.push(id)
          entry.pinnedIds = ids
          return
        }
      }
    })
  }

  // Font Awesome solid, \u escapes only -- never a pasted glyph, per
  // ruixen.pluginpins' own established reasoning (corrupted-byte issues
  // hit twice already elsewhere in this repo).
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

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  RowLayout {
    id: row
    anchors.fill: parent
    spacing: Style.space(6)

    Repeater {
      model: root.pinnedIds

      RowLayout {
        id: pinnedBadge
        required property var modelData
        readonly property var device: root.deviceById(modelData)
        // A pin can outlive the device it points at (unplugged, out of
        // range) -- render nothing rather than a stale/blank badge.
        visible: pinnedBadge.device !== null
        spacing: Style.space(3)

        Text {
          text: pinnedBadge.device ? root.kindGlyph(pinnedBadge.device.kind) : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          text: pinnedBadge.device ? root.percentText(pinnedBadge.device) : ""
          color: root.percentColor(pinnedBadge.device)
          font.family: root.fontFamily
          font.pixelSize: Style.font.bodySmall
        }
      }
    }

    BarIconButton {
      id: button
      bar: root.bar
      text: "\uf1e6"
      tooltipText: "Wireless peripherals"
      onPressed: function() { root.popupOpen = !root.popupOpen }
    }
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

    Text {
      id: glyph
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(10)
      width: Style.space(16)
      horizontalAlignment: Text.AlignHCenter
      text: root.kindGlyph(rowRoot.device.kind)
      color: root.foreground
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
      anchors.right: pinGlyph.left
      anchors.rightMargin: Style.space(8)
      width: Style.space(28)
      horizontalAlignment: Text.AlignRight
      text: root.percentText(rowRoot.device)
      color: root.percentColor(rowRoot.device)
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    // Star ("star", U+F005) filled-in color when pinned, muted outline
    // color otherwise -- same slot/position convention as
    // ruixen.pluginpins' own checkGlyph.
    Text {
      id: pinGlyph
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      width: Style.space(16)
      horizontalAlignment: Text.AlignHCenter
      text: "\uf005"
      color: root.isPinned(rowRoot.device.id) ? Color.accent : Qt.darker(root.foreground, 1.6)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
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
    contentWidth: popup.fittedContentWidth(Style.space(240))
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
            onTriggered: root.togglePin(modelData.id)
          }
        }
      }
    }
  }
}
