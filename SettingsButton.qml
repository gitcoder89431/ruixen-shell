import QtQuick
import qs.Ui
import qs.Commons

// Toggles the standalone ruixen.settings overlay plugin (a separate repo,
// no direct dependency between the two -- this widget just shells out to
// the same real command any keybind or script would use). Left side of
// the bar, next to ruixen.applauncher/ruixen.workspaces, per direct
// request ("a button on my bar next to the window to toggle it").
// Gear glyph matches ruixen.settings' own panel header icon (fa-gear,
// U+F013) so the button and what it opens read as the same thing.
BarWidget {
  id: root
  moduleName: "ruixen.settingsbutton"

  function toggleSettings() {
    if (root.bar) root.bar.run("omarchy-shell shell toggle ruixen.settings")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    tooltipText: "Settings"
    onPressed: function() { root.toggleSettings() }
  }
}
