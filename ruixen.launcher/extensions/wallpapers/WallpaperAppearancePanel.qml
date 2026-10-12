import QtQuick
import QtQuick.Layouts
import QtQuick.Controls as Controls
import Quickshell
import Quickshell.Io
import "WallpaperEffectModel.js" as EffectModel

// Flattened replacement for the old WallpaperEffects.qml accordion card
// (title row, a separate 180px preview tile, a 3-column grid of 13
// transition buttons, Duration/Softness/Distortion/Density sliders,
// CRT/Matrix buttons with their own Intensity/Speed sliders, 3 ambient
// toggles, a Reset button) -- direct correction: "since we already have
// a hero, that can be used for the preview... we can make this a panel
// to select the transition and some progress bar scroll settings? or
// should we just do preset options", settled on "keep them as separate
// chips so clicking on them is easier... for the transition, we can
// have preset we think looks good assigned to it, so its baked in with
// the animations... for the CRT and Matrix, maybe a slider or two".
//
// Sits where 4 ordinary wallpaper thumbnails used to, in the grid cells
// immediately right of heroTile (see WallpapersContent.qml's own
// heroSpacerIndices/gridModel comments) -- an overlay Item on
// grid.contentItem, same mechanism as heroTile itself, not a GridView
// delegate. heroTile now doubles as this panel's live preview (see its
// own comment) instead of a separate preview box.
//
// Each of the 13 transitions is its own chip with a FIXED, baked-in
// duration/softness (mask effects) or strength/density (glitch
// effects) -- no exposed sliders for those, so "baked in" here
// honestly means "the system's own existing defaults asserted
// explicitly", not hand-tuned per effect; this file's own author can't
// watch each one render to judge "looks good" per effect, so it
// deliberately didn't invent 13 bespoke numbers. CRT/Matrix keep two
// real sliders (Intensity always, Speed only for Matrix -- CRT has no
// animation timer, see docs/CUSTOMIZATION.md's own note).
//
// Two features, one shared renderer enable/disable flag, same
// maybeDisableRenderer pattern as the notch's WallpaperAppearanceState
// .qml (ported here, not shared -- this file talks to its own local
// wallpaper-effects.py the same direct-script way every picker in this
// plugin family already does, never IPC): Transition's own on/off
// signal is transitionDurationMs > 0, Effect's is
// backgroundEffect !== "none", and the renderer only turns off once
// both are off, so Stock Transition + active CRT (or the reverse) both
// hold correctly.
Item {
  id: root
  property bool active: false
  property string currentBackground: ""
  property var artworkEntries: []
  property color textColor: "white"
  property color muted: "#999999"
  property color accent: "#3ecf5b"
  readonly property color hintColor: Qt.rgba(textColor.r, textColor.g, textColor.b, .7)
  property string fontFamily: "JetBrainsMono Nerd Font"

  property var settings: ({})
  property string pending: ""
  property bool available: false
  property bool rendererEnabled: false
  property string errorText: ""
  readonly property bool transitionOn: (settings.transitionDurationMs || 0) > 0
  readonly property bool backgroundEffectOn: (settings.backgroundEffect || "none") !== "none"

  // Hover-preview state -- null means "not previewing that axis right
  // now". Driven by HoverHandlers on the chips below, read by heroTile.
  property string previewTransition: ""
  property string previewBackgroundEffect: ""
  readonly property string previewNext: EffectModel.nextPreviewArtwork(currentBackground, artworkEntries)

  readonly property var choices: [
    {key: "reveal", label: "Reveal"}, {key: "bleed", label: "Bleed through"}, {key: "pixel-dissolve", label: "Pixel dissolve"},
    {key: "iris", label: "Iris bloom"}, {key: "shutters", label: "Glass shutters"}, {key: "scanline", label: "Scanline"},
    {key: "ink-spread", label: "Ink spread"}, {key: "aurora", label: "Aurora wash"}, {key: "vortex", label: "Vortex"},
    {key: "signal-tear", label: "Signal tear"}, {key: "datamosh", label: "Datamosh"},
    {key: "vhs", label: "VHS tracking"}, {key: "code-bleed", label: "Code bleed"}
  ]
  readonly property var glitchKeys: ["signal-tear", "datamosh", "vhs", "code-bleed"]
  function effectLabel(key) { for (var i = 0; i < choices.length; i++) if (choices[i].key === key) return choices[i].label; return "Reveal" }

  readonly property string helper: decodeURIComponent(Qt.resolvedUrl("wallpaper-effects.py").toString().replace(/^file:\/\//, ""))

  function refresh() { if (active && !probe.running) probe.running = true }
  function change(updates) {
    settings = Object.assign({}, settings, updates)
    pending = JSON.stringify(settings)
    errorText = ""
    saveDelay.restart()
  }
  function savePending() {
    if (writer.running || !pending) return
    writer.command = ["python3", root.helper, pending]
    pending = ""
    writer.running = true
  }
  function setRenderer(enabled) {
    if (rendererToggle.running || enabled === rendererEnabled) return
    rendererToggle.command = ["python3", root.helper, enabled ? "enable" : "disable"]
    rendererToggle.running = true
  }
  function maybeDisableRenderer() {
    if (!transitionOn && !backgroundEffectOn) setRenderer(false)
  }

  // Baked-in per-effect preset -- see this file's own header comment
  // for why these are the system's existing defaults, not bespoke
  // hand-tuning. Also auto-enables the renderer, same "no separate
  // enable step" the notch chips already do.
  //
  // Duration bumped well past the system's own original 420ms default
  // -- direct correction: "slow down the quick onces like iris bloom
  // abit, make these feel more premium, i dont like snappy unless its
  // has to be". Mask effects (the fade/dissolve/wipe family) get a
  // real 900ms -- snappy read as cheap on those. Glitch effects keep
  // more punch (550ms, still up from 420) since a glitch reads as
  // itself BECAUSE it's abrupt -- that's the one case duration "has to"
  // stay quick rather than a default to slow down.
  readonly property int maskDurationMs: 900
  readonly property int glitchDurationMs: 550
  function selectTransition(key) {
    var isGlitch = glitchKeys.indexOf(key) >= 0
    var updates = {transitionEffect: key, transitionDurationMs: isGlitch ? glitchDurationMs : maskDurationMs}
    if (isGlitch) {
      var options = Object.assign({}, settings.transitionOptions || {})
      options[key] = {strength: .65, density: 1}
      updates.transitionOptions = options
    } else {
      updates.transitionSoftness = .02
    }
    change(updates)
    setRenderer(true)
  }
  // Stock -- duration 0 is already "instant cut, no visible transition"
  // to the renderer's own crossfade code, same meaning as the notch
  // chip's own Stock. Only disables the renderer if Effect isn't also
  // keeping it on.
  function selectStock() {
    if (!transitionOn) return
    change({transitionDurationMs: 0})
    maybeDisableRenderer()
  }
  function selectBackgroundEffect(key) {
    change({backgroundEffect: key})
    if (key !== "none") setRenderer(true)
    else maybeDisableRenderer()
  }

  onActiveChanged: refresh()
  Component.onCompleted: refresh()
  Timer { id: saveDelay; interval: 180; onTriggered: root.savePending() }
  // Old card relied solely on a FileView watching wallpaper-appearance
  // .json for live reactivity to external changes -- this panel instead
  // polls on the same cadence WallpaperAppearanceState.qml (the notch's
  // own equivalent) already uses, since now BOTH surfaces can write
  // rendererEnabled/backgroundEffect/transitionEffect independently and
  // each needs to notice the other's changes, not just its own.
  // Direct bug caught live: without this, selecting CRT from the notch
  // (or any external change) never showed up here until the panel was
  // recreated.
  Timer { interval: 1000; running: root.active; repeat: true; onTriggered: root.refresh() }
  Process {
    id: probe
    command: ["python3", root.helper, "status"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.pending || writer.running || rendererToggle.running) return
        try {
          var state = JSON.parse(text)
          root.available = state.installed === true
          root.rendererEnabled = state.rendererEnabled === true
          root.errorText = state.error || ""
          root.settings = state
        } catch (e) { root.available = false }
      }
    }
    onExited: (code, status) => { if (code !== 0) root.available = false }
  }
  Process {
    id: writer
    onExited: (code, status) => {
      if (code !== 0) root.errorText = "Could not save effects; try again"
      if (root.pending) saveDelay.restart()
      else root.refresh()
    }
  }
  Process {
    id: rendererToggle
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: { try { root.errorText = JSON.parse(text).error || "" } catch (e) { root.errorText = "Unable to switch renderer" } }
    }
    onExited: (code, status) => root.refresh()
  }

  // Same public IPC surface the old card had (docs/CONTROL.md's own
  // "Local wallpaper previews" section) -- preview(effect) now drives
  // heroTile instead of a dedicated preview tile, status() drops the
  // old "expanded" field since this panel has no collapsed state to
  // report any more.
  IpcHandler {
    target: "ruixen-wallpaper-preview-launcher"
    function preview(effect: string): void {
      for (var i = 0; i < root.choices.length; i++) if (root.choices[i].key === effect) { root.previewTransition = effect; return }
    }
    function clearPreview(): void { root.previewTransition = "" }
    function status(): string {
      return JSON.stringify({
        preview: root.previewTransition, selected: root.settings.transitionEffect, active: root.active,
        durationMs: root.settings.transitionDurationMs, from: root.currentBackground, to: root.previewNext
      })
    }
  }

  // This panel sits in a FIXED-height reserved area (same footprint as
  // heroTile beside it, see WallpapersContent.qml's own
  // appearancePanel comment) -- its content (Effect row, conditional
  // sliders, up to 14 wrapped Transition chips, 2 toggle rows) can
  // easily run taller than that, so it scrolls internally instead of
  // pushing the grid rows below it around, same Flickable+ScrollBar
  // shape the old accordion card already used for the same reason.
  Flickable {
    id: viewport
    anchors.fill: parent
    contentWidth: width
    contentHeight: content.implicitHeight
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    Controls.ScrollBar.vertical: Controls.ScrollBar {
      policy: Controls.ScrollBar.AsNeeded
      active: true
      contentItem: Rectangle { implicitWidth: 4; implicitHeight: 30; radius: 2; color: root.accent; opacity: .6 }
    }

  ColumnLayout {
    id: content
    width: viewport.width
    spacing: 10

    Text { text: "Effect"; color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11 }
    Row {
      spacing: 6
      Repeater {
        model: [{key: "none", label: "Off"}, {key: "crt", label: "CRT"}, {key: "matrix", label: "Matrix"}]
        Rectangle {
          id: effectChip
          required property var modelData
          readonly property bool selected: (root.settings.backgroundEffect || "none") === modelData.key
          width: effectChipLabel.implicitWidth + 20
          height: 28
          radius: 8
          color: effectChip.selected ? root.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, .05)
          border.width: 1
          border.color: effectChip.selected ? root.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, .12)
          Text {
            id: effectChipLabel
            anchors.centerIn: parent
            text: effectChip.modelData.label
            color: effectChip.selected ? "#000000" : root.accent
            font.family: root.fontFamily; font.pixelSize: 11
          }
          HoverHandler {
            onHoveredChanged: root.previewBackgroundEffect = hovered ? effectChip.modelData.key : (root.previewBackgroundEffect === effectChip.modelData.key ? "" : root.previewBackgroundEffect)
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectBackgroundEffect(effectChip.modelData.key)
          }
        }
      }
    }

    RowLayout {
      Layout.fillWidth: true
      visible: root.backgroundEffectOn
      Text { text: "Intensity"; color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11; Layout.preferredWidth: 60 }
      WallpaperSlider {
        Layout.fillWidth: true
        from: 0; to: 1; stepSize: .01
        accent: root.accent; textColor: root.textColor
        value: root.settings.backgroundIntensity === undefined ? .25 : root.settings.backgroundIntensity
        Accessible.name: "Background effect intensity"
        onMoved: root.change({backgroundIntensity: Math.round(value * 100) / 100})
      }
      Text {
        text: Math.round((root.settings.backgroundIntensity === undefined ? .25 : root.settings.backgroundIntensity) * 100) + "%"
        color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11; Layout.preferredWidth: 36
      }
    }
    RowLayout {
      Layout.fillWidth: true
      visible: (root.settings.backgroundEffect || "none") === "matrix"
      Text { text: "Speed"; color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11; Layout.preferredWidth: 60 }
      WallpaperSlider {
        Layout.fillWidth: true
        from: .1; to: 3; stepSize: .1
        accent: root.accent; textColor: root.textColor
        value: root.settings.backgroundSpeed === undefined ? 1 : root.settings.backgroundSpeed
        Accessible.name: "Background animation speed"
        onMoved: root.change({backgroundSpeed: Math.round(value * 10) / 10})
      }
      Text {
        text: Number(root.settings.backgroundSpeed || 1).toFixed(1) + "×"
        color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11; Layout.preferredWidth: 36
      }
    }

    Text { text: "Transition"; color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11 }
    Flow {
      Layout.fillWidth: true
      width: content.width
      spacing: 6

      Rectangle {
        id: stockChip
        readonly property bool selected: !root.transitionOn
        width: stockChipLabel.implicitWidth + 20
        height: 28
        radius: 8
        color: stockChip.selected ? root.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, .05)
        border.width: 1
        border.color: stockChip.selected ? root.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, .12)
        Text {
          id: stockChipLabel
          anchors.centerIn: parent
          text: "Stock"
          color: stockChip.selected ? "#000000" : root.accent
          font.family: root.fontFamily; font.pixelSize: 11
        }
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.PointingHandCursor
          onClicked: root.selectStock()
        }
      }

      Repeater {
        model: root.choices
        Rectangle {
          id: transitionChip
          required property var modelData
          readonly property bool selected: root.transitionOn && root.settings.transitionEffect === transitionChip.modelData.key
          width: transitionChipLabel.implicitWidth + 20
          height: 28
          radius: 8
          color: transitionChip.selected ? root.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, .05)
          border.width: 1
          border.color: transitionChip.selected ? root.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, .12)
          Text {
            id: transitionChipLabel
            anchors.centerIn: parent
            text: transitionChip.modelData.label
            color: transitionChip.selected ? "#000000" : root.accent
            font.family: root.fontFamily; font.pixelSize: 11
          }
          HoverHandler {
            onHoveredChanged: root.previewTransition = hovered ? transitionChip.modelData.key : (root.previewTransition === transitionChip.modelData.key ? "" : root.previewTransition)
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.selectTransition(transitionChip.modelData.key)
          }
        }
      }
    }

    // Ambient zoom (max ~0.7% scale variance over a 3-minute cycle) and
    // Theme glow (max ~4% opacity over a 60s cycle) dropped -- direct
    // correction: "idk they dont seem to be doing anything significant
    // enough as options", confirmed against ruixen.background/
    // Service.qml's own math, genuinely too subtle to read as a real
    // toggle. Disable motion kept -- it's not a cosmetic knob like
    // those two, it's the one real accessibility/preference switch
    // (freezes transitions, zoom, glow, and Matrix rain together,
    // while keeping static CRT), a materially different kind of
    // control. Renderer-side support for ambientZoom/ambientGlow is
    // untouched, just no longer exposed from either picker UI.
    RowLayout {
      Layout.fillWidth: true
      WallpaperToggle {
        text: "Disable motion"; checked: root.settings.disableMotion === true
        accent: root.accent; textColor: root.textColor; font.family: root.fontFamily
        onClicked: root.change({disableMotion: checked})
      }
    }
  }
  }
}
