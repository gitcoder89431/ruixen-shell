import QtQuick
import Quickshell
import Quickshell.Io
import "../.."
import "ClipboardHistory.js" as ClipboardHistory
import "../../search/FileSearchRanking.js" as FileSearchRanking
import "../../search/LauncherHelpers.js" as LauncherHelpers

Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"
  property bool active: false
  property string searchText: ""

  readonly property string searchPlaceholder: "Search Clipboard"
  readonly property bool showsEnterHint: true
  readonly property bool interceptsArrowKeys: true

  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  property var entries: []
  property var imageDimensionsByPath: ({})
  readonly property var rows: ClipboardHistory.rows(root.entries, root.searchText, root.accent, root.imageDimensionsByPath)
  property int selectedIndex: 0
  readonly property var selectedRow: root.rows[root.selectedIndex] || null
  readonly property var selectedEntry: root.selectedRow && root.selectedRow.clipboardEntry ? root.selectedRow.clipboardEntry : null
  readonly property int scrollOff: 2
  property string pendingImageDetailsPath: ""
  property string imageDimensions: ""
  property string imageSize: ""

  function reloadHistory() {
    historyFile.reload()
  }

  function loadHistory(raw) {
    // sourceIndex is just a position in the file and shifts when a new
    // item is copied while the launcher is open, so re-find the
    // highlighted entry by identity instead of keeping the old index.
    var keepKey = root.active ? ClipboardHistory.entryKey(root.selectedEntry) : ""
    root.entries = ClipboardHistory.parseHistory(raw)
    if (keepKey !== "") {
      for (var i = 0; i < root.rows.length; i++) {
        if (ClipboardHistory.entryKey(root.rows[i].clipboardEntry) === keepKey) {
          root.selectedIndex = i
          break
        }
      }
    }
    root.requestImageLabels()
    if (root.selectedIndex >= root.rows.length) root.selectedIndex = Math.max(0, root.rows.length - 1)
  }

  function ensureSelectionVisible() {
    if (clipboardResultsList.count === 0) return
    clipboardResultsList.positionViewAtIndex(Math.min(root.selectedIndex + root.scrollOff, root.rows.length - 1), ListView.Contain)
    clipboardResultsList.positionViewAtIndex(Math.max(root.selectedIndex - root.scrollOff, 0), ListView.Contain)
    clipboardResultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
  }

  onRowsChanged: {
    if (root.selectedIndex >= root.rows.length) root.selectedIndex = Math.max(0, root.rows.length - 1)
    root.ensureSelectionVisible()
  }

  onSelectedIndexChanged: root.ensureSelectionVisible()

  onSelectedEntryChanged: root.loadImageDetails()

  onActiveChanged: {
    if (root.active) {
      root.reloadHistory()
      root.selectedIndex = 0
      Qt.callLater(function() { clipboardResultsList.positionViewAtBeginning() })
    }
  }

  function moveSelectionUp() {
    if (root.selectedIndex > 0) root.selectedIndex--
  }

  function moveSelectionDown() {
    if (root.selectedIndex < root.rows.length - 1) root.selectedIndex++
  }

  function activateSelection() {
    root.pasteSelected()
  }

  function pasteSelected() {
    if (!root.selectedEntry) return
    if (root.selectedEntry.type === "text" || root.selectedEntry.type === "link") {
      pasteTextProc.exec(["omarchy-clipboard-paste-text", "--history-index", String(root.selectedEntry.sourceIndex)])
    } else if (root.selectedEntry.type === "image") {
      pasteFileProc.exec(["omarchy-clipboard-paste-file", root.selectedEntry.mime || "image/png", root.selectedEntry.path])
    }
  }

  function copySelected() {
    if (!root.selectedEntry) return
    if (root.selectedEntry.type === "text" || root.selectedEntry.type === "link") {
      pasteTextProc.exec(["omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(root.selectedEntry.sourceIndex)])
    } else if (root.selectedEntry.type === "image") {
      pasteFileProc.exec(["omarchy-clipboard-paste-file", "--copy-only", root.selectedEntry.mime || "image/png", root.selectedEntry.path])
    }
  }

  function openSelected() {
    if (!root.selectedEntry) return
    openProc.exec(["omarchy-clipboard-open", "--history-index", String(root.selectedEntry.sourceIndex)])
  }

  function pasteSelectedPath() {
    if (!root.selectedEntry || root.selectedEntry.type !== "image") return
    pastePathProc.exec(["bash", "-c",
      "set -euo pipefail\n" +
      "printf '%s' \"$1\" | wl-copy\n" +
      "sleep 0.15\n" +
      "class=$(hyprctl activewindow -j 2>/dev/null | jq -r '.class // \"\"' 2>/dev/null || true)\n" +
      "case \"$class\" in\n" +
      "  kitty|Alacritty|org.wezfurlong.wezterm|foot|ghostty|com.mitchellh.ghostty) wtype -M shift -k Insert -m shift 2>/dev/null || true ;;\n" +
      "  *) wtype -M ctrl -k v -m ctrl 2>/dev/null || true ;;\n" +
      "esac",
      "ruixen-clipboard-paste-path", root.selectedEntry.path])
  }

  function loadImageDetails() {
    root.pendingImageDetailsPath = ""
    root.imageDimensions = ""
    root.imageSize = ""
    imageStatProc.running = false
    imageDimensionsProc.running = false
    if (!root.selectedEntry || root.selectedEntry.type !== "image" || !root.selectedEntry.path) return
    root.pendingImageDetailsPath = root.selectedEntry.path
    imageStatProc.exec(["stat", "--format=%s|%n", "--", root.selectedEntry.path])
    imageDimensionsProc.exec(["bash", "-c", "printf '%s|' \"$1\"; if [ -e \"$1\" ]; then file -- \"$1\"; else printf MISSING; fi", "ruixen-clipboard-image-dimensions", root.selectedEntry.path])
  }

  // Image row labels ("Image (1600x1200)"): probe only paths we haven't
  // seen yet, capped per run, in one worker at a time. Results merge by
  // path (a path's dimensions never change), so a late result from an
  // older run can't overwrite anything newer; a reload that arrives
  // mid-run just marks the worker dirty and reruns after its real exit.
  readonly property int imageProbeLimit: 40
  readonly property int imageCacheLimit: 300
  property bool imageLabelsDirty: false

  function requestImageLabels() {
    if (imageRowLabelsProc.running) {
      root.imageLabelsDirty = true
      return
    }
    var paths = ClipboardHistory.pathsToProbe(root.entries, root.imageDimensionsByPath, root.imageProbeLimit)
    if (paths.length === 0) return
    imageRowLabelsProc.exec(["python3", "-c",
      "import json, re, subprocess, sys\n" +
      "out = {}\n" +
      "for path in sys.argv[1:]:\n" +
      "    try:\n" +
      "        info = subprocess.run(['file', '--', path], check=False, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=1).stdout\n" +
      "    except Exception:\n" +
      "        out[path] = ''\n" +
      "        continue\n" +
      "    matches = re.findall(r'(\\d+)\\s*x\\s*(\\d+)', info, re.I)\n" +
      "    out[path] = f'{matches[-1][0]}x{matches[-1][1]}' if matches else ''\n" +
      "print(json.dumps(out, separators=(',', ':')))"].concat(paths))
  }

  FileView {
    id: historyFile
    path: root.historyPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadHistory(text())
    onLoadFailed: root.loadHistory("[]")
  }

  Process { id: pasteTextProc }
  Process { id: pasteFileProc }
  Process { id: openProc }
  Process { id: pastePathProc }

  Process {
    id: imageRowLabelsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "{}")
          if (parsed && typeof parsed === "object")
            root.imageDimensionsByPath = ClipboardHistory.mergeDimensions(root.imageDimensionsByPath, parsed, root.imageCacheLimit)
        } catch (e) {}
      }
    }
    onRunningChanged: {
      if (!running && root.imageLabelsDirty) {
        root.imageLabelsDirty = false
        root.requestImageLabels()
      }
    }
  }

  Process {
    id: imageStatProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = text.trim().split("|")
        if (parts.length < 2) return
        var path = parts.slice(1).join("|")
        if (path !== root.pendingImageDetailsPath) return
        root.imageSize = LauncherHelpers.formatSize(parseInt(parts[0], 10) || 0)
      }
    }
  }

  Process {
    id: imageDimensionsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = text.split("|")
        if (parts.length < 2) return
        var path = parts.shift()
        if (path !== root.pendingImageDetailsPath) return
        var info = parts.join("|")
        if (info === "MISSING") {
          root.imageDimensions = "File missing"
          root.imageSize = "File missing"
          return
        }
        root.imageDimensions = FileSearchRanking.parseFileDimensions(info) || "Unknown"
      }
    }
  }

  ExtensionTwoPanel {
    id: panel
    anchors.fill: parent
    detailRatio: 0.6
  }

  ResultsList {
    id: clipboardResultsList
    parent: panel.leftPane
    anchors.fill: parent
    model: root.rows
    fontFamily: root.fontFamily
    mutedColor: root.muted
    textColor: root.textColor
    accentColor: root.accent
    filesMode: true
    selectedIndex: root.selectedIndex
    rowHeightPx: 44
    sectionHeaderHeight: 26
    onRowHovered: (idx) => root.selectedIndex = idx
    onRowActivated: (idx) => { root.selectedIndex = idx; root.pasteSelected() }
  }

  ClipboardDetailsPanel {
    parent: panel.rightPane
    anchors.fill: parent
    row: root.selectedRow
    imageDimensions: root.imageDimensions
    imageSize: root.imageSize
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onPasteRequested: root.pasteSelected()
    onCopyRequested: root.copySelected()
    onOpenRequested: root.openSelected()
    onPastePathRequested: root.pasteSelectedPath()
  }
}
