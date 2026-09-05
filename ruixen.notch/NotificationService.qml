import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "NotificationModel.js" as NotificationModel

// Backing store for the notch's own notification history card (Column 3
// of the Widgets dashboard -- see DashboardContent.qml). Approach
// studied directly from BitYoungjae/byj-omarchy-notifications (MIT):
// attach to Omarchy's own first-party omarchy.notifications service
// in-process rather than running a second notification daemon, and add
// the two things that service has no reason to keep on its own --
// a read flag per notification, and a backlog deeper than the 10
// entries its own history directory retains.
//
// Deliberate scope difference from that project: no toast-outliving
// click-through. Its LiveNotifications.qml keeps a notification "open"
// at the sender past its own toast by swapping in stand-in objects
// inside the first-party service's private internals (liveRefs,
// popupModel, refreshPopup, ...) so a row click can still run a
// sender's exact default action minutes later. Confirmed that Omarchy
// 4.0.2-1 on this machine really does expose everything that needs --
// but those are undocumented internals, not a public API, and that
// mechanism is the one part of the reference project genuinely likely
// to break on some future Omarchy release. This service instead reads
// two things every real service here already treats as safe, ordinary
// data: an action toast's own execArgv role (written into the plain
// snapshot, no live object involved), and Omarchy's own
// omarchy-hyprland-focus-app for bringing the sender's window forward.
// A future pass can add the deeper mechanism if it turns out to be
// worth the fragility -- see COMPATIBILITY.md if it ever does, the
// same way every other host-contract dependency here is tracked.
Item {
  id: service

  // Injected by Overlay.qml, same as every other service reference
  // this plugin already threads through (mediaService, etc).
  property var shell: null

  readonly property var source: shell && typeof shell.firstPartyServiceFor === "function"
    ? shell.firstPartyServiceFor("omarchy.notifications") : null
  readonly property bool sourceReady: source !== null && source !== undefined

  readonly property string home: Quickshell.env("HOME")
  // Flat under ~/.local/state/ruixen/, matching every other piece of
  // state this plugin already keeps there (launcher-favorites.json,
  // avatar.json, animation-profile) rather than a second, plugin-named
  // subdirectory.
  readonly property string storePath: home + "/.local/state/ruixen/notifications-store.json"

  // Where the first-party service parks a notification that never
  // reached the screen at all -- the do-not-disturb backstop below.
  // Everything else is picked up from popupModel, in process, the
  // moment it happens.
  readonly property string sourceHistoryDir: home + "/.local/state/omarchy/notifications/history/"

  // The first-party history directory itself is capped at 10; this is
  // the reason the card can show more than that.
  readonly property int retention: 200

  // Newest-first plain snapshots -- never the live Notification objects
  // themselves, which die with their sender.
  property var entries: []

  readonly property int unreadCount: {
    var n = 0
    for (var i = 0; i < entries.length; i++) if (entries[i].unread) n++
    return n
  }

  // Notifications cleared out of the card. The first-party history is
  // left as it is -- not this plugin's state to wipe -- so a watermark
  // is what tells "already cleared" from "not seen yet" apart; without
  // it, a do-not-disturb sweep would read a cleared notification
  // straight back in.
  property double clearedBefore: 0

  // Keys dismissed one at a time via the card's own per-row "x"
  // (forgetOne below) -- clearedBefore's single watermark only covers
  // "everything older than X" (clearAll), not "this one specific
  // entry while its neighbors stay", so a dismissed key needs its own
  // record. Without this, a do-not-disturb history sweep re-reads the
  // exact same on-disk file every 5 seconds and would otherwise
  // silently bring a dismissed row right back.
  property var forgottenKeys: []

  function entryFor(key) {
    var k = String(key || "")
    for (var i = 0; i < entries.length; i++) if (entries[i].key === k) return entries[i]
    return null
  }

  // ------------------------------------------------------------- ingest

  // Fold a batch of freshly-read entries into the store. An entry
  // already known keeps its own read flag -- a sweep must never
  // resurrect something already read -- but still picks up an edit the
  // sender made in place (a download's percentage, say).
  function absorb(incoming) {
    if (!incoming || incoming.length === 0) return

    var next = entries.slice()
    var index = ({})
    for (var i = 0; i < next.length; i++) index[next[i].key] = i
    var forgotten = ({})
    for (var f = 0; f < service.forgottenKeys.length; f++) forgotten[service.forgottenKeys[f]] = true

    var changed = false
    for (var j = 0; j < incoming.length; j++) {
      var entry = incoming[j]
      if (!entry || entry.timestamp <= service.clearedBefore) continue
      if (forgotten[entry.key]) continue

      var at = index[entry.key]
      if (at === undefined) {
        next.push(entry)
        index[entry.key] = next.length - 1
        changed = true
      } else if (NotificationModel.entryChanged(next[at], entry)) {
        entry.unread = next[at].unread
        next[at] = entry
        changed = true
      }
    }
    if (changed) commit(next)
  }

  function commit(list) {
    entries = NotificationModel.normalize(list, retention)
    scheduleSave()
  }

  // Every notification that reaches the screen passes through the
  // first-party popup model, in this same process -- insertions,
  // removals and reorders all land here, and the scan only ever adds
  // what it has not seen, so running it more than strictly necessary
  // costs nothing.
  Connections {
    target: service.sourceReady ? service.source.popupModel : null
    ignoreUnknownSignals: true
    function onCountChanged() { service.ingestPopups() }
    function onDataChanged() { service.ingestPopups() }
  }

  function ingestPopups() {
    if (!sourceReady) return
    var model = source.popupModel
    if (!model) return

    var batch = []
    for (var i = 0; i < model.count; i++) {
      var row = null
      try {
        row = model.get(i)
      } catch (e) {
        continue
      }
      // The first-party "No recent notifications" replay placeholder
      // carries originalId -1 and is not a real notification.
      if (!row || row.originalId < 0) continue
      var entry = NotificationModel.entryFromRow(row)
      if (entry) batch.push(entry)
    }
    absorb(batch)
  }

  // Do-not-disturb is the one path that never reaches popupModel: a
  // silenced notification is written straight into the first-party
  // history and never shown, so that directory is the only place to
  // read it back from. True once the first sweep has folded in --
  // counting whatever was already on the machine before this service
  // ever ran as unread would hand a brand-new install a badge no one
  // earned, so that first batch is absorbed as already read instead.
  property bool primed: false

  Process {
    id: historyProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var batch = NotificationModel.parseHistory(text)
        if (!service.primed) {
          for (var i = 0; i < batch.length; i++) batch[i].unread = false
          service.primed = true
        }
        service.absorb(batch)
      }
    }
  }

  function sweepHistory() {
    if (historyProc.running) return
    // awk 1 rather than cat: a torn file missing its trailing newline
    // must not glue itself onto the next one and take a valid entry
    // down with it.
    historyProc.command = ["bash", "-c",
      "awk 1 \"$1\"/*.json 2>/dev/null || true", "--", service.sourceHistoryDir]
    historyProc.running = true
  }

  readonly property bool doNotDisturb: sourceReady && source.doNotDisturb === true

  // The first-party history keeps ten entries, so a five-second beat
  // cannot miss one unless more than ten arrive between ticks -- and it
  // only ever runs while do-not-disturb is actually on.
  Timer {
    running: service.doNotDisturb && service.storeLoaded
    interval: 5000
    repeat: true
    triggeredOnStart: true
    onTriggered: service.sweepHistory()
  }

  // Catch the tail of a do-not-disturb window the moment it ends, and
  // anything that arrived while the shell was not running at all.
  onDoNotDisturbChanged: if (storeLoaded) sweepHistory()

  // ------------------------------------------------------------- read state

  function markRead(key) {
    var k = String(key || "")
    if (!k) return
    var next = entries.slice()
    for (var i = 0; i < next.length; i++) {
      if (next[i].key !== k || !next[i].unread) continue
      var copy = {}
      for (var role in next[i]) copy[role] = next[i][role]
      copy.unread = false
      next[i] = copy
      entries = next
      scheduleSave()
      return
    }
  }

  // Empties the card. The first-party history is left as it is -- its
  // own showHistory replay is not this plugin's to erase -- so the
  // watermark below is what keeps the next do-not-disturb sweep from
  // reading it all straight back in.
  function clearAll() {
    var newest = 0
    for (var i = 0; i < entries.length; i++)
      if (entries[i].timestamp > newest) newest = entries[i].timestamp
    clearedBefore = Math.max(clearedBefore, newest)
    entries = []
    scheduleSave()
    ingestPopups()
  }

  // Dismisses one specific row -- the card's own per-row "x" -- rather
  // than everything. Recorded in forgottenKeys, not folded into
  // clearedBefore: that single watermark can only say "everything up
  // to here", which would also hide every OTHER entry still sitting
  // between here and the last real clearAll().
  function forgetOne(key) {
    var k = String(key || "")
    if (!k) return
    entries = entries.filter(function(entry) { return entry.key !== k })
    forgottenKeys = NotificationModel.pruneForgottenKeys(forgottenKeys.concat([k]), retention)
    scheduleSave()
  }

  // ------------------------------------------------------------- activation

  // A row click, without the toast-outliving retention this service
  // doesn't take on (see the header comment): an action toast's own
  // execArgv replays exactly like it would have from the toast itself
  // (a plain data field, not a live object); everything else falls
  // back to bringing the sender's own window forward.
  function activate(key) {
    var entry = entryFor(key)
    markRead(key)
    if (!entry) return

    var argv = NotificationModel.parseExecArgv(entry.execArgv)
    if (argv) {
      Util.execArgv(argv)
    } else {
      focusWindow(NotificationModel.focusPatterns(entry))
    }
  }

  function focusWindow(patterns) {
    if (!patterns || patterns.length === 0 || focusProc.running) return
    focusProc.command = ["bash", "-c",
      'for pattern in "$@"; do omarchy-hyprland-focus-app "$pattern" && exit 0; done; exit 1',
      "--"].concat(patterns)
    focusProc.running = true
  }

  Process { id: focusProc; running: false }

  // ------------------------------------------------------------- persistence

  property bool storeLoaded: false

  FileView {
    id: storeFile
    path: service.storePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: service.loadStore(text(), true)
    // First run: the file does not exist yet. Without this branch the
    // store never counts as loaded, every save stays a no-op, and
    // nothing is ever written.
    onLoadFailed: service.loadStore("", false)
  }

  Timer {
    id: saveTimer
    interval: 400
    repeat: false
    onTriggered: service.flushStore()
  }

  function scheduleSave() {
    if (!service.storeLoaded) return
    saveTimer.restart()
  }

  function loadStore(raw, existed) {
    if (service.storeLoaded) return

    // Only a genuine first run gets the read-everything-as-read grace
    // above; a store that already exists has been tracking read state
    // all along.
    service.primed = existed === true

    var loaded = []
    var watermark = 0
    var forgotten = []
    try {
      var parsed = JSON.parse(String(raw || "").trim() || "{}")
      if (parsed && Array.isArray(parsed.entries)) {
        for (var i = 0; i < parsed.entries.length; i++) {
          var value = parsed.entries[i]
          if (!value || !value.key) continue
          var entry = NotificationModel.entryFromRow(value)
          if (!entry) continue
          entry.key = String(value.key)
          entry.unread = value.unread === true
          loaded.push(entry)
        }
      }
      watermark = Number(parsed && parsed.clearedBefore) || 0
      if (parsed && Array.isArray(parsed.forgottenKeys)) forgotten = parsed.forgottenKeys
    } catch (e) {
      console.warn("ruixen.notch: notification store parse failed:", e)
    }

    service.clearedBefore = watermark
    service.forgottenKeys = NotificationModel.pruneForgottenKeys(forgotten, service.retention)
    // A notification can land in the tick between startup and this
    // read finishing; folding what is already in memory in keeps it.
    service.entries = NotificationModel.normalize(loaded.concat(service.entries), service.retention)
    service.storeLoaded = true

    // Pick up whatever arrived while the shell was not running, then
    // take over from the live model.
    service.sweepHistory()
    service.ingestPopups()
  }

  function flushStore() {
    storeFile.setText(JSON.stringify({
      version: 1,
      clearedBefore: service.clearedBefore,
      forgottenKeys: service.forgottenKeys,
      entries: service.entries
    }) + "\n")
  }

  Process {
    id: ensureDirProc
    command: ["mkdir", "-p", service.home + "/.local/state/ruixen"]
    running: false
  }

  Component.onCompleted: {
    ensureDirProc.running = true
    // Give mkdir a tick before the read; FileView reports a missing
    // file through onLoadFailed, which loadStore already handles.
    Qt.callLater(function() { storeFile.reload() })
  }
}
