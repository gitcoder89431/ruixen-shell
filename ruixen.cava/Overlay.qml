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
// Bars shipped first, a near-verbatim port of Ryoku's own
// shell/modules/bar/MusicBars.qml (a plain Repeater of Rectangle bars).
// Segments (direct follow-up, "lets do it") reuses every bit of this
// plumbing -- cava process management, live audio data, edge-docked
// overlay, peak-normalization, theme-color gradient, edge glow -- and
// only swaps each band's own visual for a stack of discrete blocks
// instead of one continuous pill, same "10 segments" default Ryoku's
// own VizItem.qml ships. A true "Waves" style (a smooth continuous
// curve, not a bars variant) is still its own, separate follow-up.
Item {
  id: root
  property var shell: null
  property var manifest: null

  // State read from ~/.local/state/ruixen/cava-visualizer.json --
  // written by ruixen.launcher/SettingsContent.qml's own Visualizer
  // category, same Settings-writes/this-reads split already
  // established for notch-visibility.json and applauncher-icon.json.
  property bool vizEnabled: false
  property string style: "bars"        // "bars" | "segments"
  // 10, matching Ryoku's own default (VizItem.qml's own
  // segments: item.val("segments", 10)) -- fixed, not a Settings
  // knob, same "don't need a lot of customization" approach the
  // other visual constants here (bloom's own intensity/spread) use.
  readonly property int segmentCount: 10
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
        root.style = (p && ["bars", "segments"].indexOf(p.style) >= 0) ? p.style : "bars"
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

  // Warm-center/cool-edge gradient, built from the ACTIVE theme's own
  // palette instead of a hardcoded rainbow -- direct follow-up:
  // "can we still have that color pattern where its warm and cool on
  // the edges for bass but instead of hardcoded color, we alrady have
  // the data from omarchy theme colors toml, so can we use the theme
  // colors". Same file qs.Commons's own Color singleton reads
  // (Commons/Color.qml's colorsFile), read again here directly rather
  // than pulling in Color's own dozen unrelated per-surface roles for
  // two colors -- watchChanges: true (Color's own copy isn't watched)
  // so a live theme switch retints the spectrum without a restart.
  // `red`/`blue` are the two roles present, and at genuinely different
  // hues, across every theme checked (Everforest, Catppuccin, Nord,
  // Gruvbox, Tokyo Night, Rose Pine, Hackerman, Lumon) -- including the
  // grayscale ones (White, Vantablack), where they simply resolve to
  // two close shades of gray instead of a hue split, matching those
  // themes' own monochrome intent rather than fighting it with a fake
  // rainbow.
  property color warmColor: Color.accent
  property color coolColor: Color.accent

  function parseThemeColor(raw, key, fallback) {
    var m = String(raw || "").match(new RegExp("^\\s*" + key + "\\s*=\\s*[\"']?(#[0-9A-Fa-f]{6})", "m"))
    return m ? m[1] : fallback
  }

  FileView {
    id: themeColorsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/colors.toml"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      var t = text()
      root.warmColor = root.parseThemeColor(t, "red", Color.accent)
      root.coolColor = root.parseThemeColor(t, "blue", Color.accent)
    }
    // Direct live report/repro: "im stuck on like the risotto colors
    // for the cava bars now, it doesn't switch theme colors anymore,
    // seems to be stuck?" Confirmed directly by instrumenting this
    // FileView: a theme switch replaces this file via an atomic
    // delete-then-recreate (its own mtime/inode are fresh on every
    // switch), which fires TWO file-change events -- the delete
    // usually lands a reload() in the brief window where the path
    // doesn't exist yet (onLoadFailed, caught here), then the recreate
    // fires a second event that reloads correctly. That self-heals
    // for one switch. Rapid switching (cycling through a theme
    // switcher/gallery) can land the LAST reload() attempt exactly on
    // a mid-swap gap with no further file event ever arriving to
    // retry it -- reproduced directly by scripting 5 switches ~300ms
    // apart, which left this stuck on the Color.accent fallback
    // (both warm and cool collapsed to the same flat color)
    // indefinitely, matching the reported symptom exactly. A short,
    // one-shot retry closes that gap without needing a real file
    // event to arrive.
    onLoadFailed: {
      root.warmColor = Color.accent
      root.coolColor = Color.accent
      themeColorsRetryTimer.restart()
    }
  }

  Timer {
    id: themeColorsRetryTimer
    interval: 200
    onTriggered: themeColorsFile.reload()
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

    // Bloom, take 2 -- direct follow-up after the first pass (a
    // blurred duplicate of the bars themselves): "not sure if i like
    // that, the blur is nice but its like contrasting with the sharp
    // bar, it doesnt look like drop shadow or something, looks more
    // like an artifact or dupe... i dont want it to look like floating
    // bars, it should spill in from the edges." A per-bar blur
    // duplicate reads as a second, slightly-offset copy of the same
    // shape (an "artifact") rather than ambient light -- this instead
    // washes color in from whichever screen edge the panel is docked
    // to, fading out toward the panel's own inner edge, same
    // root-at-the-edge/fade-inward direction the bars themselves
    // already use (see the bars' own y/x formulas below). Reacts to
    // feed.energy (the mean band level, computed every frame but
    // otherwise unused until now) so it breathes brighter on louder
    // passages instead of sitting at one fixed strength.
    // Toned down and pulled in tight to the edge -- direct live
    // follow-up: "maybe less wash out? so like distance of the bloom
    // is abit left? its the glow is abit too much yea its washing or
    // fading out the wallpaper." glowSpread is how far INTO the panel
    // (as a fraction of its own thickness) the wash reaches before
    // going fully transparent, instead of stretching across the
    // entire panel thickness -- 0.32 means it's already invisible by
    // a third of the way in, hugging the edge instead of washing the
    // whole strip. Base/energy opacity both cut roughly in half too.
    readonly property real glowBaseOpacity: 0.10
    readonly property real glowEnergyBoost: 0.28
    readonly property real glowSpread: 0.32
    readonly property bool glowEdgeAtStart: root.position === "top" || root.position === "left"
    readonly property color glowTint: Qt.rgba(
      (root.warmColor.r + root.coolColor.r) / 2,
      (root.warmColor.g + root.coolColor.g) / 2,
      (root.warmColor.b + root.coolColor.b) / 2, 1)

    Rectangle {
      anchors.fill: parent
      opacity: panel.glowBaseOpacity + panel.glowEnergyBoost * feed.energy
      gradient: Gradient {
        orientation: root.vertical ? Gradient.Horizontal : Gradient.Vertical
        // Opaque stop sits at whichever edge the panel actually
        // touches (same edge the bars root at); the transparent stop
        // sits glowSpread of the way toward the panel's own inner
        // edge, not all the way at it -- "spill in from the edges",
        // a tight wash, not a halo hugging the bar shapes or a wash
        // stretching the full strip.
        GradientStop { position: panel.glowEdgeAtStart ? 0.0 : 1.0; color: panel.glowTint }
        GradientStop { position: panel.glowEdgeAtStart ? panel.glowSpread : (1.0 - panel.glowSpread); color: Qt.rgba(panel.glowTint.r, panel.glowTint.g, panel.glowTint.b, 0) }
      }
    }

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
      id: barsData
      anchors.fill: parent

      readonly property real sliver: 2

      function levelAt(i) {
        var l = feed.levels
        return (l && i < l.length) ? l[i] : 0
      }

      // Warm center, cool edges -- direct follow-up after shipping a
      // single-accent shade ramp ("it look uhh kinda boring? especially
      // if we're gonna do waves and stuff next"). dist is 0 at the
      // middle band, 1 at either edge (a symmetric "V", not a left-to-
      // right sweep -- same shape github.com/pennyfx/omarchy-spectrum's
      // own barColor() uses), lerped between root.warmColor (center)
      // and root.coolColor (edges) instead of their fixed HSLA hue
      // ramp. Louder still lightens the result a little, same
      // level-reactive touch the single-accent version had.
      function bandColor(i, level) {
        var mid = feed.bands / 2
        var dist = feed.bands > 1 ? Math.abs(i - mid + 0.5) / mid : 0
        var c = Qt.rgba(
          root.warmColor.r + (root.coolColor.r - root.warmColor.r) * dist,
          root.warmColor.g + (root.coolColor.g - root.warmColor.g) * dist,
          root.warmColor.b + (root.coolColor.b - root.warmColor.b) * dist,
          1)
        return Qt.lighter(c, 1 + 0.35 * level)
      }

      Repeater {
        model: feed.bands

        // Per-band container, sized to the FULL potential growth range
        // (maxLen) always -- not just the current level's worth, the
        // way the single Bars pill used to size itself directly. Both
        // looks below now root/grow WITHIN this fixed footprint, so the
        // container's own position only ever handles the perpendicular
        // (across-bands) slot spacing; edge-rooting lives in each
        // look's own local x/y instead. That split is what makes
        // Segments possible without duplicating the slot/thick math a
        // second time -- both looks share this one container.
        Item {
          id: bandItem
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
          readonly property real maxLen: root.barsHoriz ? parent.width : parent.height
          readonly property real grow: Math.max(parent.sliver, maxLen * level)
          readonly property color col: parent.bandColor(index, level)

          width: root.barsHoriz ? maxLen : thick
          height: root.barsHoriz ? thick : maxLen
          x: root.barsHoriz ? 0 : (index * slot + (slot - thick) / 2)
          y: root.barsHoriz ? (index * slot + (slot - thick) / 2) : 0

          // Bars -- one continuous rounded pill. Vertical bars (Top/
          // Bottom docking) root at whichever screen edge the panel
          // actually touches and grow AWAY from it -- direct live
          // report after Top shipped still rooted at the panel's
          // bottom (growing up, same as Bottom): "we need to like flip
          // it around... we are kinda flipping it upside down so it
          // mirrors down, from the top down the bars." Bottom's root
          // (screen edge) is this container's own bottom, growing up --
          // already correct, since the container's bottom edge and the
          // screen's bottom edge are the same line there. Top's root is
          // the container's own top (y=0, growing down) instead, since
          // for a top-docked panel the screen edge is y=0, not the
          // container's bottom. Left/Right get the identical treatment
          // -- direct live follow-up: "for the left and right side,
          // same idea there, right now it seems like its mirror or
          // something on the side? i want it like flowing in same idea
          // as the top." These used to grow from the container's own
          // horizontal CENTER in both directions at once (ported as-is
          // from MusicBars.qml's own "horizontal" mode), which reads as
          // "mirrored" rather than rooted to the dock edge. Left roots
          // at x=0 and grows right; Right roots at the container's
          // right edge and grows left -- same "root at whichever edge
          // the panel actually touches, grow inward" rule Top/Bottom
          // already follow.
          Rectangle {
            visible: root.style !== "segments"
            width: root.barsHoriz ? bandItem.grow : bandItem.thick
            height: root.barsHoriz ? bandItem.thick : bandItem.grow
            x: (root.barsHoriz && root.position === "right") ? (bandItem.width - width) : 0
            y: (!root.barsHoriz && root.position === "bottom") ? (bandItem.height - height) : 0
            radius: Math.min(width, height) / 2
            antialiasing: true
            color: bandItem.col

            Behavior on height { enabled: !root.barsHoriz; NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
            Behavior on width { enabled: root.barsHoriz; NumberAnimation { duration: 90; easing.type: Easing.OutQuad } }
          }

          // Segments -- Ryoku's own default 10-block LED-meter look,
          // direct follow-up ("lets do it"). Same edge-rooted growth
          // direction as Bars (segment 0 sits nearest the screen edge,
          // ascending indices move inward), just chopped into discrete
          // blocks with small gaps instead of one continuous pill.
          // Unlit blocks stay dimly visible (a constant low opacity)
          // so the full potential range always reads, the same way a
          // real VU meter's unlit LEDs stay visible rather than
          // vanishing outright.
          Repeater {
            model: root.style === "segments" ? root.segmentCount : 0

            Rectangle {
              required property int index
              readonly property real segGap: 2
              readonly property real segLen: (bandItem.maxLen - (root.segmentCount - 1) * segGap) / root.segmentCount
              readonly property bool lit: bandItem.level * root.segmentCount > index

              width: root.barsHoriz ? segLen : bandItem.thick
              height: root.barsHoriz ? bandItem.thick : segLen
              radius: Math.min(width, height) / 4
              antialiasing: true
              color: bandItem.col
              opacity: lit ? 1.0 : 0.15

              x: root.barsHoriz
                ? ((root.position === "left")
                   ? index * (segLen + segGap)
                   : (bandItem.width - (index + 1) * segLen - index * segGap))
                : 0
              y: root.barsHoriz
                ? 0
                : ((root.position === "top")
                   ? index * (segLen + segGap)
                   : (bandItem.height - (index + 1) * segLen - index * segGap))

              Behavior on opacity { NumberAnimation { duration: 90 } }
            }
          }
        }
      }
    }
  }
}
