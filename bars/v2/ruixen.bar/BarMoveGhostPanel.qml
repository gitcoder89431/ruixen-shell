import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// Per-screen ghost window shown while dragging the whole bar to
// reposition it.
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 2) as a pure file
// move: this was previously `component BarMoveGhostPanel: PanelWindow { ... }`
// declared inline inside Bar.qml's own `Item { id: root }`. barRoot is
// the explicit back-reference every `root.foo` read was rewritten to go
// through, wired at this component's one instantiation site
// (`barRoot: root`). No behavior change from this move.
PanelWindow {
  id: moveGhostWindow

  required property Item barRoot
  required property var ghostScreen
  readonly property bool screenMatches: moveGhostWindow.barRoot.barMoveScreen === ghostScreen ||
    (moveGhostWindow.barRoot.barMoveScreen && ghostScreen && moveGhostWindow.barRoot.barMoveScreen.name && ghostScreen.name && moveGhostWindow.barRoot.barMoveScreen.name === ghostScreen.name)
  visible: moveGhostWindow.barRoot.barMoveActive && screenMatches
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-bar-move-ghost"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Visual-only preview of the candidate edge. Keep the input region empty
  // so the overlay never steals the gesture area's active pointer grab.
  mask: Region {}

  // One fixed-geometry slab per edge, crossfaded on candidate changes.
  // Resizing a single slab between edges repaints mid-transition and
  // flickers; fading between static ones does not.
  Repeater {
    model: ["top", "bottom", "left", "right"]

    BorderSurface {
      id: edgeSlab

      required property string modelData
      readonly property bool edgeVertical: modelData === "left" || modelData === "right"
      readonly property int edgeSize: edgeVertical ? Style.bar.sizeVertical : Style.bar.sizeHorizontal

      x: modelData === "right" ? parent.width - edgeSize : 0
      y: modelData === "bottom" ? parent.height - edgeSize : 0
      width: edgeVertical ? edgeSize : parent.width
      height: edgeVertical ? parent.height : edgeSize
      color: moveGhostWindow.barRoot.transparent ? "transparent" : moveGhostWindow.barRoot.background
      borderSpec: Border.flat(moveGhostWindow.barRoot.barForeground, 1)
      visible: opacity > 0
      opacity: moveGhostWindow.barRoot.barMoveCandidate === modelData ? (moveGhostWindow.barRoot.transparent ? 0.45 : 0.7) : 0

      Behavior on opacity {
        NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
      }
    }
  }
}
