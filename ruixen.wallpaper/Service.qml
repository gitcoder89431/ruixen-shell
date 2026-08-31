import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtMultimedia

// Muted, looping video wallpaper support -- direct request ("can we
// remake one in our shell like ruixen-wallpaper plugin that works
// with our notch... it just needs to show up in the notch wallpaper
// picker and it needs to work backend wise"). Investigated
// yesheytenzin/live-wallpaper as a reference for the real mechanism
// (not guessed, not copied wholesale) -- this is a from-scratch port
// of that same design onto this repo's own conventions:
//
// Omarchy's own desktop background is a separate first-party plugin
// (omarchy.background, kind: service) -- a per-screen WlrLayer.
// Background layer-shell surface (namespace "omarchy-background")
// that just shows a static Image. It has no video concept at all and
// we never touch it directly (per this repo's own standing rule
// about never patching anything Omarchy owns). This plugin adds a
// SECOND, separate WlrLayer.Background surface per screen (namespace
// "ruixen-wallpaper") that sits on top of it and stays fully
// transparent -- letting Omarchy's own real background show through
// underneath -- except while a video is actively playing AND has
// decoded a real first frame, at which point the video visually
// covers it. No video active, nothing decoded yet, or playback
// stopped -> fully invisible, Omarchy's own layer is all that's ever
// seen. Has to be its own kind: service plugin, not folded into
// ruixen.notch's own kind: overlay -- a service plugin runs
// persistently regardless of whether any UI panel is open, which is
// exactly what an "always-on desktop layer" needs; ruixen.notch's own
// Wallpapers tab is just the CLIENT that tells this one what to play,
// over the same qs ipc call convention every other cross-plugin
// action in this repo already uses.
Item {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string stateDir: home + "/.local/state/ruixen"
  readonly property string statePath: stateDir + "/wallpaper-video"
  readonly property string posterDir: home + "/.cache/ruixen/wallpaper-posters"

  property string videoPath: ""
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
        if (poster !== "" && root.videoPath === root.posterExpectedFor) {
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

    stateWriteProc.command = ["bash", "-c", "printf '%s' \"$1\" > \"$HOME/.local/state/ruixen/wallpaper-video\"", "_", path]
    stateWriteProc.running = true
  }

  function stop() {
    root.videoPath = ""
    root.posterPath = ""
    root.playGeneration += 1
    stateWriteProc.command = ["bash", "-c", "rm -f \"$HOME/.local/state/ruixen/wallpaper-video\""]
    stateWriteProc.running = true
  }

  Process {
    id: stateWriteProc
    stdout: StdioCollector { waitForEnd: true }
  }

  // Resume after a shell restart -- direct parity with live-wallpaper's
  // own --resume. Reads the plain-text state file (same convention
  // every other persisted setting in this repo already uses) and
  // replays play() if it names a video that still actually exists.
  Process {
    id: resumeProc
    command: ["bash", "-c",
      "f=\"$HOME/.local/state/ruixen/wallpaper-video\"; " +
      "[[ -f \"$f\" ]] && p=$(cat \"$f\") && [[ -f \"$p\" ]] && printf '%s' \"$p\""]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var p = String(text || "").trim()
        if (p !== "") root.play(p)
      }
    }
  }

  // Safety net for the case our own picker doesn't cover: someone
  // opens Omarchy's OWN stock Style -> Background picker (or the
  // desktop double-click shortcut, forwarded below) and picks a plain
  // static image while a video is playing. That flow calls the real
  // omarchy-theme-bg-set directly, which has no idea this plugin
  // exists -- so current/background's own symlink target changes out
  // from under us. Polling and comparing against our own last-set
  // poster is how live-wallpaper's own --stop-if-changed does the
  // same detection; if it no longer matches, something else changed
  // the background, so stop.
  Process {
    id: readCurrentBgProc
    command: ["readlink", "-f", root.home + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.videoPath === "" || root.posterPath === "") return
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
      if (root.videoPath !== "" && !readCurrentBgProc.running) readCurrentBgProc.running = true
    }
  }

  IpcHandler {
    target: "ruixen.wallpaper"
    function playVideo(path: string): void { root.play(path) }
    function stop(): void { root.stop() }
    function status(): string {
      return JSON.stringify({ active: root.videoPath !== "", video: root.videoPath, poster: root.posterPath })
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
