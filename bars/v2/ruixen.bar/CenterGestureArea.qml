import QtQuick
import qs.Commons

// MouseArea for double-click-to-toggle-transparency and drag-to-move-bar
// gestures, sitting over the bar's center section.
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 4) as a pure file
// move: this was previously `component CenterGestureArea: MouseArea { ... }`
// declared inline inside Bar.qml's own `Item { id: root }`. barRoot is
// the explicit back-reference every `root.foo` read was rewritten to go
// through, wired at each of this component's instantiation sites
// (`barRoot: <the enclosing scope's own barRoot>`). No behavior change
// from this move.
MouseArea {
  id: gestureArea

  required property Item barRoot

  property bool dragging: false
  property bool suppressClick: false
  property real pressedX: 0
  property real pressedY: 0
  readonly property real dragThreshold: Style.space(4)

  acceptedButtons: Qt.LeftButton
  cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
  pressAndHoldInterval: 200

  function startDrag(x, y) {
    // Disabled: ruixen.bar's inset/padding (frameInset, the extra
    // left/right content padding) is hardcoded for position === "top"
    // to clear ruixen.frame-widget's rounded corners. Dragging to
    // left/right/bottom would look wrong there — no matching insets for
    // those edges. Re-enable once those positions get their own inset
    // handling, if ever needed.
    return
  }

  onPressed: function(mouse) {
    dragging = false
    suppressClick = false
    pressedX = mouse.x
    pressedY = mouse.y
  }

  onPressAndHold: function(mouse) {
    startDrag(mouse.x, mouse.y)
  }

  onPositionChanged: function(mouse) {
    if (!(mouse.buttons & Qt.LeftButton)) return

    if (!dragging) {
      var distance = Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY)
      if (distance < dragThreshold) return
      startDrag(mouse.x, mouse.y)
      return
    }

    var scenePoint = gestureArea.mapToItem(null, mouse.x, mouse.y)
    gestureArea.barRoot.updateBarMove(gestureArea.barRoot.windowScreenPoint(scenePoint, gestureArea.barRoot.barMoveWindow))
  }

  onReleased: function(mouse) {
    if (!dragging) return
    dragging = false
    suppressClick = true
    gestureArea.barRoot.finishBarMove()
    mouse.accepted = true
  }

  onCanceled: {
    dragging = false
    suppressClick = false
    gestureArea.barRoot.clearBarMove()
  }

  onClicked: function(mouse) {
    if (suppressClick) {
      suppressClick = false
      mouse.accepted = true
    }
  }

  onDoubleClicked: function(mouse) {
    if (suppressClick) {
      suppressClick = false
      return
    }
    if (mouse.button === Qt.LeftButton) {
      gestureArea.barRoot.toggleTransparency()
      mouse.accepted = true
    }
  }
}
