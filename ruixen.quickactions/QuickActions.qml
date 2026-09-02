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

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  property bool popupOpen: false

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
      color: mouse.containsMouse ? Style.hoverFillFor(root.foreground, root.foreground) : "transparent"
    }

    Text {
      id: iconText
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      width: Style.space(22)
      horizontalAlignment: Text.AlignHCenter
      text: rowRoot.glyph
      color: rowRoot.active ? root.foreground : Qt.darker(root.foreground, 1.4)
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      anchors.left: iconText.right
      anchors.leftMargin: Style.space(8)
      text: rowRoot.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }

    Text {
      visible: rowRoot.statusText !== ""
      anchors.verticalCenter: parent.verticalCenter
      anchors.right: parent.right
      anchors.rightMargin: Style.space(10)
      text: rowRoot.statusText
      color: Qt.darker(root.foreground, 1.4)
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
    // Back to anchored under this widget's own icon (PopupCard's own
    // default: centerOnBar false, margin unoverridden) -- direct
    // request to revert the screen-centered match with weather/clock
    // from e0429b7/61ef0bd: "it doesn't need to be center anymore, it
    // can go back to being below the icon". That earlier change was
    // purely a visual-consistency choice, not a fix for anything broken
    // here -- this popup's own icon-relative position was never
    // reported as a problem (unlike weather/clock's, which genuinely
    // did overlap the Notch). The margin compensation from 61ef0bd
    // (backing root.bar.screenMarginTop out of margin) existed only to
    // match weather/clock's screen-centered Y exactly; reverting to
    // plain icon-relative positioning drops the need for it too, so
    // both are removed together rather than leaving one half-applied.
    contentWidth: popup.fittedContentWidth(Style.space(200))
    contentHeight: popup.fittedContentHeight(column.implicitHeight)

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
