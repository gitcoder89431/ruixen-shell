import QtQuick
import Quickshell
import Quickshell.Io

// Polls helper/status.py on a timer and exposes the live device list.
// Shape (Process on a Timer, JSON stdout) ported from
// github.com/xgborgeso/omarchy-peripheral-batteries's own Service.qml (MIT
// license) -- notification/threshold logic from that original was NOT
// ported, see helper/status.py's own header comment for why.
Item {
  id: root

  property var devices: []
  property string lastError: ""
  readonly property bool hasDevices: devices.length > 0

  readonly property int refreshIntervalSec: 30

  function helperScript() {
    var resolved = Qt.resolvedUrl("helper/status.py").toString()
    return resolved.replace(/^file:\/\//, "")
  }

  function refresh() {
    if (statusProcess.running) return
    statusProcess.command = ["python3", helperScript()]
    statusProcess.running = true
  }

  function applyStatus(raw) {
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (e) {
      root.lastError = "Could not parse peripheral status"
      return
    }
    if (!parsed || parsed.ok !== true || !Array.isArray(parsed.devices)) {
      root.lastError = String((parsed && parsed.error) || "Could not query peripherals")
      return
    }
    root.lastError = ""
    root.devices = parsed.devices
  }

  Component.onCompleted: refresh()

  Timer {
    interval: Math.max(5, root.refreshIntervalSec) * 1000
    running: true
    repeat: true
    onTriggered: root.refresh()
  }

  Process {
    id: statusProcess
    running: false
    command: []
    stdout: StdioCollector { id: statusStdout; waitForEnd: true }
    stderr: StdioCollector { id: statusStderr; waitForEnd: true }
    onExited: function(exitCode) {
      var out = String(statusStdout.text || "")
      var err = String(statusStderr.text || "")
      if (exitCode === 0 && out) root.applyStatus(out)
      else root.lastError = err || "Could not query peripherals"
    }
  }
}
