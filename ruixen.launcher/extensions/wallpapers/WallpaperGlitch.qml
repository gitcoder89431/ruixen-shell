import QtQuick

// Adapted from DasPoxy/Glitch-Launcher-Collection (MIT; GLITCH-LICENSE.txt).
Item {
  id: root
  property string fromPath: ""
  property string toPath: ""
  property string effect: "signal-tear"
  property real strength:.65
  property real density:1
  property real progress: 1
  property bool active: false
  property color accent: "#3ecf5b"
  readonly property int kind: effect === "datamosh" ? 1 : effect === "vhs" ? 2 : effect === "code-bleed" ? 4 : 0
  readonly property bool ready: oldImage.status===Image.Ready && newImage.status===Image.Ready
  function imageUrl(path) { return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : "" }
  visible: active && ready
  Image { id:oldImage; anchors.fill:parent; source:root.active && root.fromPath ? root.imageUrl(root.fromPath) : ""; fillMode:Image.PreserveAspectCrop; sourceSize:Qt.size(Math.max(1,width),Math.max(1,height)); visible:false; asynchronous:true }
  Image { id:newImage; anchors.fill:parent; source:root.active && root.toPath ? root.imageUrl(root.toPath) : ""; fillMode:Image.PreserveAspectCrop; sourceSize:Qt.size(Math.max(1,width),Math.max(1,height)); visible:false; asynchronous:true }
  ShaderEffectSource { id:oldTexture; sourceItem:oldImage; hideSource:true; live:root.active; visible:false }
  ShaderEffectSource { id:newTexture; sourceItem:newImage; hideSource:true; live:root.active; visible:false }
  ShaderEffect {
    anchors.fill:parent
    property var source: newTexture
    property var desk: oldTexture
    property real time: root.progress * 8
    property vector2d resolution: Qt.vector2d(width,height)
    property real intensity: Math.sin(root.progress*Math.PI)*.65
    property real seed: 17
    property real scanlines: 0
    property color tint: root.accent
    property real kind: root.kind
    property real trans: root.progress
    property real crt: 0
    property real closing: 0
    property vector2d shockCenter: Qt.vector2d(0,0)
    property real shockR: 0
    property real distortionStrength:root.strength
    property real density:root.density
    property real shockAmt: 0
    fragmentShader: Qt.resolvedUrl("shaders/glitch.frag.qsb")
  }
}
