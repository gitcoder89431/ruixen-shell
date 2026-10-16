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
  property color glassTint: "#000000"
  property color glassBorder: Qt.rgba(1, 1, 1, 0.08)
  property string fontFamily: "JetBrainsMono Nerd Font"
  property bool active: false
  property string searchText: ""

  readonly property string searchPlaceholder: "Search Clipboard"
  readonly property bool showsEnterHint: true
  readonly property bool interceptsArrowKeys: true
  readonly property bool rightFocused: root.actionsMenuOpen

  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/clipboard-history.json"
  readonly property string qrCachePath: Quickshell.env("HOME") + "/.local/state/ruixen/clipboard-qr-cache.json"
  // Our own pin layer, independent of Omarchy's own 300-entry history
  // cap -- same FileView/mkdir-p/atomicWrites convention CliampFavorites'
  // own favoritesStatePath uses (see ClipboardHistory.js's own header on
  // pinnedEntries()/togglePinned() for why). Direct ask: "an option to
  // tab and pin an item. so it doesnt get cleared out, pin clipboard
  // items shows uptop in PINNED group."
  readonly property string pinnedStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/clipboard-pinned.json"
  property string lastHistoryRaw: "[]"
  property var entries: []
  property var imageDimensionsByPath: ({})
  property var qrByPath: ({})
  property var pinStats: ({})
  readonly property var pinnedEntries: ClipboardHistory.pinnedEntries(root.pinStats, root.entries, root.qrByPath)
  readonly property bool selectedIsPinned: root.selectedEntry !== null && ClipboardHistory.isPinned(root.pinStats, root.selectedEntry)
  // Chip-row view state (see chipRow below): Type filter + sort.
  property string kindFilter: ""
  property string sortKey: "recent"
  property string sortDirection: "asc"
  readonly property var kindsPresent: ClipboardHistory.kindsPresent(root.entries)
  readonly property var view: ({ kind: root.kindFilter, sort: root.sortKey, direction: root.sortDirection })
  readonly property var rows: ClipboardHistory.rows(root.entries, root.searchText, root.accent, root.imageDimensionsByPath, root.view, root.pinnedEntries)

  function loadPinStats(raw) {
    try {
      var parsed = JSON.parse(String(raw || "").trim() || "{}")
      root.pinStats = (parsed && typeof parsed === "object" && !Array.isArray(parsed)) ? parsed : ({})
    } catch (e) {
      root.pinStats = ({})
    }
  }

  // Keeps the same entry highlighted across a pin/unpin even though it
  // physically moves between the Pinned section and the rest of the
  // list -- same reason loadHistory() below re-finds the selection by
  // identity instead of trusting the old index.
  function reselectByKey(key) {
    if (key === "") return
    for (var i = 0; i < root.rows.length; i++) {
      if (ClipboardHistory.entryKey(root.rows[i].clipboardEntry) === key) {
        root.selectedIndex = i
        return
      }
    }
  }

  function togglePinSelected() {
    if (!root.selectedEntry) return
    var key = ClipboardHistory.entryKey(root.selectedEntry)
    root.pinStats = ClipboardHistory.togglePinned(root.pinStats, root.selectedEntry)
    pinnedFile.setText(JSON.stringify(root.pinStats))
    root.reselectByKey(key)
  }

  function cycleKindFilter() {
    var options = [""].concat(root.kindsPresent)
    var idx = options.indexOf(root.kindFilter)
    root.kindFilter = options[(idx + 1) % options.length]
  }

  function toggleSort(key) {
    if (root.sortKey === key) root.sortDirection = root.sortDirection === "asc" ? "desc" : "asc"
    else { root.sortKey = key; root.sortDirection = "asc" }
  }
  property int selectedIndex: 0
  readonly property var selectedRow: root.rows[root.selectedIndex] || null
  readonly property var selectedEntry: root.selectedRow && root.selectedRow.clipboardEntry ? root.selectedRow.clipboardEntry : null
  readonly property int scrollOff: 2

  // A plain MouseArea.onEntered (ResultRow.qml's own hover signal)
  // can't tell "the cursor moved onto this row" from "this row
  // scrolled under a cursor that never moved" -- keyboard navigation
  // triggers the latter on every list scroll. Same mechanism already
  // fixing the identical bug in Launcher.qml's own main results list,
  // ThemeBrowserContent.qml, and CliampContent.qml (Cliamp Radio's
  // own direct report: "i point and focus on a row then switch to
  // kbd but when i scroll up or down the page snaps back to the
  // cursor focus row" -- confirmed live as the same root cause here):
  // onRowHovered below is a no-op until the HoverHandler observes the
  // pointer at a genuinely different position than wherever it last
  // rested, and every selectedIndex change (keyboard-driven scrolls
  // included) resets that baseline.
  property bool hoverArmed: false
  property point hoverArmBaseline: Qt.point(-1, -1)
  property string pendingImageDetailsPath: ""
  property string imageDimensions: ""
  property string imageSize: ""
  property bool actionsMenuOpen: false
  property int actionsSelectedIndex: 0
  property real actionsMenuX: 0
  property real actionsMenuY: 0
  // Copy first, not Paste -- matches activateSelection()'s own Enter
  // default (copy, never an auto-paste into whatever's focused; see
  // its own comment). Then Paste, Open, then the image-only extras
  // grouped together (QR text/link, path), then Pin (works on any
  // entry, but a management action, not a "do something with the
  // content" one), Reveal (secret-only, a visibility toggle), Delete
  // always last since it's destructive.
  readonly property var clipboardActions: root.selectedEntry ? (function() {
    var out = [
      { id: "copy", label: "Copy" },
      { id: "paste", label: "Paste" },
      { id: "open", label: "Open" }
    ]
    if (root.selectedEntry.qr) out.push({ id: "copy-qr", label: "Copy QR Text" })
    if (root.selectedEntry.qrUrl) out.push({ id: "open-qr", label: "Open QR Link" })
    // Copy, not paste: direct follow-up -- "no reason to paste the path
    // into the launcher search input". The old "Paste Path" wl-copied
    // the path and then simulated a paste keystroke immediately,
    // landing wherever currently had keyboard focus -- the launcher's
    // own search field itself, since nothing closes the launcher
    // first. A path's value is being on the clipboard to paste
    // wherever the user actually wants it (a save dialog, a terminal
    // cd), not an immediate guess at the right target.
    if (root.selectedEntry.type === "image") out.push({ id: "path", label: "Copy Path" })
    out.push({ id: "pin", label: root.selectedIsPinned ? "Unpin" : "Pin" })
    if (root.selectedEntry.secret) out.push({ id: "reveal", label: root.revealed ? "Hide" : "Reveal" })
    out.push({ id: "delete", label: root.deleteArmed ? "Confirm Delete" : "Delete" })
    return out
  })() : []

  function reloadHistory() {
    historyFile.reload()
  }

  function loadHistory(raw) {
    // sourceIndex is just a position in the file and shifts when a new
    // item is copied while the launcher is open, so re-find the
    // highlighted entry by identity instead of keeping the old index.
    var keepKey = root.active ? ClipboardHistory.entryKey(root.selectedEntry) : ""
    root.lastHistoryRaw = String(raw || "[]")
    root.entries = ClipboardHistory.parseHistory(root.lastHistoryRaw, root.qrByPath)
    if (keepKey !== "") {
      for (var i = 0; i < root.rows.length; i++) {
        if (ClipboardHistory.entryKey(root.rows[i].clipboardEntry) === keepKey) {
          root.selectedIndex = i
          break
        }
      }
    }
    if (root.kindFilter !== "" && root.kindsPresent.indexOf(root.kindFilter) === -1) root.kindFilter = ""
    root.requestImageLabels()
    root.requestQrPayloads()
    if (root.selectedIndex >= root.rows.length) root.selectedIndex = Math.max(0, root.rows.length - 1)
  }

  function loadQrCache(raw) {
    try {
      var parsed = JSON.parse(String(raw || "{}"))
      root.qrByPath = parsed && typeof parsed === "object" && !Array.isArray(parsed) ? parsed : {}
    } catch (e) {
      root.qrByPath = {}
    }
    root.entries = ClipboardHistory.parseHistory(root.lastHistoryRaw, root.qrByPath)
    root.requestQrPayloads()
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

  onSelectedIndexChanged: {
    root.hoverArmed = false
    root.hoverArmBaseline = Qt.point(-1, -1)
    root.ensureSelectionVisible()
  }

  onSelectedEntryChanged: {
    root.deleteArmedKey = ""
    root.revealedKey = ""
    root.actionsMenuOpen = false
    root.loadPathStatus()
    root.loadImageDetails()
  }

  onActiveChanged: {
    if (root.active) {
      root.reloadHistory()
      root.selectedIndex = 0
      root.hoverArmed = false
      root.hoverArmBaseline = Qt.point(-1, -1)
      Qt.callLater(function() { clipboardResultsList.positionViewAtBeginning() })
    }
  }

  function moveSelectionUp() {
    if (root.actionsMenuOpen) {
      if (root.actionsSelectedIndex > 0) root.actionsSelectedIndex--
      return
    }
    if (root.selectedIndex > 0) root.selectedIndex--
  }

  function moveSelectionDown() {
    if (root.actionsMenuOpen) {
      if (root.actionsSelectedIndex < root.clipboardActions.length - 1) root.actionsSelectedIndex++
      return
    }
    if (root.selectedIndex < root.rows.length - 1) root.selectedIndex++
  }

  function activateSelection() {
    if (root.actionsMenuOpen) {
      var action = root.clipboardActions[root.actionsSelectedIndex]
      if (action) root.runClipboardAction(action.id)
      return
    }
    root.copySelected()
  }

  function focusRightPanel() {
    if (root.actionsMenuOpen) {
      root.closeActionsMenu()
      return
    }
    root.openActionsMenu()
  }

  function blurToLeftPanel() {
    root.closeActionsMenu()
  }

  function openActionsMenu() {
    if (root.clipboardActions.length === 0) return
    root.actionsSelectedIndex = 0
    root.actionsMenuOpen = true
    root.positionActionsMenuNearSelection()
  }

  function closeActionsMenu() {
    root.actionsMenuOpen = false
  }

  function positionActionsMenuNearSelection() {
    var item = clipboardResultsList.itemAtIndex(root.selectedIndex)
    if (!item) return
    var scenePos = item.mapToItem(null, 0, item.height)
    var localPos = root.mapFromItem(null, scenePos.x, scenePos.y)
    var menuHeight = root.clipboardActions.length * 34 + 8
    root.actionsMenuX = Math.max(8, Math.min(localPos.x + 6, root.width - clipboardResultsList.width - 8))
    root.actionsMenuY = Math.max(chipRow.height + 8, Math.min(localPos.y + 4, root.height - menuHeight - 8))
  }

  function runClipboardAction(id) {
    if (id === "paste") root.pasteSelected()
    else if (id === "copy") root.copySelected()
    else if (id === "open") root.openSelected()
    else if (id === "copy-qr") root.copyQrSelected()
    else if (id === "open-qr") root.openQrSelected()
    else if (id === "path") root.copySelectedPath()
    else if (id === "reveal") root.toggleReveal()
    else if (id === "pin") root.togglePinSelected()
    else if (id === "delete") root.deleteSelected()
    if (!(id === "delete" && root.deleteArmed)) root.closeActionsMenu()
  }

  // sourceIndex -1 is a pinned entry Omarchy's own history cap has
  // already dropped (see ClipboardHistory.js's own pinnedEntries()) --
  // there's no live history-index to hand the native helper, so these
  // fall back to the raw text/path it was pinned with directly. The
  // image branch already always used a direct path, never an index, so
  // it was purge-safe before pinning existed and needs no change here.
  function pasteSelected() {
    if (!root.selectedEntry) return
    if (root.selectedEntry.type === "text" || root.selectedEntry.type === "link") {
      if (root.selectedEntry.sourceIndex < 0) {
        pasteTextProc.exec(["omarchy-clipboard-paste-text", "--shift-insert", root.selectedEntry.text])
      } else {
        pasteTextProc.exec(["omarchy-clipboard-paste-text", "--history-index", String(root.selectedEntry.sourceIndex)])
      }
    } else if (root.selectedEntry.type === "image") {
      pasteFileProc.exec(["omarchy-clipboard-paste-file", root.selectedEntry.mime || "image/png", root.selectedEntry.path])
    }
  }

  function copySelected() {
    if (!root.selectedEntry) return
    if (root.selectedEntry.type === "text" || root.selectedEntry.type === "link") {
      if (root.selectedEntry.sourceIndex < 0) {
        pasteTextProc.exec(["omarchy-clipboard-paste-text", "--copy-only", root.selectedEntry.text])
      } else {
        pasteTextProc.exec(["omarchy-clipboard-paste-text", "--copy-only", "--history-index", String(root.selectedEntry.sourceIndex)])
      }
    } else if (root.selectedEntry.type === "image") {
      pasteFileProc.exec(["omarchy-clipboard-paste-file", "--copy-only", root.selectedEntry.mime || "image/png", root.selectedEntry.path])
    }
  }

  function openSelected() {
    if (!root.selectedEntry) return
    var e = root.selectedEntry
    if (e.subtype === "path") {
      openProc.exec(["xdg-open", ClipboardHistory.expandHome(e.text, Quickshell.env("HOME"))])
    } else if (e.subtype === "email") {
      openProc.exec(["xdg-open", "mailto:" + e.text.trim()])
    } else if (e.qrUrl) {
      openProc.exec(["omarchy-launch-browser", e.qrUrl])
    } else if (e.type === "link") {
      // Position-independent for every link, not just a purged pin --
      // omarchy-clipboard-open's own open_text() would just detect this
      // same URL and do the same thing, one history-index lookup later.
      openProc.exec(["omarchy-launch-browser", e.text])
    } else if (e.sourceIndex >= 0) {
      openProc.exec(["omarchy-clipboard-open", "--history-index", String(e.sourceIndex)])
    }
    // else: a purged pin that's plain text/JSON/color/secret has no
    // live index to open by and no direct equivalent here -- Open is
    // silently unavailable for it until it's copied again.
  }

  function copyQrSelected() {
    if (!root.selectedEntry || !root.selectedEntry.qr) return
    qrTextProc.exec(["wl-copy", root.selectedEntry.qr])
  }

  function openQrSelected() {
    if (!root.selectedEntry || !root.selectedEntry.qrUrl) return
    openProc.exec(["omarchy-launch-browser", root.selectedEntry.qrUrl])
  }

  // Two-step delete: the first request arms it for the highlighted entry
  // (the details panel relabels to "Press again to delete"), the second
  // on that same entry removes it. Moving the selection disarms.
  property string deleteArmedKey: ""
  readonly property bool deleteArmed: root.selectedEntry !== null && root.deleteArmedKey === ClipboardHistory.entryKey(root.selectedEntry)

  function deleteSelected() {
    if (!root.selectedEntry) return
    var key = ClipboardHistory.entryKey(root.selectedEntry)
    if (root.deleteArmedKey !== key) {
      root.deleteArmedKey = key
      return
    }
    root.deleteArmedKey = ""
    var e = root.selectedEntry
    if (root.selectedIsPinned) root.togglePinSelected()
    // A purged pin (see pasteSelected()'s own comment above) has
    // nothing left in the live history to delete -- unpinning it above
    // is the whole delete.
    if (e.sourceIndex < 0) return
    // Identity-matched, never a bare index: the history file can have
    // shifted since this row was drawn. Atomic temp+rename rewrite; an
    // ambiguous or vanished entry aborts rather than guessing.
    deleteProc.exec(["python3", "-c",
      "import json, os, sys, tempfile\n" +
      "history, kind, captured, ident, hint = sys.argv[1:6]\n" +
      "try:\n" +
      "    with open(history) as f:\n" +
      "        data = json.load(f)\n" +
      "except Exception:\n" +
      "    print('error'); raise SystemExit\n" +
      "if not isinstance(data, list):\n" +
      "    print('error'); raise SystemExit\n" +
      "def utf16len(s):\n" +
      "    return len(s.encode('utf-16-le', 'surrogatepass')) // 2\n" +
      "def same(e):\n" +
      "    if not isinstance(e, dict) or e.get('type') != kind:\n" +
      "        return False\n" +
      "    if (e.get('capturedAt') or '') != captured:\n" +
      "        return False\n" +
      "    if kind == 'image':\n" +
      "        return e.get('path') == ident\n" +
      "    return isinstance(e.get('text'), str) and str(utf16len(e['text'])) == ident\n" +
      "hits = [i for i, e in enumerate(data) if same(e)]\n" +
      "try:\n" +
      "    hint = int(hint)\n" +
      "except ValueError:\n" +
      "    hint = -1\n" +
      "idx = hint if hint in hits else (hits[0] if len(hits) == 1 else -1)\n" +
      "if idx < 0:\n" +
      "    print('ambiguous' if hits else 'gone'); raise SystemExit\n" +
      "removed = data.pop(idx)\n" +
      "fd, tmp = tempfile.mkstemp(dir=os.path.dirname(history), prefix='.clipboard-history.')\n" +
      "with os.fdopen(fd, 'w') as f:\n" +
      "    json.dump(data, f)\n" +
      "os.replace(tmp, history)\n" +
      "if kind == 'image':\n" +
      "    path = removed.get('path') or ''\n" +
      "    still = any(isinstance(e, dict) and e.get('path') == path for e in data)\n" +
      "    if path and not still and os.path.basename(os.path.dirname(path)) == 'clipboard-images':\n" +
      "        try:\n" +
      "            os.remove(path)\n" +
      "        except OSError:\n" +
      "            pass\n" +
      "print('ok')\n",
      root.historyPath, e.type === "image" ? "image" : "text", e.capturedAt || "",
      e.type === "image" ? e.path : String(e.text.length), String(e.sourceIndex)])
  }

  // Masked-secret reveal is per-entry and resets with the selection.
  property string revealedKey: ""
  readonly property bool revealed: root.selectedEntry !== null && root.revealedKey === ClipboardHistory.entryKey(root.selectedEntry)

  function toggleReveal() {
    if (!root.selectedEntry || !root.selectedEntry.secret) return
    root.revealedKey = root.revealed ? "" : ClipboardHistory.entryKey(root.selectedEntry)
  }

  // Alt+<key>, routed here by Launcher.qml via the generic extension
  // handleShortcut(key) hook.
  function handleShortcut(key) {
    if (key === Qt.Key_C) root.copySelected()
    else if (key === Qt.Key_O) root.openSelected()
    else if (key === Qt.Key_P) root.copySelectedPath()
    else if (key === Qt.Key_R) root.toggleReveal()
    else if (key === Qt.Key_I) root.togglePinSelected()
    else if (key === Qt.Key_D || key === Qt.Key_Delete || key === Qt.Key_Backspace) root.deleteSelected()
  }

  // Copies the path onto the clipboard and stops -- no paste keystroke.
  // Direct follow-up: "no reason to paste the path into the launcher
  // search input". The old version simulated a paste immediately after
  // copying, which landed wherever currently had keyboard focus: the
  // launcher's own search field, since nothing closes the launcher
  // first. A path is useful ON the clipboard, to paste wherever the
  // user actually wants it -- a save dialog, a terminal -- not
  // auto-typed into a guessed target.
  function copySelectedPath() {
    if (!root.selectedEntry || root.selectedEntry.type !== "image") return
    copyPathProc.exec(["wl-copy", root.selectedEntry.path])
  }

  property string pendingPathStatusPath: ""
  property string pathStatus: ""

  function loadPathStatus() {
    root.pendingPathStatusPath = ""
    root.pathStatus = ""
    pathStatusProc.running = false
    var e = root.selectedEntry
    if (!e || e.subtype !== "path") return
    root.pendingPathStatusPath = e.text.trim()
    pathStatusProc.exec(["bash", "-c",
      "printf '%s\\n' \"$1\"; if [ -e \"$2\" ]; then stat --format='%F|%s' -- \"$2\"; else printf MISSING; fi",
      "ruixen-clipboard-path-status", e.text.trim(), ClipboardHistory.expandHome(e.text, Quickshell.env("HOME"))])
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
  readonly property int qrProbeLimit: 20
  readonly property int qrCacheLimit: 300
  property bool imageLabelsDirty: false
  property bool qrPayloadsDirty: false

  function requestImageLabels() {
    if (imageRowLabelsProc.running) {
      root.imageLabelsDirty = true
      return
    }
    var paths = ClipboardHistory.pathsToProbe(root.entries.concat(root.pinnedEntries), root.imageDimensionsByPath, root.imageProbeLimit)
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

  function requestQrPayloads() {
    if (qrPayloadsProc.running) {
      root.qrPayloadsDirty = true
      return
    }
    var paths = ClipboardHistory.qrPathsToProbe(root.entries.concat(root.pinnedEntries), root.qrByPath, root.qrProbeLimit)
    if (paths.length === 0) return
    qrPayloadsProc.exec(["python3", "-c",
      "import json, shutil, subprocess, sys\n" +
      "out = {}\n" +
      "zbar = shutil.which('zbarimg')\n" +
      "for path in sys.argv[1:]:\n" +
      "    payload = ''\n" +
      "    if zbar:\n" +
      "        try:\n" +
      "            r = subprocess.run([zbar, '-q', '--raw', '--', path], check=False, stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, timeout=3)\n" +
      "            if r.returncode == 0:\n" +
      "                payload = r.stdout.decode('utf-8', 'replace').rstrip('\\n')\n" +
      "        except Exception:\n" +
      "            payload = ''\n" +
      "    out[path] = payload\n" +
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

  FileView {
    id: qrCacheFile
    path: root.qrCachePath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadQrCache(text())
    onLoadFailed: root.loadQrCache("{}")
  }

  // mkdir -p before pinnedFile's first write rather than assuming
  // ~/.local/state/ruixen already exists -- same belt-and-suspenders
  // pattern CliampContent.qml's own favoritesFile uses.
  Process {
    id: ensurePinnedDirProc
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/ruixen"]
  }
  Component.onCompleted: ensurePinnedDirProc.running = true

  FileView {
    id: pinnedFile
    path: root.pinnedStatePath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.loadPinStats(text())
    onLoadFailed: root.loadPinStats("")
  }

  Process { id: pasteTextProc }
  Process { id: pasteFileProc }
  Process { id: openProc }
  Process { id: copyPathProc }
  Process { id: qrTextProc }
  Process {
    id: pathStatusProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var nl = text.indexOf("\n")
        if (nl < 0) return
        if (text.slice(0, nl) !== root.pendingPathStatusPath) return
        var info = text.slice(nl + 1).trim()
        if (info === "MISSING") { root.pathStatus = "Not found"; return }
        var parts = info.split("|")
        var kind = (parts[0] || "").toLowerCase()
        root.pathStatus = kind === "regular file" || kind === "regular empty file"
          ? "File, " + LauncherHelpers.formatSize(parseInt(parts[1], 10) || 0)
          : (kind || "Exists")
      }
    }
  }
  Process {
    id: deleteProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.reloadHistory()
    }
  }

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
    id: qrPayloadsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text || "{}")
          if (parsed && typeof parsed === "object") {
            root.qrByPath = ClipboardHistory.mergeQr(root.qrByPath, parsed, root.qrCacheLimit)
            qrCacheFile.setText(JSON.stringify(root.qrByPath, null, 2) + "\n")
            root.entries = ClipboardHistory.parseHistory(root.lastHistoryRaw, root.qrByPath)
          }
        } catch (e) {}
      }
    }
    onRunningChanged: {
      if (!running && root.qrPayloadsDirty) {
        root.qrPayloadsDirty = false
        root.requestQrPayloads()
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

  // Same look as the theme browser's chip row (24px pills, same tint):
  // Type cycles through the kinds present (right-click resets to All);
  // Recent / Type are the sort key, and clicking the active one flips
  // direction.
  Item {
    id: chipRow
    anchors.top: parent.top
    anchors.left: parent.left
    anchors.right: parent.right
    height: 32

    Row {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      spacing: 6

      Rectangle {
        width: Math.max(76, kindChipLabel.implicitWidth + 20)
        height: 24
        radius: 6
        color: root.kindFilter !== "" ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : Qt.rgba(1, 1, 1, 0.06)
        border.width: 1
        border.color: root.kindFilter !== "" ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) : Qt.rgba(1, 1, 1, 0.12)

        Text {
          id: kindChipLabel
          anchors.centerIn: parent
          text: "Type: " + (root.kindFilter === "" ? "All" : root.kindFilter)
          color: root.textColor
          font.family: root.fontFamily
          font.pixelSize: 11
        }

        MouseArea {
          anchors.fill: parent
          acceptedButtons: Qt.LeftButton | Qt.RightButton
          cursorShape: Qt.PointingHandCursor
          onClicked: (mouse) => {
            if (mouse.button === Qt.RightButton) root.kindFilter = ""
            else root.cycleKindFilter()
          }
        }
      }

      Repeater {
        model: [{ key: "recent", label: "Recent" }, { key: "type", label: "By Type" }]

        Rectangle {
          required property var modelData
          readonly property bool isActive: root.sortKey === modelData.key
          width: sortChipLabel.implicitWidth + 16
          height: 24
          radius: 6
          color: isActive ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.18) : Qt.rgba(1, 1, 1, 0.06)
          border.width: 1
          border.color: isActive ? Qt.rgba(root.accent.r, root.accent.g, root.accent.b, 0.45) : Qt.rgba(1, 1, 1, 0.12)

          Text {
            id: sortChipLabel
            anchors.centerIn: parent
            text: modelData.label + (isActive ? (root.sortDirection === "asc" ? " \u2191" : " \u2193") : "")
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 11
          }

          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleSort(modelData.key)
          }
        }
      }
    }
  }

  ExtensionTwoPanel {
    id: panel
    anchors.top: chipRow.bottom
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.bottom: parent.bottom
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
    // !root.rightFocused -- same fix KanbanBoardContent.qml's own
    // onRowHovered needed (see that file's own comment for the full
    // "why"): opening the actions menu via Tab leaves the real mouse
    // cursor wherever it already was, so reaching for the menu with the
    // mouse crosses other rows first, each one's own hover reselecting
    // and closing the menu before the click could land.
    onRowHovered: (idx) => { if (root.hoverArmed && !root.rightFocused) root.selectedIndex = idx }
    onRowActivated: (idx) => { root.selectedIndex = idx; root.copySelected() }
    onRowActionsRequested: (idx) => {
      root.selectedIndex = idx
      root.openActionsMenu()
    }

    // Arms hoverArmed (see its own property comment above) on the
    // first REAL pointer movement -- a passive input handler, not a
    // MouseArea, so it observes pointer events over the whole list
    // without stealing anything from each row's own MouseArea
    // beneath it. The first onPointChanged after any reset is
    // captured as a baseline instead of treated as movement, so a
    // content-shift-under-a-still-cursor (this list scrolling itself
    // under the keyboard above) is never mistaken for the user's
    // hand actually moving.
    HoverHandler {
      onPointChanged: {
        if (root.hoverArmed) return
        if (root.hoverArmBaseline.x < 0) {
          root.hoverArmBaseline = point.position
          return
        }
        if (Math.abs(point.position.x - root.hoverArmBaseline.x) > 0.5
            || Math.abs(point.position.y - root.hoverArmBaseline.y) > 0.5)
          root.hoverArmed = true
      }
    }
  }

  ResultActionsMenu {
    parent: root
    x: root.actionsMenuX
    y: root.actionsMenuY
    visible: root.actionsMenuOpen
    actions: root.clipboardActions
    selectedIndex: root.actionsSelectedIndex
    textColor: root.textColor
    accentColor: root.accent
    glassTint: root.glassTint
    glassBorder: root.glassBorder
    fontFamily: root.fontFamily
    menuWidth: clipboardResultsList.width - 12
    onActionHovered: (idx) => root.actionsSelectedIndex = idx
    onActionActivated: (id) => root.runClipboardAction(id)
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
    deleteArmed: root.deleteArmed
    revealed: root.revealed
    pathStatus: root.pathStatus
    onRevealRequested: root.toggleReveal()
    filtered: (root.searchText.trim() !== "" || root.kindFilter !== "") && root.entries.length > 0
    onCopyPathRequested: root.copySelectedPath()
    pinned: root.selectedIsPinned
    onPinRequested: root.togglePinSelected()
    onDeleteRequested: root.deleteSelected()
  }
}
