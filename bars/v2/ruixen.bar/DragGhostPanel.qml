import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Commons
import qs.Ui

// Per-screen ghost window shown while dragging a bar widget between
// slots.
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 2) as a pure file
// move: this was previously `component DragGhostPanel: PanelWindow { ... }`
// declared inline inside Bar.qml's own `Item { id: root }`. barRoot is
// the explicit back-reference every `root.foo` read was rewritten to go
// through, wired at this component's one instantiation site
// (`barRoot: root`). No behavior change from this move.
PanelWindow {
  id: ghostWindow

  required property Item barRoot
  required property var ghostScreen
  readonly property bool screenMatches: ghostWindow.barRoot.barDragScreen === ghostScreen ||
    (ghostWindow.barRoot.barDragScreen && ghostScreen && ghostWindow.barRoot.barDragScreen.name && ghostScreen.name && ghostWindow.barRoot.barDragScreen.name === ghostScreen.name)
  readonly property bool active: ghostWindow.barRoot.barDragSource && ghostWindow.barRoot.barDragScreen && screenMatches
  readonly property var sourceItem: ghostWindow.barRoot.barDragSource ? ghostWindow.barRoot.barDragSource.activeItem : null
  readonly property int ghostPadding: Style.space(1)
  readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
  readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

  visible: active && sourceItem !== null
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "omarchy-bar-drag-ghost"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Visual-only drag feedback. Keep the input region empty so the ghost can
  // sit under the cursor without stealing the MouseArea's active pointer grab.
  mask: Region {}

  Item {
    visible: ghostWindow.visible
    x: Math.round(ghostWindow.barRoot.barDragScreenX - ghostWindow.barRoot.barDragOffsetX - ghostWindow.ghostPadding)
    y: Math.round(ghostWindow.barRoot.barDragScreenY - ghostWindow.barRoot.barDragOffsetY - ghostWindow.ghostPadding)
    width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
    height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

    BorderSurface {
      anchors.fill: parent
      color: ghostWindow.barRoot.transparent ? "transparent" : ghostWindow.barRoot.background
      borderSpec: Border.flat(ghostWindow.barRoot.barForeground, 1)
      radius: Math.min(Style.cornerRadius, height / 2)
      opacity: ghostWindow.barRoot.transparent ? 0.45 : 0.94
    }

    Image {
      anchors.fill: parent
      anchors.margins: ghostWindow.ghostPadding
      source: ghostWindow.barRoot.barDragImageUrl
      fillMode: Image.Stretch
      smooth: true
      opacity: 0.84
    }
  }

  Rectangle {
    readonly property var targetRect: ghostWindow.barRoot.barDragTargetGeometry

    visible: ghostWindow.active && targetRect !== null
    x: targetRect ? Math.round(targetRect.x) : 0
    y: targetRect ? Math.round(targetRect.y) : 0
    width: targetRect ? targetRect.width : 0
    height: targetRect ? targetRect.height : 0
    color: Color.accent
    radius: Math.min(width, height) / 2
  }
}
