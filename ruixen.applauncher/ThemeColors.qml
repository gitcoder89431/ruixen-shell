import QtQuick
import Quickshell
import Quickshell.Io

// Extra theme-palette roles Omarchy's own Color.qml singleton (qs.Commons,
// /usr/share/omarchy/shell/Commons/Color.qml) doesn't expose -- it only
// parses foreground/background/accent/muted/red (aliased to `urgent`) out
// of colors.toml. Every theme's own colors.toml additionally defines a
// full ANSI-style ramp -- yellow/orange/green/cyan/blue/magenta/brown --
// confirmed directly across several real themes (this repo's own Aura
// Soft, plus Omarchy's stock retro-82/nord/catppuccin), already used by
// Omarchy's own generated per-app theme files (e.g.
// /usr/share/omarchy/default/themed/btop.theme.tpl maps its CPU/Memory/
// Network box outlines to magenta/green/red). This reads the exact same
// file Color.qml itself reads, same regex shape, just capturing the roles
// it leaves out -- so a widget can be genuinely theme-aware (whatever
// color THIS theme's own colors.toml defines) instead of hardcoding one
// theme's specific hex values.
//
// Not a pragma Singleton -- cross-plugin singleton visibility isn't
// guaranteed the way Omarchy's own qs.Commons is (that's the host shell's
// own global import path, not something a plugin folder can vouch for).
// Instantiate one copy per plugin that needs it, same "real copy, not a
// symlink" convention already used for AppLibrary.qml across ruixen.notch/
// ruixen.pinnedapps/ruixen.launcher.
QtObject {
  id: root

  readonly property string home: Quickshell.env("HOME")
  readonly property string currentThemePath: home + "/.local/state/omarchy/current/theme"

  // Neutral gray placeholders, not any one theme's real colors -- same
  // "obviously a fallback, never a real theme's own value" convention
  // Color.qml itself uses for its own foreground/background/accent
  // defaults. Only visible if colors.toml is ever missing/unreadable.
  property color red: "#999999"
  property color yellow: "#999999"
  property color orange: "#999999"
  property color green: "#999999"
  property color cyan: "#999999"
  property color blue: "#999999"
  property color magenta: "#999999"
  property color brown: "#999999"

  function load(raw) {
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var match = lines[i].match(/^\s*([A-Za-z0-9_-]+)\s*=\s*["']?(#[0-9A-Fa-f]{6})/)
      if (!match) continue
      switch (match[1]) {
        case "red": root.red = match[2]; break
        case "yellow": root.yellow = match[2]; break
        case "orange": root.orange = match[2]; break
        case "green": root.green = match[2]; break
        case "cyan": root.cyan = match[2]; break
        case "blue": root.blue = match[2]; break
        case "magenta": root.magenta = match[2]; break
        case "brown": root.brown = match[2]; break
      }
    }
  }

  property FileView colorsFile: FileView {
    // Same path Color.qml reads (~/.local/state/omarchy/current/theme is
    // the symlink Omarchy repoints on every theme switch). watchChanges:
    // false, matching Color.qml's own choice for this exact file -- a
    // theme switch restarts the whole shell (same way this plugin's own
    // colors reload today), so there's nothing this FileView would ever
    // need to notice mid-session that a restart doesn't already cover.
    path: root.currentThemePath + "/colors.toml"
    watchChanges: false
    printErrors: false
    onLoaded: root.load(text())
  }

  // Semantic vocabulary -- direct request ("i wanna be able to
  // communicate primary secondary and accent as token"), confirmed:
  // primary=green, secondary=blue. Deliberately mirrors Omarchy's own
  // /etc/fastfetch/config.jsonc, which colors the Arch logo itself
  // "green" and its Software block "blue" -- reusing those exact two
  // roles means "primary" already looks like the same green the Arch
  // logo shows in a terminal, not an arbitrarily different green.
  // "accent" is NOT a property here -- it's just Color.accent (qs.
  // Commons), same single theme-hero token already used everywhere
  // else in ruixen; this file only covers the two roles that singleton
  // doesn't expose.
  readonly property color primary: root.green
  readonly property color secondary: root.blue

  // A handful of real themes (Vantablack confirmed directly: EVERY
  // color role in its own colors.toml, including green/blue, is just a
  // shade of gray by design -- a genuinely monochrome theme, not a bug)
  // have no real hue for `primary` to carry at all. Direct guidance for
  // that case was explicit: "except for black then do the white/or
  // yellow instead" -- but hardcoding that to one theme's NAME would be
  // exactly the kind of one-theme special-case this whole exercise was
  // about avoiding (a second monochrome theme added later would silently
  // miss it). Chroma (max channel - min channel) is a cheap, theme-name-
  // agnostic proxy for "does this color have a real hue": 0 for any true
  // gray, large for a saturated color -- confirmed against real
  // colors.toml values (Vantablack's green #b6b6b6 -> chroma 0; Aura
  // Soft's #54c59f -> 113; retro-82's #028391 -> 143). A caller should
  // use `foreground` (Color.accent's own neighbor, already the theme's
  // adaptive white/cream/etc token) instead of `primary` whenever this
  // is true.
  function chroma(c) {
    var mx = Math.max(c.r, c.g, c.b)
    var mn = Math.min(c.r, c.g, c.b)
    return mx - mn
  }
  readonly property bool monochrome: root.chroma(root.primary) < (20 / 255)
}
