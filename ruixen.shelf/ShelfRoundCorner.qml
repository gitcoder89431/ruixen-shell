import QtQuick

// One quarter-circle wedge, used as material for the Shelf's concave "wing"
// shoulders. A copy of ruixen.notch's own RoundCorner, which is an INLINE
// component inside that plugin's Overlay.qml (not a shared type -- importing
// it from elsewhere is the "RoundCorner is not a type" trap AGENTS.md
// section 8 warns about), so this plugin keeps its own, per the repo's
// "each surface keeps its own copy" convention (AGENTS.md section 9).
//
// A quarter-circle arc of radius `cornerSize`, centered on the box's
// diagonally opposite corner, closed off by a line back to this wedge's own
// sharp corner. `corner` is a plain int: 0 TopLeft, 1 TopRight,
// 2 BottomLeft, 3 BottomRight.
Item {
  id: rc
  property int corner: 0
  property int cornerSize: 20
  property color fillColor: "#ffffff"

  implicitWidth: cornerSize
  implicitHeight: cornerSize

  onFillColorChanged: canvas.requestPaint()
  onCornerChanged: canvas.requestPaint()
  onCornerSizeChanged: canvas.requestPaint()
  onVisibleChanged: if (visible) canvas.requestPaint()

  readonly property var cornerGeometry: ([
    { centerX: 1, centerY: 1, startAngle: Math.PI, endAngle: 1.5 * Math.PI, pointX: 0, pointY: 0 },
    { centerX: 0, centerY: 1, startAngle: 1.5 * Math.PI, endAngle: 2 * Math.PI, pointX: 1, pointY: 0 },
    { centerX: 1, centerY: 0, startAngle: 0.5 * Math.PI, endAngle: Math.PI, pointX: 0, pointY: 1 },
    { centerX: 0, centerY: 0, startAngle: 0, endAngle: 0.5 * Math.PI, pointX: 1, pointY: 1 }
  ])

  Canvas {
    id: canvas
    anchors.fill: parent
    antialiasing: true
    onPaint: {
      var ctx = getContext("2d")
      var size = rc.cornerSize
      var g = rc.cornerGeometry[rc.corner]
      ctx.clearRect(0, 0, width, height)
      if (!g) return

      ctx.beginPath()
      ctx.arc(g.centerX * size, g.centerY * size, size, g.startAngle, g.endAngle)
      ctx.lineTo(g.pointX * size, g.pointY * size)
      ctx.closePath()
      ctx.fillStyle = rc.fillColor
      ctx.fill()
    }
  }
}
