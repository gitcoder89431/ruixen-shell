import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// A live, edge-docked, audio-reactive cava spectrum overlay -- direct
// request/community pointer to github.com/Ryoku-dev/ryoku's own cava
// integration. Persistent decorative effect (this plugin, always
// loaded, gated on its own enabled flag) + control surface (the
// Visualizer category in ruixen.launcher's Settings extension) --
// same split ruixen.wallpaper already establishes for a different
// persistent desktop effect.
//
// Bars only for v1 -- a near-verbatim port of Ryoku's own
// shell/modules/bar/MusicBars.qml (a plain Repeater of Rectangle bars).
// A true "Waves" style (a smooth continuous curve, not a bars variant)
// is an explicit, named follow-up once this core plumbing -- cava
// process management, live audio data, edge-docked overlay -- is
// confirmed working well here.
Item {
  id: root
  property var shell: null
  property var manifest: null

  // State read from ~/.local/state/ruixen/cava-visualizer.json --
  // written by ruixen.launcher/SettingsContent.qml's own Visualizer
  // category, same Settings-writes/this-reads split already
  // established for notch-visibility.json and applauncher-icon.json.
  property bool vizEnabled: false
  property string style: "bars"        // only "bars" ships in v1
  // Bottom, not Top -- direct follow-up after trying it live: "cool i
  // guess at 310 i like it, buttom 310 and 64 bands as default."
  property string position: "bottom"   // "top" | "bottom" | "left" | "right"
  property int bands: 64               // 32 | 48 | 64 | 96
  // A real pixel height, not a Small/Medium/Large preset -- direct
  // follow-up: "the large is still way too small, maybe instead of
  // small medium large we do scroll progress bar slider for height?"
  // Range/default mirror SettingsContent.qml's own cavaThicknessMin/
  // Max/default exactly (40-400, default 310) -- kept in sync by hand
  // since each file already owns its own copy of every other clamped
  // range here (bands, position), not worth a shared-constants file
  // for three small numbers.
  readonly property int thicknessMin: 40
  readonly property int thicknessMax: 400
  property int thickness: 310

  readonly property bool vertical: root.position === "left" || root.position === "right"
  // MusicBars.qml's own "vertical"/"horizontal" describe the BARS' own
  // growth axis, not which screen edge they're docked to -- inverted
  // relative to root.vertical (our docking flag) by definition: docking
  // to left/right (root.vertical true) means bars grow SIDEWAYS spread
  // down height, which is MusicBars' own "horizontal" orient.
  readonly property bool barsHoriz: root.vertical

  FileView {
    id: stateFile
    path: Quickshell.env("HOME") + "/.local/state/ruixen/cava-visualizer.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var p = JSON.parse(text() || "{}")
        root.vizEnabled = !!(p && p.enabled)
        root.position = (p && ["top", "bottom", "left", "right"].indexOf(p.position) >= 0) ? p.position : "bottom"
        root.bands = (p && [32, 48, 64, 96].indexOf(p.bands) >= 0) ? p.bands : 64
        var t = p && typeof p.thickness === "number" ? Math.round(p.thickness) : 310
        root.thickness = Math.max(root.thicknessMin, Math.min(root.thicknessMax, t))
      } catch (e) {
        // Leave at last known values on a transient parse failure.
      }
    }
    onLoadFailed: root.vizEnabled = false
  }

  // Same real Wayland foreign-toplevel fullscreen watching already
  // proven in ruixen.frame-widget/Overlay.qml and ruixen.notch/
  // Overlay.qml -- a real fullscreen window (a game, a video) should
  // cover this overlay, not have it float on top uninvited.
  readonly property bool fullscreenActive: ToplevelManager.activeToplevel
    ? ToplevelManager.activeToplevel.fullscreen : false

  CavaFeed {
    id: feed
    enabled: root.vizEnabled && !root.fullscreenActive
    bands: root.bands
  }

  PanelWindow {
    id: panel
    visible: root.vizEnabled && !root.fullscreenActive
    color: "transparent"

    WlrLayershell.namespace: "ruixen-cava"
    // Bottom, not Overlay -- direct live report after shipping with
    // Overlay ("its layered kinda wrong, its over the frame and the
    // hyprland terminal windows etc... it should sit on the wallpaper
    // but not over the frame shell"). Confirmed directly in Ryoku's own
    // reference (shell/modules/visualizer/Visualizer.qml): its default
    // "desktop" mode is explicitly WlrLayer.Bottom specifically so the
    // spectrum draws on the wallpaper BEHIND every window, only ever
    // raising to WlrLayer.Top for its own separate, opt-in "overlay"
    // mode -- Overlay (this repo's frame-widget/notch layer, ABOVE
    // normal windows) was never the right layer for a decorative
    // desktop effect at all. wlr-layer-shell stacking is background <
    // bottom < [normal windows] < top < overlay -- Bottom sits right
    // where ruixen.wallpaper's own WlrLayer.Background ends and normal
    // windows begin, exactly "on the wallpaper, not over the frame."
    WlrLayershell.layer: WlrLayer.Bottom
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    // Never reserves screen space -- a decorative strip, not a bar.
    exclusionMode: ExclusionMode.Ignore
    // Purely decorative, zero interactive elements -- same "mask:
    // Region {}" convention ruixen.frame-widget's own comment
    // documents: without it, a topmost-layer surface swallows scroll/
    // click input for everything underneath even with no MouseArea at
    // all.
    mask: Region {}

    // Only 3 of the 4 edges get anchored, matching ruixen.bar's own
    // BarPanel -- the docked edge plus the two edges perpendicular to
    // it, so the strip spans the full length of whichever edge it's
    // docked to. No margins block (unlike BarPanel, which needs one for
    // its own hide-past-the-edge trick) -- visible:false is enough
    // here, there's no slide animation to support.
    anchors {
      top: root.position === "top" || root.vertical
      bottom: root.position === "bottom" || root.vertical
      left: root.position === "left" || !root.vertical
      right: root.position === "right" || !root.vertical
    }

    implicitWidth: root.vertical ? root.thickness : 0
    implicitHeight: root.vertical ? 0 : root.thickness

    // Bars -- ported from MusicBars.qml's own slot/thick/grow formulas,
    // simplified: displayed band count and cava's own config band count
    // are the SAME value here (root.bands drives both), so there is no
    // "coarse strip averaging several cava bands into one displayed
    // bar" step to port -- feed.levels[index] maps 1:1 to a displayed
    // bar. Smoothing is a plain symmetric Behavior animation rather
    // than MusicBars' own asymmetric fast-attack/slow-decay tick()
    // timer -- simpler, and good enough for v1; the snappier asymmetric
    // feel is a nice-to-have polish pass, not core plumbing.
    Item {
      anchors.fill: parent

      readonly property real sliver: 2

      function levelAt(i) {
        var l = feed.levels
        return (l && i < l.length) ? l[i] : 0
      }

      // A single theme accent with subtle per-band lightness shading, not
      // a two-color gradient -- direct port of Ryoku's own reasoning
      // (Singletons/Scheme.qml's header comment): "the spectrum paints
      // in the accent the rest of the shell uses... pushing every band a
      // fixed step off the wallpaper is what used to send it near-white
      // on a dark picture." Bass bands sit slightly darker, treble
      // slightly lighter, but every band stays the same hue as
      // Color.accent -- the same color the bar/notch already use.
      function bandColor(i, level) {
        var t = feed.bands > 1 ? i / (feed.bands - 1) : 0.5
        var shade = 0.82 + 0.36 * t + 0.25 * level
        return shade >= 1 ? Qt.lighter(Color.accent, shade) : Qt.darker(Color.accent, 1 / shade)
      }

      Repeater {
        model: feed.bands

        Rectangle {
          id: bar
          required property int index
          readonly property real level: parent.levelAt(index)
          readonly property real slot: (root.barsHoriz ? parent.height : parent.width) / Math.max(1, feed.bands)
          // 0.68 of the slot, not the fixed few-pixel cap MusicBars.qml's
          // own formula uses -- direct live report ("the gaps between
          // the bar is alot, it looks like baby tooth"). That cap makes
          // sense for MusicBars' own small embedded-bar-widget context
          // (narrow width, small slots, so the cap is rarely the
          // binding constraint); here the full-screen overlay hands out
          // much wider slots per bar, so a tiny fixed cap left almost
          // the whole slot empty. Ryoku's own real default (Config.qml's
          // adapter.thickness: 0.58) confirms a slot-proportional
          // fraction, not a fixed pixel count, is the right shape here.
          readonly property real thick: Math.max(2, slot * 0.68)
          readonly property real grow: Math.max(parent.sliver, (root.barsHoriz ? parent.width : parent.height) * level)

          width: root.barsHoriz ? grow : thick
          height: root.barsHoriz ? thick : grow
          x: root.barsHoriz ? (parent.width - width) / 2 : (index * slot + (slot - thick) / 2)
          y: root.barsHoriz ? (index * slot + (slot - thick) / 2) : (parent.height - height)
          radius: Math.min(width, height) / 2
          antialiasing: true
          color: parent.bandColor(index, level)

          Behavior on height { enabled: !root.barsHoriz; NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
          Behavior on width { enabled: root.barsHoriz; NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
        }
      }
    }
  }
}
