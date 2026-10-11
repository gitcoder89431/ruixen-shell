import QtQuick
import QtQuick.Effects
import Quickshell.Widgets

ClippingRectangle {
  id: root
  property string effect: "reveal"
  property string fromPath: ""
  property string toPath: ""
  property bool playing: false
  property real softness: 0.02
  property var transitionOptions:({})
  property bool ambientActive:false
  property string backgroundEffect:"none"
  property real backgroundIntensity:.25
  property real backgroundSpeed:1
  property bool disableMotion:false
  readonly property bool glitchTransition:["signal-tear","datamosh","vhs","code-bleed"].indexOf(effect)>=0
  property real progress: 0
  property int durationMs: 420
  property color accent: "#3ecf5b"
  function imageUrl(path) { return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : "" }
  radius: 10
  color: Qt.rgba(accent.r,accent.g,accent.b,.08)
  border.width: 1
  border.color: Qt.rgba(accent.r,accent.g,accent.b,.3)
  readonly property bool imagesReady: (!fromPath || fromImage.status === Image.Ready) && (!toPath || toImage.status === Image.Ready) && (!glitchTransition || glitchPreview.ready)
  function restartPreview() {
    loop.stop()
    progress=0
    if (!playing || !imagesReady) return
    if (durationMs === 0) { loop.stop(); progress=1 }
    else loop.restart()
  }
  onEffectChanged: restartPreview()
  onDurationMsChanged: restartPreview()
  onPlayingChanged: restartPreview()
  onImagesReadyChanged: restartPreview()
  onFromPathChanged: restartPreview()
  onToPathChanged: restartPreview()
  Rectangle { anchors.fill:parent; color:Qt.rgba(root.accent.r,root.accent.g,root.accent.b,.18) }
  Image { id:fromImage; anchors.fill:parent; source:root.fromPath ? root.imageUrl(root.fromPath) : ""; fillMode:Image.PreserveAspectCrop; asynchronous:true; sourceSize:Qt.size(360,220) }
  Item {
    anchors.fill:parent
    visible: root.playing && !root.glitchTransition
    layer.enabled: root.playing
    opacity: root.effect === "bleed" ? root.progress : 1
    layer.effect: MultiEffect { maskEnabled:root.effect !== "bleed"; maskSource:previewMask; maskThresholdMin:.5; maskSpreadAtMin:root.softness }
    Rectangle { anchors.fill:parent; color:root.accent }
    Image { id:toImage; anchors.fill:parent; source:root.toPath ? root.imageUrl(root.toPath) : ""; fillMode:Image.PreserveAspectCrop; asynchronous:true; sourceSize:Qt.size(360,220) }
  }
  WallpaperGlitch {
    id:glitchPreview
    anchors.fill:parent
    active:root.playing && root.glitchTransition
    fromPath:root.fromPath; toPath:root.toPath
    strength:(root.transitionOptions[root.effect] || {}).strength===undefined ? .65 : root.transitionOptions[root.effect].strength
    density:(root.transitionOptions[root.effect] || {}).density || 1
    effect:root.effect; progress:root.progress; accent:root.accent
  }
  WallpaperAmbient {
    anchors.fill:parent
    effect:root.backgroundEffect; intensity:root.backgroundIntensity; speed:root.backgroundSpeed
    disableMotion:root.disableMotion; active:root.ambientActive; accent:root.accent
  }
  WallpaperTransitionMask { id:previewMask; anchors.fill:parent; effect:root.effect; progress:root.progress; active:root.playing && !root.glitchTransition }
  SequentialAnimation {
    id:loop
    loops:Animation.Infinite
    PropertyAction { target:root; property:"progress"; value:0 }
    NumberAnimation { target:root; property:"progress"; from:0; to:1; duration:root.durationMs; easing.type:Easing.InOutCubic }
    PauseAnimation { duration:450 }
  }
}
