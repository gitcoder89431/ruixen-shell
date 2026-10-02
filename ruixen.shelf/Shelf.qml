import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

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

    // pathsJson: a JSON array of paths / file:// URLs. source: "user" or
    // "agent" (anything else is treated as "user").
    function addMany(pathsJson: string, source: string): string {
      var paths = []
      try {
        var parsed = JSON.parse(pathsJson)
        if (Array.isArray(parsed)) paths = parsed.map(String)
      } catch (e) {
        return JSON.stringify({ ok: false, error: "pathsJson is not a JSON array" })
      }
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

  readonly property int shelfWidth: 400
  // Grows with the item count, clamped; the window is only ever as big as
  // the visible shelf (no fullscreen surface, no input mask needed).
  readonly property int shelfHeight: service.items.length === 0
    ? 200
    : Math.min(420, 52 + service.items.length * 62 + 12)

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

    Rectangle {
      anchors.fill: parent
      radius: 18
      color: root.surfaceColor
      border.width: 1
      border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.1)

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
          onCloseRequested: root.dismiss()
        }
      }
    }
  }
}
