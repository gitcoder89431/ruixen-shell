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
    root.entries = ClipboardHistory.parseHistory(raw)
    root.loadImageRowLabels()
    if (root.selectedIndex >= root.rows.length) root.selectedIndex = Math.max(0, root.rows.length - 1)
  }

  onRowsChanged: {
    if (root.selectedIndex >= root.rows.length) root.selectedIndex = Math.max(0, root.rows.length - 1)
    if (clipboardResultsList.count > 0) {
      clipboardResultsList.positionViewAtIndex(Math.min(root.selectedIndex + root.scrollOff, root.rows.length - 1), ListView.Contain)
      clipboardResultsList.positionViewAtIndex(Math.max(root.selectedIndex - root.scrollOff, 0), ListView.Contain)
      clipboardResultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }
  }

  onSelectedIndexChanged: {
    if (clipboardResultsList.count > 0) {
      clipboardResultsList.positionViewAtIndex(Math.min(root.selectedIndex + root.scrollOff, root.rows.length - 1), ListView.Contain)
      clipboardResultsList.positionViewAtIndex(Math.max(root.selectedIndex - root.scrollOff, 0), ListView.Contain)
      clipboardResultsList.positionViewAtIndex(root.selectedIndex, ListView.Contain)
    }
  }

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
    imageDimensionsProc.exec(["bash", "-c", "printf '%s|' \"$1\"; file -- \"$1\"", "ruixen-clipboard-image-dimensions", root.selectedEntry.path])
  }

  function loadImageRowLabels() {
    imageRowLabelsProc.exec(["python3", "-c",
      "import json, re, subprocess, sys\n" +
      "history = sys.argv[1]\n" +
      "try:\n" +
      "    data = json.load(open(history))\n" +
      "except Exception:\n" +
      "    print('{}')\n" +
      "    raise SystemExit\n" +
      "out = {}\n" +
      "for entry in data if isinstance(data, list) else []:\n" +
      "    path = entry.get('path') if isinstance(entry, dict) and entry.get('type') == 'image' else None\n" +
      "    if not path or path in out:\n" +
      "        continue\n" +
      "    try:\n" +
      "        info = subprocess.run(['file', '--', path], check=False, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, timeout=1).stdout\n" +
      "    except Exception:\n" +
      "        continue\n" +
      "    matches = re.findall(r'(\\d+)\\s*x\\s*(\\d+)', info, re.I)\n" +
      "    if matches:\n" +
      "        w, h = matches[-1]\n" +
      "        out[path] = f'{w}x{h}'\n" +
      "print(json.dumps(out, separators=(',', ':')))",
      root.historyPath])
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
          root.imageDimensionsByPath = parsed && typeof parsed === "object" ? parsed : ({})
        } catch (e) {
          root.imageDimensionsByPath = ({})
        }
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
        root.imageDimensions = FileSearchRanking.parseFileDimensions(parts.join("|"))
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
