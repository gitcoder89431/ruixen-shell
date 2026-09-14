import QtQuick
import qs.Ui

// Separate from omarchy.menu's own icon on purpose -- that one stays wired
// to Super+Space via the stock omarchy-menu CLI (can't be touched, see
// ruixen-notch's README for why cloning it breaks that keybind). This is
// its own icon that opens ruixen.notch's own launcher mode instead, via
// omarchy-shell's IPC front door, not the omarchy-menu CLI.
BarWidget {
  id: root
  moduleName: "ruixen.applauncher"

  // omarchy-shell, not a raw `qs -p /usr/share/omarchy/shell ipc call`
  // -- direct review finding ("Replace hardcoded /usr/share/omarchy/
  // shell IPC calls with omarchy-shell", #24): see
  // WallpapersContent.qml's own comment on the same fix for the full
  // "why" (resolves $OMARCHY_PATH itself, real IPC timeout instead of
  // none). No -q -- opening the launcher IS the whole point of this
  // click, so a real failure should still be visible in the journal.
  function toggleLauncher() {
    if (root.bar) root.bar.run("omarchy-shell ruixen.notch toggleLauncher")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Arch Linux logo -- direct follow-up ("instead of the home,
    // can we use the arch linux icon... the house is appearing kinda
    // small in some screen ive seen people share, not sure why").
    // Root cause: BarIconButton's own OpticalGlyph (qs.Ui) only
    // recenters a glyph horizontally within its box (tightBoundingRect-
    // based), it doesn't scale a glyph up to compensate for one whose
    // own ink shape is naturally thin/sparse within its em-square --
    // a house OUTLINE (thin strokes, lots of internal empty space) is
    // exactly that case, so it read smaller than bulkier glyphs at the
    // same nominal size. linux-archlinux (U+F303) is a denser filled
    // shape, same font family already used everywhere else in this
    // repo -- confirmed present in JetBrainsMonoNerdFont's own cmap
    // directly, not guessed.
    text: ""
    // No custom `foreground` override -- back to BarIconButton's own
    // plain default (bar.barForeground/Color.foreground), same as every
    // other static bar icon. Direct follow-up after trying both
    // primary/themeGreen and Color.accent here: coloring every always-on
    // decorative icon (this one, plugins, settings, info) would turn
    // accent into visual noise instead of a real signal -- "i feel like
    // thats a bit too much accent... maybe best arch just stays surface
    // white or yellow? seems most balance". Accent stays reserved for
    // actual state (the workspace switcher's focused dot).
    tooltipText: "App Launcher"
    onPressed: function() { root.toggleLauncher() }
  }
}
