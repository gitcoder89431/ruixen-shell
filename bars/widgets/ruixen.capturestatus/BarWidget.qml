import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Live privacy/status chip for Omarchy's built-in screen recorder.
// Omarchy's capture script starts gpu-screen-recorder and stops it with
// SIGINT so the video finalizes cleanly; mirror that same process contract
// instead of inventing separate state.
BarWidget {
  id: root
  moduleName: "ruixen.capturestatus"

  property bool recording: false
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  function refresh() {
    if (!recordingProbe.running) recordingProbe.running = true
  }

  Component.onCompleted: refresh()

  Timer {
    interval: 2000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: recordingProbe
    command: ["pgrep", "--quiet", "-f", "^gpu-screen-recorder"]
    onExited: function(exitCode) { root.recording = exitCode === 0 }
  }

  implicitWidth: root.recording ? chip.implicitWidth : 0
  implicitHeight: chip.implicitHeight
  visible: root.recording

  BarIconButton {
    id: chip
    anchors.fill: parent
    bar: root.bar
    text: "●"
    foreground: Color.urgent
    fontSize: Style.font.body
    tooltipText: "Screen recording active. Click to stop."
    onPressed: function() {
      if (root.bar) root.bar.run("omarchy-capture-screenrecording --stop-recording")
    }
  }
}
