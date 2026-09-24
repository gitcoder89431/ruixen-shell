import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "NotificationModel.js" as NotificationModel

// Backing store for the notch's own notification history card (Column 3
// of the Widgets dashboard -- see DashboardContent.qml). Originally
// attached to Omarchy's own first-party omarchy.notifications service
// in-process (approach studied from BitYoungjae/byj-omarchy-notifications,
// MIT), adding a read flag per notification and a backlog deeper than
// the 10 entries its own history directory retains.
//
// ruixen-shell issue #42/#38: Omarchy v4.0.3 restricts
// shell.firstPartyServiceFor() to a fixed allowlist, and only for a
// plugin declaring manifest kind "bar" -- ruixen.notch (kind:
// ["overlay","service"]) was never going to have bar capabilities to
// use it even for "omarchy.notifications", which IS nominally in that
// allowlist. Verified directly against
// /usr/share/omarchy/shell/plugins/notifications/Service.qml: every
// notification the real service shows or silences is also mirrored to
// its own on-disk state as a plain, single-line JSON file -- one file
// per live on-screen popup directly under omarchyStateDir, moved into
// historyDir the moment it leaves the screen (dismissed/expired/
// archived), written by the exact same serializePopup() call in both
// places. Reading both directories (rather than the in-process
// popupModel) is now the ingestion path -- swept on a timer instead of
// being told about arrivals immediately, but the same
// timestamp-originalId identity this store already keyed its entries
// by (see NotificationModel.js's rowKey) means a notification read
// live and the same one later read out of history collapse onto one
// entry rather than appearing twice.
//
// Deliberate scope difference from the BitYoungjae project this was
// studied from: no toast-outliving click-through. Its
// LiveNotifications.qml keeps a notification "open" at the sender past
// its own toast by swapping in stand-in objects inside the first-party
// service's private internals (liveRefs, popupModel, refreshPopup,
// ...) so a row click can still run a sender's exact default action
// minutes later -- those are undocumented internals, not a public API,
// and were already the one part of that approach genuinely likely to
// break on some future Omarchy release (this v4.0.3 pass is exactly
// that break). This service instead reads two things every real
// service here already treats as safe, ordinary data: an action
// toast's own execArgv role (written into the plain snapshot, no live
// object involved), and Omarchy's own omarchy-hyprland-focus-app for
// bringing the sender's window forward.
Item {
  id: service

  // Injected by Overlay.qml, same as every other service reference
  // this plugin already threads through (mediaService, etc) -- kept
  // even though nothing here calls shell.firstPartyServiceFor() any
  // more, in case a future need for shell.appLibrary/etc arises here.
  property var shell: null

  readonly property string home: Quickshell.env("HOME")
  // Flat under ~/.local/state/ruixen/, matching every other piece of
  // state this plugin already keeps there (launcher-favorites.json,
  // avatar.json, animation-profile) rather than a second, plugin-named
  // subdirectory.
  readonly property string storePath: home + "/.local/state/ruixen/notifications-store.json"

  // The real Omarchy notifications service's own on-disk state: one
  // file per notification currently showing on screen lives directly
  // here, moved into historyDir the moment it leaves the screen.
  readonly property string omarchyStateDir: home + "/.local/state/omarchy/notifications/"
  readonly property string historyDir: omarchyStateDir + "history/"

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
  // it, the recurring sweep would read a cleared notification straight
  // back in.
  property double clearedBefore: 0

  // Keys dismissed one at a time via the card's own per-row "x"
  // (forgetOne below) -- clearedBefore's single watermark only covers
  // "everything older than X" (clearAll), not "this one specific
  // entry while its neighbors stay", so a dismissed key needs its own
  // record. Without this, the recurring sweep re-reads the exact same
  // on-disk file every few seconds and would otherwise silently bring
  // a dismissed row right back.
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

  // No more in-process popup model to be told about arrivals through --
  // sweep both of the real service's own on-disk directories instead.
  // Both are plain, single-line JSON files in the exact shape
  // NotificationModel.entryFromRow already expects (the real service
  // writes both through the same serializePopup() call), so one parser
  // already proven against the history directory covers this too.
  //
  // Counting whatever was already on the machine before this service
  // ever ran as unread would hand a brand-new install a badge no one
  // earned, so the very first sweep is absorbed as already read
  // instead.
  property bool primed: false

  Process {
    id: sweepProc
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

  function sweepNotifications() {
    if (sweepProc.running) return
    // awk 1 rather than cat: a torn file missing its trailing newline
    // must not glue itself onto the next one and take a valid entry
    // down with it. Both dirs in one pass -- a notification only ever
    // lives in exactly one of them at a time (the real service mv's it
    // across on archive), so there is nothing to dedup between the two
    // halves of this read, only against what absorb() already knows.
    sweepProc.command = ["bash", "-c",
      "awk 1 \"$1\"/*.json \"$2\"/*.json 2>/dev/null || true", "--",
      service.omarchyStateDir, service.historyDir]
    sweepProc.running = true
  }

  // Was gated on the first-party service's own do-not-disturb flag
  // (only worth polling while a silenced notification could otherwise
  // be missed) -- now the only ingestion path there is, so it just
  // always runs. Three seconds keeps the card feeling live without
  // spawning a process per notification the way immediate in-process
  // notice used to.
  Timer {
    running: service.storeLoaded
    interval: 3000
    repeat: true
    triggeredOnStart: true
    onTriggered: service.sweepNotifications()
  }

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
  // watermark below is what keeps the next sweep from reading it all
  // straight back in.
  function clearAll() {
    var newest = 0
    for (var i = 0; i < entries.length; i++)
      if (entries[i].timestamp > newest) newest = entries[i].timestamp
    clearedBefore = Math.max(clearedBefore, newest)
    entries = []
    scheduleSave()
    sweepNotifications()
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

    // Pick up whatever arrived while the shell was not running; the
    // Timer above takes over the recurring sweep from here.
    service.sweepNotifications()
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
