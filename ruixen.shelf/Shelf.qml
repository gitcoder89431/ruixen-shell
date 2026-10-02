import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import "ShelfModel.js" as ShelfModel

// Ruixen Shelf: a drop pocket for file references, as its own overlay
// plugin. It is deliberately NOT a notch dashboard tab: the expanded
// notch is a modal surface (fullscreen layer + fullscreen input mask +
// Exclusive keyboard focus + click-away dismissal), which is exactly
// wrong for cross-app drag and drop -- the pointer has to leave the
// shelf and reach the real destination app. This window is sized to the
// shelf itself, takes keyboard focus only on demand, has no outside-click
// catcher, and reserves no screen space, so every other app stays
// reachable while it is open.
//
// Entry points:
//   - the host's own lifecycle: `omarchy-shell shell toggle ruixen.shelf`
//     calls open()/close()/toggle() below
//   - this plugin's own IPC target (see IpcHandler): `omarchy-shell
//     ruixen.shelf open|close|toggle|add|addMany|remove|clear|list`
//   - ruixen.notch's collapsed pill, which relays dropped files to `addMany`
//     over that same IPC (no shared live objects between plugins)
//
// ShelfService.qml is the only writer of shelf.json (unchanged path:
// ~/.local/state/ruixen/shelf.json). State survives this window opening
// and closing -- the plugin is keepLoaded.
Item {
  id: root
  property var shell: null
  property var manifest: null

  property bool opened: false

  // --- surface identity ------------------------------------------------
  // Same Black/Theme choice the frame, notch and docked bar share via
  // ~/.local/state/ruixen/bar-surface.json (legacy fallback:
  // frame-appearance.json). Each consumer keeps its own copy of this
  // resolve logic on purpose (AGENTS.md section 9) -- there is no live
  // object link between plugins. Solid material only for now, like the
  // notch itself; a glass pass belongs with the coupled frame/notch one.
  property string surfaceMode: "black"
  property bool surfaceStateLoaded: false
  readonly property color surfaceBlack: "#000000"
  readonly property color surfaceSafeLightForeground: "#e8e8e8"
  readonly property color surfaceSafeDarkForeground: "#101010"
  readonly property color surfaceColor: root.surfaceMode === "theme" ? Color.background : root.surfaceBlack

  function surfaceLuminance(c) {
    return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
  }

  function readableForegroundForSurface(surface, preferred) {
    var surfaceIsLight = root.surfaceLuminance(surface) > 0.5
    var preferredIsLight = root.surfaceLuminance(preferred) > 0.45
    return surfaceIsLight
      ? (preferredIsLight ? root.surfaceSafeDarkForeground : preferred)
      : (preferredIsLight ? preferred : root.surfaceSafeLightForeground)
  }

  readonly property color textColor: readableForegroundForSurface(root.surfaceColor, Color.bar.text)
  readonly property color muted: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5)
  readonly property color accent: Color.accent
  readonly property string fontFamily: "JetBrainsMono Nerd Font"

  function normalizeSurfaceMode(mode) {
    return mode === "theme" ? "theme" : "black"
  }

  function loadSurfaceState(raw) {
    try {
      var p = JSON.parse(String(raw || "").trim() || "{}")
      root.surfaceMode = root.normalizeSurfaceMode(p && p.color)
      root.surfaceStateLoaded = true
    } catch (e) {
      root.surfaceStateLoaded = false
      legacyFrameFile.reload()
    }
  }

  FileView {
    path: Quickshell.env("HOME") + "/.local/state/ruixen/bar-surface.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadSurfaceState(text())
    onLoadFailed: {
      root.surfaceStateLoaded = false
      legacyFrameFile.reload()
    }
  }

  FileView {
    id: legacyFrameFile
    path: Quickshell.env("HOME") + "/.local/state/ruixen/frame-appearance.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      if (root.surfaceStateLoaded) return
      try {
        var p = JSON.parse(String(text() || "").trim() || "{}")
        root.surfaceMode = root.normalizeSurfaceMode(p && p.mode)
      } catch (e) {
        root.surfaceMode = "black"
      }
    }
    onLoadFailed: if (!root.surfaceStateLoaded) root.surfaceMode = "black"
  }

  // --- lifecycle (host contract: open(payloadJson)/close()/toggle(payloadJson))

  function open(payloadJson) {
    root.opened = true
    service.refreshStats()
    Qt.callLater(function() { focusScope.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  // A user-initiated close (Escape, the close button, toggle while open):
  // also tells the host, the way ruixen.launcher's dismiss() does, so its
  // own notion of which overlay is showing stays in sync.
  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "ruixen.shelf")
  }

  function toggle(payloadJson) {
    if (root.opened) root.dismiss()
    else root.open(payloadJson)
  }

  // --- state + agent-facing API ----------------------------------------

  ShelfService {
    id: service
  }

  // Plugin-owned IPC target. Same JSON-returning shape the old notch tab
  // had, under this plugin's own name. `add` is for agents/scripts (items
  // are tagged source "agent" and get the panel's agent badge); `addMany`
  // takes a whole batch in one call with an explicit source -- ruixen.notch's
  // quick-drop uses it so a multi-file drop is one IPC call, not one
  // process per path.
  IpcHandler {
    target: "ruixen.shelf"

    function open(): void { root.open("") }
    function close(): void { if (root.opened) root.dismiss() }
    function toggle(): void { root.toggle("") }

    // Absolute path, file:// URL or ~/ path. Relative paths are rejected
    // (the shell's own working directory is not the caller's).
    function add(path: string): string {
      var result = service.addPaths([path], "agent")
      if (result.added.length === 0)
        return JSON.stringify({ ok: false, error: "not an absolute local path: " + path })
      return JSON.stringify({ ok: true, id: result.added[0] })
    }

    // pathsArg: newline-delimited paths / file:// URLs. source: "user" or
    // "agent" (anything else is treated as "user").
    //
    // NEWLINE-delimited, not a JSON array, and that is load-bearing
    // rather than stylistic. Confirmed live: a bracketed JSON array does
    // not survive the trip through the IPC boundary as one argument.
    // `addMany '["/a","/b"]' user` arrived as THREE arguments and was
    // refused by the host with "Too many arguments provided (2 required
    // but 3 were provided)", with the count tracking the array length
    // exactly; a one-element array arrived as a scalar, so
    // Array.isArray() was false and the call silently added nothing
    // (`{"ok":false,"added":0,"rejected":0}`). Semicolons, newlines and
    // plain comma-separated text all arrive intact as a single argument
    // -- only the bracketed form is torn apart. Newline is used rather
    // than comma or semicolon because `ShelfModel.normalizePath` already
    // rejects any path containing \n or \r, so a newline can never occur
    // inside a legitimate path and there is no ambiguity to encode
    // around.
    //
    // A leading "[" is still parsed as JSON, purely so an in-process
    // caller can keep passing an array literal.
    function addMany(pathsArg: string, source: string): string {
      // Decoding lives in ShelfModel.parsePathsArg so it has real unit
      // tests (tests/js/ShelfModel.test.js); null = bracketed but not a
      // valid JSON array.
      var paths = ShelfModel.parsePathsArg(pathsArg)
      if (paths === null)
        return JSON.stringify({ ok: false, error: "pathsArg is not a JSON array" })
      var result = service.addPaths(paths, source)
      return JSON.stringify({ ok: result.added.length > 0, added: result.added.length, rejected: result.rejected })
    }

    // By id (from list) or by path.
    function remove(idOrPath: string): string {
      return JSON.stringify({ ok: service.removeItem(idOrPath) })
    }

    function clear(): void { service.clear() }

    // {"items":[{id,path,name,source,addedAt,exists,kind,size}]}. "exists"
    // is null until a path has been checked.
    function list(): string { return service.listItems() }
  }

  // --- the window --------------------------------------------------------

  // Deliberately the SAME width as ruixen.notch's own launcherOpen mode
  // (Overlay.qml:1715's 420), so the shelf reads as one more step of the
  // notch's own size progression rather than its own separate family:
  //
  //   284 collapsed -> 420 launcherOpen -> [shelf, also 420] -> 900 pinned
  //
  // 420 is chosen over anything wider deliberately: it is a size this notch
  // has already proven safe, and Overlay.qml's own history (1718-1723, and
  // the "almost square edges" report at 1770-1787) is a history of NEW
  // sizes breaking the notch silhouette's mask non-deterministically, with
  // the breakage only showing up at the larger end. Reusing a proven number
  // is the whole point.
  readonly property int shelfWidth: 420

  // Fixed height now, not item-count driven: the rows scroll HORIZONTALLY
  // (see ShelfContent's own comment), so there is no "taller as it fills"
  // case left to grow into, and a stable footprint is what lets the
  // silhouette below stay one proven shape instead of a resizing one.
  readonly property int shelfHeight: 236

// --- the silhouette ----------------------------------------------------
  //
  // Deliberately NOT reusing ruixin.notch's own notchBg MultiEffect
  // instance, and deliberately not adding shadow properties to an effect of
  // our own here either. Overlay.qml:1770-1787 documents, from a live
  // report, that adding shadow* to that masked shape reproducibly destroys
  // the silhouette ("almost square edges, the curves are gone") and does so
  // non-deterministically -- confirmed absent at the collapsed and 420x190
  // sizes, then present at 900x400. That is why the notch's own shadow
  // works at all: notchShadowBlur duplicates the SAME geometry into its own
  // shape and blurs that, with a separate outer Item (notchShadowClip)
  // deciding where the blur is allowed to spill, rather than shadowing the
  // masked shape directly. This mirrors that arrangement exactly.
  //
  // The geometry itself is simpler than the notch's: it builds the shape
  // from two RoundCorner shoulders plus a square-topped centerMask, because
  // its own flank pieces have to tuck UNDER the shoulders. This window has
  // no such pieces -- it is one plain rounded box -- so a single Rectangle
  // with all four radii set draws exactly the same silhouette, with no seam
  // to hide and nothing to keep in sync. The visible result is identical;
  // the radii below are still the notch's own numbers.
  readonly property int cornerSize: 28
  readonly property int bottomRadius: 44
  // Asymmetric, in the same direction as the notch's own notchShadowClip:
  // flush against the top edge (no gap upward, it has to meet the notch),
  // expanded on the open sides so the blur has room to actually be visible.
  readonly property int shadowClipMargin: 40

  PanelWindow {
    id: win
    visible: root.opened
    // Top-anchored only: a layer surface anchored to one edge is centered
    // along the perpendicular axis, which is where the notch is.
    anchors { top: true }
    // The notch's collapsed bottom edge is 48px (notchCollapsedBottomEdge);
    // a small gap keeps the two surfaces reading as attached without
    // overlapping the notch's own input region.
    margins.top: 52
    implicitWidth: root.shelfWidth
    implicitHeight: root.shelfHeight
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "ruixen-shelf"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // OnDemand, not Exclusive: the shelf must not grab the keyboard from
    // whatever app the user is dragging into/out of. Escape works once the
    // shelf has been clicked.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Where the blur is allowed to spill: asymmetric clip, flush top, room
    // on the other three sides. Same shape of idea as the notch's own.
    Item {
      id: shadowClip
      anchors.fill: parent
      anchors.margins: root.shadowClipMargin
      anchors.topMargin: 0
      clip: true

      // The shadow: a solid duplicate of the real silhouette, blurred into
      // a halo. notchShadowBlur's own recipe byte-for-byte (opacity 1.0,
      // plain blurEnabled/blurMax 32/blur 0.6, NO directional offset) --
      // per AGENTS.md section 9, this is the recipe that was tuned live
      // against the frame's own hand-rolled ring shadow, and it is the one
      // new pieces of this surface are supposed to copy rather than
      // borrowing whatever mask-safe example happens to be nearby.
      Rectangle {
        id: shadowBlur
        anchors.fill: parent
        anchors.margins: root.shadowClipMargin
        anchors.topMargin: 0
        opacity: 1.0

        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
          blurEnabled: true
          blurMax: 32
          blur: 0.6
        }

        color: "#000000"
        topLeftRadius: root.cornerSize
        topRightRadius: root.cornerSize
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
      }
    }

    // The real surface, masked into the same silhouette. Same split as
    // notchBg/notchMask: a MultiEffect that only masks (no shadow), over a
    // plain always-opaque fill.
    Rectangle {
      id: shelfBg
      anchors.fill: parent
      color: root.surfaceColor

      layer.enabled: true
      layer.smooth: true
      layer.effect: MultiEffect {
        maskEnabled: true
        maskSource: shelfMask
        maskThresholdMin: 0.5
        maskThresholdMax: 1.0
        maskSpreadAtMin: 1.0
      }

      Rectangle {
        id: shelfMask
        visible: false
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true

        color: "#ffffff"
        topLeftRadius: root.cornerSize
        topRightRadius: root.cornerSize
        bottomLeftRadius: root.bottomRadius
        bottomRightRadius: root.bottomRadius
      }

      FocusScope {
        id: focusScope
        anchors.fill: parent
        focus: true
        Keys.onEscapePressed: root.dismiss()

        ShelfContent {
          anchors.fill: parent
          active: root.opened
          textColor: root.textColor
          muted: root.muted
          accent: root.accent
          fontFamily: root.fontFamily
          shelfService: service
          // The right-edge fade in ShelfContent has to end on the SAME color
          // the window behind it is filled with, or the fade is a visible
          // grey band instead of an edge. The window's own surfaceColor is
          // not otherwise visible to the content, so it is passed in.
          surfaceColor: root.surfaceColor
          onCloseRequested: root.dismiss()
        }
      }
    }
  }
}
