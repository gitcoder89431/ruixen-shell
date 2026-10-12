import QtQuick
import Quickshell
import Quickshell.Io

// Headless state for Artwork rotation -- used to be a full expandable
// card (WallpaperRotationControls: title row, Rotate artwork/Shuffle
// toggles, interval chips, a folder path field, a Next artwork button),
// then a Shuffle toggle chip plus five separate interval chips. Direct
// correction on THAT, too ("shit thats wierd, to have shuffle and off
// as a chip"): collapsed further into the one chip
// WallpapersContent.qml now renders -- left click cycles
// Off -> 5m -> 15m -> 30m -> 60m -> Off, right click toggles Shuffle
// without touching the interval/enabled state. This file is just the
// probe/debounce/write plumbing that chip uses, same IPC surface
// (ruixen-wallpaper-rotation) as before. "folder" is deliberately never
// sent -- the backend already defaults to and keeps
// ~/Pictures/ruixen-wallpapers when it's omitted from a configure call.
Item {
  id: root
  property bool active: false
  property bool available: false
  property var settings: ({})
  property string pending: ""
  readonly property var cycleSteps: [5, 15, 30, 60]
  function refresh() { if (active && !probe.running) probe.running = true }
  function change(key, value) {
    settings = Object.assign({}, settings, {[key]: value})
    pending = JSON.stringify({enabled: settings.enabled === true, shuffle: settings.shuffle === true, intervalMinutes: settings.intervalMinutes})
    debounce.restart()
  }
  // Off keeps the remembered interval untouched, so cycling back past
  // it later resumes the same cadence instead of resetting to 5m.
  // Turning rotation ON (the Off -> 5m step) also turns Shuffle on --
  // that's what "clicking on the shuffle" means for a chip that starts
  // on Off. Stepping between two already-enabled intervals (5m -> 15m
  // etc.) leaves Shuffle exactly as it is, so a prior right-click stays
  // in effect instead of getting silently re-enabled.
  function cycleInterval() {
    var currentIndex = settings.enabled === true ? cycleSteps.indexOf(settings.intervalMinutes) : -1
    var nextIndex = currentIndex + 1
    if (nextIndex >= cycleSteps.length) nextIndex = -1
    var turningOn = currentIndex === -1 && nextIndex !== -1
    var nextEnabled = nextIndex !== -1
    settings = Object.assign({}, settings, {
      enabled: nextEnabled,
      intervalMinutes: nextEnabled ? cycleSteps[nextIndex] : settings.intervalMinutes,
      shuffle: turningOn ? true : settings.shuffle
    })
    pending = JSON.stringify({enabled: settings.enabled === true, shuffle: settings.shuffle === true, intervalMinutes: settings.intervalMinutes})
    debounce.restart()
  }
  function send() {
    if (writer.running || !pending) return
    writer.command = ["omarchy-shell", "ruixen-wallpaper-rotation", "configure", pending]
    pending = ""
    writer.running = true
  }
  onActiveChanged: refresh()
  Component.onCompleted: refresh()
  Timer { id: debounce; interval: 200; onTriggered: root.send() }
  Timer { interval: 1000; running: root.active; repeat: true; onTriggered: root.refresh() }
  Process {
    id: probe
    command: ["omarchy-shell", "ruixen-wallpaper-rotation", "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.pending || writer.running) return
        try { root.settings = JSON.parse(text); root.available = true } catch (e) { root.available = false }
      }
    }
  }
  Process { id: writer; onExited: (code, status) => { if (root.pending) debounce.restart(); else root.refresh() } }
}
