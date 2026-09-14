import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons

// A dynamic-island-style notch: a small pill that expands into a wider
// panel, informed by looking at how other Omarchy Quickshell shells
// structure a similar always-on-top notch overlay. The collapsed
// DEFAULT VIEW's own widget row -- avatar | divider | wavy player |
// divider | bell -- is this file's own layout, not full backend: bell
// is a static placeholder (no notification service wired up), avatar
// reads the standard ~/.face.icon convention, wave slider shows real
// position/length but isn't drag-to-seek yet.
//
// The wave itself is WavyLine (see its own component comment below) --
// a Canvas drawing a continuous sine wave, driven by FrameAnimation
// while playing. Genuinely self-contained, no shader/effect dependency.
//
// Icons: Nerd Font glyphs, already proven working in ruixen.media/
// ruixen.dnd, rather than pulling in a new icon font dependency for
// this pass.
Item {
  id: root
  property var shell: null
  property var manifest: null

  // Real fullscreen-state watching -- see the layer comment on `panel`
  // below for why this stays on WlrLayer.Overlay instead of a layer trick.
  // ToplevelManager.activeToplevel.fullscreen is the same Wayland
  // foreign-toplevel property Omarchy's own ActiveWindow.qml reads.
  readonly property bool fullscreenActive: ToplevelManager.activeToplevel
    ? ToplevelManager.activeToplevel.fullscreen : false

  // Super+Shift+Space (stock Omarchy bind_toggle "bar") only ever told
  // ruixen.bar to hide -- this is a completely separate PanelWindow, so
  // it never heard about it at all. Direct report: "super shift space
  // hides the float and docked icons on left and right, but the notch
  // is different". Same flag-file mechanism ruixen.bar's own
  // barHiddenProbe uses (see Bar.qml), so both surfaces read the exact
  // same on-disk state `omarchy-toggle-bar` already flips -- not a
  // second, competing toggle.
  property bool barHidden: false

  Process {
    id: barHiddenProbe
    running: true
    command: ["bash", "-c", "[[ -f $HOME/.local/state/omarchy/toggles/bar-off ]] && echo yes || echo no"]
    stdout: SplitParser { onRead: function(line) { root.barHidden = String(line).trim() === "yes" } }
  }
  FileView {
    path: Quickshell.env("HOME") + "/.local/state/omarchy/toggles"
    watchChanges: true
    printErrors: false
    onFileChanged: barHiddenProbe.running = true
  }

  readonly property color notchColor: "#000000"
  // Same theme-aware-with-safety-net treatment as ruixen.bar's
  // pillForeground (see Bar.qml for the full reasoning): this notch is
  // always OLED black too, so use the theme's own foreground when it's
  // light enough to read against that, else fall back to a fixed light
  // color. Keeps each theme's actual look (off-white on nearly every
  // dark theme) instead of a single hardcoded white, while still
  // catching the real exceptions (light themes, Rose Pine's dark
  // purple foreground).
  readonly property color themeForeground: Color.bar.text
  readonly property real themeForegroundLuminance: 0.299 * themeForeground.r + 0.587 * themeForeground.g + 0.114 * themeForeground.b
  readonly property color safeForeground: "#e8e8e8"
  readonly property color textColor: themeForegroundLuminance > 0.45 ? themeForeground : safeForeground
  readonly property color muted: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5)
  // Theme-linked, per direct request ("try the accent color to follow
  // the themes... so they match too") -- was a fixed "media is active"
  // semantic green, same pattern as ruixen.media's own badge. Color.accent
  // is real theme data (theme/colors.toml's own accent key, or color4 as
  // a fallback when a theme doesn't define one -- confirmed in Commons/
  // Color.qml's loadColors()), so this now follows theme switches instead
  // of staying fixed. Single property, cascades everywhere via the
  // existing accent: root.accent passthrough below -- wave, playhead,
  // quick-control toggles, calendar's today-highlight, active tab state.
  readonly property color accent: Color.accent
  readonly property string fontFamily: "JetBrainsMono Nerd Font"

  // Bumped by the refreshAvatar IPC call below -- this plugin is
  // keepLoaded:true, so UserAvatar's Image below would otherwise keep
  // showing whatever it decoded at mount time even after ~/.face.icon's
  // bytes change on disk (ruixen.settings' own General page is what
  // actually writes that file). See UserAvatar's own Image.source for
  // why this is a "#" fragment, not a "?" query string.
  property int avatarCacheBust: 0

  // Reads ruixen.media/Service.qml's own state file directly instead of
  // shell.firstPartyServiceFor("ruixen.media") -- ruixen-shell issue
  // #39/#38: Omarchy v4.0.3 restricts that call to a fixed 4-item
  // allowlist of Omarchy's own services, which "ruixen.media" was never
  // going to be in regardless of caller. Control (play/pause/next/
  // previous) goes the other way -- through ruixen.media's own existing
  // "ruixen-media" IpcHandler target instead of calling a live service
  // object's runAction() directly, see sendMediaAction() below.
  readonly property string mediaStateHome: Quickshell.env("HOME")
  readonly property string mediaStatePath: mediaStateHome + "/.local/state/ruixen/media-state.json"

  property bool hasMedia: false
  property bool isPlaying: false
  property string title: ""
  property string artist: ""
  property string album: ""
  property string artUrl: ""
  readonly property string playIcon: isPlaying ? "\udb80\udfe4" : "\udb81\udc0a"

  FileView {
    id: mediaStateFile
    path: root.mediaStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyMediaState(text())
    onLoadFailed: root.applyMediaState("")
  }

  function applyMediaState(raw) {
    var parsed
    try {
      parsed = JSON.parse(String(raw || "").trim() || "{}")
    } catch (e) {
      parsed = {}
    }
    root.hasMedia = parsed.hasMedia === true
    root.isPlaying = parsed.playing === true
    root.title = typeof parsed.title === "string" ? parsed.title : ""
    root.artist = typeof parsed.artist === "string" ? parsed.artist : ""
    root.album = typeof parsed.album === "string" ? parsed.album : ""
    root.artUrl = typeof parsed.artUrl === "string" ? parsed.artUrl : ""
    root.trackLength = Math.max(0, Number(parsed.length || 0))
    root.trackPosition = Math.max(0, Number(parsed.position || 0))
  }

  // Fire-and-forget through ruixen.media's own IPC target -- the same
  // mechanism `omarchy-shell ruixen-media <method>` already uses
  // externally, just invoked from a Process instead of a shell script.
  // showFeedback is always false here: the notch already shows playing
  // state visually, an OSD toast on top of that would be redundant. The
  // target's own playPause()/next()/previous() convenience functions
  // hardcode showFeedback: true (for external/keybind callers, where an
  // OSD is the only feedback), so this calls the parameterized
  // runAction() instead of those.
  property bool mediaActionPending: false

  function sendMediaAction(action) {
    if (mediaActionProcess.running) return
    root.mediaActionPending = true
    mediaActionProcess.command = ["omarchy-shell", "ruixen-media", "runAction", String(action), "false"]
    mediaActionProcess.running = true
  }

  Process {
    id: mediaActionProcess
    running: false
    onExited: root.mediaActionPending = false
  }

  // ruixen-shell issue #42/#38: Omarchy v4.0.3 restricts
  // shell.firstPartyServiceFor() to a fixed allowlist, and only for a
  // plugin declaring manifest kind "bar" -- this file (kind:
  // ["overlay","service"]) was never going to have bar capabilities to
  // use it even for "omarchy.notifications", which IS nominally in
  // that allowlist. DND is now read straight off the real service's
  // own persisted state file instead (confirmed directly against
  // /usr/share/omarchy/shell/plugins/notifications/Service.qml:
  // settingsPath = ~/.local/state/omarchy/notifications.json,
  // {"version":3,"dnd":bool}, atomicWrites: true) -- watched, so an
  // external toggle (ruixen.quickactions' own pill, say) is reflected
  // here immediately, the same pattern already used for the
  // stay-awake flag file in DashboardContent.qml.
  property bool dnd: false

  FileView {
    id: dndStateFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/notifications.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text() || "{}")
        root.dnd = parsed && parsed.dnd === true
      } catch (e) {
        // Leave dnd at its last known value on a transient parse
        // failure (e.g. read mid-write) rather than guessing false.
      }
    }
    onLoadFailed: root.dnd = false
  }

  function sendDndAction(action) {
    if (dndActionProcess.running) return
    dndActionProcess.command = ["omarchy-shell", "notifications", String(action)]
    dndActionProcess.running = true
  }

  Process { id: dndActionProcess; running: false }

  // The notch's own notification-history backing store (Column 3 of
  // the Widgets dashboard) -- independent of the dnd property above,
  // sweeping the real service's own on-disk state to add a read flag
  // and a deeper backlog on top of it. See NotificationService.qml's
  // own header for the full design and its one deliberate scope
  // difference from the project it was studied from.
  NotificationService {
    id: notificationHistory
    shell: root.shell
  }

  // The notch's own Kanban tab backing store (4th dashboard tab) --
  // see KanbanService.qml's own header for the full design.
  KanbanService {
    id: kanbanService
  }

  // ruixen-shell issue #44/#38: shell.appLibrary only populates for a
  // plugin declaring manifest kind "menu" -- this file has no reason to
  // claim that kind, so LauncherContent.qml's own search/launch/icons
  // now go through this instead. See AppLibrary.qml's own header for
  // the full design and its deliberately narrower scope than Omarchy's
  // own real AppLibrary.qml.
  AppLibrary {
    id: appLibrary
  }

  // Real brightness control, per direct request ("can this actually
  // control the brightness?") -- omarchy.monitor (the real Display
  // settings panel this mirrors visually) only declares kind
  // "bar-widget" in its manifest, no "service" kind, so there's no
  // shell.firstPartyServiceFor() to read here (same limitation already
  // documented for omarchy.agents elsewhere in this file). Reused the
  // exact same CLI tools their own Panel.qml calls directly instead:
  // omarchy-monitor-state to read (line 1 = brightness percent or
  // "unavailable", line 6 = the focused monitor's name -- confirmed by
  // running it directly, not guessed), omarchy-brightness-display
  // --no-osd --monitor <name> <percent>% to write.
  property real brightnessPercent: 50
  property string focusedMonitor: ""
  property bool brightnessAvailable: false

  Process {
    id: brightnessStateProc
    command: ["omarchy-monitor-state"]
    running: true
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var b = String(lines[0] || "").trim()
        root.brightnessAvailable = b !== "unavailable" && b !== ""
        if (root.brightnessAvailable) root.brightnessPercent = Math.max(0, Math.min(100, parseInt(b, 10)))
        root.focusedMonitor = String(lines[5] || "").trim()
      }
    }
  }

  // Only polls while the dashboard's actually open -- matches the real
  // Display panel's own "running: root.opened" reasoning (picks up
  // brightness changes made elsewhere, e.g. keyboard backlight keys,
  // while this is visible; no reason to poll while collapsed).
  Timer {
    interval: 5000
    running: panel.expanded
    repeat: true
    onTriggered: if (!brightnessStateProc.running) brightnessStateProc.running = true
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    // Deliberately does NOT trigger a re-read on completion -- same
    // reasoning as the real Display panel's own comment: re-reading via
    // omarchy-monitor-state right after a write races the hardware/
    // driver and can return an empty string, briefly bouncing the
    // slider back to 0. The locally-set value (below) is authoritative
    // until the next periodic poll.
  }

  function setBrightness(percent) {
    var p = Math.max(0, Math.min(100, Math.round(percent)))
    root.brightnessPercent = p
    setBrightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", root.focusedMonitor, p + "%"]
    setBrightnessProc.running = true
  }
  // The collapsed pill's own "no media" fallback content -- direct
  // request: "when theres no music it just shows active window". Same
  // real Wayland foreign-toplevel data fullscreenActive above already
  // reads, and the exact title/appId fallback omarchy.active-window's
  // own BarWidget.qml uses (confirmed by reading it directly) -- no
  // new dependency on that plugin being installed or pinned at all.
  readonly property var activeToplevel: ToplevelManager.activeToplevel
  readonly property string activeWindowTitle: activeToplevel
    ? (activeToplevel.title || activeToplevel.appId || "") : ""
  // Terminal emulators commonly set their own window title to a shell
  // prompt string ("user@host:path"), and once elided (see the Text
  // below) that format actively fights the fixed-width slot:
  // Text.ElideRight keeps the FRONT of a string -- a real report
  // ("arf26@omarchy:~/Docu...") showed the user@host prefix in full
  // while cutting off the one part that's actually useful once you're
  // not sitting at bare "~", the path itself. Stripping a detected
  // "user@host:" prefix outright (not just re-eliding differently)
  // fixes this without touching any OTHER window's own title format
  // (a browser tab, an editor's own title) at all -- the regex only
  // matches this one specific shape, and .replace() is a no-op on
  // anything that doesn't.
  readonly property string compactWindowTitle: root.activeWindowTitle.replace(/^[^\s@]+@[^\s:]+:/, "")
  // title/artist/album/artUrl/hasMedia are now plain properties set by
  // applyMediaState() above (fed by ruixen.media's own state file) --
  // the zombie-MPRIS-registration gate that used to live on artUrl's
  // own binding here (a closed app can leave a stale mpris:artUrl with
  // no title/artist behind) moved into ruixen.media/Service.qml's own
  // statusJson() instead (see its own comment), so every consumer of
  // that status gets the same protection, not just this file.

  // Never leave a blank "no media" state -- fall back to something
  // always available instead. A compositor-window-title fallback would
  // read nicer, but that's ruixen.bar's own ActiveWindow territory,
  // unrelated to this plugin, so this falls back straight to
  // user@host for now.
  readonly property string userHost: Quickshell.env("USER") + "@" + Quickshell.env("HOSTNAME")
  readonly property string displayedTitle: hasMedia
    ? (artist ? artist + " - " + title : title)
    : userHost

  // ~/.local/state/omarchy/current/background is a symlink Omarchy
  // repoints at the real wallpaper file on every theme/wallpaper change
  // -- the symlink PATH itself never changes, only what it points to.
  // Both playerPill (below) and DashboardContent.qml's own playerCard
  // used to use that path directly as their idle-background Image
  // source: Qt never saw a different URL string, so it never re-fetched
  // after the first load -- direct report ("its been stalled... when i
  // switch theme or wallpaper, its not updating that"). Omarchy's own
  // background plugin (shell/plugins/background/Background.qml) avoids
  // this by resolving the symlink with `readlink -f` and using THAT
  // (genuinely different each time) as the source; same fix here, polled
  // rather than IPC-driven since there's no shared channel to this
  // plugin for "the wallpaper changed" the way that plugin gets one.
  property string resolvedWallpaperPath: ""

  function refreshWallpaperPath() {
    if (!wallpaperReadlinkProc.running) wallpaperReadlinkProc.running = true
  }

  Component.onCompleted: refreshWallpaperPath()

  Timer {
    interval: 5000
    running: true
    repeat: true
    onTriggered: root.refreshWallpaperPath()
  }

  Process {
    id: wallpaperReadlinkProc
    command: ["readlink", "-f", Quickshell.env("HOME") + "/.local/state/omarchy/current/background"]
    stdout: StdioCollector {
      onStreamFinished: {
        var resolved = String(text || "").trim()
        if (resolved) root.resolvedWallpaperPath = resolved
      }
    }
  }

  // trackPosition/trackLength are now plain properties set by
  // applyMediaState() (see the media-state block above) instead of being
  // read live off activePlayer -- ruixen.media/Service.qml refreshes the
  // state file on a matching ~500ms cadence while playing (see its own
  // comment), and this file's own FileView (watchChanges: true) reloads
  // on every write, so position updates arrive the same way they always
  // did, just pushed via the file instead of polled off a live object.
  // No separate syncPosition()/Timer needed here any more.
  property real trackPosition: 0
  property real trackLength: 0
  readonly property real progressRatio: trackLength > 0 ? Math.min(1, trackPosition / trackLength) : 0

  function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(value / 60)
    var rest = value % 60
    return minutes + ":" + String(rest).padStart(2, "0")
  }

  // Quarter-circle silhouette, one corner at a time -- used as mask
  // material for the concave flanks. Same data-driven shape as
  // ruixen.bar/Bar.qml's own RoundCorner (see its comment for the
  // geometry explanation) -- a quarter-circle arc of radius
  // `cornerSize`, centered on the box's diagonally opposite corner,
  // closed off by a line back to this wedge's own sharp corner. Keyed
  // by an int here (0 TopLeft, 1 TopRight, 2 BottomLeft, 3
  // BottomRight) instead of a string, matching how this copy's own
  // callers already pass `corner` as a plain int.
  component RoundCorner: Item {
    id: rc
    property int corner: 0
    property int cornerSize: 20
    property color fillColor: "#ffffff"

    implicitWidth: cornerSize
    implicitHeight: cornerSize

    onFillColorChanged: canvas.requestPaint()
    onCornerChanged: canvas.requestPaint()
    onCornerSizeChanged: canvas.requestPaint()
    onVisibleChanged: if (visible) canvas.requestPaint()

    readonly property var cornerGeometry: ([
      { centerX: 1, centerY: 1, startAngle: Math.PI, endAngle: 1.5 * Math.PI, pointX: 0, pointY: 0 },
      { centerX: 0, centerY: 1, startAngle: 1.5 * Math.PI, endAngle: 2 * Math.PI, pointX: 1, pointY: 0 },
      { centerX: 1, centerY: 0, startAngle: 0.5 * Math.PI, endAngle: Math.PI, pointX: 0, pointY: 1 },
      { centerX: 0, centerY: 0, startAngle: 0, endAngle: 0.5 * Math.PI, pointX: 1, pointY: 1 }
    ])

    Canvas {
      id: canvas
      anchors.fill: parent
      antialiasing: true
      onPaint: {
        var ctx = getContext("2d")
        var size = rc.cornerSize
        var g = rc.cornerGeometry[rc.corner]
        ctx.clearRect(0, 0, width, height)
        if (!g) return

        ctx.beginPath()
        ctx.arc(g.centerX * size, g.centerY * size, size, g.startAngle, g.endAngle)
        ctx.lineTo(g.pointX * size, g.pointY * size)
        ctx.closePath()
        ctx.fillStyle = rc.fillColor
        ctx.fill()
      }
    }
  }

  // A continuous sine-wave line, in the spirit of Material 3
  // Expressive's own wavy active-indicator pattern (amplitude +
  // wavelength describing the wave, animated by a looping phase
  // offset) -- written independently against that public design
  // language rather than ported from any one project's own
  // implementation. Parametrized directly in physical terms
  // (wavelengthPx: the px distance between crests) instead of a raw
  // cycle count relative to some separately-tracked reference length,
  // which also removes the need for a second "what is this frequency
  // relative to" property entirely -- the wave's spatial density no
  // longer depends on the canvas's own current width at all, so it
  // stays visually consistent even while that width is animating (see
  // the caller below, where the visible portion shrinks/grows as
  // playback progresses).
  //
  // Phase advances from an accumulated elapsed-time counter
  // (FrameAnimation's own per-frame frameTime, in seconds) rather than
  // dividing a raw Date.now() timestamp -- avoids the wave's motion
  // silently losing precision from an ever-growing epoch value over a
  // long-running session, and reads as "speed in radians/second"
  // directly instead of an opaque magic divisor.
  component WavyLine: Canvas {
    id: wave
    property color lineColor: "#ffffff"
    property real lineWidth: 2
    property real wavelengthPx: 24
    property real amplitudeRatio: 0.5
    property bool running: true
    // Radians/second -- 2.5 matches the undulation speed the previous
    // Date.now()/400 divisor gave (1000ms / 400 = 2.5 rad/s).
    property real phaseSpeed: 2.5

    readonly property bool shouldAnimate: running && visible && width > 0 && opacity > 0
    property real phase: 0

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (width <= 0 || height <= 0 || wave.wavelengthPx <= 0) return

      var amplitude = wave.lineWidth * wave.amplitudeRatio
      var angularStep = (2 * Math.PI) / wave.wavelengthPx
      var centerY = height / 2
      var halfStroke = wave.lineWidth / 2

      ctx.strokeStyle = wave.lineColor
      ctx.lineWidth = wave.lineWidth
      ctx.lineCap = "round"
      ctx.beginPath()

      var drawnFirstPoint = false
      for (var x = halfStroke; x <= wave.width - halfStroke; x += 1) {
        var y = centerY + amplitude * Math.sin(angularStep * x + wave.phase)
        if (!drawnFirstPoint) {
          ctx.moveTo(x, y)
          drawnFirstPoint = true
        } else {
          ctx.lineTo(x, y)
        }
      }
      ctx.stroke()
    }

    FrameAnimation {
      running: wave.shouldAnimate
      onTriggered: {
        wave.phase += wave.phaseSpeed * frameTime
        wave.requestPaint()
      }
    }
  }

  // Small circular user avatar, same ~/.face.icon convention as
  // UserInfo.qml. Falls back to a plain dark circle if the file doesn't
  // exist -- Image just shows nothing, the Rectangle behind it still
  // reads as an avatar-shaped placeholder.
  component UserAvatar: Item {
    id: avatar
    property int avatarSize: 20

    implicitWidth: avatarSize
    implicitHeight: avatarSize

    // Placeholder shown until/unless ~/.face.icon exists -- a gradient
    // square (see its own no-radius comment below) instead of a shipped
    // PNG asset, so there's no fixed resolution/ratio to pick and it
    // scales cleanly at any avatarSize. Explicitly hidden once a real
    // image is loaded, not just painted over by an assumed-opaque one
    // -- direct follow-up ("why do we need to keep showing the
    // fallback gradient, why cant gradient just be something on and
    // then off between dicebear... why do we need both to appear and
    // overlap"): the two layers overlapping regardless of load state
    // is exactly what let any imperfection show up as the gradient
    // visibly bleeding through, real bug hit live and fixed twice
    // before landing here. With this, the gradient is structurally
    // absent whenever a real avatar is showing.
    Rectangle {
      anchors.fill: parent
      // Circular, unlike the real DiceBear avatars this sits behind
      // (deliberately plain square now, see selectAvatar's own
      // comment) -- direct follow-up ("keep it for the gradient
      // though, the gradient default we load in is square now... why
      // not just make the gradient a circle"). Never shown at the same
      // time as a real avatar (visible below is gated on the image
      // NOT being ready), so the two shapes never need to match.
      radius: width / 2
      visible: avatarImage.status !== Image.Ready
      // Theme-aware, not two hardcoded colors -- direct follow-up
      // ("install you get the fallback or default gradient, maybe
      // theme aware?"). root.accent is already Color.accent (see its
      // own declaration above), so this now follows the active
      // Omarchy theme instead of a fixed indigo/violet pair.
      gradient: Gradient {
        GradientStop { position: 0.0; color: Qt.lighter(root.accent, 1.6) }
        GradientStop { position: 1.0; color: Qt.darker(root.accent, 1.4) }
      }
    }

    // No circular treatment -- direct follow-up chain: first "why do
    // we still hard cap a circle around it, doesnt dicebear take care
    // of it" (tried DiceBear's own radius=50 param, which scales each
    // style's content to fit a circle instead of the old MultiEffect
    // mask's blind crop), then, after actually seeing it, "the circle
    // is still there... the circle mask comes back" -- radius=50 still
    // produces a circle, just a better-behaved one, which wasn't the
    // actual ask. Dropped radius=50 too (see ruixen.settings'
    // selectAvatar).
    //
    // Rounded-square clip, not a hard rectangle though -- direct
    // follow-up ("on the site it shows it has like a curved around the
    // edge, its not suppose to be rectangular with hard edge"). That
    // curve is DiceBear's own website preview-card CSS, not part of
    // the fetched image -- confirmed by reading pixelbot's raw SVG
    // directly, rx="0" regardless of style, same as every other style
    // checked so far. So a real mask is what gets that look here, same
    // MultiEffect technique the notch's own shape uses, just a small
    // proportional radius instead of width/2 -- a rounded square, not
    // a circle (the circle stays for the gradient placeholder only,
    // per its own comment above).
    Image {
      id: avatarImage
      anchors.fill: parent
      source: "file://" + Quickshell.env("HOME") + "/.face.icon#" + root.avatarCacheBust
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      cache: false
      visible: false
    }

    Rectangle {
      id: avatarImageMask
      anchors.fill: parent
      radius: width * 0.2
      color: "#ffffff"
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: parent
      source: avatarImage
      maskEnabled: true
      maskSource: avatarImageMask
      maskThresholdMin: 0.5
      maskThresholdMax: 1.0
    }

    // The click target for opening the dashboard now that hover-to-
    // expand is gone -- per direct request. Only ever visible/hit-
    // testable in the collapsed row (its parent Row's own visible:
    // false while expanded already makes this inert then, no extra
    // guard needed). Margins widen the actual hit target past the
    // small 20px visual circle, same -6 pattern used elsewhere in this
    // file for small icons.
    MouseArea {
      anchors.fill: parent
      anchors.margins: -6
      cursorShape: Qt.PointingHandCursor
      onClicked: panel.pinnedOpen = true
    }
  }

  // Thin vertical divider, ported from Separator.qml.
  component NotchSeparator: Rectangle {
    implicitWidth: 3
    implicitHeight: 16
    radius: width / 2
    color: root.textColor
    opacity: 0.1
  }

  // Left-side vertical tab-bar button (Widgets/Wallpapers/Metrics
  // stacked, plus a settings gear pinned at the bottom). Just a plain
  // icon + tonal hover/active background, no external styling
  // dependency, same approach as every other component in this file.
  component TabButton: Rectangle {
    id: tabBtn
    property string glyph: ""
    property bool active: false
    signal activated()

    // 48 -> 56, glyph 18 -> 20 -- per direct request to grow the
    // left/right rail icons together rather than keep chasing a
    // sub-pixel detail on the dial tip.
    Layout.preferredWidth: 56
    Layout.preferredHeight: 56
    Layout.alignment: Qt.AlignHCenter
    radius: 14
    color: active ? Qt.rgba(1, 1, 1, 0.14) : (tabMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.07) : "transparent")
    Behavior on color { ColorAnimation { duration: 120 } }

    Text {
      anchors.centerIn: parent
      text: tabBtn.glyph
      color: tabBtn.active ? root.accent : root.textColor
      font.family: root.fontFamily
      font.pixelSize: 20
    }

    MouseArea {
      id: tabMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tabBtn.activated()
    }
  }

  PanelWindow {
    id: panel
    visible: !root.fullscreenActive && !root.barHidden
    // bottom:true too, not just top/left/right -- the click-away-to-
    // dismiss MouseArea (see below) needs the panel's own surface to
    // actually reach the full screen height for its widened mask to
    // cover anywhere outside the notch. Anchoring both top and bottom
    // makes the surface fill the full height regardless of
    // implicitHeight; exclusionMode stays Ignore so this never reserves
    // screen space the way ruixen.bar's own window does.
    anchors { top: true; left: true; right: true; bottom: true }
    // ruixen.bar's own notchCollapsedBottomEdge constant manually mirrors
    // this value (ruixen-shell issue #41/#38) -- change this, change that
    // one too.
    margins.top: 4
    implicitHeight: 220
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "ruixen-notch"
    // REVERTED back to Overlay -- the Overlay -> Top change (made to
    // auto-hide over fullscreen windows) broke click-to-expand: this
    // namespace's own layer surface geometry spans nearly the full
    // screen (see `hyprctl layers`), overlapping omarchy-bar's own
    // surface, which is ALSO on `top`. Two same-layer surfaces with
    // overlapping geometry have compositor-decided (not
    // deterministic-to-us) stacking order for pointer hit-testing --
    // omarchy-bar apparently won that contest, eating clicks meant for
    // the notch pill before they ever reached this surface. Overlay is
    // strictly above every other layer including top, so there's no
    // same-layer contention -- confirmed working again after this
    // revert. Fullscreen-hide needs a different mechanism (real
    // fullscreen-state watching) that doesn't reuse a layer another
    // always-on surface already occupies.
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // None except while expanded (pinned dashboard or launcher), when it
    // switches to Exclusive (same mode ruixen.settings/Settings.qml and
    // Omarchy's own real Menu.qml use for their modal panels) so Escape
    // can dismiss either view and the launcher's own TextInput can
    // receive typed characters. Collapsed stays None -- passive hover, no
    // reason to grab keyboard input. v1 of the launcher's search box
    // needed this SAME flip, but combined it with a taller notch size,
    // which is what actually broke (see launcherContent's own comment
    // below) -- this flip alone, without the resize, is the untested
    // half of that old combination. Extending it to pinnedOpen too
    // carries the same low risk noted there: no new size involved, just
    // a focus-mode change on an already-proven 900x400 footprint.
    WlrLayershell.keyboardFocus: expanded ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    // Widens to the full panel only while open (pinned or launcher --
    // see expanded below), so a click anywhere outside the notch itself
    // actually reaches this surface (see the click-away MouseArea
    // below) instead of passing straight through to whatever's behind.
    // Collapsed is the only other state now -- hover-to-expand was
    // removed (see expanded below), so there's no longer a third
    // "briefly widened but shouldn't swallow other clicks" case to
    // exclude here.
    mask: Region {
      x: panel.expanded ? 0 : notchOuter.x
      y: panel.expanded ? 0 : notchOuter.y
      width: panel.expanded ? panel.width : notchOuter.width
      height: panel.expanded ? panel.height : notchOuter.height
    }

    // Hover-to-expand removed entirely, per direct request -- clicking
    // the avatar (see UserAvatar's own MouseArea) is now the only way
    // to open the dashboard, dismissing by clicking away (below).
    // Deliberate over accidental: hovering near the top of the screen
    // for an unrelated reason (dragging a window, reaching for
    // something else at the top edge) no longer pops the notch open.
    // This also removes the hoverExitTimer debounce hack that hover
    // needed (see the old git history if that's ever wanted back) --
    // a real click has no equivalent "did I actually mean to leave"
    // ambiguity a hover does.
    property bool pinnedOpen: false
    // Launcher mode grabs focus itself (its own TextInput needs it to
    // receive typed characters -- see launcherContent's onVisibleChanged
    // below). pinnedOpen has no such input by default, so it needs an
    // explicit focus target of its own for Escape to have anything to
    // bubble up from -- WlrKeyboardFocus.Exclusive alone only grants the
    // *surface* keyboard focus at the Wayland level, not Qt Quick's own
    // scene-level activeFocus (same lesson learned building the
    // launcher's search box). notchOuter is the shared ancestor of every
    // dashboard tab's content, so giving it focus here means Escape
    // closes the panel by default, and if the user then clicks into
    // WallpapersContent's own search box, focus moves there like normal
    // -- Escape typed there has nothing to handle it locally and bubbles
    // back up to notchOuter's own Keys.onPressed (see below), so it
    // keeps working either way without WallpapersContent.qml needing any
    // changes of its own.
    onPinnedOpenChanged: if (pinnedOpen) Qt.callLater(function() { notchOuter.forceActiveFocus() })
    // Third mode, alongside collapsed/media -- quick app launcher (a
    // few favorite icons), triggered by ruixen.applauncher's own bar
    // icon over IPC (see IpcHandler below), not by clicking the avatar
    // like pinnedOpen.
    property bool launcherOpen: false
    // Only two ways to be open now (pinned or launcher), both from a
    // real click -- used directly for the widened click-away mask too
    // (see above), no separate "clickedOpen" needed anymore now that
    // there's no passing-hover state to exclude from it.
    readonly property bool expanded: pinnedOpen || launcherOpen

    // Which dashboard tab is showing (media/media hover/pin state only --
    // launcher mode is unrelated). 0 Widgets (DashboardContent, the real
    // port), 1 Wallpapers, 2 Metrics -- the latter two are stub panes for
    // now, shell only, per direct request to build the tab switcher
    // before the actual pages.
    property int dashboardTab: 0

    IpcHandler {
      target: "ruixen.notch"
      function openLauncher(): void { panel.launcherOpen = true }
      function closeLauncher(): void { panel.launcherOpen = false }
      function toggleLauncher(): void { panel.launcherOpen = !panel.launcherOpen }
      // Real, permanent counterparts for the dashboard itself (not the
      // launcher) -- direct Discord ask ("a keybind to summon the
      // notch"), same shape as the launcher trio above.
      //
      // Always resets to the Widgets tab (0) -- direct follow-up after
      // a live report that Super+K (openDashboardTab kanban) followed
      // by Super+N (toggleDashboard) "stays in kanban": the two keys
      // are meant to do different jobs (K jumps straight to Kanban,
      // N opens/closes the dashboard itself) but originally shared
      // dashboardTab's own "wherever you left it" state, so N looked
      // like it did nothing right after K. Deliberately NOT touching
      // the plain click-to-expand interaction elsewhere in this file
      // (onClicked: panel.pinnedOpen = true) or openDashboardTab below
      // -- clicking the notch itself still opens on whatever tab was
      // last selected, and a keybind can still jump straight to any
      // specific tab; only these two IPC entry points force Widgets.
      function openDashboard(): void {
        panel.dashboardTab = 0
        panel.pinnedOpen = true
      }
      function closeDashboard(): void { panel.pinnedOpen = false }
      function toggleDashboard(): void {
        if (!panel.pinnedOpen) panel.dashboardTab = 0
        panel.pinnedOpen = !panel.pinnedOpen
      }
      // Jump straight to one tab -- direct follow-up ("a keybind that
      // opens to the kanban board... to see updates"). A separate
      // function with a required plain-string arg, not an optional
      // JSON payload bolted onto openDashboard above: Quickshell's
      // IpcHandler enforces exact arity against the declared typed
      // signature (confirmed live -- "Too few arguments provided (1
      // required but 0 were provided)" the moment openDashboard grew a
      // required param), so a single shared function would have broken
      // every existing zero-arg `openDashboard` call instead of
      // actually being optional. Valid tab values: "widgets" (0),
      // "wallpapers" (1), "metrics" (2), "kanban" (3) -- matching
      // dashboardTab's own fixed index order, left/right tab bar top
      // to bottom. An unrecognized name is a no-op on the tab (still
      // opens on whichever tab was already selected).
      function openDashboardTab(tab: string): void {
        var tabNames = ["widgets", "wallpapers", "metrics", "kanban"]
        var index = tabNames.indexOf(tab)
        if (index >= 0) panel.dashboardTab = index
        panel.pinnedOpen = true
      }
      // Called by ruixen.settings' General page after Shuffle/Reset
      // writes or removes ~/.face.icon -- this plugin is keepLoaded:
      // true, so nothing else would tell UserAvatar's Image to re-read
      // the file.
      function refreshAvatar(): void { root.avatarCacheBust = root.avatarCacheBust + 1 }

      // Kanban tab (4th dashboard tab) -- direct request, agent-native
      // by design: these are the SAME functions KanbanContent.qml's
      // own UI calls on kanbanService directly, exposed here too so
      // the board can be driven entirely from the CLI, e.g.
      // `omarchy-shell ruixen.notch kanbanAddCard "Fix bug" todo`.
      // Column ids are always exactly "todo"/"in-progress"/"done" --
      // see KanbanModel.js's own header for why the count is fixed.
      // priority is "high"/"medium"/"low" (defaults to "medium" if
      // omitted or unrecognized) -- direct request ("take care of the
      // priority via the api, this shit will be agent run mostly"): no
      // manual UI to set it, CLI/agent-only, same as add/rename.
      function kanbanAddCard(title: string, columnId: string, priority: string): string {
        return kanbanService.addCard(title, columnId, priority)
      }
      function kanbanMoveCard(cardId: string, columnId: string): void {
        kanbanService.moveCard(cardId, columnId)
      }
      function kanbanAdvanceCard(cardId: string): void { kanbanService.advanceCard(cardId) }
      function kanbanRegressCard(cardId: string): void { kanbanService.regressCard(cardId) }
      function kanbanRemoveCard(cardId: string): void { kanbanService.removeCard(cardId) }
      function kanbanRenameColumn(columnId: string, label: string): void {
        kanbanService.renameColumn(columnId, label)
      }
      function kanbanSetPriority(cardId: string, priority: string): void {
        kanbanService.setPriority(cardId, priority)
      }
      // No-op on a blank title -- see KanbanModel.renameCard's own
      // comment. Fixes a real gap: a card's title was write-once at
      // creation before this, no way to fix a typo or reword it after.
      function kanbanRenameCard(cardId: string, title: string): void {
        kanbanService.renameCard(cardId, title)
      }
      // date is meant to be typed by hand -- "2026-09-12",
      // "2026-09-12T18:00", or anything else Date.parse() recognizes
      // -- not a raw epoch number computed by the caller. An empty
      // string explicitly clears the due date; anything else that
      // fails to parse is a no-op rather than also clearing it, so a
      // typo cannot silently wipe a real deadline that was already set.
      function kanbanSetDueDate(cardId: string, date: string): void {
        var text = String(date || "").trim()
        if (text === "") {
          kanbanService.setDueDate(cardId, 0)
          return
        }
        var parsed = Date.parse(text)
        if (!isNaN(parsed)) kanbanService.setDueDate(cardId, parsed)
      }
      // One free-text label per card, not a multi-tag array -- see
      // KanbanModel.js's own comment for why. An empty string clears
      // it; a real one is capped (KanbanModel.clampLabel) for a fixed-
      // width card row, not rejected -- an overlong label is just
      // trimmed, never an error.
      function kanbanSetLabel(cardId: string, label: string): void {
        kanbanService.setLabel(cardId, label)
      }
      // A short second line under the title, always shown as a single
      // elided line in the panel -- direct request: "i wanna see a
      // short title and description... further detail might be better
      // thru the terminal or agent context". There is no fuller notes
      // field anywhere in this board on purpose. An empty string
      // clears it; an overlong one is capped, not rejected.
      function kanbanSetDescription(cardId: string, description: string): void {
        kanbanService.setDescription(cardId, description)
      }
      // Returns the whole board as JSON ({columns, cards}) -- how a
      // script (or me, driving the board on your behalf) reads it back
      // without any QML access at all.
      function kanbanListCards(): string { return kanbanService.listCards() }
    }

    // Fire-once, not auto-running -- triggered by the tab bar's bottom
    // button (see expandedContent below). Opens Omarchy's own real main
    // menu -- the exact same command Super+Space itself runs (confirmed
    // in ~/.config/hypr/bindings/utilities.lua: `o.bind("SUPER + SPACE",
    // "Omarchy menu", "omarchy-menu toggle")`) -- rather than jumping
    // straight to the settings submenu or reimplementing a menu here.
    Process {
      id: mainMenuProc
      command: ["omarchy-menu", "toggle"]
      running: false
    }

    // Click-away-to-dismiss -- covers the whole (now-widened) mask
    // while deliberately clicked open (pinned dashboard or launcher).
    // Declared before notchOuter on purpose: later siblings win
    // hit-testing in QML, so notchOuter's own content (tab buttons,
    // icon cards, the hover/pin MouseArea) still gets first crack at any
    // click within its own bounds; this only ever catches clicks that
    // land outside the notch shape entirely. Resets both flags rather
    // than picking one -- only one is ever true at a time in practice,
    // but clearing both is simpler than tracking which.
    MouseArea {
      anchors.fill: parent
      // Was panel.clickedOpen, a property that never existed on panel --
      // enabled evaluated to undefined (silently falsy), so click-away
      // never actually worked despite the comment above describing it as
      // live. Real fix: the same expanded flag everything else already
      // uses.
      enabled: panel.expanded
      onClicked: { panel.pinnedOpen = false; panel.launcherOpen = false }
    }

    Item {
      id: notchOuter
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top

      // Escape closes the expanded dashboard, same as the launcher's own
      // search box already does. Placed here (not on some deeper child)
      // so it catches Escape by default (see onPinnedOpenChanged's
      // forceActiveFocus above) and still catches it if focus later
      // moves to a child that doesn't handle Escape itself, since
      // unhandled key events bubble up the visual parent chain.
      //
      // Tab rotates the three real dashboard panels -- Widgets ->
      // Wallpapers -> Metrics -> back to Widgets, same as clicking each
      // TabButton in turn. The bottom button deliberately isn't part of
      // this cycle: it's a one-shot action (mainMenuProc, opens
      // Omarchy's real main menu), not a view, and landing on it via Tab
      // either fired it immediately (one direct report: "giving me a
      // jump scare") or needed a whole separate selected-vs-activated
      // state to avoid that -- simpler to just leave it mouse-only.
      // Guarded to pinnedOpen only so this never fights the launcher's
      // own Tab handler (launcherOpen's Tab is fully consumed inside
      // launcherContent before it could bubble here anyway, but the
      // guard makes the split explicit rather than relying on that).
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape && panel.expanded) {
          panel.pinnedOpen = false
          panel.launcherOpen = false
          event.accepted = true
        } else if (event.key === Qt.Key_Tab && panel.pinnedOpen && !panel.launcherOpen) {
          panel.dashboardTab = (panel.dashboardTab + 1) % 4
          event.accepted = true
        }
      }
      // Notch corner geometry derived from this machine's own window
      // rounding (Hyprland rounding=24), not a flat guess:
      // cornerSize=roundness+4, collapsed radius=roundness+4, expanded
      // radius=roundness+20 -- cornerSize=28, collapsed radius=28 (see centerMask
      // below), expanded radius=44.
      //
      // Manually mirrored in ruixen.bar's own notchReservedWidth constant
      // (#28, ruixen.bar's own reserved-space calculation; #41/#38 for
      // why it's a plain constant there rather than a live read) --
      // change this value, change that one too.
      readonly property int cornerSize: 28
      // Collapsed width trimmed down from an initial 290 -- this row's
      // actual content (avatar + divider + play glyph/wave + divider +
      // bell) is narrower than that, so 290 left a big empty gap
      // between the avatar/bell and the notch's own curved edges. First
      // attempt went to 240, but collapsedContent's real parent is a
      // clip:true Item sized to exactly bodyWidth (see below) --
      // content measures ~236-240px wide (avatar 20 + 2 dividers +
      // wave-track 140 + play glyph + bell + Row spacing), landing
      // right at that clip edge and cutting the bell off. 260 gives
      // real margin instead of a knife's-edge fit. Expanded width (420)
      // still fits this notch's own expanded content comfortably.
      // Media hover/pin tries a real dashboard-sized target (implicitWidth
      // 900, implicitHeight 56+48*6 = 344) instead of reusing the
      // smaller 420x190 -- untested territory for this notch (only 44
      // and 190 are proven safe against the masking bug below), so
      // watch for the same flat-bottom-corner symptom if this doesn't
      // pan out.
      //
      // launcherOpen deliberately does NOT follow this -- it keeps its
      // own separate 420x190 branch, proven safe, since an earlier
      // attempt at a new size for launcher specifically (340x260, then
      // up to 360) hit that exact masking bug. Decoupled from
      // pinnedOpen here so a size change on one never risks the other.
      //
      // Collapsed 260 -> 284: the playerPill (see collapsedContent
      // below) added its own ~20px of internal padding around the play
      // glyph/wave that the old bare Row didn't have, pushing content
      // back out to ~260px total -- the exact knife's-edge fit 260 was
      // originally chosen to avoid. Per direct report ("avatar circle
      // and bell icon is too close to the notch edge now"), bumped by
      // roughly that same ~20-24px to restore real margin on both
      // sides again.
      //
      // The collapsed case (284, both launcherOpen/pinnedOpen false) is
      // manually mirrored in ruixen.bar's own notchReservedWidth constant
      // (#28, #41/#38) -- change this default, change that one too. The
      // 420/900 expanded cases are deliberately NOT reflected there:
      // ruixen.bar only ever needs to reserve space for the Notch's
      // always-present collapsed footprint, not its temporary expanded
      // states.
      readonly property int bodyWidth: panel.launcherOpen ? 420 : (panel.pinnedOpen ? 900 : 284)
      width: bodyWidth + cornerSize * 2
      // 44px collapsed -- ruixen-bar's own reserved screen zone
      // (notchClearance) was bumped to cover this plus a buffer, so it
      // no longer overlaps tiled windows the way it did when this was
      // smaller but the reserved zone was still just barSize-sized.
      // Dashboard height bumped past the initial 344 to 400 per direct
      // feedback ("a bit too short") -- past the
      // previously-tested-safe value, so stress-tested 3x (open/close
      // cycles, checking the bottom-corner mask each time) before
      // keeping it. Collapsed case (44) manually mirrored in ruixen.bar's
      // own notchCollapsedBottomEdge constant (#41/#38) -- change this
      // value, change that one too.
      height: panel.launcherOpen ? 190 : (panel.pinnedOpen ? 400 : 44)

      Behavior on width { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
      Behavior on height { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }

      // Painted background, masked into the notch silhouette below.
      Rectangle {
        id: notchBg
        anchors.fill: parent
        color: root.notchColor

        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
          maskEnabled: true
          maskSource: notchMask
          maskThresholdMin: 0.5
          maskThresholdMax: 1.0
          maskSpreadAtMin: 1.0
        }

        // Tried, reverted: adding shadowEnabled/shadowColor/shadowBlur/
        // etc. to this same MultiEffect instance ("start with notch
        // then", trying the settings card's own shadow effect here
        // too). Direct live report at the pinned/dashboard size (900x400):
        // "the shape is completely broken, it has almost square edges
        // now, the curves are gone" -- this is exactly the documented,
        // non-deterministic masking bug this same effect has hit
        // before (see this file's own launcher-history comments),
        // reproduced live, not just a theoretical risk. Confirmed at
        // the collapsed and launcher (420x190) sizes without visible
        // breakage first, but the bug didn't show until the larger
        // pinned size -- matches its own documented non-determinism,
        // not a case of skipping the stress test. Reverted immediately
        // per this file's own standing rule: "if the masking bug
        // reproduces despite the size-avoidance, stop and report it
        // rather than pushing through." Do not re-add shadow
        // properties to this MultiEffect instance without solving the
        // underlying masking fragility first -- a real fix, not
        // another attempt at the same combination.

        // No blurred album-art here anymore -- was previously applied
        // across the WHOLE collapsed notch (matching CompactPlayer.qml's
        // backgroundArt treatment), but per direct feedback that "doesn't
        // look too nice on some theme[s]", the notch itself now stays
        // plain OLED black at all times. The art moved into its own
        // small pill instead, scoped to just the play/pause + wave
        // progress area below (see playerPill) -- avatar, dividers, and
        // bell all still sit directly on this same flat black.
      }

      // Mask silhouette: left flank (concave toward center) + center
      // block (square top, animated round bottom) + right flank
      // (concave toward center). Never drawn directly -- only sampled
      // as texture by notchBg's layer.effect above.
      Item {
        id: notchMask
        visible: false
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true

        RoundCorner {
          id: leftFlank
          anchors.top: parent.top
          anchors.left: parent.left
          cornerSize: notchOuter.cornerSize
          corner: 1
          fillColor: "#ffffff"
        }

        Rectangle {
          id: centerMask
          anchors.top: parent.top
          anchors.left: leftFlank.right
          anchors.right: rightFlank.left
          height: parent.height
          color: "#ffffff"
          topLeftRadius: 0
          topRightRadius: 0
          bottomLeftRadius: panel.expanded ? 44 : 28
          bottomRightRadius: panel.expanded ? 44 : 28

          Behavior on bottomLeftRadius { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
          Behavior on bottomRightRadius { NumberAnimation { duration: 230; easing.type: Easing.OutCubic } }
        }

        RoundCorner {
          id: rightFlank
          anchors.top: parent.top
          anchors.right: parent.right
          cornerSize: notchOuter.cornerSize
          corner: 0
          fillColor: "#ffffff"
        }
      }

      // No general-purpose background MouseArea here anymore -- opening
      // is now only via clicking the avatar (see UserAvatar's own
      // MouseArea below), closing only via clicking away (the mask
      // MouseArea above). Individual interactive elements in the
      // collapsed row (avatar, play/pause, bell) each own their exact
      // click target instead of one catch-all area behind everything.

      Item {
        anchors.fill: parent
        anchors.leftMargin: notchOuter.cornerSize
        anchors.rightMargin: notchOuter.cornerSize
        clip: true

        // Collapsed: avatar | divider | play glyph + small wave | divider | bell.
        // Matches DefaultView.qml's mainRow layout.
        Row {
          id: collapsedContent
          // expanded already folds in launcherOpen (see panel.expanded),
          // so !expanded alone correctly excludes launcher mode too.
          visible: !panel.expanded
          opacity: panel.expanded ? 0 : 1
          anchors.centerIn: parent
          // The frame visually eats the top ~6px (it merges into the
          // frame's own border there), so centering in the notch's full
          // height reads as shifted too high relative to the actually
          // visible space below that. Nudge down to compensate.
          anchors.verticalCenterOffset: 2
          spacing: 8
          Behavior on opacity { NumberAnimation { duration: 140 } }

          UserAvatar { anchors.verticalCenter: parent.verticalCenter }
          NotchSeparator { anchors.verticalCenter: parent.verticalCenter }

          // Art pill -- the ONLY place blurred album art shows in the
          // collapsed notch now (see notchBg above for why). Wraps just
          // the play/pause glyph + wave progress, per direct scoping
          // request ("leave the bell and avatar and separator bar
          // outside the pill as is"). ClippingRectangle, not a plain
          // Rectangle -- same documented gotcha as playerCard/the art
          // disc in DashboardContent.qml: plain Rectangle.clip only
          // clips to the bounding BOX, ignores radius.
          ClippingRectangle {
            id: playerPill
            anchors.verticalCenter: parent.verticalCenter
            width: pillRow.implicitWidth + pillPadding * 2
            height: 28
            radius: height / 2
            color: Color.background

            readonly property int pillPadding: 10
            // root.resolvedWallpaperPath (see its own comment) rather
            // than the symlink path directly -- see that comment for why.
            readonly property string wallpaperPath: root.resolvedWallpaperPath !== ""
              ? "file://" + root.resolvedWallpaperPath
              : "file://" + Quickshell.env("HOME") + "/.local/state/omarchy/current/background"
            readonly property string pillBgSource: root.artUrl !== "" ? root.artUrl : wallpaperPath

            Image {
              id: pillBgArt
              anchors.fill: parent
              source: playerPill.pillBgSource
              sourceSize: Qt.size(64, 64)
              fillMode: Image.PreserveAspectCrop
              asynchronous: true
              visible: false
            }

            MultiEffect {
              anchors.fill: parent
              source: pillBgArt
              blurEnabled: true
              blurMax: 32
              blur: 1.0
              opacity: 0.28
            }

            // Dark scrim on top of the blur so the glyph/wave/playhead
            // stay readable regardless of how bright the underlying art
            // is -- same reasoning as notchBg's own flat base color.
            Rectangle {
              anchors.fill: parent
              color: Qt.rgba(0, 0, 0, 0.35)
            }

            Row {
              id: pillRow
              anchors.centerIn: parent
              spacing: 6

              Text {
                id: collapsedPlayGlyph
                anchors.verticalCenter: parent.verticalCenter
                // Direct follow-up: "we dont need the inactive play
                // button to show then" -- showing a play/pause glyph
                // next to the active-window title (not a track) never
                // made sense once that title took over this slot.
                visible: root.hasMedia
                text: root.playIcon
                color: root.textColor
                font.family: root.fontFamily
                // Matches the bar's own icon standard (18px) -- was 11,
                // visibly undersized next to the 20px avatar in this
                // same row.
                font.pixelSize: 18

                // Own click target, same pattern as the avatar/bell now
                // that there's no big background MouseArea to compete
                // with -- each interactive element in this row owns its
                // exact hit area independently.
                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -6
                  enabled: root.hasMedia
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.sendMediaAction("playPause")
                }
              }

              // Track (full length, dim) + wave (played portion only, up
              // to progressRatio) -- actually reflects position now,
              // instead of a decorative full-width wave. No drag-to-seek
              // yet, position display only.
              Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 140
                // Direct follow-up: "when theres no music it just shows
                // active window? that might be kinda cool" -- this whole
                // wave/track/playhead group is the "there is media"
                // half; ActiveWindowLabel (below, same 140x20 slot) is
                // the "there is not" half. Same fixed slot either way so
                // the pill's own width never jumps between the two.
                visible: root.hasMedia
              // Grown 12 -> 20 alongside the thickness bump below --
              // WavyLine is a Canvas, and Canvas content outside its
              // own item bounds is simply never drawn (an implicit
              // clip, not a real mask, but reads the same). At
              // lineWidth 4 / amplitudeMultiplier 1.4 the wave's peak
              // extent is +-(amp + lineWidth/2) = +-7.6px from center,
              // needing >=15.2px of height -- the old 12px container
              // was already too short for that, clipping the top/
              // bottom of the wave's crests and troughs.
              height: 20

              // Split point -- where the wave's played portion meets
              // the dim unplayed track, before any gap trim.
              readonly property real splitX: width * root.progressRatio
              // Same gap-around-the-tip design as the player ring/
              // dials/brightness bar, ported here too now that it's
              // right on the other components -- per direct request
              // ("bring the design there too"). Computed the same
              // width-aware way that fixed the player ring's real bug
              // (a flat copied constant doesn't clear a custom-sized
              // tip): half the wave's own line width + half the
              // playhead's own width + the desired real clearance.
              // wave lineWidth 4 (half 2) + playhead width 4 (half 2)
              // + 2px desired = 6px, applied as the FULL trim on EACH
              // side independently (not split further) -- matches how
              // the ring's own gapPx already works, not a fresh guess.
              readonly property real gapPx: 6

              // Track/wave/playhead thickened 2px -> 4px together, then
              // wave/playhead alone toned back to 3 (read too thick next
              // to the track). Direct follow-up while music was actually
              // playing: "the wave thickness... kinda too thin now" --
              // back to 4, matching the track again.
              Rectangle {
                // Unplayed remainder, trimmed short of the playhead by
                // gapPx on this side -- starts past the split point,
                // not right at it.
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: Math.max(0, parent.width - parent.splitX - parent.gapPx)
                height: 4
                radius: 2
                color: Qt.rgba(1, 1, 1, 0.15)
              }

              WavyLine {
                // Trimmed short of the playhead by gapPx on this side
                // too -- the wave's own Canvas bounding width directly
                // controls where its rightmost point sits, so shrinking
                // it here is enough on its own, no separate lineCap
                // handling needed (unlike the circular ring's Canvas
                // arc, this is just a smaller bounding box).
                width: Math.max(0, parent.splitX - parent.gapPx)
                height: parent.height
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                lineColor: root.hasMedia ? root.accent : root.muted
                lineWidth: 4
                // 140/6 preserves the same wave density the old
                // frequency: 6 (cycles across a fixed 140px reference)
                // gave -- expressed directly as a physical wavelength
                // now, so it no longer needs that separate reference
                // length property at all.
                wavelengthPx: 140 / 6
                amplitudeRatio: root.isPlaying ? 1.4 : 0.15
                running: root.isPlaying
              }

              // Playhead -- stays centered exactly at the true split
              // point, unchanged -- only the wave/track on either side
              // of it pull back now.
              Rectangle {
                width: 4
                height: parent.height
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.textColor
                x: parent.splitX - width / 2
                visible: root.hasMedia

                Behavior on x { NumberAnimation { duration: 450 } }
              }
              }

              // The "no media" half of this same 140x20 slot -- direct
              // request: "when theres no music it just shows active
              // window". Reads Quickshell.Wayland's own ToplevelManager
              // directly (already imported, already used for
              // fullscreenActive above) rather than depending on the
              // separate omarchy.active-window plugin being installed
              // or pinned at all. Centered + elided, not a marquee --
              // direct follow-up ("is there an effect where it scrolls
              // horizontally, or i guess truncate is fine tbh? center
              // and truncate?") -- simpler, and matches ActiveWindow.qml's
              // own elide: Text.ElideRight treatment of the same title
              // string. "~" is the empty-state fallback for the rare
              // moment nothing is focused at all (just closed
              // everything, say), rather than leaving the pill blank.
              Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 140
                height: 20
                visible: !root.hasMedia
                text: root.compactWindowTitle !== "" ? root.compactWindowTitle : "~"
                // Direct follow-up ("are the text a bit muted") -- this
                // is the primary content of the slot now, not a
                // secondary status readout, so it gets the same full
                // textColor a real track title would use, not muted.
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
              }
            }
          }

          NotchSeparator { anchors.verticalCenter: parent.verticalCenter }

          Text {
            anchors.verticalCenter: parent.verticalCenter
            text: "󰂛"
            // Matches the dashboard's own bell exactly (see
            // DashboardContent.qml's notification header) -- theme
            // accent when notifications are live, the same fixed red
            // when silenced. Was root.muted, per direct request to
            // bring the same theme-color/red treatment here too.
            color: root.dnd ? "#e05252" : root.accent
            font.family: root.fontFamily
            font.pixelSize: 18

            Behavior on color { ColorAnimation { duration: 160 } }

            // Real toggle now, not just a state readout -- per direct
            // request ("the notification toggle right"). Goes through
            // the real "notifications" IPC target (confirmed against
            // the real service's own IpcHandler) rather than
            // ruixen.quickactions' own bar.shell.firstPartyServiceFor()
            // call -- this file has no bar capabilities to make that
            // same call with, see the dnd property comment above.
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: root.sendDndAction("toggleDnd")
            }
          }
        }

        // Expanded: blurred-art thumbnail, title/artist, big wave
        // progress, transport controls.
        // Expanded: dashboard content (player + quick controls/calendar +
        // notifications + volume dials) -- see DashboardContent.qml
        // for the full breakdown. Media data/colors passed through
        // from the same root-level properties the collapsed view
        // already reads.
        Item {
          id: expandedContent
          visible: panel.expanded && !panel.launcherOpen
          opacity: panel.expanded && !panel.launcherOpen ? 1 : 0
          anchors.fill: parent
          anchors.topMargin: 20
          anchors.bottomMargin: 12
          anchors.leftMargin: 12
          anchors.rightMargin: 12
          Behavior on opacity { NumberAnimation { duration: 160 } }

          RowLayout {
            anchors.fill: parent
            // 8px -- tightened from 10, a bit looser than this row's
            // own rhythm otherwise.
            spacing: 8

            // Left vertical tab bar: Widgets/Wallpapers/Metrics stacked
            // icon buttons, settings gear pinned at the bottom via a
            // fillHeight spacer above it. All three are real now (see
            // WallpapersContent.qml/MetricsContent.qml) -- Metrics'
            // own right-side stat tiles are still a stub within that
            // file, see its own comments.
            ColumnLayout {
              Layout.preferredWidth: 78
              Layout.maximumWidth: 78
              Layout.fillHeight: true
              spacing: 8

              // Explicitly sets pinnedOpen: true too, even though it's
              // already true by the time a tab is clickable at all
              // (this whole bar only exists inside the pinned-open
              // dashboard now that hover-to-expand is gone) -- cheap
              // safety net, not load-bearing anymore.
              TabButton {
                glyph: "󰕰"
                active: panel.dashboardTab === 0
                onActivated: { panel.dashboardTab = 0; panel.pinnedOpen = true }
              }
              TabButton {
                glyph: ""
                active: panel.dashboardTab === 1
                onActivated: { panel.dashboardTab = 1; panel.pinnedOpen = true }
              }
              TabButton {
                glyph: ""
                active: panel.dashboardTab === 2
                onActivated: { panel.dashboardTab = 2; panel.pinnedOpen = true }
              }
              TabButton {
                glyph: ""
                active: panel.dashboardTab === 3
                onActivated: { panel.dashboardTab = 3; panel.pinnedOpen = true }
              }

              Item { Layout.fillHeight: true }

              // The one real action in this tab bar -- opens Omarchy's
              // actual main menu (see mainMenuProc above), the same
              // Super+Space menu, not a notch-local settings page. Was
              // "omarchy-menu summon settings" (straight to the Setup
              // submenu) per direct follow-up asking for the real root
              // menu instead. Mouse-only on purpose -- see notchOuter's
              // Keys.onPressed comment for why Tab deliberately skips
              // this one.
              TabButton {
                glyph: ""
                onActivated: mainMenuProc.running = true
              }
            }

            // Right: active tab's content.
            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

              DashboardContent {
                anchors.fill: parent
                visible: panel.dashboardTab === 0
                shell: root.shell
                // This whole tab bar + content area (an ancestor of this
                // item) stays visible: true/opacity-based, not behind a
                // Loader -- DashboardContent is alive for the entire
                // session, not just while the dashboard is open. Needed
                // here so its own nightlight status poll (ruixen-shell
                // issue #43) can gate on the same "only while actually
                // visible" condition brightnessStateProc's own Timer
                // above already uses, instead of polling forever.
                panelExpanded: panel.expanded
                textColor: root.textColor
                muted: root.muted
                accent: root.accent
                fontFamily: root.fontFamily
                sendMediaAction: root.sendMediaAction
                hasMedia: root.hasMedia
                isPlaying: root.isPlaying
                playIcon: root.playIcon
                title: root.title
                artist: root.artist
                album: root.album
                artUrl: root.artUrl
                resolvedWallpaperPath: root.resolvedWallpaperPath
                progressRatio: root.progressRatio
                trackPosition: root.trackPosition
                trackLength: root.trackLength
                userHost: root.userHost
                displayedTitle: root.displayedTitle
                dnd: root.dnd
                sendDndAction: root.sendDndAction
                notificationHistory: notificationHistory
                brightnessPercent: root.brightnessPercent
                brightnessAvailable: root.brightnessAvailable
                setBrightness: root.setBrightness
              }

              WallpapersContent {
                anchors.fill: parent
                visible: panel.dashboardTab === 1
                active: panel.dashboardTab === 1 && panel.expanded
                textColor: root.textColor
                muted: root.muted
                accent: root.accent
                fontFamily: root.fontFamily
              }

              MetricsContent {
                anchors.fill: parent
                visible: panel.dashboardTab === 2
                active: panel.dashboardTab === 2 && panel.expanded
                textColor: root.textColor
                muted: root.muted
                accent: root.accent
                fontFamily: root.fontFamily
                avatarCacheBust: root.avatarCacheBust
              }

              KanbanContent {
                anchors.fill: parent
                visible: panel.dashboardTab === 3
                textColor: root.textColor
                muted: root.muted
                accent: root.accent
                fontFamily: root.fontFamily
                kanbanService: kanbanService
              }
            }
          }
        }

        LauncherContent {
          overlayRoot: root
          panel: panel
          appLibrary: appLibrary
        }
      }
    }
  }
}
