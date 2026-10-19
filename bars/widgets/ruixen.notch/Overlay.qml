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
  // bar.style="fullbar" is a saved alternate bar skin that intentionally has
  // no notch overlay. Keep this plugin loaded so switching back to "notch"
  // is a config reload, not an install/uninstall operation.
  property bool fullbarStyle: false

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

  readonly property string shellConfigPath: Quickshell.env("HOME") + "/.config/omarchy/shell.json"

  function loadShellConfig(raw) {
    try {
      var p = JSON.parse(String(raw || "").trim() || "{}")
      root.fullbarStyle = p && p.bar && p.bar.style === "fullbar"
    } catch (e) {
      root.fullbarStyle = false
    }
  }

  FileView {
    path: root.shellConfigPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadShellConfig(text())
    onLoadFailed: root.loadShellConfig("")
  }

  // Reads the same persisted surface identity as ruixen.bar without
  // reaching into the bar's live QML object. bar-surface.json is the
  // #78 source of truth for the new color/material axes; the older
  // frame-appearance.json remains a compatibility fallback so existing
  // installs do not reset appearance on update.
  //
  // Just "theme" or "black" now -- was a Themed/Custom split with a
  // 3-swatch color picker (OLED Black/Charcoal/White), direct correction
  // after live testing: "some themes uses white like lupine and few
  // other light theme, this would make the notch unusable... remove
  // white from the setting as an option then and just leave Black and
  // Theme." The luminance clamp below stays regardless -- Theme mode on
  // an actually-installed light theme (lupine, catppuccin-latte,
  // flexoki-light all ship with this repo's own theme-overlays) can
  // still resolve to a light Color.background even with the White
  // swatch gone, and this notch's whole color system (accent hues,
  // warning colors, media art tints, icons, not just plain text) assumes
  // a dark background throughout -- making every one of those
  // individually light-background-aware would be a much bigger rework
  // than this feature warrants. Whichever color the frame resolves to,
  // fall back to plain black here specifically whenever that color is
  // too light to safely host this notch's existing content, otherwise
  // use it as-is. The frame itself has nothing painted on it, so it
  // keeps whatever light color Theme mode actually gives it -- this
  // clamp is notch-only.
  //
  // ruixen-shell#89: that clamp is gone. Direct correction, mid-thought,
  // from the person who filed it: this must NOT become "follow whatever
  // the real theme's own light/dark-ness is" -- Black mode has to stay
  // dark even under a light theme, since bar surface color mode is its
  // own independent choice from the real theme. notchColor now just
  // takes resolveSurfaceColor()'s own answer directly, same as
  // ruixen.bar's own floatingPillSurface -- Black mode already resolves
  // dark (surfaceBlack) before this point, so nothing here needs to
  // ALSO know which mode is active; it only needs to stop overriding a
  // correctly-resolved light Theme-mode color back to black.
  // textColor below is what changed to make this safe: it now picks a
  // readable foreground AGAINST notchColor's own real luminance
  // (readableForegroundForSurface, ported from ruixen.bar's own
  // already-proven version -- same surfaceSafeLightForeground value,
  // #e8e8e8, this file's own old safeForeground already used) instead
  // of judging readability from themeForeground's luminance alone with
  // no idea what background it would land on.
  readonly property color surfaceBlack: "#000000"
  readonly property color surfaceSafeLightForeground: "#e8e8e8"
  readonly property color surfaceSafeDarkForeground: "#101010"
  property string frameColorMode: "black"
  property string notchSurfaceMaterial: "solid"
  property bool frameEnabled: true
  property bool barSurfaceStateLoaded: false
  readonly property color resolvedFrameColor: resolveSurfaceColor(root.frameColorMode)
  readonly property real resolvedFrameColorLuminance: surfaceLuminance(resolvedFrameColor)
  readonly property color notchColor: resolvedFrameColor
  readonly property string barSurfaceStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/bar-surface.json"
  readonly property string frameColorStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/frame-appearance.json"
  readonly property string barIconToneStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/bar-icon-tone.json"
  property string barIconTone: "mono"

  function surfaceLuminance(c) {
    return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
  }

  function normalizeIconTone(tone) {
    return tone === "accent" ? "accent" : "mono"
  }

  function loadBarIconTone(raw) {
    try {
      var p = JSON.parse(String(raw || "").trim() || "{}")
      root.barIconTone = normalizeIconTone(p && p.tone)
    } catch (e) {
      root.barIconTone = "mono"
    }
  }

  FileView {
    id: barIconToneFile
    path: root.barIconToneStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadBarIconTone(text())
    onLoadFailed: root.barIconTone = "mono"
  }

  function normalizeSurfaceColorMode(mode) {
    return mode === "theme" ? "theme" : "black"
  }

  function normalizeSurfaceMaterial(material) {
    return material === "glass" ? "glass" : "solid"
  }

  function resolveSurfaceColor(mode) {
    return mode === "theme" ? Color.background : root.surfaceBlack
  }

  function applyBarSurfaceState(colorMode, material, frameEnabled) {
    root.frameColorMode = normalizeSurfaceColorMode(colorMode)
    // The notch remains Solid-only until the coupled frame/notch glass
    // pass. Still store the normalized material so Settings/state have a
    // compatible contract without accidentally making this surface glass.
    root.notchSurfaceMaterial = normalizeSurfaceMaterial(material)
    root.frameEnabled = frameEnabled !== false
  }

  function loadBarSurfaceState(raw) {
    try {
      var p = JSON.parse(String(raw || "").trim() || "{}")
      root.applyBarSurfaceState(p && p.color, p && p.material, p && p.frameEnabled)
      root.barSurfaceStateLoaded = true
    } catch (e) {
      root.barSurfaceStateLoaded = false
      frameColorFile.reload()
    }
  }

  FileView {
    id: barSurfaceFile
    path: root.barSurfaceStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadBarSurfaceState(text())
    onLoadFailed: {
      root.barSurfaceStateLoaded = false
      frameColorFile.reload()
    }
  }

  // Old frame-appearance files from before the surface-state migration
  // degrade safely here too: "custom" is no longer recognized, so it
  // falls through to the new "black" default, same as Bar.qml.
  function loadFrameAppearance(raw) {
    if (root.barSurfaceStateLoaded) return
    try {
      var p = JSON.parse(String(raw || "").trim() || "{}")
      root.frameColorMode = normalizeSurfaceColorMode(p && p.mode)
      root.notchSurfaceMaterial = "solid"
    } catch (e) {
      root.frameColorMode = "black"
      root.notchSurfaceMaterial = "solid"
    }
  }

  FileView {
    id: frameColorFile
    path: root.frameColorStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadFrameAppearance(text())
    onLoadFailed: root.loadFrameAppearance("")
  }
  // ruixen-shell#89: this notch is no longer always OLED black, so
  // textColor can't just judge readability from the theme's own
  // foreground luminance in isolation anymore -- that told you nothing
  // about the background it would actually land on. Same
  // readableForegroundForSurface pattern as ruixen.bar's own
  // pillForeground (see Bar.qml), judged against notchColor itself:
  // prefer the theme's own foreground when it reads fine against
  // whatever notchColor really resolved to, otherwise fall back to a
  // fixed safe color on the opposite end from that surface. Keeps each
  // dark theme's actual look (off-white on nearly every one) instead of
  // a single hardcoded white, while now also covering Theme mode
  // resolving to an actually-light background.
  readonly property color themeForeground: Color.bar.text
  function readableForegroundForSurface(surface, preferred) {
    var surfaceIsLight = root.surfaceLuminance(surface) > 0.5
    var preferredIsLight = root.surfaceLuminance(preferred) > 0.45
    return surfaceIsLight
      ? (preferredIsLight ? root.surfaceSafeDarkForeground : preferred)
      : (preferredIsLight ? preferred : root.surfaceSafeLightForeground)
  }
  readonly property color textColor: readableForegroundForSurface(notchColor, themeForeground)
  readonly property color muted: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5)
  // ruixen-shell#89 follow-up: a few tonal surfaces in this file
  // (collapsed-row hover states, the mini progress-bar track) were
  // still flat white-tinted translucent overlays (Qt.rgba(1,1,1,X)),
  // same bug class as muted above already avoids -- see
  // MetricsContent/KanbanContent/WallpapersContent/LauncherContent's
  // own surfaceTint for the full reasoning, ported here identically.
  function surfaceTint(alpha) {
    return Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, alpha)
  }
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
  property bool avatarAnimated: false
  property int avatarFrameCount: 0
  property int avatarFrameDelayMs: 80
  readonly property string avatarStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/avatar.json"
  readonly property string avatarGifPath: Quickshell.env("HOME") + "/.local/state/ruixen/avatar.gif"
  readonly property string avatarFrameDir: Quickshell.env("HOME") + "/.local/state/ruixen/avatar-frames"

  function loadAvatarState(raw) {
    try {
      var p = JSON.parse(String(raw || "").trim() || "{}")
      root.avatarAnimated = !!p.animated
      root.avatarFrameCount = Math.max(0, parseInt(p.frameCount || 0))
      root.avatarFrameDelayMs = Math.max(40, parseInt(p.frameDelayMs || 80))
    } catch (e) {
      root.avatarAnimated = false
      root.avatarFrameCount = 0
      root.avatarFrameDelayMs = 80
    }
  }

  FileView {
    id: avatarStateFile
    path: root.avatarStatePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadAvatarState(text())
    onLoadFailed: root.loadAvatarState("")
  }

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
  property bool canSeek: false
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
    root.canSeek = parsed.canSeek === true
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

  function sendMediaSeek(seconds) {
    mediaSeekProcess.command = ["omarchy-shell", "ruixen-media", "seek", String(Math.round(seconds))]
    mediaSeekProcess.running = true
  }

  Process {
    id: mediaSeekProcess
    running: false
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

  // Bar page's own Notch "Show / On Hover / Hidden" setting -- Hidden
  // goes through the real plugin enable/disable (unloads this whole
  // service entirely, see ruixen.launcher/extensions/settings/SettingsContent.qml's own
  // comment), so this file only ever needs to distinguish "always
  // show the collapsed pill" from "only reveal it on hover" for the
  // other two. Same watched-FileView pattern as dndStateFile above --
  // a different plugin's Settings extension is the only writer, this
  // is a pure reader.
  property string notchVisibilityMode: "always"

  FileView {
    id: notchVisibilityFile
    path: Quickshell.env("HOME") + "/.local/state/ruixen/notch-visibility.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text() || "{}")
        root.notchVisibilityMode = parsed && parsed.mode === "hover" ? "hover" : "always"
      } catch (e) {
        // Leave at its last known value on a transient parse failure.
      }
    }
    onLoadFailed: root.notchVisibilityMode = "always"
  }

  function sendDndAction(action) {
    if (dndActionProcess.running) return
    dndActionProcess.command = ["omarchy-shell", "notifications", String(action)]
    dndActionProcess.running = true
  }

  Process { id: dndActionProcess; running: false }

  // Quick-drop relay (see shelfQuickDrop below): one `omarchy-shell
  // ruixen.shelf addMany` call per drop, carrying the whole batch as one
  // newline-delimited argument -- not a process per path. A drop that
  // lands while a previous relay is still running is queued and sent
  // after that one's real exit (never reassigning the Process out from
  // under a live child). Fire-and-forget, same pattern as
  // dndActionProcess above.
  property var shelfRelayQueue: []

  function relayToShelf(urls) {
    // NEWLINE-delimited, matching ruixen.shelf's addMany contract -- not
    // JSON.stringify(urls). Confirmed live: a bracketed JSON array does
    // not survive the IPC boundary as one argument, so the host split it
    // into one argument per array element and refused the call
    // ("Too many arguments provided"), which broke every multi-file
    // drop. Newlines pass through intact, and normalizePath rejects any
    // path containing \n or \r, so this encoding is unambiguous.
    root.shelfRelayQueue = root.shelfRelayQueue.concat([urls.join("\n")])
    root.drainShelfRelay()
  }

  function drainShelfRelay() {
    if (shelfRelayProcess.running || root.shelfRelayQueue.length === 0) return
    var next = root.shelfRelayQueue[0]
    root.shelfRelayQueue = root.shelfRelayQueue.slice(1)
    shelfRelayProcess.exec(["omarchy-shell", "ruixen.shelf", "addMany", next, "user"])
  }

  Process {
    id: shelfRelayProcess
    onRunningChanged: if (!running) root.drainShelfRelay()
  }

  // Asks ruixen.shelf to open for a drag that just entered the pill. One
  // call per drag-enter; a call still in flight is not queued behind (the
  // Shelf ignores a second open anyway, and a stale one is worthless).
  Process { id: shelfOpenProcess }

  function relayShelfOpen() {
    if (shelfOpenProcess.running) return
    shelfOpenProcess.exec(["omarchy-shell", "ruixen.shelf", "openFromDrag"])
  }

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
    // panel.expanded (the old single window's own property) doesn't
    // exist here any more -- this Timer lives on root, not on any one
    // screen's own NotchWindow.qml instance. root.pinnedOpen/launcherOpen
    // are the same "is the dashboard open at all" signal now, just
    // shared instead of local to one window.
    running: root.pinnedOpen || root.launcherOpen
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

  // Which of {seeker, cava} the collapsed pill's fixed "now playing"
  // slot shows while media is actually playing -- see nowPlayingSlot's
  // own comment (collapsedContent below) for why this only ever
  // applies to the media-present state. Persisted so the choice
  // survives a reopen, same small-JSON-file convention as every other
  // bit of state under ~/.local/state/ruixen/.
  property string mediaVizMode: "seeker"
  // Which of {bars, wave} the cava mode itself renders as -- click-
  // toggled, only meaningful while mediaVizMode is already "cava" (see
  // nowPlayingSlot's own MouseArea). No "segments" here: the full
  // overlay's own segment style splits each bar's growth length into
  // 10 LED blocks with 2px gaps -- at this slot's 20px height that
  // works out to ~0.2px per segment, not just cramped but literally
  // sub-pixel, so it's left out entirely rather than shipped broken.
  property string cavaMiniStyle: "bars"
  readonly property string mediaVizModeStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/notch-media-viz-mode.json"

  function loadMediaVizMode(raw) {
    try {
      var parsed = JSON.parse(String(raw || "").trim() || "{}")
      root.mediaVizMode = (parsed && parsed.mode === "cava") ? "cava" : "seeker"
      root.cavaMiniStyle = (parsed && parsed.style === "wave") ? "wave" : "bars"
    } catch (e) {
      root.mediaVizMode = "seeker"
      root.cavaMiniStyle = "bars"
    }
  }

  function writeMediaVizMode() {
    mediaVizModeFile.setText(JSON.stringify({ mode: root.mediaVizMode, style: root.cavaMiniStyle }, null, 2) + "\n")
  }

  function setMediaVizMode(mode) {
    var next = mode === "cava" ? "cava" : "seeker"
    if (next === root.mediaVizMode) return
    root.mediaVizMode = next
    root.writeMediaVizMode()
  }

  function toggleMediaVizMode() {
    root.setMediaVizMode(root.mediaVizMode === "seeker" ? "cava" : "seeker")
  }

  function toggleCavaMiniStyle() {
    root.cavaMiniStyle = root.cavaMiniStyle === "bars" ? "wave" : "bars"
    root.writeMediaVizMode()
  }

  FileView {
    id: mediaVizModeFile
    path: root.mediaVizModeStatePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadMediaVizMode(text())
    onLoadFailed: root.loadMediaVizMode("")
  }

  // A separate, smaller CavaFeed instance from ruixen.cava's own edge-
  // docked overlay (a different plugin entirely, plugin folders can't
  // share state) -- only enabled while this exact mode is actually
  // visible, so it never spawns a real `cava` process just for having
  // been toggled on once. cavaAvailable's own existing latch
  // (CavaFeed.qml's own header) is what a missing `cava` binary flips
  // false after a real spawn attempt -- caught here to fall back to
  // the seeker automatically rather than leaving the pill on a
  // permanently-flat, dead visualizer with no way back except manually
  // scrolling again.
  //
  // 6 real bands, mirrored to 12 displayed bars (see cavaMiniSlot's own
  // mirrorBandAt below) -- direct request: real bass-on-both-edges/
  // treble-in-the-center, not just a color impression of one. Fewer
  // real bands than a plain 1:1 mapping would need for the same visual
  // bar count also means each bar is wider at this tiny 140px scale --
  // direct follow-up ("we can decrease the amount of bars and make
  // them wider if that helps").
  readonly property int cavaMirrorBands: 6
  CavaFeed {
    id: compactCavaFeed
    enabled: root.hasMedia && root.mediaVizMode === "cava"
    bands: root.cavaMirrorBands
    onCavaAvailableChanged: if (!cavaAvailable) root.setMediaVizMode("seeker")
  }

  // Warm/cool theme colors for the mini cava bars -- same live mechanism
  // ruixen.cava/Overlay.qml's own warmColor/coolColor already uses
  // (this repo's own established pattern, not rebuilt from scratch):
  // reads the real active theme's "red"/"blue" swatches, Color.accent
  // as the fallback when either is missing. See that file's own
  // FileView comment for the theme-switch atomic delete-then-recreate
  // race this same onFileChanged/onLoadFailed pairing already guards
  // against.
  property color cavaWarmColor: Color.accent
  property color cavaCoolColor: Color.accent
  property color kanbanSuccessColor: Color.accent
  property color kanbanDangerColor: Color.accent
  property color kanbanWarningColor: Color.accent
  property color themeSecondaryColor: Color.accent

  function parseCavaThemeColor(raw, key, fallback) {
    var m = String(raw || "").match(new RegExp("^\\s*" + key + "\\s*=\\s*[\"']?(#[0-9A-Fa-f]{6})", "m"))
    return m ? m[1] : fallback
  }

  FileView {
    id: cavaThemeColorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var t = text()
      root.cavaWarmColor = root.parseCavaThemeColor(t, "red", Color.accent)
      root.cavaCoolColor = root.parseCavaThemeColor(t, "blue", Color.accent)
      root.kanbanSuccessColor = root.parseCavaThemeColor(t, "green", Color.accent)
      root.kanbanDangerColor = root.parseCavaThemeColor(t, "red", Color.accent)
      root.kanbanWarningColor = root.parseCavaThemeColor(t, "yellow", Color.accent)
      root.themeSecondaryColor = root.parseCavaThemeColor(t, "secondary", Color.accent)
    }
    // Same one-shot retry ruixen.cava/Overlay.qml's own themeColorsFile
    // already uses -- a theme switch replaces this file via an atomic
    // delete-then-recreate, which can (rapid switching especially) land
    // a reload() exactly in the gap where the path doesn't exist yet
    // with no further file event ever arriving to retry it. See that
    // file's own comment for the full direct-repro history.
    onLoadFailed: {
      root.cavaWarmColor = Color.accent
      root.cavaCoolColor = Color.accent
      root.kanbanSuccessColor = Color.accent
      root.kanbanDangerColor = Color.accent
      root.kanbanWarningColor = Color.accent
      root.themeSecondaryColor = Color.accent
      cavaThemeColorsRetryTimer.restart()
    }
  }

  Timer {
    id: cavaThemeColorsRetryTimer
    interval: 200
    onTriggered: cavaThemeColorsFile.reload()
  }
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

  // Shared, genuinely-singleton dashboard/launcher state -- one logical
  // notch, even though NotchWindow.qml below is instantiated once per
  // screen. Previously lived directly on the one-and-only PanelWindow
  // when there was only ever one; moved here so every screen's own
  // window can read the same open/closed/tab state instead of each
  // tracking its own independent copy. See NotchWindow.qml's own
  // panel.isActiveScreen comment for why only ONE screen at a time
  // actually renders the expanded view / grabs exclusive keyboard
  // focus for it, rather than every monitor doing so simultaneously.
  property bool pinnedOpen: false
  property bool launcherOpen: false
  property int dashboardTab: 0
  // Which screen's own window is currently showing the expanded view --
  // set by NotchWindow.qml's own openPinned() the moment a click opens
  // it on that screen. Empty until the first open; each window falls
  // back to treating Quickshell.screens[0] as the active one while it's
  // empty, so a cold start (or an IPC-driven open, which has no "which
  // screen" concept of its own) still behaves exactly like the old
  // single-window build always did.
  property string activeScreenName: ""

  // Aliases so NotchWindow.qml (a separate file/document, one instance
  // per screen) can reach these singleton services across the file
  // boundary -- a plain id is only visible within the SAME document,
  // unlike a nested `component` declaration, which is why these need
  // an explicit property here at all.
  property alias appLibrary: appLibrary
  property alias notificationHistory: notificationHistory
  property alias kanbanService: kanbanService
  property alias compactCavaFeed: compactCavaFeed

  IpcHandler {
    target: "ruixen.notch"
    function openLauncher(): void { root.launcherOpen = true }
    function closeLauncher(): void { root.launcherOpen = false }
    function toggleLauncher(): void { root.launcherOpen = !root.launcherOpen }
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
    // (onClicked: root.pinnedOpen = true) or openDashboardTab below
    // -- clicking the notch itself still opens on whatever tab was
    // last selected, and a keybind can still jump straight to any
    // specific tab; only these two IPC entry points force Widgets.
    function openDashboard(): void {
      root.dashboardTab = 0
      root.pinnedOpen = true
    }
    function closeDashboard(): void { root.pinnedOpen = false }
    function toggleDashboard(): void {
      if (!root.pinnedOpen) root.dashboardTab = 0
      root.pinnedOpen = !root.pinnedOpen
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
      if (index >= 0) root.dashboardTab = index
      root.pinnedOpen = true
    }
    // Wallpapers tab's own toggle -- same shape as toggleDashboard
    // above (a closed notch opens ON the wallpapers tab, an open one
    // just flips pinnedOpen), so the recommended keybind reads like
    // the other notch keys instead of always re-opening. Keybind
    // recipe: o.bind("SUPER + CTRL + SPACE", "Ruixen wallpapers",
    // "omarchy-shell ruixen.notch toggleWallpapers") -- that key is
    // Omarchy's default Background switcher, so it needs an explicit
    // hl.unbind first (install.sh's --with-launcher-keybind recommends
    // it but leaves a taken key untouched, printing the collision).
    function toggleWallpapers(): void {
      if (!root.pinnedOpen) root.dashboardTab = 1
      root.pinnedOpen = !root.pinnedOpen
    }
    // Called by ruixen.settings' General page after Shuffle/Reset
    // writes or removes ~/.face.icon -- this plugin is keepLoaded:
    // true, so nothing else would tell UserAvatar's Image to re-read
    // the file.
    function refreshAvatar(): void {
      avatarStateFile.reload()
      root.avatarCacheBust = root.avatarCacheBust + 1
    }

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
    function kanbanClearDone(): void { kanbanService.clearDone() }
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
    // orderedIds: the full desired top-to-bottom order for columnId's
    // own cards, newline-delimited -- e.g. `omarchy-shell ruixen.notch
    // kanbanReorderColumn todo $'card-123\ncard-456'`. NOT a JSON
    // array: confirmed live that `qs ipc call` tears a bracketed
    // `[...]` argument into several before this function ever sees
    // it (a real "2 required but 5 provided" error for a 4-id JSON
    // array) -- plain comma- or semicolon-joined text arrives intact
    // as one argument, only the brackets themselves are special.
    // Newline matches ruixen.shelf's own addMany(pathsArg) convention
    // for the identical problem (see its own comment) -- a real card
    // id is always "card-<epochMs>-<rand>" (KanbanModel.makeCardId),
    // so it can never contain one anyway, same reasoning addMany's
    // own comment gives for a path. Meant to be driven by an agent
    // after reading the board back via kanbanListCards above, not
    // typed by hand -- see KanbanModel.reorderColumn's own comment
    // for the "clean up/reorganize the board" request this answers.
    function kanbanReorderColumn(columnId: string, orderedIds: string): void {
      var ids = String(orderedIds || "").split("\n").filter(function(id) { return id !== "" })
      kanbanService.reorderColumn(columnId, ids)
    }
  }

  // One instance per connected screen -- was a single unbound
  // PanelWindow with no `screen:` property at all, so Hyprland/wlroots
  // picked exactly one output to map it to and every other monitor got
  // no notch whatsoever (direct report: works fine mirrored, since
  // that is literally the same framebuffer duplicated, but "isn't
  // showing up on his other monitors" in a real extended multi-monitor
  // setup). Same per-screen `Variants` shape ruixen.bar/Bar.qml already
  // uses for its own four windows.
  Variants {
    model: Quickshell.screens

    delegate: Component {
      NotchWindow {
        required property var modelData

        screen: modelData
        notchRoot: root
      }
    }
  }
}
