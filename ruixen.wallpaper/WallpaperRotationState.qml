import QtQuick
import Quickshell
import Quickshell.Io

// Issue #105: this is now the one real, hand-maintained copy. Every
// picker UI that needs it (ruixen.notch, and both of ruixen.launcher's
// Wallpapers/Wallpaper Shuffle extensions) gets its own copy deployed
// here by install.sh (inject_shared_wallpaper_files) at install/update
// time -- plugins must be self-contained directories (no cross-plugin
// imports), so each still carries a real file on disk, just no longer a
// hand-copied one. Edit only here; tests/install-shared-wallpaper-
// files.sh proves install.sh actually deploys an identical copy to all
// three picker UIs.
//
// Headless state for Artwork rotation -- used to be a full expandable
// card (WallpaperRotationControls: title row, Rotate artwork/Shuffle
// toggles, interval chips, a folder path field, a Next artwork button),
// then a Shuffle toggle chip plus five interval chips, then a
// Shuffle-label/value grouped pill with a separate right-click shuffle
// toggle. Direct correction on all of that ("i just need to shuffle...
// at intervals... is it like that", "keep the shape as chips"): there's
// no separate shuffle on/off state any more exposed from either chip --
// just the interval. One flat chip: left click cycles Off -> 5m -> 15m
// -> 30m -> 60m -> Off, right click jumps straight back to Off. This
// file is just the probe/debounce/write plumbing that chip uses, same
// IPC surface (ruixen-wallpaper-rotation) as before.
//
// Does NOT control whether rotation shuffles or walks the queue in
// order -- that's the Wallpaper Shuffle launcher extension's own job
// now (its reorderable list IS the sequence), and every function below
// deliberately leaves `shuffle` out of its own payload so it never
// fights that back into random mode. Direct correction once that
// extension existed: "all that notch thing will do is control the
// interval and off now, the shuffle and rotation is managed with the
// list in wallpaper shuffle only."
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
  // Direct correction once the Wallpaper Shuffle launcher extension's
  // own reorderable queue existed: "all that notch thing will do is
  // control the interval and off now, the shuffle and rotation is
  // managed with the list in wallpaper shuffle only" -- this file (and
  // the launcher's own older Shuffle interval section, selectInterval
  // below, same bug) used to force shuffle:true on every write, which
  // silently fought the queue back into random mode the moment anyone
  // touched enabled/interval from here. `shuffle` is left out of every
  // payload below now, so configure()'s own "preserves omitted
  // settings" merge leaves it exactly as whatever the queue last set.
  function cycleInterval() {
    var currentIndex = settings.enabled === true ? cycleSteps.indexOf(settings.intervalMinutes) : -1
    var nextIndex = currentIndex + 1
    if (nextIndex >= cycleSteps.length) nextIndex = -1
    var nextEnabled = nextIndex !== -1
    settings = Object.assign({}, settings, {
      enabled: nextEnabled,
      intervalMinutes: nextEnabled ? cycleSteps[nextIndex] : settings.intervalMinutes
    })
    pending = JSON.stringify({enabled: settings.enabled === true, intervalMinutes: settings.intervalMinutes})
    debounce.restart()
  }
  // Right-click shortcut straight back to Off, same remembered-interval
  // behavior as landing on Off via the normal left-click cycle.
  function turnOff() {
    if (settings.enabled !== true) return
    settings = Object.assign({}, settings, {enabled: false})
    pending = JSON.stringify({enabled: false, intervalMinutes: settings.intervalMinutes})
    debounce.restart()
  }
  // Direct-select an exact interval (0 for Off) -- for a host whose
  // chips are each individually clickable instead of cycling (the
  // launcher's own Shuffle section, matching how every other control
  // in that panel is a direct pick, not a cycle, unlike this file's
  // own cycleInterval() the notch's single pill uses).
  function selectInterval(minutes) {
    if (minutes === 0) { turnOff(); return }
    settings = Object.assign({}, settings, {enabled: true, intervalMinutes: minutes})
    pending = JSON.stringify({enabled: true, intervalMinutes: minutes})
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
