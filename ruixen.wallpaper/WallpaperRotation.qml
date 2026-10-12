import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property bool paused: false
  property real selectionEpoch: -1
  property real requestedEpoch: -1
  property int revision: 0
  property int requestedRevision: 0
  property var settings: ({enabled: false, shuffle: false, folder: Quickshell.env("HOME") + "/Pictures/ruixen-wallpapers", intervalMinutes: 15})
  property string pendingConfig: ""
  property string errorText: ""
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("wallpaper-rotation.py").toString().replace(/^file:\/\//, ""))
  function resetClock() {
    clock.stop()
    if (settings.enabled === true && !paused) clock.start()
  }
  onPausedChanged: { if(paused && apply.running) apply.running=false; resetClock() }
  onSelectionEpochChanged: if(apply.running && requestedEpoch!==selectionEpoch) apply.running=false
  function next() {
    if (paused) { errorText = "Rotation pauses during video/GIF playback"; return }
    if (choose.running || apply.running || save.running || pendingConfig) return
    requestedEpoch = selectionEpoch
    requestedRevision = revision
    errorText = ""
    choose.running = true
  }
  function drainConfig() {
    if (save.running || !pendingConfig) return
    save.command = ["python3", helper, "configure", pendingConfig]
    pendingConfig = ""
    save.running = true
  }
  FileView {
    id: config
    path: Quickshell.env("HOME") + "/.local/state/ruixen/wallpaper-rotation.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      try { root.settings = Object.assign({shuffle:false}, JSON.parse(text())); root.revision++; root.resetClock() }
      catch (e) { root.settings = Object.assign({}, root.settings, {enabled:false}); root.errorText = "Invalid rotation settings"; root.resetClock() }
    }
    onFileChanged: reload()
  }
  Timer {
    id: clock
    interval: Math.max(1, Math.min(1440, root.settings.intervalMinutes || 15)) * 60000
    running: false
    repeat: true
    onTriggered: root.next()
  }
  Process {
    id: save
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try { var c=JSON.parse(text); root.errorText=c.error || "" } catch(e) { root.errorText="Unable to save rotation settings" }
      }
    }
    onExited: (code, status) => { if (root.pendingConfig) root.drainConfig(); else config.reload() }
  }
  Process {
    id: choose
    command: ["python3", root.helper, "next"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var result=JSON.parse(text)
          if (root.paused || root.requestedEpoch !== root.selectionEpoch || root.requestedRevision !== root.revision) return
          if (result.error) { root.errorText=result.error; return }
          apply.command=["omarchy", "theme", "bg", "set", result.path]
          apply.running=true
        } catch(e) { root.errorText="Unable to choose next artwork" }
      }
    }
  }
  Process {
    id: apply
    onExited: (code, status) => { if(code !== 0) root.errorText="Unable to apply artwork"; root.resetClock() }
  }
  IpcHandler {
    target: "ruixen-wallpaper-rotation"
    function status(): string { return JSON.stringify(Object.assign({}, root.settings, {paused:root.paused, error:root.errorText})) }
    function configure(json: string): void {
      try { JSON.parse(json); root.revision++; root.pendingConfig=json; root.drainConfig() }
      catch(e) { root.errorText="Invalid rotation settings" }
    }
    function next(): void { root.next() }
  }
}
