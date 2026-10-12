import QtQuick
import Quickshell
import Quickshell.Io

// Headless state for Artwork rotation -- used to be a full expandable
// card (WallpaperRotationControls: title row, Rotate artwork/Shuffle
// toggles, interval chips, a folder path field, a Next artwork button),
// then a Shuffle toggle chip plus five interval chips, then a
// Shuffle-label/value grouped pill with a separate right-click shuffle
// toggle. Direct correction on all of that ("i just need to shuffle...
// at intervals... is it like that", "keep the shape as chips"): there's
// no separate shuffle on/off state any more -- rotation always shuffles
// whenever it's on, so the only real axis left is the interval. One
// flat chip, left click only, cycling Off -> 5m -> 15m -> 30m -> 60m ->
// Off. This file is just the probe/debounce/write plumbing that chip
// uses, same IPC surface (ruixen-wallpaper-rotation) as before.
// "folder" is deliberately never sent -- the backend already defaults
// to and keeps ~/Pictures/ruixen-wallpapers when it's omitted from a
// configure call.
Item {
  id: root
  property bool active: false
  property bool available: false
  property var settings: ({})
  property string pending: ""
  readonly property var cycleSteps: [5, 15, 30, 60]
  function refresh() { if (active && !probe.running) probe.running = true }
  // Off keeps the remembered interval untouched, so cycling back past
  // it later resumes the same cadence instead of resetting to 5m.
  // shuffle is always sent true whenever enabled -- there's no UI path
  // left that can set it to false.
  function cycleInterval() {
    var currentIndex = settings.enabled === true ? cycleSteps.indexOf(settings.intervalMinutes) : -1
    var nextIndex = currentIndex + 1
    if (nextIndex >= cycleSteps.length) nextIndex = -1
    var nextEnabled = nextIndex !== -1
    settings = Object.assign({}, settings, {
      enabled: nextEnabled,
      intervalMinutes: nextEnabled ? cycleSteps[nextIndex] : settings.intervalMinutes,
      shuffle: true
    })
    pending = JSON.stringify({enabled: settings.enabled === true, shuffle: true, intervalMinutes: settings.intervalMinutes})
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
