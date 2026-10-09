import QtQuick
import qs.Ui
import qs.Commons

// Discoverability icon for ruixen.launcher -- direct request: "for the
// bar, im thinking about adding a magnify glass icon to the right of
// the pluginspin icon. it will open the super r ruixen launcher,
// apparentely people dont even know it exists lol". Same shell-out
// pattern as ruixen.settingsbutton right next to it: no direct
// dependency on ruixen.launcher's own repo, just the same command the
// SUPER+R keybind in bindings.lua already runs. No payload, unlike
// settingsbutton's own extension-scoped toggle -- this opens the
// launcher's default/root page, same as the plain keybind.
BarWidget {
  id: root
  moduleName: "ruixen.launcherbutton"

  function toggleLauncher() {
    if (root.bar) root.bar.run("omarchy-shell shell toggle ruixen.launcher")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    foreground: root.bar ? root.bar.iconForeground : "#ffffff"
    tooltipText: "Ruixen Launcher"
    onPressed: function() { root.toggleLauncher() }
  }
}
