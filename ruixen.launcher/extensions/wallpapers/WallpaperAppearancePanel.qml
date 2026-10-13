import QtQuick
import QtQuick.Layouts
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

  // Hover-preview state -- "" means "not previewing that axis right
  // now". Driven by HoverHandlers on the chips below, read by heroTile.
  property string previewTransition: ""
  property string previewBackgroundEffect: ""
  // One-shot confirmation flash on click, separate from the continuous
  // hover loop -- direct request: "have it show on click of a new
  // transition though for sure", so picking one is still confirmed
  // immediately even with the hover loop itself now spaced out (see
  // WallpaperEffectPreview.qml's own comment). Cleared by
  // clickPreviewTimer after roughly one real cycle of that effect's
  // own baked duration.
  property string clickPreviewEffect: ""
  Timer { id: clickPreviewTimer; onTriggered: root.clickPreviewEffect = "" }
  readonly property string previewNext: EffectModel.nextPreviewArtwork(currentBackground, artworkEntries)
  // What the hero should actually be animating right now, if anything,
  // and at what speed -- hover wins over a click flash still finishing
  // (an active hover IS the user actively comparing options, more
  // authoritative than a click-confirm that already did its job).
  // durationFor falls back to the real selected transition (or Reveal)
  // so the duration stays sensible even if this ever reads with no
  // preview active.
  readonly property string activePreviewTransition: previewTransition || clickPreviewEffect
  readonly property bool previewingTransition: activePreviewTransition !== ""
  function durationFor(key) { return glitchKeys.indexOf(key) >= 0 ? glitchDurationMs : maskDurationMs }
  readonly property int activePreviewDurationMs: durationFor(activePreviewTransition || settings.transitionEffect || "reveal")

  readonly property var choices: [
    {key: "reveal", label: "Reveal"}, {key: "bleed", label: "Bleed through"}, {key: "pixel-dissolve", label: "Pixel dissolve"},
    {key: "iris", label: "Iris bloom"}, {key: "shutters", label: "Glass shutters"}, {key: "scanline", label: "Scanline"},
    {key: "ink-spread", label: "Ink spread"}, {key: "aurora", label: "Aurora wash"}, {key: "vortex", label: "Vortex"},
    {key: "signal-tear", label: "Signal tear"}, {key: "datamosh", label: "Datamosh"},
    {key: "vhs", label: "VHS tracking"}, {key: "code-bleed", label: "Code bleed"}
  ]
  readonly property var glitchKeys: ["signal-tear", "datamosh", "vhs", "code-bleed"]
  function effectLabel(key) { for (var i = 0; i < choices.length; i++) if (choices[i].key === key) return choices[i].label; return "Reveal" }

  // Stock plus all 13 real transitions, packed into rows by hand
  // instead of a Flow -- direct correction: Flow's own implicitHeight
  // depends on its width (how many chips wrap per row), and that
  // width-for-height negotiation against a ColumnLayout kept producing
  // a stale, oversized height no matter how the surrounding layout was
  // restructured (nested, then flat, then width-only). Same fix
  // already proven in this repo for the exact same class of problem
  // (CliampStationPanel.qml's own EQ chips, packEqRows) -- plain Row
  // elements inside a Column have real, deterministic heights, nothing
  // implicit to get stuck.
  readonly property var transitionChipData: [{key: "stock", label: "Stock"}].concat(choices)
  function packTransitionRows(maxWidth) {
    var rows = []
    var current = []
    var currentWidth = 0
    for (var i = 0; i < transitionChipData.length; i++) {
      var item = transitionChipData[i]
      var chipWidth = transitionMetrics.advanceWidth(item.label) + 20
      var next = current.length === 0 ? chipWidth : currentWidth + 6 + chipWidth
      if (current.length > 0 && next > maxWidth) {
        rows.push(current)
        current = [item]
        currentWidth = chipWidth
      } else {
        current.push(item)
        currentWidth = next
      }
    }
    if (current.length > 0) rows.push(current)
    return rows
  }

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
    // Confirmation flash -- see clickPreviewEffect's own comment.
    clickPreviewEffect = key
    clickPreviewTimer.interval = (isGlitch ? glitchDurationMs : maskDurationMs) + 1500
    clickPreviewTimer.restart()
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

  // Real text measurement for packTransitionRows -- same technique
  // CliampStationPanel.qml's own packEqRows already uses.
  FontMetrics {
    id: transitionMetrics
    font.family: root.fontFamily
    font.pixelSize: 11
  }

  // Headless probe/debounce/write state for the Shuffle section below --
  // ported from the notch's own WallpaperRotationState.qml (same public
  // IPC surface, ruixen-wallpaper-rotation, not a local script, so no
  // new helper file is needed here). A root sibling, not a Column child
  // -- see content's own header comment above for exactly why a 0x0
  // non-visual item inside that Column would reintroduce the dead-space
  // bug already fixed once in the notch's equivalent panel.
  WallpaperRotationState {
    id: rotationState
    active: root.active
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
        durationMs: root.activePreviewDurationMs, from: root.currentBackground, to: root.previewNext
      })
    }
  }

  // Used to be wrapped in a Flickable+ScrollBar -- this panel sits in a
  // FIXED-height reserved area (same footprint as heroTile beside it,
  // see WallpapersContent.qml's own appearancePanel comment), and back
  // when the content included Duration/Softness sliders and 3 ambient
  // toggles it really could run taller than that. Direct correction
  // once those were gone: "we dont need a scroll bar thing that shows
  // up cause theres nothing to scroll anymore in the nested panel" --
  // Effect row, its conditional sliders, and the Transition flow now
  // fit the reserved height on their own, so this is a plain anchored
  // ColumnLayout again, no Flickable.
  // Direct correction after the nested-ColumnLayout version this went
  // through ("make the transition start at the top of the panel...
  // tooo gap between the effect and where the progress sliders are"):
  // a ColumnLayout nested inside this outer ColumnLayout (grouping
  // Transition+Effect's chips together) was adding real extra space
  // beyond its own declared `spacing: 6` -- confirmed by temporarily
  // marking both the panel's true top and that inner group's own top
  // with loud debug-colored Rectangles and comparing against a
  // matching marker inside heroTile (same y binding, so they're a
  // reliable ruler): heroTile's marker and this panel's own top lined
  // up exactly, but the inner group's own top sat ~40px below that,
  // not the ~18px (6px spacing + marker height) the declared spacing
  // alone should produce. Root cause not fully chased past that
  // (nested nested ColumnLayout + Flow width-for-height sizing is a
  // known rough edge in Qt Quick Layouts), fixed by removing the
  // nesting instead: one FLAT ColumnLayout for every chip, an explicit
  // Item spacer (not a second Layout's own `spacing`) for the one real
  // gap before Effect's slider section.
  // Plain Column, not ColumnLayout -- direct correction: "when i hit
  // effect off, theres still tons of gaps between everything, it comes
  // back". Reproduced live: fine on first render, but toggling Effect
  // through Matrix (which shows both sliders) and back to Off left
  // stale extra height behind in the Transition chip rows above --
  // ColumnLayout's constraint-based sizing not fully invalidating after
  // a managed child's `visible` flipped, same underlying class of
  // "implicit size gets stuck" issue Flow had (see the packed-rows
  // comment below), just triggered by visibility instead of width-for-
  // height. A plain Column's sizing is simpler and more predictable --
  // same fix direction that already solved Flow's own version of this.
  Column {
    id: content
    anchors.fill: parent
    clip: true
    // Tight and uniform now -- every label/chip-row/slider-row 4px
    // apart (was 6 -- direct report: adding the Shuffle group between
    // Transition and Effect pushed Speed's row past this panel's fixed
    // clipped height whenever Matrix shows both sliders, cutting it off
    // instead of scrolling). The one real extra gap (before the slider
    // section) is a manual spacer Item below instead of a second
    // Layout's own spacing value.
    spacing: 4

    Text { text: "Transition"; color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11 }
    // Packed rows, not Flow -- see root.packTransitionRows's own
    // comment for why. "stock" key handled inline (selected/click
    // branch on it) rather than as a separate hardcoded chip, so it
    // packs into the same rows as the real transitions exactly like it
    // did visually before.
    Column {
      width: content.width
      spacing: 6
      Repeater {
        model: root.packTransitionRows(content.width)
        Row {
          id: transitionChipRow
          required property var modelData
          spacing: 6
          Repeater {
            model: transitionChipRow.modelData
            Rectangle {
              id: transitionChip
              required property var modelData
              readonly property bool isStock: transitionChip.modelData.key === "stock"
              readonly property bool selected: transitionChip.isStock ? !root.transitionOn
                : (root.transitionOn && root.settings.transitionEffect === transitionChip.modelData.key)
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
                enabled: !transitionChip.isStock
                onHoveredChanged: root.previewTransition = hovered ? transitionChip.modelData.key : (root.previewTransition === transitionChip.modelData.key ? "" : root.previewTransition)
              }
              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: transitionChip.isStock ? root.selectStock() : root.selectTransition(transitionChip.modelData.key)
              }
            }
          }
        }
      }
    }

    // Shuffle, between Transition and Effect -- direct request: "adding
    // the Shuffle interval inbetween Transition and Effect group for
    // Off 5m 15m etc", Effect staying last specifically because its own
    // Intensity/Speed sliders expand underneath it (see that section's
    // own header comment). Same direct-pick chip style as Transition/
    // Effect's own rows (click the exact interval you want), not the
    // notch's single cycling pill -- every other control on this panel
    // is already a direct pick, and there's room here for all five.
    Text { text: "Shuffle"; color: root.hintColor; font.family: root.fontFamily; font.pixelSize: 11 }
    Row {
      spacing: 6
      Repeater {
        model: [{minutes: 0, label: "Off"}, {minutes: 5, label: "5m"}, {minutes: 15, label: "15m"},
          {minutes: 30, label: "30m"}, {minutes: 60, label: "60m"}]
        Rectangle {
          id: shuffleChip
          required property var modelData
          readonly property bool selected: shuffleChip.modelData.minutes === 0
            ? rotationState.settings.enabled !== true
            : (rotationState.settings.enabled === true && rotationState.settings.intervalMinutes === shuffleChip.modelData.minutes)
          width: shuffleChipLabel.implicitWidth + 20
          height: 28
          radius: 8
          color: shuffleChip.selected ? root.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, .05)
          border.width: 1
          border.color: shuffleChip.selected ? root.accent : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, .12)
          Text {
            id: shuffleChipLabel
            anchors.centerIn: parent
            text: shuffleChip.modelData.label
            color: shuffleChip.selected ? "#000000" : root.accent
            font.family: root.fontFamily; font.pixelSize: 11
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: rotationState.selectInterval(shuffleChip.modelData.minutes)
          }
        }
      }
    }

    // Same flat cluster as Transition above (still 6px spacing, same
    // ColumnLayout) -- direct correction: "chips up top section for
    // effect under". Both chip groups now read as one selector block;
    // only Effect's actual expandable content (Intensity/Speed) breaks
    // out into its own section below.
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

    // Effect's own expandable section -- the ONLY thing that grows/
    // shrinks as CRT/Matrix get picked, kept out of the chip cluster
    // above entirely so its own expand/collapse never reflows a single
    // chip. A manual spacer Item, not a second Layout's own `spacing`,
    // for the one real gap -- the nested-ColumnLayout version of this
    // (see content's own header comment) added far more space than its
    // declared spacing accounted for; a flat structure throughout
    // sidesteps whatever caused that instead of chasing it further.
    // clip:true above catches this section if it ever runs past the
    // panel's fixed height instead of spilling into the grid below.
    Item { height: 6; visible: root.backgroundEffectOn }
    RowLayout {
      width: content.width
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
      width: content.width
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

    // Ambient zoom/Theme glow/Disable motion all dropped now -- the
    // first two for being too subtle to read as real options (max
    // ~0.7% scale variance over 3 minutes, ~4% opacity swing over 60s,
    // checked against ruixen.background/Service.qml's own math, not
    // guessed). Disable motion followed on direct correction: "theres
    // no reason for disable motion, that just means turn the effect or
    // transition off anyways" -- Transition Stock + Effect Off already
    // reaches the same "nothing moving" state through controls that
    // already exist, so a third toggle for it wasn't pulling its
    // weight either. Renderer-side support for all three settings is
    // untouched, just no longer exposed from either picker UI.
  }
}
