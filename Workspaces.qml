import QtQuick
import Quickshell.Hyprland
import qs.Commons
import qs.Ui

// GNOME/Ubuntu-style workspace switcher -- small dots for inactive
// workspaces, the focused one stretching into a wider horizontal pill,
// instead of the real omarchy.workspaces' numbered digits. Per direct
// request ("swap from digits to like the linux kinda one with the dots
// and bar... i think it will look better more softer").
//
// Reads the exact same real data/dispatch mechanism as
// omarchy.workspaces (confirmed by reading that file directly:
// /usr/share/omarchy/shell/plugins/bar/widgets/Workspaces.qml) --
// Quickshell.Hyprland's own workspaces/focusedWorkspace, hyprctl
// dispatch to focus. Own plugin, not an edit to that file, because
// omarchy.workspaces is Omarchy-owned (wiped on every omarchy-update,
// never a customization target per this project's own standing rule) --
// the underlying logic didn't need reinventing, just a different
// rendering of the same state.
BarWidget {
  id: root
  moduleName: "ruixen.workspaces"

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }
    return null
  }

  // Same padding-to-5 + append-any-higher-active-ones logic as the
  // real widget, verbatim.
  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }
    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  // Dot/pill geometry -- classic GNOME Shell look: small round dots,
  // the focused one stretches into a horizontal capsule instead of
  // just changing color or swapping a glyph.
  readonly property int dotSize: 8
  readonly property int pillWidth: 20
  readonly property int itemSpacing: 6

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  Row {
    id: row
    anchors.centerIn: parent
    spacing: root.itemSpacing

    Repeater {
      model: root.workspaceIds()

      Item {
        id: indicator
        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property bool occupied: workspace !== null && workspace.toplevels.values.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        width: focused ? root.pillWidth : root.dotSize
        height: root.dotSize
        anchors.verticalCenter: parent.verticalCenter

        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }

        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: indicator.focused ? Color.accent : Color.foreground
          opacity: indicator.focused ? 1 : (indicator.occupied ? 0.6 : 0.3)
          Behavior on color { ColorAnimation { duration: 180 } }
          Behavior on opacity { NumberAnimation { duration: 180 } }
        }

        MouseArea {
          anchors.fill: parent
          // Small dots need a much bigger real hit target than their
          // own visual size -- same -N margin pattern used throughout
          // this project's other small-icon click targets.
          anchors.margins: -6
          cursorShape: Qt.PointingHandCursor
          onClicked: root.focusWorkspace(indicator.modelData)
        }
      }
    }
  }
}
