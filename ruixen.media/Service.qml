import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import "MediaModel.js" as MediaModel

Item {
  id: root

  property var shell: null
  property string preferredPlayerKey: ""
  property var playerStartedAt: ({})
  property var pendingTrackOsd: null
  property int playSerial: 0

  readonly property var players: Mpris.players ? Mpris.players.values : []
  readonly property var nodes: Pipewire.nodes ? Pipewire.nodes.values : []
  readonly property var playbackStreams: {
    var list = []
    for (var i = 0; i < nodes.length; i++) {
      var n = nodes[i]
      if (n && n.isStream && isPlaybackStream(n) && n.audio) list.push(n)
    }
    return list
  }
  readonly property var sourcePlayers: orderedSourcePlayers()
  readonly property var sourceCyclePlayers: orderedCycleSourcePlayers()
  readonly property var activePlayer: selectActivePlayer()
  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  // Both gated on hasMedia, not just activePlayer -- a closed app can
  // leave a zombie MPRIS registration behind (e.g. chromium after
  // quitting still owns org.mpris.MediaPlayer2.chromium.* on the session
  // bus, PlaybackStatus "Stopped", with stale metadata but no title/
  // artist). Ungated, consumers reading these directly would show stale
  // art/album for a player that isn't actually playing anything.
  readonly property string album: hasMedia && activePlayer && activePlayer.trackAlbum ? activePlayer.trackAlbum : ""
  readonly property string artUrl: hasMedia && activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""
  readonly property string identity: activePlayer ? (activePlayer.identity || activePlayer.desktopEntry || "") : ""

  function isProxyPlayer(player) {
    return MediaModel.isProxyPlayer(player)
  }

  function hasMetadata(player) {
    return MediaModel.hasMetadata(player)
  }

  function hasTrackMetadata(player) {
    return MediaModel.hasTrackMetadata(player)
  }

  function playerCanControl(player) {
    return MediaModel.playerCanControl(player)
  }

  function canHandleAction(player, action) {
    return MediaModel.canHandleAction(player, action)
  }

  function canCycleSource(player) {
    return MediaModel.canCycleSource(player)
  }

  function nodeProps(node) {
    return MediaModel.nodeProps(node)
  }

  function isPlaybackStream(node) {
    return MediaModel.isPlaybackStream(node)
  }

  function streamLabelKey(label) {
    return MediaModel.streamLabelKey(label)
  }

  function rawStreamLabel(node) {
    return MediaModel.rawStreamLabel(node)
  }

  function playerAppLabel(player) {
    return MediaModel.playerAppLabel(player)
  }

  function playerHasPlaybackStream(player) {
    return MediaModel.playerHasPlaybackStream(player, playbackStreams)
  }

  function playerKey(player) {
    return MediaModel.playerKey(player)
  }

  function playerForKey(key) {
    if (!key) return null
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (playerKey(p) === key) return p
    }
    return null
  }

  function playerOrder(player, fallback) {
    var key = playerKey(player)
    var value = key ? playerStartedAt[key] : undefined
    return value === undefined ? fallback : value
  }

  function syncPlayingOrder() {
    var next = {}
    var alive = {}
    var serial = playSerial

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      var key = playerKey(p)
      if (!key) continue

      alive[key] = true
      if (!p.isPlaying) continue

      if (playerStartedAt[key] === undefined) {
        serial += 1
        next[key] = serial
      } else {
        next[key] = playerStartedAt[key]
      }
    }

    if (preferredPlayerKey && !alive[preferredPlayerKey]) preferredPlayerKey = ""

    playSerial = serial
    playerStartedAt = next
  }

  function orderedSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (hasMetadata(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (!!a.isPlaying !== !!b.isPlaying) return a.isPlaying ? -1 : 1
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      if (a.isPlaying && b.isPlaying) {
        var orderDelta = playerOrder(a, 1000) - playerOrder(b, 1000)
        if (orderDelta !== 0) return orderDelta
      }
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  function orderedCycleSourcePlayers() {
    var list = []
    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (canCycleSource(p)) list.push(p)
    }

    list.sort(function(a, b) {
      if (isProxyPlayer(a) !== isProxyPlayer(b)) return isProxyPlayer(a) ? 1 : -1
      return labelFor(a).localeCompare(labelFor(b))
    })

    return list
  }

  // Picks whichever currently-playing source started most recently
  // instead of longest ago. playerStartedAt assigns an increasing serial
  // the first time a player is seen playing, so a higher order means it
  // started more recently. Stock always preferred the oldest, which meant
  // a tab still technically "playing" (autoplay/looping in the
  // background, MPRIS not always prompt about isPlaying going false)
  // kept winning over whatever was actually just started.
  function newestPlayingPlayer(requirePlaybackStream) {
    var newest = null
    var newestOrder = -1
    var playingProxy = null
    var proxyOrder = -1

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxyPlayer = isProxyPlayer(p)
      if (p.isPlaying) {
        if (requirePlaybackStream && !playerHasPlaybackStream(p)) continue

        var order = playerOrder(p, i + 1000)
        if (!proxyPlayer && (!newest || order > newestOrder)) {
          newest = p
          newestOrder = order
        } else if (proxyPlayer && (!playingProxy || order > proxyOrder)) {
          playingProxy = p
          proxyOrder = order
        }
      }
    }

    return newest || playingProxy || null
  }

  function selectActivePlayer() {
    var preferred = null
    var trackPlayer = null
    var trackProxy = null
    var streamPlayer = null
    var streamProxy = null
    var controllablePlayer = null
    var controllableProxy = null
    var identityPlayer = null
    var identityProxy = null

    for (var i = 0; i < players.length; i++) {
      var p = players[i]
      if (!p) continue

      var proxy = isProxyPlayer(p)

      if (preferredPlayerKey && playerKey(p) === preferredPlayerKey && hasMetadata(p)) preferred = p

      if (playerHasPlaybackStream(p)) {
        if (!proxy && !streamPlayer) streamPlayer = p
        else if (proxy && !streamProxy) streamProxy = p
      } else if (hasTrackMetadata(p)) {
        if (!proxy && !trackPlayer) trackPlayer = p
        else if (proxy && !trackProxy) trackProxy = p
      } else if (playerCanControl(p)) {
        if (!proxy && !controllablePlayer) controllablePlayer = p
        else if (proxy && !controllableProxy) controllableProxy = p
      } else if (hasMetadata(p)) {
        if (!proxy && !identityPlayer) identityPlayer = p
        else if (proxy && !identityProxy) identityProxy = p
      }
    }

    if (preferred && preferred.isPlaying) return preferred
    var streamCandidate = streamPlayer || streamProxy
    var streamPreferred = preferred && playerHasPlaybackStream(preferred) ? preferred : null
    return newestPlayingPlayer(true) || newestPlayingPlayer(false) || streamPreferred || streamCandidate || preferred || trackPlayer || trackProxy || controllablePlayer || controllableProxy || identityPlayer || identityProxy || null
  }

  function labelFor(player) {
    return MediaModel.labelFor(player)
  }

  function osdMessage(player, fallback) {
    return MediaModel.osdMessage(player, fallback)
  }

  function trackSignature(player) {
    return MediaModel.trackSignature(player)
  }

  function showOsd(actionLabel, iconName, player) {
    if (!shell) return
    shell.summon("omarchy.osd", JSON.stringify({
      icon: iconName || "media",
      message: osdMessage(player || activePlayer, actionLabel)
    }))
  }

  function scheduleOsd(actionLabel, iconName, player, waitForTrackChange, beforeTrackSignature) {
    if (waitForTrackChange) {
      pendingTrackOsd = {
        actionLabel: actionLabel,
        iconName: iconName,
        player: player,
        playerKey: playerKey(player),
        before: beforeTrackSignature,
        attempts: 0
      }
      trackOsdTimer.restart()
    } else {
      Qt.callLater(function() { root.showOsd(actionLabel, iconName, player) })
    }
  }

  function flushPendingTrackOsd(force) {
    var pending = pendingTrackOsd
    if (!pending) return

    var player = playerForKey(pending.playerKey) || pending.player
    if (force || MediaModel.trackChanged(pending.before, player) || pending.attempts >= 10) {
      pendingTrackOsd = null
      trackOsdTimer.stop()
      root.showOsd(pending.actionLabel, pending.iconName, player)
      return
    }

    pending.attempts = pending.attempts + 1
    pendingTrackOsd = pending
    trackOsdTimer.restart()
  }

  function selectPlayer(key) {
    var player = playerForKey(key)
    if (!player || !hasMetadata(player)) return false
    preferredPlayerKey = playerKey(player)
    return true
  }

  function playPlayer(player) {
    if (!player) return false
    if (player.canPlay) {
      player.play()
      return true
    }
    return false
  }

  function pausePlayer(player) {
    if (!player) return false
    if (player.canPause) {
      player.pause()
      return true
    }
    if (player.canTogglePlaying && player.isPlaying) {
      player.togglePlaying()
      return true
    }
    return false
  }

  function switchSource(delta, transferPlayback, showFeedback) {
    var list = sourceCyclePlayers
    if (!list || list.length === 0) return false

    var activeKey = playerKey(activePlayer)
    var index = 0
    for (var i = 0; i < list.length; i++) {
      if (playerKey(list[i]) === activeKey) {
        index = i
        break
      }
    }

    index = (index + delta + list.length) % list.length
    var current = activePlayer
    var next = list[index]
    var currentWasPlaying = current && current.isPlaying
    var currentKey = playerKey(current)
    var nextKey = playerKey(next)

    preferredPlayerKey = nextKey

    if (transferPlayback && currentWasPlaying && next && nextKey !== currentKey) {
      var nextWasPlaying = next.isPlaying
      var nextStarted = nextWasPlaying || playPlayer(next)
      if (nextStarted) pausePlayer(current)
    }

    if (showFeedback !== false) Qt.callLater(function() {
      root.showOsd("Source", "media-source", next)
    })

    return true
  }

  function playerForAction(action, targetKey) {
    var targeted = playerForKey(targetKey)
    if (targeted) return targeted

    if (action === "pause" || action === "playPause") {
      var newest = newestPlayingPlayer(true) || newestPlayingPlayer(false)
      if (newest) return newest
    }

    if (canHandleAction(activePlayer, action)) return activePlayer

    var list = sourcePlayers
    for (var i = 0; i < list.length; i++) {
      if (canHandleAction(list[i], action)) return list[i]
    }

    return activePlayer
  }

  function runAction(action, showFeedback, targetKey) {
    var player = playerForAction(action, targetKey)
    var key = playerKey(player)
    var actionLabel = "Play/pause"
    var iconName = "media"
    var beforeTrackSignature = trackSignature(player)
    var handled = false

    if (action === "next") {
      actionLabel = "Next"
      iconName = "media-next"
      if (player && player.canGoNext) {
        player.next()
        handled = true
      }
    } else if (action === "previous") {
      actionLabel = "Previous"
      iconName = "media-previous"
      if (player && player.canGoPrevious) {
        player.previous()
        handled = true
      }
    } else if (action === "play") {
      actionLabel = "Play"
      iconName = "media-play"
      if (player && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying && !player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "pause") {
      actionLabel = "Pause"
      iconName = "media-pause"
      if (player && player.canPause) {
        player.pause()
        handled = true
      } else if (player && player.canTogglePlaying && player.isPlaying) {
        player.togglePlaying()
        handled = true
      }
    } else if (action === "playPause") {
      actionLabel = player && player.isPlaying ? "Pause" : "Play"
      iconName = player && player.isPlaying ? "media-pause" : "media-play"
      if (player && player.isPlaying && player.canPause) {
        player.pause()
        handled = true
      } else if (player && !player.isPlaying && player.canPlay) {
        player.play()
        handled = true
      } else if (player && player.canTogglePlaying) {
        player.togglePlaying()
        handled = true
      }
    }

    if (handled && key) preferredPlayerKey = key
    if (showFeedback !== false)
      scheduleOsd(actionLabel, iconName, player, handled && (action === "next" || action === "previous"), beforeTrackSignature)
    return handled
  }

  // Recompute play-order reactively instead of polling every 500ms.
  // syncPlayingOrder only depends on the set of players and each player's
  // isPlaying state: onPlayersChanged covers players appearing/disappearing,
  // and the Instantiator wires isPlayingChanged for each live player.
  Component.onCompleted: {
    root.syncPlayingOrder()
    mediaEnsureDirProc.running = true
  }
  onPlayersChanged: root.syncPlayingOrder()

  // Mirrors statusJson() to a small state file
  // (~/.local/state/ruixen/media-state.json) -- ruixen-shell issue
  // #39/#38: Omarchy v4.0.3 restricts shell.firstPartyServiceFor() to a
  // fixed 4-item allowlist of Omarchy's own services, which
  // "ruixen.media" was never going to be in, so ruixen.notch (a
  // separate QML instance, only ever handed whatever ruixen.bar's own
  // ModuleSlot injects, never a shell property of its own) can no
  // longer reach this service directly.
  //
  // Refreshed on a 500ms poll, unlike syncPlayingOrder's own reactive
  // wiring above -- confirmed necessary, not guessed: ruixen.notch's
  // own pre-#39 code had to poll activePlayer.position itself on a
  // matching 500ms Timer rather than bind to a positionChanged signal,
  // because Quickshell's own MPRIS binding does not push position
  // updates the way it does for isPlaying (see syncPlayingOrder's own
  // comment for the contrast). Runs whenever there is any player at all
  // (not just while actually playing), so a paused-track metadata
  // change is still reflected within 500ms; the immediate
  // onActivePlayerChanged flush below covers the player
  // appearing/disappearing edges without waiting on the timer's own
  // first tick.
  readonly property string mediaStateHome: Quickshell.env("HOME")
  readonly property string mediaStatePath: mediaStateHome + "/.local/state/ruixen/media-state.json"

  function flushMediaState() {
    mediaStateFile.setText(root.statusJson() + "\n")
  }

  onActivePlayerChanged: root.flushMediaState()

  Timer {
    interval: 500
    running: root.activePlayer !== null
    repeat: true
    triggeredOnStart: true
    onTriggered: root.flushMediaState()
  }

  FileView {
    id: mediaStateFile
    path: root.mediaStatePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
  }

  Process {
    id: mediaEnsureDirProc
    command: ["mkdir", "-p", root.mediaStateHome + "/.local/state/ruixen"]
    running: false
  }

  Instantiator {
    model: root.players
    delegate: Connections {
      required property var modelData
      target: modelData
      function onIsPlayingChanged() { root.syncPlayingOrder() }
    }
  }

  Timer {
    id: trackOsdTimer
    interval: 120
    repeat: false
    onTriggered: root.flushPendingTrackOsd(false)
  }

  PwObjectTracker { objects: root.playbackStreams }

  function statusJson() {
    var p = activePlayer
    return JSON.stringify({
      hasPlayer: p !== null,
      hasMedia: root.hasMedia,
      playing: p ? !!p.isPlaying : false,
      identity: p ? (p.identity || "") : "",
      desktopEntry: p ? (p.desktopEntry || "") : "",
      title: p ? (p.trackTitle || "") : "",
      artist: p ? (p.trackArtist || "") : "",
      album: p && p.trackAlbum ? p.trackAlbum : "",
      // Gated on hasMedia, not just p.trackArtUrl -- a closed app can
      // leave a zombie MPRIS registration behind (confirmed: chromium
      // after quitting still owns org.mpris.MediaPlayer2.chromium.* on
      // the session bus, PlaybackStatus "Stopped", with a stale
      // mpris:artUrl but no title/artist) -- this is the same gate
      // ruixen.notch's own consuming code used to apply itself before
      // it started reading this JSON directly (see ruixen-shell issue
      // #39), moved here so every consumer of this status gets it, not
      // just that one.
      artUrl: root.hasMedia && p && p.trackArtUrl ? p.trackArtUrl : "",
      // Added for ruixen-shell issue #39 -- ruixen.notch's own progress
      // bar reads these off the state file this JSON gets mirrored into
      // (see flushMediaState() above). Harmless additive fields for any
      // existing consumer of this same JSON (the public `ruixen-media
      // status` IPC command included) that only reads keys it knows.
      length: p ? Math.max(0, Number(p.length || 0)) : 0,
      position: p ? Math.max(0, Number(p.position || 0)) : 0,
      canGoNext: p ? !!p.canGoNext : false,
      canGoPrevious: p ? !!p.canGoPrevious : false,
      canTogglePlaying: p ? !!p.canTogglePlaying : false,
      // Added for ruixen-shell issue #39 -- ruixen.media/BarWidget.qml's
      // own play/pause button enable-state needs these two specifically
      // (canTogglePlaying alone isn't always set even when one of these
      // is), see its own MediaModel.js-style canHandleAction checks.
      canPlay: p ? !!p.canPlay : false,
      canPause: p ? !!p.canPause : false
    })
  }

  IpcHandler {
    // Not "media" -- that collides with the stock omarchy.media service,
    // which also ships keepLoaded and registers the same target regardless
    // of whether its bar widget is enabled/placed. Whichever loads first
    // wins the registration; the other's calls (including our
    // ruixen-specific sourceNext/sourcePrevious/sourceSwitch) silently do
    // nothing. External callers (a keybind calling `omarchy-shell shell
    // media ...`) need a name that's ours alone regardless.
    //
    // Bar-widget clicks (ruixen.media/BarWidget.qml, ruixen.notch's own
    // dashboard buttons) used to call this service directly via
    // firstPartyServiceFor("ruixen.media") instead of this IPC target --
    // now they go through this same target too (the parameterized
    // runAction() below), via a Process running `omarchy-shell
    // ruixen-media runAction ...`, since Omarchy v4.0.3 restricts that
    // direct call to a fixed allowlist "ruixen.media" was never going to
    // be in (see ruixen-shell issue #39).
    target: "ruixen-media"

    function status(): string {
      return root.statusJson()
    }

    function playPause(): string {
      return root.runAction("playPause", true) ? "ok" : "unhandled"
    }

    function next(): string {
      return root.runAction("next", true) ? "ok" : "unhandled"
    }

    function previous(): string {
      return root.runAction("previous", true) ? "ok" : "unhandled"
    }

    function play(): string {
      return root.runAction("play", true) ? "ok" : "unhandled"
    }

    function pause(): string {
      return root.runAction("pause", true) ? "ok" : "unhandled"
    }

    // Parameterized variant for in-process callers that need
    // showFeedback: false -- ruixen-shell issue #39: ruixen.notch's own
    // dashboard buttons call this (via a Process running `omarchy-shell
    // ruixen-media runAction <action> false`) instead of playPause()/
    // next()/previous() above, which hardcode showFeedback: true for
    // external/keybind callers where an OSD toast is the only feedback.
    // The notch already shows playing state visually, so a toast on top
    // of that would be redundant.
    function runAction(action: string, showFeedback: bool): string {
      return root.runAction(String(action), showFeedback === true) ? "ok" : "unhandled"
    }

    function sourceNext(): string {
      return root.switchSource(1, false, true) ? "ok" : "unhandled"
    }

    function sourcePrevious(): string {
      return root.switchSource(-1, false, true) ? "ok" : "unhandled"
    }

    function sourceSwitch(): string {
      return root.switchSource(1, true, true) ? "ok" : "unhandled"
    }

    function sourceSwitchPrevious(): string {
      return root.switchSource(-1, true, true) ? "ok" : "unhandled"
    }

    function ping(): string {
      return "ok"
    }
  }
}
