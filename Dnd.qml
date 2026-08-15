import QtQuick
import qs.Ui
import qs.Commons

// Same notifications service the stock indicators cluster uses
// ("omarchy.notifications"), just as its own always-visible bar-widget
// instead of a conditionally-concealed indicator that only shows on hover.
// Ported from plugins/bar/indicators/Dnd.qml, minus the BarIndicator base's
// hover-reveal/dim machinery -- this always renders plainly, active or not.
BarWidget {
  id: root
  moduleName: "ruixen.dnd"

  readonly property var notificationService: bar ? bar.shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property bool dnd: notificationService ? notificationService.doNotDisturb : false

  function toggle() {
    if (root.notificationService) root.notificationService.setDoNotDisturb(!root.dnd)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "󰂛"
    dimmed: !root.dnd
    tooltipText: root.dnd ? "Allow Notifications" : "Silence Notifications"
    onPressed: function() { root.toggle() }
  }
}
