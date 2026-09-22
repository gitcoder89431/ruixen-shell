import QtQuick
import Quickshell.Io

// Ported from github.com/Ryoku-dev/ryoku's own
// shell/services/AudioBars.qml (MIT-style project, direct community
// pointer -- "it has a really cool cava visualizer feature"), simplified
// for this repo's own single-consumer shape: no multi-owner refcounting
// (that file shares one analyser across six different UI surfaces;
// Overlay.qml is the only consumer here), and no Perf.pillFrozen
// power-profile gate (this repo has no equivalent service) -- `enabled`
// alone is the gate, driven by Overlay.qml's own vizEnabled &&
// !fullscreenActive.
//
// Plain QtObject, not a pragma Singleton -- AudioBars.qml needs Singleton
// specifically because several independent QML files each import and
// read the same shared feed; this one is only ever instantiated once,
// directly inside Overlay.qml, so a singleton would add import-path
// overhead for nothing.
QtObject {
  id: root

  property bool enabled: false
  property int bands: 20
  readonly property int fps: 30

  property var levels: root.flat()
  property real energy: 0
  property real lastReadMs: 0

  function flat() {
    var a = []
    for (var i = 0; i < root.bands; i++) a.push(0)
    return a
  }

  // Playback spectrum via cava's own native pipewire backend (source =
  // auto, the default sink's monitor) -- confirmed in the reference
  // project's own comment that the pulse backend can't connect here even
  // with pipewire-pulse up ("Connection terminated"), so this needs no
  // pactl fallback. `command -v cava || exit 0` is the entire "cava not
  // installed" story: the process exits instantly and silently, no error
  // surfaced anywhere -- Omarchy doesn't ship cava by default, and a
  // visualizer with nothing to visualize should just stay flat, not
  // complain. `exec cava -p "$cfg"` (not a plain trailing command) so
  // Quickshell's own SIGTERM on this Process reaches cava directly,
  // rather than leaving an orphaned analyser behind when the surface
  // unloads or enabled goes false.
  property Process cavaProc: Process {
    id: cavaProc
    command: ["sh", "-c",
      "command -v cava >/dev/null 2>&1 || exit 0; " +
      "cfg=\"${XDG_RUNTIME_DIR:-/tmp}/ruixen-cava-visualizer.conf\"; " +
      "printf '%s\\n' '[general]' 'framerate = " + root.fps + "' 'bars = " + root.bands + "' '' " +
      "'[input]' 'method = pipewire' 'source = auto' '' " +
      "'[output]' 'method = raw' 'raw_target = /dev/stdout' 'data_format = ascii' 'ascii_max_range = 100' 'channels = mono' 'mono_option = average' '' " +
      "'[smoothing]' 'noise_reduction = 45' > \"$cfg\"; exec cava -p \"$cfg\""]
    // Bound, never imperatively assigned -- see AudioBars.qml's own
    // comment on this exact point: an imperative `cavaProc.running =
    // true` from a restart path would destroy this binding, and cava
    // would then outlive every gate meant to stop it (enable toggle,
    // fullscreen). The backoff flag below expresses the same "retry
    // after a hiccup" behavior without ever taking the binding away.
    running: root.enabled && !cavaProc.backoff
    property bool backoff: false
    stdout: SplitParser {
      splitMarker: "\n"
      onRead: (line) => root.readBars(line)
    }
    // cava exiting while still wanted (a transient pipewire hiccup, or
    // simply not installed) earns one paced retry rather than a tight
    // spin -- harmless either way since a missing-cava retry exits in a
    // few ms each time.
    onExited: if (root.enabled) {
      cavaProc.backoff = true
      restartTimer.restart()
    }
  }

  property Timer restartTimer: Timer {
    id: restartTimer
    interval: 1200
    onTriggered: cavaProc.backoff = false
  }

  // cava sleeps and stops emitting frames once playback idles -- settle
  // back to flat when no frame has arrived recently, same 260ms
  // threshold AudioBars.qml itself uses, so bars don't visibly freeze on
  // the last peak.
  property Timer idleTimer: Timer {
    interval: 120
    running: root.enabled
    repeat: true
    onTriggered: if (Date.now() - root.lastReadMs > 260) {
      root.levels = root.flat()
      root.energy = 0
    }
  }

  onEnabledChanged: {
    levels = flat()
    energy = 0
    if (enabled) lastReadMs = 0
  }

  // Process.command is read once at spawn, not a live binding cava
  // itself reacts to -- changing bands mid-run needs an explicit
  // restart or the already-running cava process keeps analysing with
  // its OLD band count forever, silently mismatching root.bands. This
  // has no equivalent in AudioBars.qml, whose own bars count is a fixed
  // constant that never changes at runtime -- ported logic stops at
  // readBars/flat/norm above, this restart is new for the "Bands"
  // setting specifically.
  // Qt.binding(), not a plain `cavaProc.running = root.enabled` --
  // direct live bug caught testing this exact path: a bare imperative
  // assignment replaces the declarative `running: root.enabled &&
  // !cavaProc.backoff` binding above with a frozen snapshot, so the
  // very next real Enable/disable toggle (or backoff cycle) is
  // silently ignored forever after -- cava keeps running (or stays
  // dead) regardless of root.enabled from that point on, since nothing
  // is bound to it anymore. Qt.binding() re-installs the same live
  // expression instead of a static value, so reactivity survives this
  // forced restart.
  onBandsChanged: {
    levels = flat()
    if (cavaProc.running) {
      cavaProc.running = false
      Qt.callLater(function() {
        cavaProc.running = Qt.binding(function() { return root.enabled && !cavaProc.backoff })
      })
    }
  }

  function norm(v) {
    var n = parseInt(v)
    if (isNaN(n)) return 0
    return Math.max(0, Math.min(1, n / 100))
  }

  function readBars(line) {
    var t = line.trim()
    if (!t) return
    var parts = t.split(/[;\s]+/)
    if (parts.length < root.bands) return
    var out = []
    var sum = 0
    for (var i = 0; i < root.bands; i++) {
      var v = root.norm(parts[i])
      out.push(v)
      sum += v
    }
    root.levels = out
    root.energy = sum / root.bands
    root.lastReadMs = Date.now()
  }
}
