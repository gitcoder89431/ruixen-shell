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
//   - SUPER+D, installed by install.sh --with-shelf-keybind, which binds
//     it to this same IPC (see docs/KEYBINDS.md). Never a forced bind:
//     the installer leaves keybinds alone unless asked, since a plugin that
//     grabs a key without permission can clobber the user's own.
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

  // --- the silhouette: an expanded notch hanging from the frame ------------
  //
  // The same family as ruixen.notch's expanded launcher shape, not a
  // floating box: a body flush with the top of the screen, with a concave
  // "wing" shoulder on each side flaring out to meet the frame, and rounded
  // bottom corners. Built the way the notch builds it -- left flank +
  // square-topped center + right flank, the center overlapping both flanks
  // by seamOverlap so fractional output scales can't show a hairline -- and
  // with the notch's own numbers: 28 shoulders, 44 bottom radius, and a 900
  // body -- the notch's own EXPANDED (pinned) width, not the launcher's 420.
  // Fixed height: the inbox strip scrolls horizontally, so the panel never
  // has to grow.
  //
  // Width choice, and it is the exact thing the notch's own history warns
  // about, so read this before changing the number. Overlay.qml:1687-1692
  // records that 900 is "untested territory for this notch (only 44 and 190
  // are proven safe against the masking bug below)" -- and the bug in
  // question is the one at 1770-1787, where a masked shape's silhouette
  // goes non-deterministically flat at the larger sizes. The notch itself
  // then took 900 anyway for its pinned dashboard, and it holds up live, so
  // 900 is a real, working value and not a hypothetical. It is the right
  // pick here on the merits too: 420 fit ~4 cards of a horizontal strip and
  // spent the rest of its width on empty surface, while 900 shows roughly
  // seven. If the silhouette ever does flatten, that comment is the place
  // to look first.
  //
  // Where it sits: flush under the frame at the notch's own resting offset
  // (notchOuter.restY, 4), centered, so it reads as the notch expanded into
  // a bigger panel rather than a window parked below it. It is wider than
  // the collapsed pill, so while open it covers the pill, the way the
  // launcher's expansion does. (Both are Overlay-layer surfaces; the shelf
  // maps later, so it stacks on top -- live-test item in the PR.)
  readonly property int cornerSize: 28
  readonly property int bottomRadius: 44
  readonly property int seamOverlap: 2
  readonly property int bodyWidth: 900
  readonly property int shapeWidth: bodyWidth + cornerSize * 2
  readonly property int shapeHeight: 236
  // Mirrors ruixen.notch's notchOuter.restY. Keep the two in step.
  readonly property int frameInset: 4
  // The frame visually eats the top few px (it merges into the shelf's own
  // top edge), so content sits a little lower than the shape's top, same
  // nudge the notch applies to its own collapsed row.
  readonly property int contentTopInset: 6
  // Room around the shape for the shadow halo (the window is bigger than
  // the shape by this much on the left, right and bottom, never the top --
  // it has to meet the frame). The INPUT region is still only the shape
  // (mask below), so the halo area is click-through and other apps stay
  // reachable; this is not a fullscreen blocker.
  readonly property int haloPad: 40

  PanelWindow {
    id: win
    visible: root.opened
    // Top-anchored only: a layer surface anchored to one edge is centered
    // along the perpendicular axis, which is where the notch is.
    anchors { top: true }
    margins.top: root.frameInset
    implicitWidth: root.shapeWidth + root.haloPad * 2
    implicitHeight: root.shapeHeight + root.haloPad
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.namespace: "ruixen-shelf"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.exclusionMode: ExclusionMode.Ignore
    // OnDemand, not Exclusive: the shelf must not grab the keyboard from
    // whatever app the user is dragging into/out of. Escape works once the
    // shelf has been clicked.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // Input only where the visible shape is. Without this the halo padding
    // above would silently become a dead strip around the shelf.
    mask: Region {
      x: root.haloPad
      y: 0
      width: root.shapeWidth
      height: root.shapeHeight
    }

    // The shape's own coordinate space, positioned inside the padded window.
    Item {
      id: shape
      x: root.haloPad
      y: 0
      width: root.shapeWidth
      height: root.shapeHeight

      // Shadow. Overlay.qml documents (from a live report) that adding
      // shadow* properties to a MASKED shape destroys the silhouette
      // non-deterministically ("almost square edges, the curves are gone"),
      // so the notch's own shadow is a separate, blurred DUPLICATE of the
      // shape behind it, spilling through an outward-extended clip. This is
      // that arrangement, byte-for-byte on the recipe (AGENTS.md section 9:
      // opacity 1.0, plain blurEnabled / blurMax 32 / blur 0.6, no
      // directional offset), and the clip extends OUT by haloPad on the left,
      // right and bottom, flush at the top where the shape meets the frame.
      Item {
        id: shadowClip
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.leftMargin: -root.haloPad
        anchors.right: parent.right
        anchors.rightMargin: -root.haloPad
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -root.haloPad
        z: -1
        clip: true

        Item {
          id: shadowBlur
          anchors.fill: parent
          anchors.margins: root.haloPad
          anchors.topMargin: 0
          opacity: 1.0

          ShelfRoundCorner {
            anchors.top: parent.top
            anchors.left: parent.left
            cornerSize: root.cornerSize
            corner: 1
            fillColor: "#000000"
          }

          Rectangle {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.leftMargin: root.cornerSize - root.seamOverlap
            anchors.right: parent.right
            anchors.rightMargin: root.cornerSize - root.seamOverlap
            height: parent.height
            color: "#000000"
            topLeftRadius: 0
            topRightRadius: 0
            bottomLeftRadius: root.bottomRadius
            bottomRightRadius: root.bottomRadius
          }

          ShelfRoundCorner {
            anchors.top: parent.top
            anchors.right: parent.right
            cornerSize: root.cornerSize
            corner: 0
            fillColor: "#000000"
          }

          layer.enabled: true
          layer.smooth: true
          layer.effect: MultiEffect {
            blurEnabled: true
            blurMax: 32
            blur: 0.6
          }
        }
      }

      // The real surface, masked into the silhouette. Same split as the
      // notch's notchBg/notchMask: a MultiEffect that only masks (no
      // shadow), over a plain always-opaque fill.
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
      }

      // Mask silhouette: left flank (concave toward the body) + center block
      // (square top, round bottom) + right flank. Never drawn directly --
      // only sampled as a texture by shelfBg's layer.effect above.
      Item {
        id: shelfMask
        visible: false
        anchors.fill: parent
        layer.enabled: true
        layer.smooth: true

        ShelfRoundCorner {
          id: leftFlank
          anchors.top: parent.top
          anchors.left: parent.left
          cornerSize: root.cornerSize
          corner: 1
          fillColor: "#ffffff"
        }

        Rectangle {
          anchors.top: parent.top
          anchors.left: leftFlank.right
          anchors.leftMargin: -root.seamOverlap
          anchors.right: rightFlank.left
          anchors.rightMargin: -root.seamOverlap
          height: parent.height
          color: "#ffffff"
          topLeftRadius: 0
          topRightRadius: 0
          bottomLeftRadius: root.bottomRadius
          bottomRightRadius: root.bottomRadius
        }

        ShelfRoundCorner {
          id: rightFlank
          anchors.top: parent.top
          anchors.right: parent.right
          cornerSize: root.cornerSize
          corner: 0
          fillColor: "#ffffff"
        }
      }

      // Content: a sibling of the masked fill (like the notch's own rows),
      // inset by the shoulders so it lives inside the body, not the wings.
      FocusScope {
        id: focusScope
        anchors.fill: parent
        anchors.leftMargin: root.cornerSize
        anchors.rightMargin: root.cornerSize
        anchors.topMargin: root.contentTopInset
        focus: true
        Keys.onEscapePressed: root.dismiss()
        // Arrows/Home/End scroll the strip whenever the shelf has keyboard
        // focus, not only when the search field or the list holds item
        // focus (clicking a card or empty space leaves neither focused).
        // Only those keys are accepted; everything else, Escape included,
        // falls through to the handlers below and above.
        Keys.onPressed: (event) => shelfContent.handleStripKey(event)

        ShelfContent {
          id: shelfContent
          anchors.fill: parent
          active: root.opened
          textColor: root.textColor
          muted: root.muted
          accent: root.accent
          fontFamily: root.fontFamily
          shelfService: service
          // The right-edge fade in ShelfContent has to end on the SAME color
          // the window behind it is filled with, or the fade is a visible
          // grey band instead of an edge.
          surfaceColor: root.surfaceColor
          onCloseRequested: root.dismiss()
        }
      }
    }
  }
}
