import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtMultimedia
import "GenerationGuard.js" as GenerationGuard

// Muted, looping video wallpaper support, plus animated GIF wallpaper
// support -- direct request ("can we remake one in our shell like
// ruixen-wallpaper plugin that works with our notch... it just needs
// to show up in the notch wallpaper picker and it needs to work
// backend wise"), GIF added as the planned fast-follow ("yea lets do
// the gif next"). Investigated yesheytenzin/live-wallpaper as a
// reference for the real video mechanism (not guessed, not copied
// wholesale) -- this is a from-scratch port of that same design onto
// this repo's own conventions. GIF has no equivalent reference --
// QML's own AnimatedImage handles looping natively, so it needed none
// of the MediaPlayer/VideoOutput/ffmpeg-poster machinery video does,
// just the same layer-shell placement and mutual-exclusion handling.
//
// Omarchy's own desktop background is a separate first-party plugin
// (omarchy.background, kind: service) -- a per-screen WlrLayer.
// Background layer-shell surface (namespace "omarchy-background")
// that just shows a static Image. It has no video/gif concept at all
// and we never touch it directly (per this repo's own standing rule
// about never patching anything Omarchy owns). This plugin adds a
// SECOND, separate WlrLayer.Background surface per screen (namespace
// "ruixen-wallpaper") that sits on top of it and stays fully
// transparent -- letting Omarchy's own real background show through
// underneath -- except while a video or gif is actively playing AND
// (for video specifically) has decoded a real first frame, at which
// point it visually covers it. Nothing active, nothing decoded yet,
// or playback stopped -> fully invisible, Omarchy's own layer is all
// that's ever seen. Has to be its own kind: service plugin, not
// folded into ruixen.notch's own kind: overlay -- a service plugin
// runs persistently regardless of whether any UI panel is open, which
// is exactly what an "always-on desktop layer" needs; ruixen.notch's
// own Wallpapers tab is just the CLIENT that tells this one what to
// play, over the same qs ipc call convention every other cross-plugin
// action in this repo already uses.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/ruixen"
  readonly property string statePath: stateDir + "/wallpaper-media"
  readonly property string posterDir: home + "/.cache/ruixen/wallpaper-posters"

  property string videoPath: ""
  property string gifPath: ""
  // Whatever current/background actually got set to for the active
  // wallpaper -- a generated poster frame for video, the gif file
  // itself for gif (no extraction needed, Omarchy's own background
  // Image already renders a gif's first frame fine as a plain static
  // image). Same property serves both kinds: the readCurrentBgProc
  // poll below just needs "what do we expect current/background to
  // be right now", not which kind produced it.
  property string posterPath: ""
  property int playGeneration: 0

  // Cross-IPC generation guard -- direct review finding ("Make rapid
  // asynchronous Process actions last-action-wins"). WallpapersContent
  // .qml's own select() dispatches playVideo/playGif/stop through
  // THREE SEPARATE Process objects (one per kind), each an
  // independent OS subprocess spawn (`qs ipc call ...`). Confirmed
  // directly, not assumed: reassigning a Quickshell Process's own
  // command while it's already running does NOT cancel the in-flight
  // run -- it finishes, THEN the reassigned command fires -- so
  // reusing ONE process per kind already gives "last click for that
  // SAME kind wins" for free. What that doesn't cover is rapid
  // switches ACROSS kinds (video -> gif -> image): nothing guarantees
  // three independent subprocesses deliver their IPC calls in the
  // same order they were dispatched, especially under real scheduling
  // pressure, so a later click's call could in principle be processed
  // before an earlier click's own call finishes. selectGeneration
  // tracks the highest generation number this service has accepted
  // across ALL THREE of those entry points; acceptsGeneration() below
  // rejects anything older, so an out-of-order arrival can no longer
  // win over the user's actual latest choice. Same principle
  // posterAndSetProc's own onStreamFinished below already applies to
  // its own stale-result check, just extended to the IPC boundary
  // itself instead of only after the fact.
  //
  // real, not int (#22) -- WallpapersContent.qml now seeds its own
  // counter from Date.now() (milliseconds since epoch, ~13 digits) at
  // creation rather than 0, so a freshly (re)created client instance
  // can never look older than whatever this long-lived service already
  // saw from a PREVIOUS client's lifetime -- see that file's own
  // comment for the full "why". A 13-digit value silently overflows
  // QML's 32-bit `int` (confirmed empirically, not assumed, via an
  // isolated Quickshell test: Date.now() assigned to a property int
  // truncated to a completely different, smaller number). `real` (a
  // JS double/QML's floating-point type) safely holds integers up to
  // 2^53, comfortably covering millisecond timestamps for millennia.
  property real selectGeneration: -1

  // Only enforced when a caller actually provides a generation --
  // resumeProc's own play()/playGif() calls below bypass the
  // IpcHandler entirely (they call these functions directly), so
  // there's nothing external to race against on that path.
  //
  // The actual accept/reject decision is GenerationGuard.acceptGeneration
  // (#22) -- extracted to its own file so it's unit-testable
  // (tests/js/GenerationGuard.test.js) rather than only reachable
  // through a live IPC round-trip. This function's own job is just
  // applying that decision to root.selectGeneration.
  function acceptsGeneration(generationText) {
    var next = GenerationGuard.acceptGeneration(root.selectGeneration, generationText)
    if (next === null) return false
    root.selectGeneration = next
    return true
  }

  // Ensures the poster exists (same md5-of-real-path naming
  // WallpapersContent.qml's own listProc already uses when building
  // the picker, so this is very likely already cached from just
  // having seen the tile) and sets it as the real Omarchy background
  // -- direct parity with live-wallpaper's own "keeps a static poster
  // as the lock-screen and transition fallback": if this plugin ever
  // gets disabled, or a screen fails to decode a frame, or something
  // reads current/background directly (lock screen, some other
  // tool), there's still a real, correct-looking image there instead
  // of whatever static wallpaper happened to be active before.
  property string posterExpectedFor: ""

  Process {
    id: posterAndSetProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var poster = String(text || "").trim()
        // Still the currently-requested play/playGif, not a stale
        // result from a since-superseded selection -- checks both
        // kinds' own active path since either could be what this
        // process run was actually for.
        var stillCurrent = (root.videoPath === root.posterExpectedFor) || (root.gifPath === root.posterExpectedFor)
        if (poster !== "" && stillCurrent) {
          root.posterPath = poster
        }
      }
    }
  }

  Process {
    id: ensureDirsProc
    command: ["bash", "-c", "mkdir -p \"$HOME/.local/state/ruixen\" \"$HOME/.cache/ruixen/wallpaper-posters\""]
  }

  function play(path) {
    path = String(path || "").trim()
    if (path === "") return
    ensureDirsProc.running = true
    root.videoPath = path
    root.gifPath = ""
    root.posterPath = ""
    root.playGeneration += 1

    root.posterExpectedFor = path
    // Regenerates when the source video is newer than its cached
    // poster (-nt), not just when the poster is entirely missing --
    // same fix, same reasoning, as WallpapersContent.qml's own
    // discovery script (both sides share this exact cache naming
    // convention, see that file's own comment): otherwise replacing
    // a video's content at the same path kept showing the OLD poster
    // indefinitely.
    posterAndSetProc.command = ["bash", "-c",
      "hash=$(printf '%s' \"$1\" | md5sum | cut -d' ' -f1); " +
      "poster=\"$HOME/.cache/ruixen/wallpaper-posters/$hash.jpg\"; " +
      "if [[ ! -f \"$poster\" ]] || [[ \"$1\" -nt \"$poster\" ]]; then " +
      "ffmpeg -y -loglevel quiet -i \"$1\" -vframes 1 -q:v 3 \"$poster\" 2>/dev/null; fi; " +
      "if [[ -f \"$poster\" ]]; then omarchy-theme-bg-set \"$poster\"; printf '%s' \"$poster\"; fi",
      "_", path]
    posterAndSetProc.running = true

    stateWriteProc.command = ["bash", "-c", "printf 'video\\n%s' \"$1\" > \"$HOME/.local/state/ruixen/wallpaper-media\"", "_", path]
    stateWriteProc.running = true
  }

  // GIF's own play -- direct request ("yea lets do the gif next").
  // Used to set the raw gif file itself as current/background (Image
  // can render a gif's own first frame directly, same as any other
  // static image -- true, and still how the picker's own thumbnails
  // work), but that meant current/background could point at a real
  // multi-frame animated file. Direct review finding ("Use a static
  // fallback poster for GIF wallpapers to avoid Omarchy ImageMagick
  // memory blowups"): Omarchy's own omarchy-bar-text-color passes
  // whatever current/background is into `magick` with no frame
  // limit, and on a genuinely multi-frame source that decodes EVERY
  // frame -- hit 8GB+ RSS twice live this session, once causing a
  // real OOM cascade that took down the whole Hyprland session. Same
  // fix as video's own poster generation below, now applied to GIF
  // too: extract a single static frame via ffmpeg (GIF is a real
  // ffmpeg input format, no different from a video source here) into
  // the exact same md5-of-path poster cache video already uses, and
  // set THAT as current/background -- never the raw animated file.
  // The actual animated rendering is entirely unaffected: that's
  // AnimatedImage on this service's own separate WlrLayer.Background
  // surface, which never reads current/background at all.
  //
  // If ffmpeg is missing or extraction fails (a genuinely corrupt
  // gif, say), current/background is deliberately left UNCHANGED
  // rather than falling back to the raw gif -- that fallback would
  // silently reopen the exact hole this fix exists to close. The gif
  // still plays correctly either way (again, that part never depended
  // on current/background), it just means lock screen/other external
  // consumers keep showing whatever was there before until a real
  // poster can be produced.
  function playGif(path) {
    path = String(path || "").trim()
    if (path === "") return
    root.gifPath = path
    root.videoPath = ""
    root.posterPath = ""
    root.playGeneration += 1

    root.posterExpectedFor = path
    posterAndSetProc.command = ["bash", "-c",
      "hash=$(printf '%s' \"$1\" | md5sum | cut -d' ' -f1); " +
      "poster=\"$HOME/.cache/ruixen/wallpaper-posters/$hash.jpg\"; " +
      "if command -v ffmpeg >/dev/null 2>&1; then " +
      "if [[ ! -f \"$poster\" ]] || [[ \"$1\" -nt \"$poster\" ]]; then " +
      "ffmpeg -y -loglevel quiet -i \"$1\" -vframes 1 -q:v 3 \"$poster\" 2>/dev/null; fi; fi; " +
      "if [[ -f \"$poster\" ]]; then omarchy-theme-bg-set \"$poster\"; printf '%s' \"$poster\"; fi",
      "_", path]
    posterAndSetProc.running = true

    stateWriteProc.command = ["bash", "-c", "printf 'gif\\n%s' \"$1\" > \"$HOME/.local/state/ruixen/wallpaper-media\"", "_", path]
    stateWriteProc.running = true
  }

  function stop() {
    root.videoPath = ""
    root.gifPath = ""
    root.posterPath = ""
    root.playGeneration += 1
    stateWriteProc.command = ["bash", "-c", "rm -f \"$HOME/.local/state/ruixen/wallpaper-media\""]
    stateWriteProc.running = true
  }

  Process {
    id: stateWriteProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Resume after a shell restart -- direct parity with live-wallpaper's
  // own --resume. Reads the plain-text state file (same convention
  // every other persisted setting in this repo already uses) and
  // replays play()/playGif() if it names a file that still actually
  // exists. First line is the kind (video/gif), second is the path --
  // needed now that either kind can be active, not just video.
  Process {
    id: resumeProc
    command: ["bash", "-c",
      "f=\"$HOME/.local/state/ruixen/wallpaper-media\"; " +
      "[[ -f \"$f\" ]] || exit 0; " +
      "kind=$(sed -n '1p' \"$f\"); p=$(sed -n '2p' \"$f\"); " +
      "[[ -f \"$p\" ]] && printf '%s\\n%s' \"$kind\" \"$p\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var kind = (lines[0] || "").trim()
        var p = (lines[1] || "").trim()
        if (p === "") return
        if (kind === "gif") root.playGif(p)
        else if (kind === "video") root.play(p)
      }
    }
  }

  // Safety net for the case our own picker doesn't cover: someone
  // opens Omarchy's OWN stock Style -> Background picker (or the
  // desktop double-click shortcut, forwarded below) and picks a plain
  // static image while a video/gif is playing. That flow calls the
  // real omarchy-theme-bg-set directly, which has no idea this plugin
  // exists -- so current/background's own symlink target changes out
  // from under us. Polling and comparing against our own last-set
  // posterPath is how live-wallpaper's own --stop-if-changed does the
  // same detection; if it no longer matches, something else changed
  // the background, so stop.
  Process {
    id: readCurrentBgProc
    command: ["readlink", "-f", root.home + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if ((root.videoPath === "" && root.gifPath === "") || root.posterPath === "") return
        var current = String(text || "").trim()
        if (current !== root.posterPath) root.stop()
      }
    }
  }

  Timer {
    interval: 1000
    repeat: true
    running: true
    onTriggered: {
      if ((root.videoPath !== "" || root.gifPath !== "") && !readCurrentBgProc.running) readCurrentBgProc.running = true
    }
  }

  IpcHandler {
    target: "ruixen.wallpaper"
    function playVideo(path: string, generation: string): void {
      if (!root.acceptsGeneration(generation)) return
      root.play(path)
    }
    function playGif(path: string, generation: string): void {
      if (!root.acceptsGeneration(generation)) return
      root.playGif(path)
    }
    function stop(generation: string): void {
      if (!root.acceptsGeneration(generation)) return
      root.stop()
    }
    function status(): string {
      return JSON.stringify({
        active: root.videoPath !== "" || root.gifPath !== "",
        video: root.videoPath, gif: root.gifPath, poster: root.posterPath
      })
    }
  }

  Component.onCompleted: resumeProc.running = true

  Variants {
    model: Quickshell.screens

    PanelWindow {
      id: panel
      required property var modelData
      property bool frameDecoded: false
      property int playerGeneration: -1

      function syncPlayer() {
        var generation = root.playGeneration
        playerGeneration = generation
        frameDecoded = false
        player.stop()
        player.source = ""
        if (root.videoPath === "") return
        player.source = "file://" + root.videoPath
        player.play()
      }

      screen: modelData
      color: "transparent"
      anchors { top: true; bottom: true; left: true; right: true }
      exclusionMode: ExclusionMode.Ignore

      WlrLayershell.namespace: "ruixen-wallpaper"
      WlrLayershell.layer: WlrLayer.Background
      WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

      // No AudioOutput attached anywhere -- that's the actual "muted".
      // A MediaPlayer with no audio sink connected has nowhere for
      // sound to go, so this plays picture-only with no separate
      // mute flag/property needed.
      MediaPlayer {
        id: player
        videoOutput: videoOutput
        loops: MediaPlayer.Infinite
      }

      VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectCrop
        // Invisible until a real frame has actually decoded -- avoids
        // a black flash between "video selected" and "first frame
        // ready", same reasoning as Omarchy's own Background.qml
        // reveal-mask trick, just simpler here since there's no
        // crossfade to also manage.
        visible: root.videoPath !== "" && panel.frameDecoded
      }

      // GIF's own output -- no imperative play()/stop()/source-sync
      // function needed the way MediaPlayer's own syncPlayer() above
      // is, unlike video: AnimatedImage just plays/loops on its own
      // once given a source, so plain reactive bindings off
      // root.gifPath are enough on their own. This is the whole
      // reason GIF was the easier fast-follow -- no MediaPlayer, no
      // VideoOutput, no ffmpeg poster step, no generation-tracking
      // needed to avoid racing a superseded selection.
      AnimatedImage {
        id: gifOutput
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        cache: false
        source: root.gifPath !== "" ? ("file://" + root.gifPath) : ""
        playing: root.gifPath !== ""
        // Same "don't show a blank/broken frame" reasoning as video's
        // own frameDecoded gate, just checking AnimatedImage's own
        // status instead since there's no separate video-frame signal
        // to hook for a gif.
        visible: root.gifPath !== "" && status === AnimatedImage.Ready
      }

      Connections {
        target: root
        function onPlayGenerationChanged() { panel.syncPlayer() }
      }

      Connections {
        target: videoOutput.videoSink
        function onVideoFrameChanged() {
          if (root.videoPath !== "" && !panel.frameDecoded && panel.playerGeneration === root.playGeneration)
            panel.frameDecoded = true
        }
      }

      Component.onCompleted: syncPlayer()

      // Forwards the same real desktop double-click actions Omarchy's
      // own Background.qml handles -- direct parity with live-
      // wallpaper's own "preserves desktop double-click behavior
      // through the video/input surface". Without this, this
      // transparent-but-input-catching layer sitting on top would
      // silently eat the click and Omarchy's own surface underneath
      // would never see it.
      MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onDoubleClicked: mouse => {
          if (mouse.button === Qt.RightButton)
            themeSwitchProc.running = true
          else
            bgSwitchProc.running = true
          mouse.accepted = true
        }
      }
    }
  }

  Process {
    id: bgSwitchProc
    command: ["bash", "-c", "background=$(omarchy-theme-bg-switcher); [[ -n $background ]] && omarchy-theme-bg-set \"$background\""]
  }

  Process {
    id: themeSwitchProc
    command: ["bash", "-c", "theme=$(omarchy-theme-switcher); [[ -n $theme ]] && omarchy-theme-set \"$theme\" >/dev/null 2>&1 &"]
  }
}
