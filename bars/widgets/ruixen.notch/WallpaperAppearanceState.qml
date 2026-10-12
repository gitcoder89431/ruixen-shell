import QtQuick
import Quickshell
import Quickshell.Io

// Headless state for the quick Transition and Effect chips sitting next
// to Shuffle in the filter row -- same role for Wallpaper appearance
// that WallpaperRotationState.qml plays for Artwork rotation: this
// plugin doesn't carry the full expandable "Wallpaper appearance" card
// (that stays in the launcher's Wallpapers extension only, see
// WallpapersContent.qml's own header comment for the rotation/
// appearance split), just enough plumbing for two compact cycling
// chips. "stock"/"none" stand in for a chip's own off state, same idea
// as the rotation chip's own Off. Landing on a real transition or
// background effect turns the renderer on automatically; Transition's
// own Off (stock) turns it back off -- direct request: "clicking it
// cycles through the transition and automatically turns the renderer
// on so we dont need that extra enable step". Effect's own Off does
// NOT disable the renderer (see cycleBackgroundEffect's own comment) --
// Transition owns that shared decision, Effect only ever asks for the
// renderer, never turns it off from under Transition. Talks to its own
// local wallpaper-effects.py (kept byte-identical to ruixen.background's
// and the launcher's copies by tests/wallpaper-effects.py's own parity
// test), same as those two pickers already do -- not an IPC call, since
// writing appearance settings has always been a direct local-script
// call in this plugin family, never routed through another plugin's
// IPC target.
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
  // CRT/Matrix background effect -- same cycling-chip idea, but
  // independent of the Transition chip's own renderer-enable/disable
  // authority: picking CRT or Matrix enables the renderer (nothing to
  // see otherwise), but cycling back to its own Off only clears
  // backgroundEffect, never force-disables the renderer -- Transition
  // might still have a real effect selected and depending on it.
  readonly property var backgroundEffectCycle: ["none", "crt", "matrix"]
  function effectLabel(key) { return labels[key] || "Reveal" }
  function backgroundEffectLabel(key) { return key === "crt" ? "CRT" : key === "matrix" ? "Matrix" : "Off" }
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
  function cycleBackgroundEffect() {
    var current = rendererEnabled ? (settings.backgroundEffect || "none") : "none"
    var index = backgroundEffectCycle.indexOf(current)
    var next = backgroundEffectCycle[(index < 0 ? 0 : index + 1) % backgroundEffectCycle.length]
    settings = Object.assign({}, settings, {backgroundEffect: next})
    pending = JSON.stringify(settings)
    debounce.restart()
    if (next !== "none") setRenderer(true)
  }
  function setRenderer(enabled) {
    if (rendererToggle.running || enabled === rendererEnabled) return
    rendererToggle.command = ["python3", helper, enabled ? "enable" : "disable"]
    rendererToggle.running = true
  }
  // Right-click shortcut straight back to Stock -- same idea as
  // WallpaperRotationState's turnOff(), leaves the remembered
  // transitionEffect untouched so re-enabling later resumes it.
  function resetToStock() { setRenderer(false) }
  // Right-click shortcut straight back to Off -- clears backgroundEffect
  // only, same "don't force-disable the shared renderer" reasoning as
  // cycleBackgroundEffect's own Off step above.
  function resetBackgroundEffect() {
    if ((settings.backgroundEffect || "none") === "none") return
    settings = Object.assign({}, settings, {backgroundEffect: "none"})
    pending = JSON.stringify(settings)
    debounce.restart()
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
