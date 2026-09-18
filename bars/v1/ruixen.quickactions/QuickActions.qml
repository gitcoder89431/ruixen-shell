import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// A small "more actions" menu for the toggles/tray area, for indicators
// that aren't clean booleans like stay-awake/DND (see ruixen-tray-widgets)
// and so aren't worth their own permanent pill icon: dictation and screen
// recording are process/status driven with a command dispatched on click,
// reminders are a count + a "compose" flow. All four bodies are ported
// straight from their stock plugins/bar/indicators/*.qml counterparts,
// just rendered as popup rows instead of a hover-revealed icon cluster.
BarWidget {
  id: root
  moduleName: "ruixen.quickactions"

  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool popupOpen: false

  // Required -- PopupCard's own close() (fired by its outside-click
  // HyprlandFocusGrab) does `if (owner && "close" in owner)
  // owner.close(); else root.open = false`. Without this, it takes the
  // else branch and assigns directly to ITS OWN open property, which
  // permanently breaks the one-way `open: root.popupOpen` binding below
  // -- popupOpen keeps toggling normally on further clicks, but the
  // popup's own open property is now a dead static false, disconnected
  // from it. Same latent bug found and fixed in ruixen.pluginpins
  // (direct live report there: "it worked once but i dismissed it and
  // then clicking on it again doesnt do anything anymore") -- this
  // widget has the identical owner: root with no close(), so it was
  // exposed to the same failure, just not yet reported. Matches
  // ruixen.media's own identical close() for the identical reason.
  function close() { popupOpen = false }

  property string dictationState: "idle"
  readonly property bool dictationActive: dictationState === "recording"

  property bool recording: false

  readonly property var nightlightService: bar ? bar.shell.firstPartyServiceFor("omarchy.nightlight") : null
  readonly property bool nightlightOn: nightlightService ? nightlightService.enabled : false

  // Same real service/toggle ruixen.dnd's own standalone bar pill used --
  // that pill was removed from the bar layout (DND toggle already lives
  // in ruixen.notch's own bell now, made the standalone pill redundant),
  // folded in here instead so the action itself isn't lost.
  readonly property var notificationService: bar ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false

  property int reminderCount: 0

  function refreshRecording() {
    if (!recordingProbe.running) recordingProbe.running = true
  }

  function refreshReminders() {
    if (!reminderProbe.running) reminderProbe.running = true
  }

  Component.onCompleted: {
    refreshRecording()
    refreshReminders()
  }

  onPopupOpenChanged: if (popupOpen) {
    refreshRecording()
    refreshReminders()
  }

  // Dictation has no plain start/stop command -- omarchy-voxtype-config is
  // the only action the stock indicator offers, same here.
  Process {
    id: dictationProc
    command: ["bash", "-c", "omarchy-voxtype-status"]
    running: true
    stdout: SplitParser {
      onRead: function(data) {
        var parsed = Util.parseModuleJson(data)
        root.dictationState = String(parsed.alt || parsed.class || "idle")
      }
    }
  }

  Process {
    id: recordingProbe
    command: ["pgrep", "--quiet", "-f", "^gpu-screen-recorder"]
    onExited: function(exitCode) { root.recording = exitCode === 0 }
  }

  Process {
    id: reminderProbe
    command: ["omarchy-reminder", "show", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.reminderCount = Number(Util.parseModuleJson(text).count || 0)
    }
    onExited: function(exitCode) { if (exitCode !== 0) root.reminderCount = 0 }
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Sliders-vertical (Font Awesome sliders, U+F1DE) -- swapped from a gear icon.
    text: ""
    tooltipText: "More actions"
    onPressed: function() { root.popupOpen = !root.popupOpen }
  }

  component ActionRow: Item {
    id: rowRoot
    required property string glyph
    required property string label
    property bool active: false
    property string statusText: ""
    signal triggered()

    implicitHeight: Style.space(32)

    Rectangle {
      anchors.fill: parent
      radius: Style.cornerRadius
      color: mouse.containsMouse ? Style.hoverFillFor(Color.popups.text, Color.popups.text) : "transparent"
    }

    Text {
      id: iconText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      width: Style.space(22)
      horizontalAlignment: Text.AlignHCenter
      text: rowRoot.glyph
      color: rowRoot.active ? Color.popups.text : Util.alpha(Color.popups.text, 0.75)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: iconText.right
      anchors.leftMargin: Style.space(8)
      text: rowRoot.label
      color: Color.popups.text
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      visible: rowRoot.statusText !== ""
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      // Full strength, not muted -- direct report: status text (the
      // actual state being reported, e.g. "Enabled"/"Connected") was
      // reading as "disabled" simply for being dimmed like a secondary
      // label. Muting stays for genuinely secondary text (empty-state
      // copy, the icon glyph's own unfocused-tab dimming above); a
      // status value is the answer to the row's own question, not
      // decoration.
      color: Color.popups.text
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
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
    anchorItem: root
    owner: root
    bar: root.bar
    open: root.popupOpen
    // centerOnBar stays reverted (e0429b7 was purely a visual-consistency
    // choice, correctly dropped per direct request -- this popup should
    // stay anchored under its own icon horizontally, not screen-centered).
    //
    // The Y position needed real live tuning, not a derived formula --
    // two analytical attempts (61ef0bd's own screenMarginTop
    // compensation, calibrated for centerOnBar's different formula; then
    // a barH-cancellation meant to land exactly on the bar's own true
    // edge) were each verified live and wrong in opposite directions.
    // The plain PopupCard default (no override) was ALSO verified live
    // to be wrong, still overlapping the bar's own reserved height above
    // the icon row -- confirmed via ruixen.pluginpins' own identical
    // popup (same BarIconButton, same real height) that PopupCard's own
    // target.height + margin math needs a real live-measured margin
    // between the plain default (5, too high) and full barH cancellation
    // (29, too low). 17 is that number, confirmed live on pluginpins
    // first -- same icon component/height here, so it transfers directly.
    margin: 17
    contentWidth: popup.fittedContentWidth(Style.space(200))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

    // Escape to dismiss, matching Omarchy's own dropdowns -- direct
    // request. See ruixen.pluginpins/BarWidget.qml's identical block
    // for the full "why" (PopupCard itself has no such handling,
    // xdg-popups can still receive keys once something inside holds
    // active focus).
    Item {
      id: escapeCatcher
      anchors.fill: parent
      focus: true
      Keys.onEscapePressed: root.close()
    }
    onOpenChanged: if (open) Qt.callLater(function() { escapeCatcher.forceActiveFocus() })

    Column {
      id: column
      anchors.fill: parent
      spacing: 0

      ActionRow {
        width: column.width
        glyph: "󰍬"
        label: "Dictate"
        active: root.dictationActive
        statusText: root.dictationActive ? "Recording" : ""
        onTriggered: {
          root.popupOpen = false
          if (root.bar) root.bar.run("omarchy-voxtype-config")
        }
      }

      ActionRow {
        width: column.width
        glyph: "󰻂"
        label: "Screen Recording"
        active: root.recording
        statusText: root.recording ? "Recording" : ""
        onTriggered: {
          root.popupOpen = false
          if (root.bar) root.bar.run(root.recording ? "omarchy-capture-screenrecording --stop-recording" : "omarchy-menu toggle trigger.capture.screenrecord")
        }
      }

      ActionRow {
        width: column.width
        glyph: "󰔎"
        label: "Night Light"
        active: root.nightlightOn
        statusText: root.nightlightOn ? "On" : ""
        onTriggered: {
          root.popupOpen = false
          if (root.nightlightService) root.nightlightService.setNightlight(!root.nightlightOn)
        }
      }

      ActionRow {
        width: column.width
        glyph: "󰂛"
        label: "Do Not Disturb"
        active: root.dnd
        statusText: root.dnd ? "On" : ""
        onTriggered: {
          root.popupOpen = false
          if (root.notificationService) root.notificationService.setDoNotDisturb(!root.dnd)
        }
      }

      ActionRow {
        width: column.width
        glyph: "󰢌"
        label: "Reminders"
        active: root.reminderCount > 0
        statusText: root.reminderCount > 0 ? String(root.reminderCount) : ""
        onTriggered: {
          root.popupOpen = false
          if (root.reminderCount > 0) Quickshell.execDetached(["omarchy-reminder", "show"])
          else Quickshell.execDetached(["omarchy-reminder", "-i"])
        }
      }
    }
  }
}
