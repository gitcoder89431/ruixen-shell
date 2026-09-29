import QtQuick

// The small concave wing piece a shape needs ADDED at a corner to flow
// smoothly into whatever continues past its edge, not a Rectangle
// corner cut (which recedes into the shape instead) -- a standard
// technique for this (a quarter-circle arc plus a straight line back
// to the box's own sharp corner) common to plenty of canvas-based UI
// work, written here as a data table rather than a branch per corner.
// Used for the docked pill groups' open-facing shoulder, same
// technique ruixen.notch's own two shoulders use.
//
// Extracted out of Bar.qml (issue #78 Phase 6 -- stage 2) as a pure file
// move: unlike most of this file's other inline components, this one
// reads nothing off the enclosing root Item at all (every property --
// corner/size/color -- is set externally at each instantiation site),
// so it needed no back-reference wiring, just relocating.
Item {
  id: cornerRoot
  // Plain strings, not an enum -- a `component`-local enum's
  // qualified values don't resolve from inside an inline component.
  // One of: "topLeft", "topRight", "bottomLeft", "bottomRight".
  property string corner: "topLeft"
  property int size: 25
  property color color: "#000000"

  onColorChanged: cornerCanvas.requestPaint()
  onCornerChanged: cornerCanvas.requestPaint()
  onSizeChanged: cornerCanvas.requestPaint()
  onVisibleChanged: if (visible) cornerCanvas.requestPaint()

  // implicitWidth/Height alone only sizes this when something else (a
  // Layout, or a wrapper's anchors.fill) reads it -- placed as a bare
  // sibling Item like it is below, that never happens and it
  // silently renders at 0x0. Set the real size directly.
  width: size
  height: size
  implicitWidth: size
  implicitHeight: size

  // Every corner's wedge is the same shape, just rotated 90 degrees
  // at a time: a quarter-circle arc of radius `size`, centered on the
  // box's DIAGONALLY OPPOSITE corner (so the arc passes exactly
  // through the box's other two corners), closed off by a straight
  // line back to this wedge's own sharp corner. centerX/centerY/
  // pointX/pointY below are 0-or-1 multipliers of `size`, not raw
  // pixel values, so the same four numbers describe all four corners
  // without repeating a size-dependent literal per case.
  readonly property var cornerGeometry: ({
    topLeft: { centerX: 1, centerY: 1, startAngle: Math.PI, endAngle: 1.5 * Math.PI, pointX: 0, pointY: 0 },
    topRight: { centerX: 0, centerY: 1, startAngle: 1.5 * Math.PI, endAngle: 2 * Math.PI, pointX: 1, pointY: 0 },
    bottomLeft: { centerX: 1, centerY: 0, startAngle: 0.5 * Math.PI, endAngle: Math.PI, pointX: 0, pointY: 1 },
    bottomRight: { centerX: 0, centerY: 0, startAngle: 0, endAngle: 0.5 * Math.PI, pointX: 1, pointY: 1 }
  })

  Canvas {
    id: cornerCanvas
    anchors.fill: parent
    antialiasing: true
    onPaint: {
      var ctx = getContext("2d")
      var size = cornerRoot.size
      var g = cornerRoot.cornerGeometry[cornerRoot.corner]
      ctx.clearRect(0, 0, width, height)
      if (!g) return

      ctx.beginPath()
      ctx.arc(g.centerX * size, g.centerY * size, size, g.startAngle, g.endAngle)
      ctx.lineTo(g.pointX * size, g.pointY * size)
      ctx.closePath()
      ctx.fillStyle = cornerRoot.color
      ctx.fill()
    }
  }
}
