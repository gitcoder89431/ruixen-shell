import QtQuick
import qs.Ui
import qs.Commons

// Opens ruixen.launcher's own Settings extension directly, not the
// standalone ruixen.settings overlay plugin -- direct request: "lets
// start using our new setting in launcher then and for the bar icon
// too? opens the new setting page?" (phasing out ruixen.settings as
// the primary entry point, same follow-through as the Super+Shift+R
// keybind in bindings.lua). Payload shape matches Launcher.qml's own
// open(payloadJson) -- see its header comment. No direct dependency on
// either plugin's repo here, same as before -- this widget just shells
// out to the same real command any keybind or script would use. Left
// side of the bar, next to ruixen.applauncher/ruixen.workspaces, per
// direct request ("a button on my bar next to the window to toggle
// it"). Gear glyph matches ruixen.settings' own panel header icon
// (fa-gear, U+F013), still accurate -- the Settings extension it now
// opens is the same visual/functional successor.
BarWidget {
  id: root
  moduleName: "ruixen.settingsbutton"

  function toggleSettings() {
    if (root.bar) root.bar.run("omarchy-shell shell toggle ruixen.launcher '{\"extension\":\"settings\"}'")
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
