import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs.Commons

// Shape ported pixel-for-pixel from
// ~/REPOS/PLUGINS/quickshell-ambxst/modules/notch/Notch.qml +
// modules/corners/RoundCorner.qml (see the long comment this used to have
// -- unchanged, still applies). This pass ports the DEFAULT VIEW's actual
// widget design too (modules/widgets/defaultview/*.qml): avatar | divider
// | wavy player | divider | bell, matching their mainRow layout. Still
// design-first, not full backend -- bell is a static placeholder (no
// notification service wired up), avatar reads the same ~/.face.icon
// convention they use, wave slider shows real position/length but isn't
// drag-to-seek yet.
//
// The wave itself is WavyLine.qml ported verbatim (modules/components/
// WavyLine.qml) -- a Canvas drawing a sine wave whose phase increments
// off Date.now(), driven by FrameAnimation while playing. Genuinely
// self-contained, no shader/effect dependency.
//
// Icons: ambxst uses a "Phosphor-Bold" icon font for its player controls
// and Material Symbols codepoints for source-app icons (Spotify/Firefox/
// etc via Nerd Font). Phosphor isn't installed here, so kept the same
// Nerd Font glyphs already proven working in ruixen.media/ruixen.dnd
// instead of pulling in a new font dependency for this pass.
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

  readonly property var mediaService: shell ? shell.firstPartyServiceFor("ruixen.media") : null

  // Same first-party service ruixen.dnd reads -- the bell here just
  // reflects the real state, doesn't own it.
  readonly property var notificationService: shell ? shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false

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
  readonly property var activePlayer: mediaService ? mediaService.activePlayer : null
  readonly property bool hasMedia: activePlayer !== null && (activePlayer.trackTitle || activePlayer.trackArtist)
  readonly property bool isPlaying: activePlayer ? activePlayer.isPlaying === true : false
  readonly property string playIcon: isPlaying ? "󰏤" : "󰐊"
  readonly property string title: activePlayer ? (activePlayer.trackTitle || "") : ""
  readonly property string artist: activePlayer ? (activePlayer.trackArtist || "") : ""
  readonly property string album: activePlayer ? (activePlayer.trackAlbum || "") : ""
  // Gated on hasMedia, not just activePlayer -- a closed app can leave a
  // zombie MPRIS registration behind (confirmed: chromium after quitting
  // still owns org.mpris.MediaPlayer2.chromium.* on the session bus,
  // PlaybackStatus "Stopped", with a stale mpris:artUrl but no title/
  // artist). Without this gate the blurred background art below kept
  // showing that stale art forever since it only checked "is artUrl
  // non-empty", not whether there's actually anything playing.
  readonly property string artUrl: hasMedia && activePlayer && activePlayer.trackArtUrl ? activePlayer.trackArtUrl : ""

  // ambxst falls back to the focused window's title, then "user@host",
  // rather than ever showing a blank "no media" state. We don't have a
  // compositor-window-title service wired up (that's ruixen.bar's own
  // ActiveWindow territory, unrelated to this plugin), so fall back
  // straight to user@host for now.
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

  property real trackPosition: 0
  readonly property real trackLength: activePlayer ? Math.max(0, Number(activePlayer.length || 0)) : 0
  readonly property real progressRatio: trackLength > 0 ? Math.min(1, trackPosition / trackLength) : 0

  function syncPosition() {
    trackPosition = activePlayer ? Math.max(0, Number(activePlayer.position || 0)) : 0
  }

  function formatTime(seconds) {
    var value = Math.max(0, Math.floor(Number(seconds) || 0))
    var minutes = Math.floor(value / 60)
    var rest = value % 60
    return minutes + ":" + String(rest).padStart(2, "0")
  }

  Timer {
    interval: 500
    repeat: true
    running: root.isPlaying
    triggeredOnStart: true
    onTriggered: root.syncPosition()
  }

  // Quarter-circle silhouette, one corner at a time -- used as mask
  // material for the concave flanks. Ported verbatim from RoundCorner.qml.
  component RoundCorner: Item {
    id: rc
    // 0 TopLeft, 1 TopRight, 2 BottomLeft, 3 BottomRight
    property int corner: 0
    property int cornerSize: 20
    property color fillColor: "#ffffff"

    implicitWidth: cornerSize
    implicitHeight: cornerSize

    onFillColorChanged: canvas.requestPaint()
    onCornerChanged: canvas.requestPaint()
    onCornerSizeChanged: canvas.requestPaint()
    onVisibleChanged: if (visible) canvas.requestPaint()

    Canvas {
      id: canvas
      anchors.fill: parent
      antialiasing: true
      onPaint: {
        var ctx = getContext("2d")
        var r = rc.cornerSize
        ctx.clearRect(0, 0, width, height)
        ctx.beginPath()
        switch (rc.corner) {
          case 0: ctx.arc(r, r, r, Math.PI, 3 * Math.PI / 2); ctx.lineTo(0, 0); break
          case 1: ctx.arc(0, r, r, 3 * Math.PI / 2, 2 * Math.PI); ctx.lineTo(r, 0); break
          case 2: ctx.arc(r, 0, r, Math.PI / 2, Math.PI); ctx.lineTo(0, r); break
          case 3: ctx.arc(0, 0, r, 0, Math.PI / 2); ctx.lineTo(r, r); break
        }
        ctx.closePath()
        ctx.fillStyle = rc.fillColor
        ctx.fill()
      }
    }
  }

  // Ported verbatim from WavyLine.qml. The actual "wave" -- a sine wave
  // whose phase increments off Date.now(), so it undulates continuously
  // while `running`, redrawn every frame via FrameAnimation.
  component WavyLine: Canvas {
    id: wave
    property color lineColor: "#ffffff"
    property real lineWidth: 2
    property real frequency: 2
    property real amplitudeMultiplier: 0.5
    property real fullLength: width
    property bool running: true

    readonly property bool shouldAnimate: running && visible && width > 0 && opacity > 0

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      if (width <= 0 || height <= 0) return

      var amp = wave.lineWidth * wave.amplitudeMultiplier
      var freq = wave.frequency
      var phase = Date.now() / 400.0
      var centerY = height / 2

      ctx.strokeStyle = wave.lineColor
      ctx.lineWidth = wave.lineWidth
      ctx.lineCap = "round"
      ctx.beginPath()

      for (var x = ctx.lineWidth / 2; x <= wave.width - ctx.lineWidth / 2; x += 1) {
        var waveY = centerY + amp * Math.sin(freq * 2 * Math.PI * x / wave.fullLength + phase)
        if (x === ctx.lineWidth / 2) ctx.moveTo(x, waveY)
        else ctx.lineTo(x, waveY)
      }
      ctx.stroke()
    }

    FrameAnimation {
      running: wave.shouldAnimate
      onTriggered: wave.requestPaint()
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
    // circle instead of a shipped PNG asset, so there's no fixed
    // resolution/ratio to pick and it scales cleanly at any avatarSize.
    // Sits underneath the real image below; once that loads it fully
    // covers this (opaque), so no conditional visibility needed.
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      gradient: Gradient {
        GradientStop { position: 0.0; color: "#5b6ee8" }
        GradientStop { position: 1.0; color: "#8a4fd6" }
      }
    }

    Image {
      id: avatarImage
      anchors.fill: parent
      source: "file://" + Quickshell.env("HOME") + "/.face.icon"
      fillMode: Image.PreserveAspectCrop
      asynchronous: true
      visible: false
    }

    // Item.clip is rectangular -- circular crop needs an actual mask,
    // same MultiEffect technique as the notch shape itself.
    Rectangle {
      id: avatarMask
      anchors.fill: parent
      radius: width / 2
      color: "#ffffff"
      visible: false
      layer.enabled: true
    }

    MultiEffect {
      anchors.fill: parent
      source: avatarImage
      maskEnabled: true
      maskSource: avatarMask
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

  // Left-side vertical tab-bar button, matching ambxst's Dashboard.qml
  // tabsContainer icon buttons (Widgets/Wallpapers/Metrics stacked, plus
  // a settings gear pinned at the bottom). Just a plain icon + tonal
  // hover/active background, no ambxst StyledRect dependency, same
  // approach as every other component ported into this file.
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
    visible: !root.fullscreenActive
    // bottom:true too, not just top/left/right -- the click-away-to-
    // dismiss MouseArea (see below) needs the panel's own surface to
    // actually reach the full screen height for its widened mask to
    // cover anywhere outside the notch. Anchoring both top and bottom
    // makes the surface fill the full height regardless of
    // implicitHeight; exclusionMode stays Ignore so this never reserves
    // screen space the way ruixen.bar's own window does.
    anchors { top: true; left: true; right: true; bottom: true }
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
    // None except while the launcher's own search box is open, when it
    // switches to Exclusive (same mode ruixen.settings/Settings.qml and
    // Omarchy's own real Menu.qml use for their modal panels) so the
    // TextInput below can actually receive typed characters. Every other
    // state (collapsed, pinnedOpen) stays None -- passive hover, no
    // reason to grab keyboard input. v1 of the launcher's search box
    // needed this SAME flip, but combined it with a taller notch size,
    // which is what actually broke (see launcherContent's own comment
    // below) -- this flip alone, without the resize, is the untested
    // half of that old combination.
    WlrLayershell.keyboardFocus: launcherOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

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
    }

    // Fire-once, not auto-running -- triggered by the tab bar's settings
    // button (see expandedContent below). Opens Omarchy's own real
    // settings menu rather than reimplementing a settings page here:
    // "setup" is the root omarchy-menu.jsonc entry, aliased "settings",
    // confirmed working via `omarchy-menu summon settings`.
    Process {
      id: settingsProc
      command: ["omarchy-menu", "summon", "settings"]
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
      enabled: panel.clickedOpen
      onClicked: { panel.pinnedOpen = false; panel.launcherOpen = false }
    }

    Item {
      id: notchOuter
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.top: parent.top
      // Ambxst derives its own notch corner geometry from its window
      // rounding config (roundness=16 default): cornerSize=roundness+4,
      // collapsed radius=roundness+4, expanded radius=roundness+20. Our
      // frame/Hyprland rounding is 24, not 16 -- same formula, our own
      // rounding: cornerSize=28, collapsed radius=28 (see centerMask
      // below), expanded radius=44.
      readonly property int cornerSize: 28
      // Collapsed width trimmed from ambxst's own 290 (matched to their
      // actual DefaultView.qml row) -- our actual content (avatar +
      // divider + play glyph/wave + divider + bell) is narrower than
      // theirs, so 290 left a big empty gap between the avatar/bell and
      // the notch's own curved edges. First attempt went to 240, but
      // collapsedContent's real parent is a clip:true Item sized to
      // exactly bodyWidth (see below) -- content measures ~236-240px
      // wide (avatar 20 + 2 dividers + wave-track 140 + play glyph +
      // bell + Row spacing), landing right at that clip edge and cutting
      // the bell off. 260 gives real margin instead of a knife's-edge
      // fit. Expanded width (420) is unrelated -- ambxst's
      // notificationMinWidth target, still fits our own expanded content.
      // Media hover/pin now tries ambxst's own real dashboard size
      // (DashboardView.qml: implicitWidth 900, implicitHeight 56+48*6 =
      // 344) instead of reusing the smaller 420x190 -- untested territory
      // for this notch (only 44 and 190 are proven safe against the
      // masking bug below), so watch for the same flat-bottom-corner
      // symptom if this doesn't pan out.
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
      readonly property int bodyWidth: panel.launcherOpen ? 420 : (panel.pinnedOpen ? 900 : 284)
      width: bodyWidth + cornerSize * 2
      // Full ambxst parity (44px collapsed) -- ruixen-bar's own reserved
      // screen zone (notchClearance) was bumped to cover this plus a
      // buffer, so it no longer overlaps tiled windows the way it did
      // when this was smaller but the reserved zone was still just
      // barSize-sized. Dashboard height bumped past ambxst's own 344 to
      // 400 per direct feedback ("a bit too short") -- past the
      // previously-tested-safe value, so stress-tested 3x (open/close
      // cycles, checking the bottom-corner mask each time) against the
      // masking bug documented below before keeping it.
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
                text: root.playIcon
                color: root.hasMedia ? root.textColor : root.muted
                font.family: root.fontFamily
                // Matches the bar's new icon standard (18px, tuned to
                // ambxst's own bar-icon size) -- was 11, visibly undersized
                // next to the 20px avatar in this same row.
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
                  onClicked: if (root.mediaService) root.mediaService.runAction("playPause", false)
                }
              }

              // Track (full length, dim) + wave (played portion only, up
              // to progressRatio) -- actually reflects position now,
              // instead of a decorative full-width wave. No drag-to-seek
              // yet, position display only.
              Item {
                anchors.verticalCenter: parent.verticalCenter
                width: 140
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
              // wave lineWidth 3 (half 1.5) + playhead width 3 (half
              // 1.5) + 2px desired = 5px, applied as the FULL trim on
              // EACH side independently (not split further) -- matches
              // how the ring's own gapPx already works, not a fresh
              // guess.
              readonly property real gapPx: 5

              // Track/wave/playhead thickened 2px -> 4px together, per
              // direct feedback. Follow-up: the track was fine at 4
              // but the wave/playhead read as a bit too thick next to
              // it -- toned those two back down to 3, track left at 4.
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
                lineWidth: 3
                frequency: 6
                amplitudeMultiplier: root.isPlaying ? 1.4 : 0.15
                fullLength: 140
                running: root.isPlaying
              }

              // Playhead -- stays centered exactly at the true split
              // point, unchanged -- only the wave/track on either side
              // of it pull back now.
              Rectangle {
                width: 3
                height: parent.height
                radius: width / 2
                anchors.verticalCenter: parent.verticalCenter
                color: root.textColor
                x: parent.splitX - width / 2
                visible: root.hasMedia

                Behavior on x { NumberAnimation { duration: 450 } }
              }
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
            // request ("the notification toggle right"). Same real API
            // ruixen.dnd's own bar pill calls
            // (notificationService.setDoNotDisturb), not a separate
            // reimplementation.
            MouseArea {
              anchors.fill: parent
              anchors.margins: -6
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.notificationService) root.notificationService.setDoNotDisturb(!root.dnd)
            }
          }
        }

        // Expanded: blurred-art thumbnail, title/artist, big wave
        // progress, transport controls.
        // Expanded: dashboard content (player + quick controls/calendar +
        // notifications + volume dials), ported from ambxst's
        // WidgetsTab.qml -- see DashboardContent.qml for the full
        // breakdown. Media data/colors passed through from the same
        // root-level properties the collapsed view already reads.
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
            // 8px, matching ambxst's own mainLayout Row spacing (Dashboard.qml)
            // -- we were at 10, a bit looser than their real rhythm.
            spacing: 8

            // Left vertical tab bar -- ambxst's Dashboard.qml
            // tabsContainer: Widgets/Wallpapers/Metrics stacked icon
            // buttons, settings gear pinned at the bottom via a
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

              Item { Layout.fillHeight: true }

              // The one real action in this tab bar -- opens Omarchy's
              // actual settings menu (see settingsProc above), not a
              // notch-local settings page.
              TabButton {
                glyph: ""
                onActivated: settingsProc.running = true
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
                textColor: root.textColor
                muted: root.muted
                accent: root.accent
                fontFamily: root.fontFamily
                mediaService: root.mediaService
                activePlayer: root.activePlayer
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
              }
            }
          }
        }

        // Quick app launcher -- a search box for finding any installed app,
        // plus a row of pinned Omarchy system-menu actions shown while the
        // search is empty (Lock, Power, etc.). Deliberately stays inside
        // the exact same 420x190 launcherOpen footprint used by the old
        // click-only grid below -- v1's own search box needed
        // WlrKeyboardFocus.Exclusive (see panel's keyboardFocus above)
        // AND a taller notch (340x260/etc) to fit a scrollable list, and
        // that combination hit a real, non-deterministic bug in the
        // notchBg masking (MultiEffect layer effect below) at taller
        // heights. Only the keyboard-focus flip happens this time; no new
        // size, so the resize half of that bad combination never occurs.
        //
        // Pinned actions run through Omarchy's own `omarchy menu summon
        // <id>` CLI (launcherActionProc below) instead of duplicating any
        // command strings here -- same id space as
        // /usr/share/omarchy/default/omarchy/omarchy-menu.jsonc, so this
        // can never drift out of sync with Omarchy's real menu. Edit
        // pinnedActions below to change which ones show. App search reads
        // shell.appLibrary.sortedEntries() -- real ranking (prefix match
        // highest, then substring, then a bounded acronym fallback), not
        // fuzzy/subsequence matching, confirmed by reading AppSearch.js.
        //
        // Both states share one Grid + Repeater (model swaps, tile visual
        // stays identical) capped to a single row (6 tiles) -- deliberately
        // not enough room for a second row within 190px alongside the
        // search box, and no scrolling, so this stays a fast glance/click
        // UI rather than growing into something that needs the taller,
        // unproven notch size.
        Item {
          id: launcherContent
          visible: panel.launcherOpen
          opacity: panel.launcherOpen ? 1 : 0
          anchors.centerIn: parent
          width: 410
          height: 190
          // Inner content (search box + tile row) sits at this width,
          // centered within the 410 footprint above -- leaves real side
          // padding so neither touches the notch's own curved edge.
          readonly property int contentWidth: 366
          Behavior on opacity { NumberAnimation { duration: 160 } }

          onVisibleChanged: {
            if (visible) {
              selectedIndex = 0
              // WlrLayershell.keyboardFocus: Exclusive only grants the
              // layer surface itself keyboard focus at the Wayland level
              // -- Qt Quick's own scene-graph focus is separate, and
              // nothing gets it by default. Same forceActiveFocus() call
              // ruixen.weather/Panel.qml already needs for its own search
              // field (startEditingLocation()); without it the TextInput
              // never receives typed characters despite the surface-level
              // grab succeeding.
              Qt.callLater(function() { launcherSearchInput.forceActiveFocus() })
            } else {
              launcherSearchInput.text = ""
              searchText = ""
            }
          }

          property string searchText: ""
          readonly property bool showingSearch: searchText.length > 0
          // "actions" (Omarchy system-menu shortcuts) or "favorites"
          // (pinned apps) -- which one the empty-search view shows.
          // Toggled by the button beside the search box.
          property string pinnedMode: "actions"
          // Arrow-key selection, matching ruixen.weather/Panel.qml's own
          // Keys.onPressed pattern (its locationField -- the closest real
          // precedent in this repo). Reset on every keystroke so a new
          // query always starts from the top match, and on open so a
          // stale selection from the last session never carries over.
          // Hovering a tile also claims this (see cardMouse.onEntered
          // below), so Ctrl+F/Ctrl+R act on "whichever tile is
          // highlighted" whether that got there by mouse or keyboard.
          property int selectedIndex: 0
          onSearchTextChanged: selectedIndex = 0

          // Glyphs copied verbatim from
          // /usr/share/omarchy/default/omarchy/omarchy-menu.jsonc so these
          // tiles match what Omarchy's own menu shows for the same ids.
          readonly property var pinnedActions: [
            { id: "system.lock", label: "Lock", icon: "" },
            { id: "system", label: "Power", icon: "" },
            { id: "learn.keybindings", label: "Keybind", icon: "" },
            { id: "trigger.capture.screenshot", label: "Screenshot", icon: "" },
            { id: "style.theme", label: "Theme", icon: "󰸌" },
            { id: "setup", label: "Settings", icon: "" }
          ]

          readonly property var searchResults: {
            if (!showingSearch || !root.shell || !root.shell.appLibrary) return []
            var rows = root.shell.appLibrary.sortedEntries(searchText)
            var picked = []
            for (var i = 0; i < rows.length && picked.length < 6; i++) picked.push(rows[i].entry)
            return picked
          }

          // ---- Favorite apps: persisted list of desktop-entry ids, capped
          // at 6 so the single-row grid never overflows. Real
          // customization (the whole point of this rebuild -- see the
          // block comment above) instead of a hardcoded array: pin/unpin
          // from the UI (Ctrl+F, Ctrl+R, or right-click), same
          // FileView.setText() persistence pattern Omarchy's own
          // notifications service uses for its settings.json (confirmed
          // by reading plugins/notifications/Service.qml directly, not
          // guessed) -- debounced write, atomicWrites, a loaded guard so
          // the initial onLoaded/onLoadFailed race can't stomp state.
          readonly property string favoritesPath: Quickshell.env("HOME") + "/.local/state/ruixen/launcher-favorites.json"
          // Empty-state fallback shown only while the user has zero real
          // favorites of their own -- never written to favorites.json
          // (see favoriteEntries below). Every id here is a real package
          // in /usr/share/omarchy/install/omarchy-base.packages (confirmed
          // by reading that file, not guessed), so this reflects what a
          // fresh Omarchy install actually ships rather than one person's
          // personal app picks -- the exact problem the old hardcoded
          // favoriteAppIds array had. Desktop-entry ids confirmed against
          // /usr/share/applications/*.desktop.
          readonly property var defaultFavoriteAppIds: [
            "chromium", "foot", "org.gnome.Nautilus", "obsidian", "mpv", "com.obsproject.Studio"
          ]
          property var favoriteAppIds: []
          property bool favoritesLoaded: false
          // Brief override for the search placeholder when a 6th pin is
          // attempted -- reuses the existing placeholder text instead of
          // a separate warning element, so nothing else in the layout
          // shifts (a standalone message caused a visible jump).
          property bool favoritesFullHint: false

          function isFavorited(id) {
            return favoriteAppIds.indexOf(id) !== -1
          }

          function addFavorite(id) {
            if (!id || isFavorited(id)) return
            if (favoriteAppIds.length >= 6) {
              favoritesFullHint = true
              favoritesFullHintTimer.restart()
              return
            }
            favoriteAppIds = favoriteAppIds.concat([id])
            favoritesSaveTimer.restart()
          }

          function removeFavorite(id) {
            var idx = favoriteAppIds.indexOf(id)
            if (idx === -1) return
            var next = favoriteAppIds.slice()
            next.splice(idx, 1)
            favoriteAppIds = next
            favoritesSaveTimer.restart()
          }

          function loadFavorites(raw) {
            if (favoritesLoaded) return
            var ids = []
            try {
              var parsed = JSON.parse(raw)
              if (parsed && Array.isArray(parsed.ids)) ids = parsed.ids
            } catch (e) {}
            favoriteAppIds = ids.slice(0, 6)
            favoritesLoaded = true
          }

          function resolveEntries(ids) {
            if (!root.shell || !root.shell.appLibrary) return []
            var all = root.shell.appLibrary.sortedEntries("")
            var byId = {}
            for (var i = 0; i < all.length; i++) byId[all[i].entry.id] = all[i].entry
            var picked = []
            for (var j = 0; j < ids.length; j++) {
              if (byId[ids[j]]) picked.push(byId[ids[j]])
            }
            return picked
          }

          // favoriteAppIds itself only ever holds real, persisted, user-
          // picked favorites -- it starts and stays empty until the user
          // actually pins something (Ctrl+F / right-click). defaultFavoriteAppIds
          // is a pure display fallback for the empty state, never written
          // to favorites.json: the moment a real pin exists this falls
          // back to showing only that, and if the user later removes
          // every real favorite, this reverts to the defaults again --
          // an empty-state placeholder, not starting data to clean out.
          readonly property var favoriteEntries: resolveEntries(
            favoriteAppIds.length > 0 ? favoriteAppIds : defaultFavoriteAppIds)

          Timer {
            id: favoritesFullHintTimer
            interval: 1600
            repeat: false
            onTriggered: launcherContent.favoritesFullHint = false
          }

          Timer {
            id: favoritesSaveTimer
            interval: 200
            repeat: false
            onTriggered: favoritesFile.setText(JSON.stringify({ ids: launcherContent.favoriteAppIds }, null, 2) + "\n")
          }

          Process {
            id: ensureFavoritesDirProc
            command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/ruixen"]
          }

          FileView {
            id: favoritesFile
            path: launcherContent.favoritesPath
            watchChanges: false
            atomicWrites: true
            printErrors: false
            onLoaded: launcherContent.loadFavorites(text())
            onLoadFailed: launcherContent.loadFavorites("")
          }

          Component.onCompleted: ensureFavoritesDirProc.running = true

          // Search-results and favorite-app tiles both show real app icons
          // and names; the Omarchy-actions tiles show a static glyph +
          // label instead. Same delegate either way (see tile Item
          // below), branched on this.
          readonly property bool tilesAreApps: showingSearch || pinnedMode === "favorites"

          readonly property var activeTiles: showingSearch
            ? searchResults
            : (pinnedMode === "favorites" ? favoriteEntries : pinnedActions)

          function activateTile(data) {
            if (!data) return
            if (tilesAreApps) {
              root.shell.appLibrary.launch(data.id, root.shell.appLibrary.entryName(data))
            } else {
              launcherActionProc.command = ["omarchy", "menu", "summon", data.id]
              launcherActionProc.running = true
            }
            panel.launcherOpen = false
          }

          Process {
            id: launcherActionProc
            stdout: StdioCollector { waitForEnd: true }
          }

          // Search box sits at a FIXED offset from the top rather than
          // inside a height-based-centered Column -- with the old layout,
          // an empty result set hid the Grid entirely, shrinking the
          // Column's total height and re-centering it, which visibly
          // shifted the search box up/down every time the match count hit
          // zero. Anchoring everything to searchBox instead means the
          // Grid and the empty-state text swapping in and out never moves
          // it. topMargin chosen to match the old centered look for the
          // common (results visible) case: 36 (search) + 28 (gap) + 66
          // (tile row) = 130 content height inside a 190 box centers at
          // (190-130)/2 = 30.
          Rectangle {
            id: searchBox
            anchors.top: parent.top
            anchors.topMargin: 30
            anchors.left: parent.horizontalCenter
            anchors.leftMargin: -launcherContent.contentWidth / 2
            width: launcherContent.contentWidth - 44
            height: 36
            radius: 12
            color: Qt.rgba(1, 1, 1, 0.06)

            TextInput {
              id: launcherSearchInput
              anchors.fill: parent
              anchors.leftMargin: 12
              anchors.rightMargin: 12
              verticalAlignment: TextInput.AlignVCenter
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: 12
              clip: true

              onTextChanged: launcherContent.searchText = text

              Keys.onPressed: function(event) {
                var count = launcherContent.activeTiles.length
                var active = launcherContent.activeTiles[launcherContent.selectedIndex]
                if (event.key === Qt.Key_Escape) {
                  panel.launcherOpen = false
                  event.accepted = true
                } else if (event.key === Qt.Key_Left || event.key === Qt.Key_Up) {
                  if (launcherContent.selectedIndex > 0) launcherContent.selectedIndex--
                  event.accepted = true
                } else if (event.key === Qt.Key_Right || event.key === Qt.Key_Down) {
                  if (launcherContent.selectedIndex < count - 1) launcherContent.selectedIndex++
                  event.accepted = true
                } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                  launcherContent.activateTile(active)
                  event.accepted = true
                } else if (event.key === Qt.Key_F && (event.modifiers & Qt.ControlModifier)) {
                  // Bare "f" would collide with typing app names that
                  // contain the letter (firefox, spotify...), so this is
                  // Ctrl+F rather than the plain key.
                  if (launcherContent.showingSearch && active) launcherContent.addFavorite(active.id)
                  event.accepted = true
                } else if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
                  if (!launcherContent.showingSearch && launcherContent.pinnedMode === "favorites" && active) {
                    launcherContent.removeFavorite(active.id)
                  }
                  event.accepted = true
                }
              }

              Text {
                anchors.verticalCenter: parent.verticalCenter
                text: launcherContent.favoritesFullHint ? "Favorite Apps Full" : "Search apps..."
                color: root.muted
                font.family: root.fontFamily
                font.pixelSize: 12
                visible: launcherSearchInput.text.length === 0
              }
            }
          }

          // Toggle button -- switches the empty-search view between
          // pinned Omarchy actions and pinned favorite apps. Only changes
          // what's shown once the search box is actually empty; toggling
          // mid-query just changes what you'll see after clearing it.
          Rectangle {
            id: favoritesToggle
            anchors.top: searchBox.top
            anchors.left: searchBox.right
            anchors.leftMargin: 8
            width: 36
            height: 36
            radius: 12
            color: launcherContent.pinnedMode === "favorites"
              ? Qt.rgba(1, 1, 1, 0.16)
              : (toggleMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06))
            Behavior on color { ColorAnimation { duration: 120 } }

            Text {
              anchors.centerIn: parent
              text: ""
              font.family: root.fontFamily
              font.pixelSize: 14
              color: launcherContent.pinnedMode === "favorites" ? root.textColor : root.muted
            }

            MouseArea {
              id: toggleMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                launcherContent.pinnedMode = launcherContent.pinnedMode === "favorites" ? "actions" : "favorites"
                Qt.callLater(function() { launcherSearchInput.forceActiveFocus() })
              }
            }
          }

          Grid {
            visible: launcherContent.showingSearch
              ? launcherContent.searchResults.length > 0
              : (launcherContent.pinnedMode === "favorites" ? launcherContent.favoriteEntries.length > 0 : true)
            anchors.top: searchBox.bottom
            anchors.topMargin: 28
            anchors.horizontalCenter: parent.horizontalCenter
            width: launcherContent.contentWidth
            columns: 6
            spacing: 8

            Repeater {
              model: launcherContent.activeTiles

              Item {
                id: tile
                required property var modelData
                required property int index
                width: 54
                height: 66

                Rectangle {
                  id: cardBg
                  anchors.top: parent.top
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: 52
                  height: 52
                  radius: 14
                  color: (cardMouse.containsMouse || tile.index === launcherContent.selectedIndex)
                    ? Qt.rgba(1, 1, 1, 0.16) : Qt.rgba(1, 1, 1, 0.06)
                  Behavior on color { ColorAnimation { duration: 120 } }

                  Image {
                    visible: launcherContent.tilesAreApps
                    anchors.centerIn: parent
                    width: 26
                    height: 26
                    sourceSize: Qt.size(26, 26)
                    asynchronous: true
                    source: launcherContent.tilesAreApps && root.shell && root.shell.appLibrary
                      ? root.shell.appLibrary.iconSource(tile.modelData.icon) : ""
                  }

                  Text {
                    visible: !launcherContent.tilesAreApps
                    anchors.centerIn: parent
                    text: launcherContent.tilesAreApps ? "" : tile.modelData.icon
                    color: root.textColor
                    font.pixelSize: 20
                  }

                  // Pin badge -- only meaningful while browsing search
                  // results (favorites-view tiles are favorites by
                  // definition; action tiles aren't apps at all). Plain
                  // theme-accent dot, no glyph -- a quieter "already
                  // pinned" indicator than an icon-in-a-circle.
                  Rectangle {
                    visible: launcherContent.showingSearch && launcherContent.isFavorited(tile.modelData.id)
                    anchors.top: parent.top
                    anchors.right: parent.right
                    anchors.topMargin: -1
                    anchors.rightMargin: -1
                    width: 10
                    height: 10
                    radius: 5
                    color: root.accent
                    border.color: root.notchColor
                    border.width: 1.5
                  }
                }

                Text {
                  anchors.top: cardBg.bottom
                  anchors.topMargin: 4
                  anchors.horizontalCenter: parent.horizontalCenter
                  width: parent.width
                  horizontalAlignment: Text.AlignHCenter
                  elide: Text.ElideRight
                  text: launcherContent.tilesAreApps && root.shell && root.shell.appLibrary
                    ? root.shell.appLibrary.entryName(tile.modelData) : (tile.modelData.label || "")
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: 9
                }

                MouseArea {
                  id: cardMouse
                  anchors.fill: cardBg
                  hoverEnabled: true
                  acceptedButtons: Qt.LeftButton | Qt.RightButton
                  cursorShape: Qt.PointingHandCursor
                  onEntered: launcherContent.selectedIndex = tile.index
                  onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                      if (launcherContent.showingSearch) launcherContent.addFavorite(tile.modelData.id)
                      else if (launcherContent.pinnedMode === "favorites") launcherContent.removeFavorite(tile.modelData.id)
                    } else {
                      launcherContent.activateTile(tile.modelData)
                    }
                  }
                }
              }
            }
          }

          Text {
            visible: launcherContent.showingSearch && launcherContent.searchResults.length === 0
            anchors.top: searchBox.bottom
            anchors.topMargin: 28
            anchors.horizontalCenter: parent.horizontalCenter
            width: launcherContent.contentWidth
            horizontalAlignment: Text.AlignHCenter
            text: "No apps match \u201c" + launcherContent.searchText + "\u201d"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 12
          }

          Text {
            visible: !launcherContent.showingSearch && launcherContent.pinnedMode === "favorites" && launcherContent.favoriteEntries.length === 0
            anchors.top: searchBox.bottom
            anchors.topMargin: 28
            anchors.horizontalCenter: parent.horizontalCenter
            width: launcherContent.contentWidth
            horizontalAlignment: Text.AlignHCenter
            text: "No favorites yet"
            color: root.muted
            font.family: root.fontFamily
            font.pixelSize: 12
          }
        }
      }
    }
  }
}
