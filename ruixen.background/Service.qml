import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "AppearanceModel.js" as AppearanceModel

// Native renderer: public layer-shell/IPC APIs, no private Omarchy imports.
// Stock compatibility IPC is active only while this optional replacement is enabled.
Item {
  id: root
  readonly property string home: Quickshell.env("HOME")
  property var settings: AppearanceModel.normalize({})
  property color accent: "#7aa2f7"
  property string currentPath: ""
  property string displayedPath: ""
  property string oldPath: ""
  property string incomingPath: ""
  property string finalPath: ""
  property int generation: 0
  property int readGeneration: 0
  property real progress: 1
  property bool finishing: false
  property bool mediaPlaying: false
  property string pendingTheme: ""
  property string errorText: ""
  readonly property string effect: settings.transitionEffect || "reveal"
  readonly property int durationMs: settings.transitionDurationMs === undefined ? 420 : settings.transitionDurationMs
  readonly property bool motionDisabled: settings.disableMotion === true
  readonly property bool glitch: ["signal-tear","datamosh","vhs","code-bleed"].indexOf(effect)>=0

  function imageUrl(path) { return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : "" }
  function transition(from, path, final, instant, force) {
    if (!path || (!instant && !force && final === currentPath)) return
    animation.stop()
    generation++
    currentPath=final || path
    finalPath=currentPath
    finishing=false
    errorText=""
    if (instant || motionDisabled || durationMs===0 || !displayedPath) {
      displayedPath=finalPath; oldPath=""; incomingPath=""; progress=1
      return
    }
    oldPath=from || displayedPath
    incomingPath=path
    progress=0
    loadDeadline.restart()
  }
  function start() {
    if (!incomingPath || animation.running || progress!==0) return
    loadDeadline.stop()
    animation.restart()
  }
  function cancelIncoming(message) {
    animation.stop(); loadDeadline.stop()
    incomingPath=""; oldPath=""; finishing=false; progress=1
    currentPath=displayedPath; errorText=message
  }
  function refresh() { if(!readlink.running) {readGeneration=generation;readlink.running=true} }
  function applyTheme(colors,shell) {
    // Keep base64 payloads opaque; Omarchy's public shell IPC owns theme parsing.
    if(themeApply.running) pendingTheme=JSON.stringify([colors,shell])
    else { themeApply.command=["omarchy-shell","shell","applyTheme",colors,shell]; themeApply.running=true }
    palette.reload()
  }
  onMotionDisabledChanged: if(motionDisabled && incomingPath) {
    animation.stop(); loadDeadline.stop(); progress=1
    finishing=true; displayedPath=finalPath
  }
  FileView {
    id:configuration
    path:root.home+"/.local/state/ruixen/wallpaper-appearance.json"
    watchChanges:true; printErrors:false
    onLoaded: { try { var state=JSON.parse(text()); if(!state || typeof state!=="object" || Array.isArray(state) || (state.version!==undefined && state.version!==1)) throw new Error("Invalid schema"); root.settings=AppearanceModel.normalize(state); root.errorText="" } catch(e) { root.errorText="Invalid wallpaper appearance settings" } }
    onFileChanged:reload()
  }
  FileView {
    id:palette
    path:root.home+"/.local/state/omarchy/current/theme/colors.toml"
    printErrors:false
    onLoaded: { var match=text().match(/^accent\s*=\s*["'](#[0-9a-fA-F]{6})["']/m); if(match) root.accent=match[1] }
  }
  FileView {
    path:root.home+"/.local/state/ruixen/wallpaper-media"
    watchChanges:true; printErrors:false
    onLoaded:root.mediaPlaying=/^(video|gif)\n/.test(text())
    onFileChanged:reload()
    onLoadFailed:root.mediaPlaying=false
  }
  Process {
    id:readlink
    command:["readlink","-f",root.home+"/.local/state/omarchy/current/background"]
    stdout:StdioCollector {
      waitForEnd:true
      onStreamFinished: { if(root.readGeneration!==root.generation) return; var path=text.trim(); if(path) root.transition("",path,path,false) }
    }
  }
  Process {
    id:themeApply
    onExited: (code,status) => {
      if(code!==0) root.errorText="Unable to apply theme palette"
      if(root.pendingTheme) {var args=JSON.parse(root.pendingTheme);root.pendingTheme="";root.applyTheme(args[0],args[1])}
    }
  }
  // Issue #103: this poll is a safety net only -- the real path for a
  // background change (omarchy-theme-bg-set, or this plugin's own
  // set()/transition() IPC methods below) already notifies this service
  // synchronously, either directly or via `omarchy-shell -q background
  // set` (see that script's own comment: "IPC avoids the visible
  // delay"). The only thing this interval still needs to catch is an
  // out-of-band symlink edit that bypasses both of those paths entirely
  // -- genuinely rare, so a long interval costs nothing real. Confirmed
  // directly (isolated Quickshell FileView probe, not assumed) that a
  // file-watch alternative wouldn't even be reliable here: watchChanges
  // fires for a symlink's first creation but does not reliably refire
  // after the SAME path's symlink target is later atomically replaced
  // (ln -nsf, what every writer here actually does) -- the same reason
  // every other direct reader of this exact symlink in this repo polls
  // it too (see e.g. ruixen.notch/Overlay.qml's own comment) rather than
  // watching it.
  Timer { interval:15000; repeat:true; running:true; onTriggered:root.refresh() }
  Timer { id:loadDeadline; interval:10000; onTriggered:root.cancelIncoming("Unable to load wallpaper") }
  NumberAnimation {
    id:animation
    target:root; property:"progress"; from:0; to:1
    duration:root.durationMs; easing.type:Easing.InOutCubic
    onFinished: { root.finishing=true; root.displayedPath=root.finalPath }
  }
  Component.onCompleted:refresh()
  IpcHandler {
    target:"ruixen-wallpaper-appearance"
    function status(): string { return JSON.stringify(Object.assign({},root.settings,{rendererEnabled:true,revealProgress:root.progress,error:root.errorText, mediaPlaying:root.mediaPlaying})) }
  }
  IpcHandler {
    target:"background"
    function refresh(): void { root.refresh() }
    function set(path:string): void { root.transition("",path,path,false) }
    function setInstant(path:string): void { root.transition("",path,path,true) }
    function transition(fromPath:string,path:string): void { root.transition(fromPath,path,path,false) }
    function themeTransition(fromPath:string,path:string,finalPath:string,colorsB64:string,shellB64:string): void {
      root.transition(fromPath,path,finalPath,false,true)
      root.applyTheme(colorsB64,shellB64)
    }
  }
  Variants {
    model:Quickshell.screens
    PanelWindow {
      id:panel
      required property var modelData
      screen:modelData
      anchors {top:true;bottom:true;left:true;right:true}
      color:"transparent"
      property bool remapping:false
      visible:!remapping
      Timer {id:monitorSettle;interval:200;onTriggered:panel.remapping=true}
      Timer {interval:50;running:panel.remapping;onTriggered:panel.remapping=false}
      Connections {
        target:panel.screen
        function onXChanged() {monitorSettle.restart()}
        function onYChanged() {monitorSettle.restart()}
      }
      WlrLayershell.namespace:"ruixen-background"
      WlrLayershell.layer:WlrLayer.Background
      WlrLayershell.keyboardFocus:WlrKeyboardFocus.None
      exclusionMode:ExclusionMode.Ignore
      property real seconds:0
      readonly property bool passiveActive:!root.motionDisabled && !root.mediaPlaying
      Timer {
        interval:250; repeat:true
        running:panel.visible && panel.passiveActive && (root.settings.ambientZoom===true || root.settings.ambientGlow===true)
        onTriggered:panel.seconds+=.25
      }
      readonly property real zoom:panel.passiveActive && root.settings.ambientZoom ? 1.015-.007*Math.cos(seconds*2*Math.PI/180) : 1
      function maybeStart() {
        if(incoming.status===Image.Ready && oldFrame.status===Image.Ready && (!root.glitch || glitchFrame.ready)) root.start()
      }
      Connections {
        target:root
        function onFinishingChanged() {
          if(root.finishing) Qt.callLater(function() {
            if(root.finishing && base.status===Image.Ready && base.source.toString()===root.imageUrl(root.finalPath)) {
              root.incomingPath="";root.oldPath="";root.finishing=false
            }
          })
        }
      }
      // Content wrapped in its own Item, hidden while media plays --
      // direct fix for a real bug ("when i turn transition on... its
      // actually removing our ruixen frame"): ruixen.wallpaper's own
      // video/gif surface used to bump itself from WlrLayer.Background
      // to WlrLayer.Bottom specifically to paint-order-beat this still-
      // opaque panel during playback, which collided with the frame
      // (also Bottom) and won, visibly covering it (confirmed live via
      // `hyprctl layers`). Hiding this content here instead removes the
      // need for that bump entirely -- ruixen.wallpaper now stays at
      // Background always (see its own Service.qml), so nothing but the
      // frame and real windows ever contends for Bottom. The PanelWindow
      // itself stays mapped (visible:!remapping, untouched) so this is a
      // content-visibility toggle, not a surface remap -- same "stays
      // mapped, becomes invisible" pattern ruixen.wallpaper's own
      // surface already uses while nothing is playing.
      Item {
        id: visualLayer
        anchors.fill: parent
        visible: !root.mediaPlaying

        Image {
          id:base
          anchors.fill:parent; scale:panel.zoom
          source:root.imageUrl(root.displayedPath)
          fillMode:Image.PreserveAspectCrop; sourceSize:Qt.size(Math.max(1,width),Math.max(1,height)); asynchronous:true
          onStatusChanged: {
            if(status===Image.Ready && root.finishing) {root.incomingPath="";root.oldPath="";root.finishing=false}
          }
        }
        Image {
          id:oldFrame
          onStatusChanged:panel.maybeStart()
          anchors.fill:parent; scale:panel.zoom
          source:root.imageUrl(root.oldPath); visible:root.incomingPath!==""
          fillMode:Image.PreserveAspectCrop; sourceSize:Qt.size(Math.max(1,width),Math.max(1,height)); asynchronous:true
        }
        Item {
          anchors.fill:parent
          visible:root.incomingPath!=="" && incoming.status===Image.Ready && !root.glitch
          layer.enabled:visible
          opacity:root.effect==="bleed" ? root.progress : 1
          layer.effect:MultiEffect {
            maskEnabled:root.effect!=="bleed"; maskSource:mask
            maskThresholdMin:.5; maskSpreadAtMin:root.settings.transitionSoftness || .02
          }
          Image {
            id:incoming
            anchors.fill:parent; scale:panel.zoom
            source:root.imageUrl(root.incomingPath)
            fillMode:Image.PreserveAspectCrop; sourceSize:Qt.size(Math.max(1,width),Math.max(1,height)); asynchronous:true
            onStatusChanged: {
              if(status===Image.Ready) panel.maybeStart()
              else if(status===Image.Error && root.incomingPath) root.cancelIncoming("Unable to decode wallpaper")
            }
          }
        }
        WallpaperTransitionMask {id:mask;anchors.fill:parent;effect:root.effect;progress:root.progress;active:root.incomingPath!=="" && !root.glitch}
        WallpaperGlitch {
          id:glitchFrame; anchors.fill:parent
          active:root.glitch && root.incomingPath!==""
          fromPath:root.oldPath;toPath:root.incomingPath;effect:root.effect;progress:root.progress;accent:root.accent
          strength:((root.settings.transitionOptions || {})[root.effect] || {}).strength===undefined ? .65 : root.settings.transitionOptions[root.effect].strength
          density:((root.settings.transitionOptions || {})[root.effect] || {}).density || 1
          onReadyChanged:panel.maybeStart()
        }
        WallpaperAmbient {
          anchors.fill:parent
          effect:root.settings.backgroundEffect || "none"
          intensity:root.settings.backgroundIntensity===undefined ? .25 : root.settings.backgroundIntensity
          speed:root.settings.backgroundSpeed || 1; disableMotion:root.motionDisabled
          active:panel.visible && !root.mediaPlaying;accent:root.accent
        }
        Rectangle {
          anchors.fill:parent
          visible:panel.passiveActive && root.settings.ambientGlow===true
          opacity:.0275-.0125*Math.cos(panel.seconds*2*Math.PI/60)
          gradient:Gradient {
            GradientStop {position:0;color:root.accent}
            GradientStop {position:.55;color:"transparent"}
            GradientStop {position:1;color:root.accent}
          }
        }
      }
    }
  }
}
