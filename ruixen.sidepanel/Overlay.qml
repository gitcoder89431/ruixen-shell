import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Prototype for the "new notch" idea: instead of an overlay that floats
// above windows (ruixen.notch's own approach), this is a real wlr-layer-
// shell exclusive zone on the left edge -- tiled windows actually resize
// to make room for it, like ruixen.bar's own top-edge reservation. Direct
// request: "left panel that pushes in... wanna see how that looks with
// animation, going with more of an edex style where the panels can show
// like calendar, or next task, system update... feels like a workspace
// monitor."
//
// First pass is deliberately just the push mechanic + placeholder cards,
// not real data -- confirming the exclusiveZone animation itself feels
// right (toggle, not always-on, per direct choice) before wiring up
// calendar/tasks/logs/system-stats content.
//
// Contract matches every other Ruixen overlay plugin (see
// ruixen.settings/Settings.qml's own comment on this -- confirmed
// against Omarchy's own built-in overlay plugins directly): root exposes
// shell/manifest, open()/close()/toggle()/dismiss(), PanelWindow visible
// follows root.opened. dismiss() calls shell.hide() so
// `omarchy-shell shell toggle ruixen.sidepanel` and an in-panel
// Escape/click-away stay in sync.
Item {
  id: root
  property var shell: null
  property var manifest: null

  property bool opened: false

  function open(payloadJson) {
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "ruixen.sidepanel")
  }

  function toggle(payloadJson) {
    if (root.opened) root.dismiss()
    else root.open(payloadJson)
  }

  readonly property int panelWidth: 320

  // Drives both the window's own width AND its exclusiveZone together --
  // this single animated value IS the push effect. exclusionMode stays
  // Normal at all times (same as ruixen.bar's own docked reservation);
  // there's no need to flip to Ignore on close the way ruixen.bar does
  // for its hidden-bar case, since 0 already reserves nothing.
  property real revealWidth: 0
  Behavior on revealWidth {
    NumberAnimation { duration: 160; easing.type: Easing.OutCubic }
  }
  onOpenedChanged: {
    root.revealWidth = root.opened ? root.panelWidth : 0
    root.writeOpenState()
  }

  // ruixen.frame-widget's own decorative border has zero knowledge of
  // this panel's exclusive zone (it's a completely separate overlay
  // plugin, drawn from full-screen bounds) -- direct report after first
  // trying this live: "that fucked up our frame pretty badly... can the
  // frame move in too?" Same fix shape as barHidden's own cross-plugin
  // sync (see ruixen.notch/Overlay.qml's own comment on that): a shared
  // on-disk flag, each plugin runs its OWN local animation off it,
  // rather than one plugin calling into the other directly.
  readonly property string ruixenStateDir: Quickshell.env("HOME") + "/.local/state/ruixen"
  readonly property string openStatePath: root.ruixenStateDir + "/sidepanel-open"
  Process { id: openStateWriteProc }
  function writeOpenState() {
    openStateWriteProc.exec(["bash", "-c",
      "mkdir -p '" + root.ruixenStateDir + "' && printf '%s' '" +
      (root.opened ? "1" : "0") + "' > '" + root.openStatePath + "'"])
  }

  readonly property color panelBackground: "#000000"
  readonly property color textColor: "#e8e8e8"
  readonly property color muted: Qt.rgba(1, 1, 1, 0.45)
  readonly property color accent: Color.accent
  readonly property string fontFamily: "JetBrainsMono Nerd Font"

  PanelWindow {
    id: panel
    anchors { top: true; left: true; bottom: true }
    exclusionMode: ExclusionMode.Normal
    exclusiveZone: root.revealWidth
    implicitWidth: Math.max(1, root.revealWidth)
    color: "transparent"

    WlrLayershell.namespace: "ruixen-sidepanel"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
      anchors.fill: parent
      color: root.panelBackground
      clip: true

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        Text {
          text: "Workspace"
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 18
          font.bold: true
        }

        // Placeholder cards -- real content (calendar, next task, system
        // update, CPU/RAM, logs/permission requests) is deliberately
        // deferred until the push mechanic itself is confirmed to feel
        // right. Same OLED-card look as ruixen.settings/ruixen.notch's
        // own stat tiles (Qt.rgba(1, 1, 1, 0.05) fill).
        Repeater {
          model: ["Calendar", "Next Task", "System"]
          delegate: Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 96
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.05)

            Text {
              anchors { left: parent.left; top: parent.top; margins: 12 }
              text: modelData
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 13
            }
          }
        }

        Item { Layout.fillHeight: true }
      }
    }
  }
}
