import QtQuick

// Independent desktop/preview overlay. CRT is static; rain updates at 10 fps.
Item {
  id:root
  property string effect:"none"
  property real intensity:.25
  property real speed:1
  property bool disableMotion:false
  property bool active:true
  property color accent:"#3ecf5b"
  property real seconds:0
  visible:active && effect!=="none" && intensity>0
  layer.enabled:effect==="matrix" && visible
  layer.textureSize:Qt.size(640,Math.max(1,Math.round(640*height/Math.max(1,width))))
  Timer {
    interval:100; repeat:true
    running:root.visible && root.effect==="matrix" && !root.disableMotion
    onTriggered:root.seconds+=.1*root.speed
  }
  ShaderEffect {
    anchors.fill:parent
    property real time:root.disableMotion ? 0 : root.seconds
    property vector2d resolution:Qt.vector2d(width,height)
    property real mode:root.effect==="matrix" ? 1 : 0
    property real strength:root.intensity
    property color tint:root.accent
    fragmentShader:Qt.resolvedUrl("shaders/ambient.frag.qsb")
  }
}
