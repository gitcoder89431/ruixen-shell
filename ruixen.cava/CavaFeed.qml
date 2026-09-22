import QtQuick
import Quickshell.Io

// Spawns cava and turns its raw stdout into a normalized, smoothed
// levels array for Overlay.qml to render. Single-consumer shape --
// no multi-owner refcounting or power-profile gating, since this is
// only ever instantiated once, directly inside Overlay.qml. `enabled`
// alone is the gate, driven by Overlay.qml's own vizEnabled &&
// !fullscreenActive.
//
// Plain QtObject, not a pragma Singleton -- a singleton only earns its
// keep when multiple independent files need to import and read the
// same shared instance; this one has exactly one consumer, so that
// import-path overhead buys nothing here.
QtObject {
  id: root

  property bool enabled: false
  // 64 -- direct follow-up after the first pass shipped with 20, which
  // read as too sparse ("the gaps between the bar is alot, it looks
  // like baby tooth").
  property int bands: 64
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
  //
  // autosens = 0 / sensitivity = 70 / ascii_max_range = 1000 -- direct
  // follow-up: "do we have the right pattern... peak-normalized so
  // volume does not change bar height." Disables cava's OWN slow-
  // adapting auto-gain in favor of a fixed sensitivity plus readBars()'
  // own per-frame peak normalization below -- the two auto-gain
  // mechanisms would otherwise fight each other on different
  // timescales. The wider 0-1000 raw range (vs. this file's own
  // previous 0-100) just gives that per-frame peak math more
  // resolution to work with; readBars() divides it back down to 0..1
  // itself either way.
  property Process cavaProc: Process {
    id: cavaProc
    command: ["sh", "-c",
      "command -v cava >/dev/null 2>&1 || exit 0; " +
      "cfg=\"${XDG_RUNTIME_DIR:-/tmp}/ruixen-cava-visualizer.conf\"; " +
      "printf '%s\\n' '[general]' 'framerate = " + root.fps + "' 'bars = " + root.bands + "' 'autosens = 0' 'sensitivity = 70' '' " +
      "'[input]' 'method = pipewire' 'source = auto' '' " +
      "'[output]' 'method = raw' 'raw_target = /dev/stdout' 'data_format = ascii' 'ascii_max_range = 1000' 'channels = mono' 'mono_option = average' '' " +
      "'[smoothing]' 'noise_reduction = 45' > \"$cfg\"; exec cava -p \"$cfg\""]
    // Bound, never imperatively assigned -- an imperative
    // `cavaProc.running = true` from a restart path would destroy
    // this binding, and cava would then outlive every gate meant to
    // stop it (enable toggle, fullscreen). The backoff flag below
    // expresses the same "retry after a hiccup" behavior without ever
    // taking the binding away.
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
  // back to flat when no frame has arrived recently (260ms), so bars
  // don't visibly freeze on the last peak.
  property Timer idleTimer: Timer {
    interval: 120
    running: root.enabled
    repeat: true
    onTriggered: if (Date.now() - root.lastReadMs > 260) {
      root.levels = root.flat()
      root.prevLevels = root.flat()
      root.energy = 0
    }
  }

  onEnabledChanged: {
    levels = flat()
    prevLevels = flat()
    energy = 0
    if (enabled) lastReadMs = 0
  }

  // Process.command is read once at spawn, not a live binding cava
  // itself reacts to -- changing bands mid-run needs an explicit
  // restart or the already-running cava process keeps analysing with
  // its OLD band count forever, silently mismatching root.bands.
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
    prevLevels = flat()
    if (cavaProc.running) {
      cavaProc.running = false
      Qt.callLater(function() {
        cavaProc.running = Qt.binding(function() { return root.enabled && !cavaProc.backoff })
      })
    }
  }

  // Peak-normalized so volume doesn't change bar height. Previously a
  // flat parts[i]/ascii_max_range divide, which meant a quiet passage's
  // bars genuinely sat short and a loud passage's sat tall -- raw
  // amplitude, not volume-independent.
  // 15, not the original 3 -- direct live report: "when the music is
  // paused, the bar still sticks up... its like the base height isnt
  // low enough." Live-traced this directly (console.log on every raw
  // peak and every smoothed level): on THIS machine peak already hits
  // a clean 0 the instant playback pauses, and the EMA tail below
  // decays to astronomically small (1e-8 and beyond) within under a
  // second either way -- so the reported symptom is very likely real-
  // world background noise on their own audio interface (mic hiss,
  // USB electrical noise, a player that keeps a near-silent stream
  // open rather than closing it outright) keeping the frame's own
  // peak just above the old threshold, which peak-normalization then
  // stretches back up toward full height regardless of how quiet that
  // noise actually is. 15 is still a small fraction of the 0-1000
  // scale (comfortably below any real quiet passage) but gives much
  // more headroom against exactly this class of noise than 3 did.
  readonly property real noiseFloor: 15
  readonly property real emaSmoothing: 0.3
  // Hard floor under the EMA below -- an exponential decay only ever
  // approaches 0 asymptotically, never truly reaching it (the same
  // live trace showed real, present-but-irrelevant values like 1e-13
  // deep into a decay that already looked fully settled). Snapping
  // anything under this to a flat, exact 0 guarantees a decaying tail
  // actually terminates instead of leaving some technically-nonzero
  // residue sitting under the bars/segments/wave forever.
  readonly property real levelFloor: 0.01
  property var prevLevels: root.flat()

  function readBars(line) {
    var t = line.trim()
    if (!t) return
    var parts = t.split(/[;\s]+/)
    if (parts.length < root.bands) return

    var raw = []
    var peak = 0
    for (var i = 0; i < root.bands; i++) {
      var n = parseInt(parts[i])
      if (isNaN(n)) n = 0
      raw.push(n)
      if (n > peak) peak = n
    }

    var prev = (root.prevLevels && root.prevLevels.length === root.bands) ? root.prevLevels : root.flat()

    var out = []
    var sum = 0
    for (var j = 0; j < root.bands; j++) {
      // Relative to the LOUDEST bar in THIS frame, not a fixed scale --
      // the tallest bar is always near-full-height regardless of how
      // loud the source actually is. noiseFloor gates a near-silent
      // frame (a tiny peak) from getting falsely amplified toward 1.0
      // just because it's dividing by its own tiny peak.
      var n = peak > root.noiseFloor ? raw[j] / peak : 0
      // 30% previous / 70% new -- the reference project's own exact
      // ratio ("motion stays fluid instead of jittery"). An EMA on the
      // DATA itself, layered underneath Overlay.qml's own 90ms Behavior
      // transition on the rendered bar height/width, not a replacement
      // for it -- two different smoothing stages, one per frame of
      // data, one per rendered frame.
      var smoothed = root.emaSmoothing * prev[j] + (1 - root.emaSmoothing) * n
      if (smoothed < root.levelFloor) smoothed = 0
      out.push(smoothed)
      sum += smoothed
    }

    root.prevLevels = out
    root.levels = out
    root.energy = sum / root.bands
    root.lastReadMs = Date.now()
  }
}
