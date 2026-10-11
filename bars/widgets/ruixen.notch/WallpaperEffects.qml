import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import "WallpaperEffectModel.js" as EffectModel

// Controls for the bundled optional Ruixen renderer. Persisted settings keep
// both wallpaper pickers in sync; public plugin commands own enable/disable.
Rectangle {
  id: root
  property bool active: false
  property bool available: false
  property bool expanded: false
  property int maxExpandedHeight:480
  property color textColor: "white"
  property color muted: "#999999"
  property color accent: "#3ecf5b"
  readonly property color hintColor:Qt.rgba(textColor.r,textColor.g,textColor.b,.7)
  property string fontFamily: "JetBrainsMono Nerd Font"
  property string currentBackground: ""
  property var artworkEntries: []
  property string hoveredEffect: ""
  property var choices: [
    {key:"reveal",label:"Reveal"}, {key:"bleed",label:"Bleed through"}, {key:"pixel-dissolve",label:"Pixel dissolve"},
    {key:"iris",label:"Iris bloom"}, {key:"shutters",label:"Glass shutters"}, {key:"scanline",label:"Scanline"},
    {key:"ink-spread",label:"Ink spread"}, {key:"aurora",label:"Aurora wash"}, {key:"vortex",label:"Vortex"},
    {key:"signal-tear",label:"Signal tear"}, {key:"datamosh",label:"Datamosh"},
    {key:"vhs",label:"VHS tracking"}, {key:"code-bleed",label:"Code bleed"}
  ]
  function effectLabel(key) { for(var i=0;i<choices.length;i++) if(choices[i].key===key) return choices[i].label; return "Reveal" }
  readonly property string previewNext: EffectModel.nextPreviewArtwork(currentBackground, artworkEntries)
  property var settings: ({})
  property string pending: ""
  property bool rendererEnabled:false
  property string errorText: ""
  readonly property var selectedOptions:(settings.transitionOptions || {})[settings.transitionEffect] || ({})
  readonly property bool shaderTransition:["signal-tear","datamosh","vhs","code-bleed"].indexOf(settings.transitionEffect)>=0
  readonly property bool motionDisabled: settings.disableMotion === true
  visible: available
  implicitHeight: expanded ? Math.min(content.implicitHeight + 60, maxExpandedHeight) : 50
  color: Qt.rgba(textColor.r,textColor.g,textColor.b,.05)
  radius: 12
  border.width: 0

  function changeOption(key,value) {
    var options=Object.assign({},settings.transitionOptions || {})
    options[settings.transitionEffect]=Object.assign({},options[settings.transitionEffect] || {},{[key]:value})
    change("transitionOptions",options)
  }
  function densityLabel() {
    return settings.transitionEffect==="datamosh" ? "Block density" : settings.transitionEffect==="vhs" ? "Wobble frequency" : settings.transitionEffect==="code-bleed" ? "Column density" : "Band density"
  }
  function refresh() {
    if (active && !probe.running) probe.running = true
  }
  function change(key, value) {
    var next = Object.assign({}, settings)
    next[key] = value
    settings = next
    pending = JSON.stringify(next)
    errorText = ""
    saveDelay.restart()
  }
  function savePending() {
    if (writer.running || !pending) return
    writer.command = ["python3", decodeURIComponent(Qt.resolvedUrl("wallpaper-effects.py").toString().replace(/^file:\/\//, "")), pending]
    pending = ""
    writer.running = true
  }
  onActiveChanged: refresh()
  Component.onCompleted: refresh()

  FileView {
    id: settingsFile
    path: Quickshell.env("HOME") + "/.local/state/ruixen/wallpaper-appearance.json"
    watchChanges: true
    printErrors: false
    onLoaded: {
      if (root.pending || writer.running) return
      try { root.settings = JSON.parse(text()) } catch (e) { root.errorText = "Unable to read effect settings" }
    }
    onFileChanged: reload()
  }
  Process {
    id: probe
    command: ["python3", decodeURIComponent(Qt.resolvedUrl("wallpaper-effects.py").toString().replace(/^file:\/\//, "")), "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var state = JSON.parse(text)
          root.available = state.installed === true
          root.rendererEnabled = state.rendererEnabled === true
          root.errorText = state.error || ""
          if (!root.pending && !writer.running) root.settings = state
        } catch (e) { root.available = false }
      }
    }
    onExited: (code, status) => { if (code !== 0) root.available = false }
  }
  Timer { id: saveDelay; interval: 180; onTriggered: root.savePending() }
  Process {
    id: writer
    onExited: (code, status) => {
      if (code !== 0) root.errorText = "Could not save effects; try again"
      if (root.pending) saveDelay.restart()
      else settingsFile.reload()
    }
  }

  Process {
    id:rendererToggle
    stdout:StdioCollector {
      waitForEnd:true
      onStreamFinished: { try { root.errorText=JSON.parse(text).error || "" } catch(e) { root.errorText="Unable to switch renderer" } }
    }
    onExited: (code,status) => { if(code===0) root.refresh() }
  }
  function toggleRenderer() {
    if(writer.running || pending || rendererToggle.running) return
    rendererToggle.command=["python3", decodeURIComponent(Qt.resolvedUrl("wallpaper-effects.py").toString().replace(/^file:\/\//, "")), rendererEnabled ? "disable" : "enable"]
    rendererToggle.running=true
  }
  // Drive the same local preview as hover, without writing effect settings.
  IpcHandler {
    target: "ruixen-wallpaper-preview-notch"
    function preview(effect: string): void {
      for(var i=0;i<root.choices.length;i++) if(root.choices[i].key===effect) {
        root.expanded=true
        root.hoveredEffect=effect
        return
      }
    }
    function clearPreview(): void { root.hoveredEffect="" }
    function status(): string { return JSON.stringify({preview:root.hoveredEffect, selected:root.settings.transitionEffect, active:root.active, expanded:root.expanded, motionDisabled:root.motionDisabled, durationMs:hoverPreview.durationMs, imagesReady:hoverPreview.imagesReady, progress:hoverPreview.progress, playing:hoverPreview.playing, from:root.currentBackground, to:root.previewNext}) }
  }

  WallpaperSectionHeader {
      id:sectionHeader
      anchors.left:parent.left; anchors.right:parent.right; anchors.top:parent.top
      anchors.margins:10
      height:30
      title: "Wallpaper appearance"
      glyph: "\uf0d0"
      summary: !root.rendererEnabled ? "Preview only" : root.motionDisabled ? "Motion off" : root.effectLabel(root.settings.transitionEffect) + " · " + ((root.settings.transitionDurationMs || 0) / 1000).toFixed(1) + " s"
      expanded: root.expanded
      accent: root.accent; textColor: root.textColor; muted: root.hintColor; fontFamily: root.fontFamily
      onClicked: root.expanded = !root.expanded
    }
  Flickable {
    id:appearanceViewport
    contentWidth:width
    flickableDirection:Flickable.VerticalFlick
    anchors.left:parent.left; anchors.right:parent.right
    anchors.top:sectionHeader.bottom; anchors.topMargin:8
    anchors.bottom:parent.bottom; anchors.margins:10
    visible:root.expanded
    clip:true
    contentHeight:content.implicitHeight
    boundsBehavior:Flickable.StopAtBounds
    Controls.ScrollBar.vertical:Controls.ScrollBar {
      policy:Controls.ScrollBar.AsNeeded
      active:true
      contentItem:Rectangle {implicitWidth:4;implicitHeight:30;radius:2;color:root.accent;opacity:.6}
    }
    ColumnLayout {
      id:content
      width:appearanceViewport.width
      spacing:8
    ColumnLayout {
      visible: root.expanded
      Layout.fillWidth: true
      spacing: 8
      RowLayout {
        Layout.fillWidth:true
        Text { text:root.errorText || (root.rendererEnabled ? "Native Ruixen renderer active" : "Preview effects, then enable the renderer to apply them."); color:root.errorText ? "#ff8080" : root.hintColor; font.family:root.fontFamily; font.pixelSize:10; Layout.fillWidth:true; wrapMode:Text.Wrap }
        WallpaperAction {
          text:root.rendererEnabled ? "Use stock renderer" : "Enable renderer"
          accent:root.accent; textColor:root.textColor; font.family:root.fontFamily
          enabled:!rendererToggle.running && !writer.running && !root.pending
          onClicked:root.toggleRenderer()
        }
      }
      Text { text:"Transition"; color:root.hintColor; font.family:root.fontFamily; font.pixelSize:11 }
      RowLayout {
        Layout.fillWidth: true
        spacing: 12
        GridLayout {
          Layout.fillWidth: true
          columns: 3
          rowSpacing: 6; columnSpacing: 6
          Repeater {
            model: root.choices
            WallpaperAction {
              required property var modelData
              Layout.fillWidth: true
              text: modelData.label
              selected: root.settings.transitionEffect === modelData.key
              enabled: !root.motionDisabled
              accent: root.accent; textColor: root.textColor; font.family: root.fontFamily
              HoverHandler {
                id: effectHover
                onHoveredChanged: {
                  if (hovered) root.hoveredEffect=modelData.key
                  else if(root.hoveredEffect===modelData.key) root.hoveredEffect=""
                }
              }
              onActiveFocusChanged: {
                if(activeFocus) root.hoveredEffect=modelData.key
                else if(!effectHover.hovered && root.hoveredEffect===modelData.key) root.hoveredEffect=""
              }
              onClicked: root.change("transitionEffect",modelData.key)
            }
          }
        }
        ColumnLayout {
          Layout.preferredWidth: 180
          spacing: 4
          WallpaperEffectPreview {
            id: hoverPreview
            Layout.fillWidth: true
            Layout.preferredHeight: 100
            effect: root.hoveredEffect || root.settings.transitionEffect || "reveal"
            fromPath: root.currentBackground
            toPath: root.previewNext
            playing: root.active && root.expanded && root.hoveredEffect !== "" && !root.motionDisabled
            durationMs: root.settings.transitionDurationMs === undefined ? 420 : root.settings.transitionDurationMs
            transitionOptions:root.settings.transitionOptions || ({})
            ambientActive:root.active && root.expanded
            backgroundEffect:root.settings.backgroundEffect || "none"
            backgroundIntensity:root.settings.backgroundIntensity === undefined ? .25 : root.settings.backgroundIntensity
            backgroundSpeed:root.settings.backgroundSpeed === undefined ? 1 : root.settings.backgroundSpeed
            disableMotion:root.motionDisabled
            softness: root.settings.transitionSoftness || .02
            accent: root.accent
          }
          Text {
            Layout.fillWidth: true
            text: root.motionDisabled ? "Motion disabled" : root.hoveredEffect ? root.effectLabel(root.hoveredEffect) + " · " + (hoverPreview.durationMs / 1000).toFixed(1) + " s" : "Hover to preview"
            color: root.hintColor; font.family:root.fontFamily; font.pixelSize:10
            horizontalAlignment:Text.AlignHCenter
          }
        }
      }
      RowLayout {
        Layout.fillWidth: true
        Text { text: "Duration"; color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11; Layout.preferredWidth: 70 }
        WallpaperSlider {
          Layout.fillWidth: true
          from: 0; to: 30000; stepSize: 100
          enabled: !root.motionDisabled
          accent: root.accent; textColor: root.textColor
          value: root.settings.transitionDurationMs === undefined ? 420 : root.settings.transitionDurationMs
          Accessible.name:"Transition duration in milliseconds"
          onMoved: root.change("transitionDurationMs", Math.round(value))
        }
        Text { text: ((root.settings.transitionDurationMs || 0) / 1000).toFixed(1) + " s"; color: root.textColor; font.family: root.fontFamily; font.pixelSize: 11; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight }
      }
      RowLayout {
        visible:!root.shaderTransition && root.settings.transitionEffect!=="bleed"
        Layout.fillWidth: true
        Text { text: "Softness"; color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11; Layout.preferredWidth: 70 }
        WallpaperSlider {
          Layout.fillWidth: true
          from: 0.001; to: 0.5; stepSize: 0.001
          enabled: !root.motionDisabled && !root.shaderTransition && root.settings.transitionEffect !== "bleed"
          accent: root.accent; textColor: root.textColor
          value: root.settings.transitionSoftness === undefined ? 0.02 : root.settings.transitionSoftness
          Accessible.name:"Transition edge softness"
          onMoved: root.change("transitionSoftness", Math.round(value * 1000) / 1000)
        }
        Text { text: root.shaderTransition ? "Shader" : root.settings.transitionEffect === "bleed" ? "Blend" : Number(root.settings.transitionSoftness || 0).toFixed(3); color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11; Layout.preferredWidth: 50; horizontalAlignment: Text.AlignRight }
      }
      RowLayout {
        visible:root.shaderTransition
        Layout.fillWidth:true
        Text { text:"Distortion"; color:root.hintColor; font.family:root.fontFamily; font.pixelSize:11; Layout.preferredWidth:110 }
        WallpaperSlider {
          Layout.fillWidth:true; from:0; to:1; stepSize:.01; enabled:!root.motionDisabled
          value:((root.settings.transitionOptions || {})[root.settings.transitionEffect] || {}).strength === undefined ? .65 : root.settings.transitionOptions[root.settings.transitionEffect].strength
          accent:root.accent; textColor:root.textColor
          onMoved:root.changeOption("strength",Math.round(value*100)/100)
          Accessible.name:"Transition distortion strength"
        }
        Text { text:Math.round((root.selectedOptions.strength===undefined ? .65 : root.selectedOptions.strength)*100)+"%"; color:root.hintColor; font.family:root.fontFamily; font.pixelSize:11; Layout.preferredWidth:50 }
      }
      RowLayout {
        visible:root.shaderTransition
        Layout.fillWidth:true
        Text { text:root.densityLabel(); color:root.hintColor; font.family:root.fontFamily; font.pixelSize:11; Layout.preferredWidth:110 }
        WallpaperSlider {
          Layout.fillWidth:true; from:.5; to:2; stepSize:.1; enabled:!root.motionDisabled
          value:((root.settings.transitionOptions || {})[root.settings.transitionEffect] || {}).density || 1
          accent:root.accent; textColor:root.textColor
          onMoved:root.changeOption("density",Math.round(value*10)/10)
          Accessible.name:root.densityLabel()
        }
        Text { text:Number(root.selectedOptions.density || 1).toFixed(1)+"×"; color:root.hintColor; font.family:root.fontFamily; font.pixelSize:11; Layout.preferredWidth:50 }
      }
      RowLayout {
        Layout.fillWidth:true
        Text { text:"Background"; color:root.hintColor; font.family:root.fontFamily; font.pixelSize:11; Layout.preferredWidth:90 }
        Repeater {
          model:[{key:"none",label:"None"},{key:"crt",label:"CRT texture"},{key:"matrix",label:"Matrix rain"}]
          WallpaperAction {
            required property var modelData
            text:modelData.label; selected:(root.settings.backgroundEffect || "none")===modelData.key
            accent:root.accent; textColor:root.textColor; font.family:root.fontFamily
            onClicked:root.change("backgroundEffect",modelData.key)
          }
        }
        Item { Layout.fillWidth:true }
      }
      RowLayout {
        Layout.fillWidth:true
        Text { text:"Intensity"; color:root.hintColor; font.family:root.fontFamily; font.pixelSize:11; Layout.preferredWidth:70 }
        WallpaperSlider {
          Layout.fillWidth:true; from:0; to:1; stepSize:.01
          enabled:!!root.settings.backgroundEffect && root.settings.backgroundEffect!=="none"
          value:root.settings.backgroundIntensity===undefined ? .25 : root.settings.backgroundIntensity
          accent:root.accent; textColor:root.textColor
          Accessible.name:"Background effect intensity"
          onMoved:root.change("backgroundIntensity",Math.round(value*100)/100)
        }
        Text { text:Math.round((root.settings.backgroundIntensity===undefined ? .25 : root.settings.backgroundIntensity)*100)+"%"; color:root.hintColor; font.pixelSize:11; Layout.preferredWidth:50 }
      }
      RowLayout {
        Layout.fillWidth:true
        Text { text:"Speed"; color:root.hintColor; font.family:root.fontFamily; font.pixelSize:11; Layout.preferredWidth:70 }
        WallpaperSlider {
          Layout.fillWidth:true; from:.1; to:3; stepSize:.1
          enabled:root.settings.backgroundEffect==="matrix" && !root.motionDisabled
          value:root.settings.backgroundSpeed===undefined ? 1 : root.settings.backgroundSpeed
          accent:root.accent; textColor:root.textColor
          Accessible.name:"Background animation speed"
          onMoved:root.change("backgroundSpeed",Math.round(value*10)/10)
        }
        Text { text:Number(root.settings.backgroundSpeed || 1).toFixed(1)+"×"; color:root.hintColor; font.pixelSize:11; Layout.preferredWidth:50 }
      }
      RowLayout {
        Layout.fillWidth: true
        WallpaperToggle { text: "Ambient zoom"; checked: root.settings.ambientZoom === true; enabled: !root.motionDisabled; accent: root.accent; textColor: root.textColor; font.family: root.fontFamily; onClicked: root.change("ambientZoom", checked) }
        Item { Layout.fillWidth: true }
        WallpaperToggle { text: "Theme glow"; checked: root.settings.ambientGlow === true; enabled: !root.motionDisabled; accent: root.accent; textColor: root.textColor; font.family: root.fontFamily; onClicked: root.change("ambientGlow", checked) }
        Item { Layout.fillWidth: true }
        WallpaperToggle { text: "Disable motion"; checked: root.motionDisabled; accent: root.accent; textColor: root.textColor; font.family: root.fontFamily; onClicked: root.change("disableMotion", checked) }
      }
      RowLayout {
        Layout.fillWidth: true
        Text {
          Layout.fillWidth: true
          text: root.errorText || (root.rendererEnabled ? "Changes apply to static artwork immediately." : "Effects are saved; stock wallpaper rendering stays active.")
          color: root.errorText ? "#ff8080" : root.hintColor
          font.family: root.fontFamily; font.pixelSize: 10; wrapMode: Text.Wrap
        }
        WallpaperAction {
          text: "Reset effects"
          accent: root.accent; textColor: root.textColor; font.family: root.fontFamily
          onClicked: {
            root.settings = {transitionEffect:"reveal", transitionDurationMs:420, transitionSoftness:0.02, ambientZoom:false, ambientGlow:false, disableMotion:false, transitionOptions:{}, backgroundEffect:"none", backgroundIntensity:.25, backgroundSpeed:1}
            root.pending = JSON.stringify(root.settings)
            saveDelay.restart()
          }
        }
      }
    }
  }
  }
}
