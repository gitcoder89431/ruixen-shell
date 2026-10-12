import QtQuick
import Quickshell
import Quickshell.Io

// Headless state for the quick Transition chip sitting next to Shuffle
// in the filter row -- same role for Wallpaper appearance that
// WallpaperRotationState.qml plays for Artwork rotation: this plugin
// doesn't carry the full expandable "Wallpaper appearance" card (that
// stays in the launcher's Wallpapers extension only, see
// WallpapersContent.qml's own header comment for the rotation/
// appearance split), just enough plumbing for one compact cycling
// chip. "stock" stands in for the renderer being off, same
// idea as the rotation chip's own Off. Landing on a real transition
// turns the renderer on automatically; landing back on stock turns it
// off -- direct request: "clicking it cycles through the transition
// and automatically turns the renderer on so we dont need that extra
// enable step". Talks to its own local wallpaper-effects.py (kept
// byte-identical to ruixen.background's and the launcher's copies by
// tests/wallpaper-effects.py's own parity test), same as those two
// pickers already do -- not an IPC call, since writing appearance
// settings has always been a direct local-script call in this plugin
// family, never routed through another plugin's IPC target.
Item {
  id: root
  property bool active: false
  property bool available: false
  property var settings: ({})
  property string pending: ""
  readonly property bool rendererEnabled: settings.rendererEnabled === true
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("wallpaper-effects.py").toString().replace(/^file:\/\//, ""))
  readonly property var choices: ["reveal", "bleed", "pixel-dissolve", "iris", "shutters", "scanline",
    "ink-spread", "aurora", "vortex", "signal-tear", "datamosh", "vhs", "code-bleed"]
  readonly property var labels: ({
    reveal: "Reveal", bleed: "Bleed through", "pixel-dissolve": "Pixel dissolve", iris: "Iris bloom",
    shutters: "Glass shutters", scanline: "Scanline", "ink-spread": "Ink spread", aurora: "Aurora wash",
    vortex: "Vortex", "signal-tear": "Signal tear", datamosh: "Datamosh", vhs: "VHS tracking",
    "code-bleed": "Code bleed"
  })
  readonly property var transitionCycle: ["stock"].concat(choices)
  function effectLabel(key) { return labels[key] || "Reveal" }
  function refresh() { if (active && !probe.running) probe.running = true }
  function cycleTransition() {
    var current = rendererEnabled ? settings.transitionEffect : "stock"
    var index = transitionCycle.indexOf(current)
    var next = transitionCycle[(index < 0 ? 0 : index + 1) % transitionCycle.length]
    if (next === "stock") {
      setRenderer(false)
    } else {
      settings = Object.assign({}, settings, {transitionEffect: next})
      pending = JSON.stringify(settings)
      debounce.restart()
      setRenderer(true)
    }
  }
  function setRenderer(enabled) {
    if (rendererToggle.running || enabled === rendererEnabled) return
    rendererToggle.command = ["python3", helper, enabled ? "enable" : "disable"]
    rendererToggle.running = true
  }
  function send() {
    if (writer.running || !pending) return
    writer.command = ["python3", helper, pending]
    pending = ""
    writer.running = true
  }
  onActiveChanged: refresh()
  Component.onCompleted: refresh()
  Timer { id: debounce; interval: 200; onTriggered: root.send() }
  Timer { interval: 1000; running: root.active; repeat: true; onTriggered: root.refresh() }
  Process {
    id: probe
    command: ["python3", root.helper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.pending || writer.running || rendererToggle.running) return
        try {
          var state = JSON.parse(text)
          root.settings = state
          root.available = state.installed === true
        } catch (e) { root.available = false }
      }
    }
  }
  Process { id: writer; onExited: (code, status) => { if (root.pending) debounce.restart(); else root.refresh() } }
  Process { id: rendererToggle; onExited: (code, status) => root.refresh() }
}
