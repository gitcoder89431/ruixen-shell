import QtQuick
import qs.Ui
import qs.Commons

// Same idle service the stock indicators cluster uses ("omarchy.idle",
// see /usr/share/omarchy/shell/plugins/services/idle/Service.qml), just as
// its own always-visible bar-widget instead of a conditionally-concealed
// indicator that only shows on hover. Ported from
// plugins/bar/indicators/StayAwake.qml, minus the BarIndicator base's
// hover-reveal/dim machinery -- this always renders plainly, active or not.
BarWidget {
  id: root
  moduleName: "ruixen.stayawake"

  readonly property var idleService: bar ? bar.shell.firstPartyServiceFor("omarchy.idle") : null
  readonly property bool stayAwake: idleService ? idleService.stayAwake : false

  function toggle() {
    if (root.idleService) root.idleService.setIdleEnabled(root.stayAwake)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰅶"
    dimmed: !root.stayAwake
    tooltipText: root.stayAwake ? "Allow Idle Lock & Screensaver" : "Stay Awake"
    onPressed: function() { root.toggle() }
  }
}
