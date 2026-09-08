import QtQuick
import Quickshell
import Quickshell.Io

// Polls helper/status.py on a timer and exposes the live device list.
// Shape (Process on a Timer, JSON stdout) ported from
// github.com/xgborgeso/omarchy-peripheral-batteries's own Service.qml (MIT
// license) -- notification/threshold logic from that original was NOT
// ported, see helper/status.py's own header comment for why.
//
// Also mirrors devices/lastError to a small state file
// (~/.local/state/ruixen/peripherals-state.json) -- ruixen-shell issue
// #40: Omarchy v4.0.3 restricts shell.firstPartyServiceFor() to a fixed
// 4-item allowlist of Omarchy's own services, so BarWidget.qml (a
// separate QML instance from this one, only ever handed whatever
// ruixen.bar's own ModuleSlot chooses to inject, never a shell
// property of its own) can no longer reach this service directly.
// Write-only relay, not a real persisted store -- device state is
// always freshly recomputed from live hardware on every poll, nothing
// here is meant to survive a restart, so there is no matching load
// path the way KanbanService.qml's own real persistence needs one.
Item {
  id: root

  property var devices: []
  property string lastError: ""
  readonly property bool hasDevices: devices.length > 0

  readonly property int refreshIntervalSec: 30

  readonly property string home: Quickshell.env("HOME")
  readonly property string statePath: home + "/.local/state/ruixen/peripherals-state.json"

  // Debounced the same way KanbanService.qml's own saves are -- applyStatus
  // can update devices and lastError as two separate property writes for
  // one poll result, and there is no reason to write the file twice for
  // what is really one logical update.
  Timer {
    id: saveTimer
    interval: 400
    repeat: false
    onTriggered: root.flushState()
  }

  function scheduleSave() { saveTimer.restart() }

  function flushState() {
    stateFile.setText(JSON.stringify({ devices: root.devices, lastError: root.lastError }) + "\n")
  }

  onDevicesChanged: scheduleSave()
  onLastErrorChanged: scheduleSave()

  FileView {
    id: stateFile
    path: root.statePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", root.home + "/.local/state/ruixen"]
    running: false
  }

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

  Component.onCompleted: {
    ensureDirProc.running = true
    refresh()
  }

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
