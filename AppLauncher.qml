import QtQuick
import qs.Ui
import qs.Commons

// Separate from omarchy.menu's own icon on purpose -- that one stays wired
// to Super+Space via the stock omarchy-menu CLI (can't be touched, see
// ruixen-notch's README for why cloning it breaks that keybind). This is
// its own icon that opens ruixen.notch's own launcher mode instead, via
// Quickshell's native IPC (qs ipc call), not the omarchy-menu CLI.
BarWidget {
  id: root
  moduleName: "ruixen.applauncher"

  function toggleLauncher() {
    if (root.bar) root.bar.run("qs -p /usr/share/omarchy/shell ipc call ruixen.notch toggleLauncher")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Grid glyph, not a magnifying glass -- the launcher itself dropped
    // search entirely (a few favorite-app icons now, see ruixen-notch),
    // so a grid reads truer to what actually opens.
    text: "󰕰"
    tooltipText: "App Launcher"
    onPressed: function() { root.toggleLauncher() }
  }
}
