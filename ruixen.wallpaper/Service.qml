import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtMultimedia

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
    posterAndSetProc.command = ["bash", "-c",
      "hash=$(printf '%s' \"$1\" | md5sum | cut -d' ' -f1); " +
      "poster=\"$HOME/.cache/ruixen/wallpaper-posters/$hash.jpg\"; " +
      "[[ -f \"$poster\" ]] || ffmpeg -y -loglevel quiet -i \"$1\" -vframes 1 -q:v 3 \"$poster\" 2>/dev/null; " +
      "if [[ -f \"$poster\" ]]; then omarchy-theme-bg-set \"$poster\"; printf '%s' \"$poster\"; fi",
      "_", path]
    posterAndSetProc.running = true

    stateWriteProc.command = ["bash", "-c", "printf 'video\\n%s' \"$1\" > \"$HOME/.local/state/ruixen/wallpaper-media\"", "_", path]
    stateWriteProc.running = true
  }

  // GIF's own play -- direct request ("yea lets do the gif next").
  // No poster/ffmpeg step needed at all: unlike video, Omarchy's own
  // background Image can already render a gif directly (its own
  // first frame, same as any other static image -- confirmed earlier
  // when gifs first started showing up correctly as plain picker
  // thumbnails), so the gif file itself doubles as its own real
  // fallback background. root.posterPath still gets set to it (same
  // "whatever we expect current/background to be" role posterPath
  // already has for video), just without a separate cache file.
  function playGif(path) {
    path = String(path || "").trim()
    if (path === "") return
    root.gifPath = path
    root.videoPath = ""
    root.posterPath = ""
    root.playGeneration += 1

    root.posterExpectedFor = path
    posterAndSetProc.command = ["bash", "-c",
      "omarchy-theme-bg-set \"$1\"; printf '%s' \"$1\"", "_", path]
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
    function playVideo(path: string): void { root.play(path) }
    function playGif(path: string): void { root.playGif(path) }
    function stop(): void { root.stop() }
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
