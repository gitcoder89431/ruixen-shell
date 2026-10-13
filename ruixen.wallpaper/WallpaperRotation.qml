import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root
  property bool paused: false
  // The path this rotation itself last applied -- Service.qml's own
  // pause binding compares the currently-playing video/GIF against
  // this to tell "rotation picked this one, keep advancing on
  // schedule" apart from "someone set a video/GIF manually, leave it
  // alone", rather than pausing on every video/GIF unconditionally.
  property string lastAppliedPath: ""
  property real selectionEpoch: -1
  property real requestedEpoch: -1
  property int revision: 0
  property int requestedRevision: 0
  property var settings: ({enabled: false, shuffle: false, folder: Quickshell.env("HOME") + "/Pictures/ruixen-wallpapers", intervalMinutes: 15})
  property string pendingConfig: ""
  property string errorText: ""
  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("wallpaper-rotation.py").toString().replace(/^file:\/\//, ""))
  // Images go through omarchy's own plain bg-set; video/GIF need
  // ruixen.wallpaper's own playVideo/playGif IPC instead (the real
  // player, not something omarchy's own static-image setter
  // understands) -- same three-way split WallpapersContent.qml's own
  // select() already does for a manual pick, just reached from inside
  // rotation instead of a click. Same extension sets list-wallpapers.sh
  // and wallpaper-rotation.py's own next_artwork use.
  function kindOf(path) {
    var suffix = String(path).substring(path.lastIndexOf(".")).toLowerCase()
    if (suffix === ".gif") return "gif"
    if ([".mp4", ".mkv", ".webm", ".mov", ".m4v"].indexOf(suffix) >= 0) return "video"
    return "image"
  }
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
          root.lastAppliedPath=result.path
          // "rotation", not a real generation number -- these calls are
          // rotation applying its OWN pick, not something that needs
          // protecting against rotation's own earlier call, and a real
          // number would actively break that: it'd bump Service.qml's
          // own cross-IPC root.selectGeneration (the SAME property this
          // file's own selectionEpoch is bound to), which looks
          // identical to an external pick superseding this one and
          // kills the in-flight apply below via onSelectionEpochChanged
          // -- confirmed live, every successful apply reported "Unable
          // to apply artwork" even though the video/gif was already
          // playing correctly by the time it got killed. GenerationGuard
          // .acceptGeneration already treats a non-numeric candidate as
          // trusted but inert (applies the action, leaves the tracked
          // generation untouched) -- exactly what this needs. A genuine
          // external pick still provides its own real numeric
          // generation and still correctly pre-empts rotation's apply.
          var kind=root.kindOf(result.path)
          if (kind === "video") {
            apply.command=["omarchy-shell", "ruixen.wallpaper", "playVideo", result.path, "rotation"]
          } else if (kind === "gif") {
            apply.command=["omarchy-shell", "ruixen.wallpaper", "playGif", result.path, "rotation"]
          } else {
            // Stop any playing video/GIF first, same as select()'s own
            // image branch -- fire-and-forget alongside apply, not
            // sequenced before it (apply's own onExited is what resets
            // the clock, and that still needs to happen either way).
            stopPlayback.command=["omarchy-shell", "ruixen.wallpaper", "stop", "rotation"]
            stopPlayback.running=true
            apply.command=["omarchy", "theme", "bg", "set", result.path]
          }
          apply.running=true
        } catch(e) { root.errorText="Unable to choose next artwork" }
      }
    }
  }
  Process {
    id: stopPlayback
    stdout: StdioCollector { waitForEnd: true }
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
