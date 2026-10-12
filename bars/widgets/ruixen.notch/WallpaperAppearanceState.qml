import QtQuick
import Quickshell
import Quickshell.Io

// Appearance state for the notch's Effect and Transition dropdowns.
// Settings use the local validated writer; renderer lifecycle uses public
// Omarchy plugin commands. Each axis has its own off value, so turning one
// off leaves the renderer enabled while the other still needs it.
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
  readonly property var backgroundEffectCycle: ["none", "crt", "matrix"]
  // Each feature's own authoritative on/off signal -- deliberately NOT
  // rendererEnabled, see this file's own header comment for why.
  readonly property bool transitionOn: (settings.transitionDurationMs || 0) > 0
  readonly property bool backgroundEffectOn: (settings.backgroundEffect || "none") !== "none"
  function effectLabel(key) { return labels[key] || "Reveal" }
  function backgroundEffectLabel(key) { return key === "crt" ? "CRT" : key === "matrix" ? "Matrix" : "Off" }
  function refresh() { if (active && !probe.running) probe.running = true }
  // The renderer stays on as long as EITHER feature still wants it;
  // only turns off once both are off. Call after any write that might
  // turn a feature off.
  function maybeDisableRenderer() {
    if (!transitionOn && !backgroundEffectOn) setRenderer(false)
  }
  // Duration baked in per effect on every step, same two values and
  // same reasoning as the launcher's own chips (WallpaperAppearancePanel
  // .qml's own comment): "slow down the quick onces like iris bloom
  // abit, make these feel more premium, i dont like snappy unless its
  // has to be" -- mask effects get a real 900ms, glitch effects stay
  // punchier (550ms) since that abruptness is the whole point of a
  // glitch. No duration slider exists anywhere any more (launcher
  // dropped it the same pass this got baked in), so re-asserting it on
  // every click, not just the first one after Off, keeps both surfaces
  // consistent regardless of which effect was last selected.
  readonly property var glitchKeys: ["signal-tear", "datamosh", "vhs", "code-bleed"]
  function selectTransition(key) {
    if (key === "stock") { resetToStock(); return }
    if (choices.indexOf(key) < 0) return
    settings = Object.assign({}, settings, {transitionEffect:key, transitionDurationMs:glitchKeys.indexOf(key)>=0 ? 550 : 900})
    pending = JSON.stringify(settings)
    debounce.restart()
    setRenderer(true)
  }
  function selectBackgroundEffect(key) {
    if (backgroundEffectCycle.indexOf(key) < 0) return
    settings = Object.assign({}, settings, {backgroundEffect:key})
    pending = JSON.stringify(settings)
    debounce.restart()
    if (key !== "none") setRenderer(true)
    else maybeDisableRenderer()
  }
  function setRenderer(enabled) {
    if (rendererToggle.running || enabled === rendererEnabled) return
    rendererToggle.command = ["python3", helper, enabled ? "enable" : "disable"]
    rendererToggle.running = true
  }
  // Right-click shortcut straight back to Stock -- same idea as
  // WallpaperRotationState's turnOff(), leaves the remembered
  // transitionEffect untouched so re-enabling later resumes it. Only
  // disables the renderer if Effect isn't also keeping it on.
  function resetToStock() {
    if (!transitionOn) return
    settings = Object.assign({}, settings, {transitionDurationMs: 0})
    pending = JSON.stringify(settings)
    debounce.restart()
    maybeDisableRenderer()
  }
  // Right-click shortcut straight back to Off -- clears backgroundEffect
  // only. Only disables the renderer if Transition isn't also keeping
  // it on.
  function resetBackgroundEffect() {
    if (!backgroundEffectOn) return
    settings = Object.assign({}, settings, {backgroundEffect: "none"})
    pending = JSON.stringify(settings)
    debounce.restart()
    maybeDisableRenderer()
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
