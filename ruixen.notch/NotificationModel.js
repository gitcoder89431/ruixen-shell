// Pure helpers for the notch's own notification history card (Column 3
// of the Widgets dashboard, DashboardContent.qml) -- kept out of QML so
// they can be reasoned about and tested on their own, matching this
// repo's own BarModel.js/PluginModel.js pattern.
//
// Approach studied directly from BitYoungjae/byj-omarchy-notifications
// (MIT), specifically its Service.qml/Center.js: attach to Omarchy's
// own first-party omarchy.notifications service in-process rather than
// running a second notification daemon, and keep a read flag plus a
// deeper backlog than that service's own 10-entry history alongside
// it. This is a from-scratch implementation of that same approach for
// this repo's own compact card, not a copy of that project's file --
// see NotificationService.qml's own header comment for the one
// deliberate scope difference (no toast-outliving click-through; that
// relies on undocumented internals of the first-party service that
// this repo isn't taking on yet).

// ---------------------------------------------------------------- identity

// The first-party service's own history filename shape
// (<timestamp>-<originalId>.json, confirmed by reading
// /usr/share/omarchy/shell/plugins/notifications/Service.qml directly)
// reused verbatim as this store's own key, so a row read off the live
// popup model and the same notification later read out of the history
// directory collapse onto one entry instead of appearing twice.
function rowKey(row) {
  var r = row || {}
  var originalId = r.originalId !== undefined && r.originalId !== null ? r.originalId : r.id
  return String(r.timestamp || 0) + "-" + String(originalId || 0) + ".json"
}

// Everything the card stores about one notification. A plain snapshot,
// not a reference to the live object behind a toast -- that object dies
// with its sender, and reading a role off a destroyed one is a crash,
// not an error (confirmed by the real service's own snapshot-not-
// reference pattern for popupModel/history).
function entryFromRow(row) {
  var r = row || {}
  if (!r.summary && !r.body && !r.app) return null
  return {
    key: rowKey(r),
    app: String(r.app || ""),
    appIcon: String(r.appIcon || ""),
    summary: String(r.summary || ""),
    body: String(r.body || ""),
    glyph: String(r.glyph || ""),
    execArgv: String(r.execArgv || ""),
    urgency: typeof r.urgency === "number" ? r.urgency : 1,
    timestamp: Number(r.timestamp) || 0,
    unread: true
  }
}

// Senders edit a notification in place (a download's percentage, an
// edited chat message) without changing the identity the key is built
// from -- this is what tells the ingest loop an update actually
// happened, as opposed to seeing the exact same row again.
function entryChanged(a, b) {
  if (!a || !b) return true
  return a.summary !== b.summary || a.body !== b.body || a.app !== b.app
    || a.appIcon !== b.appIcon || a.glyph !== b.glyph || a.execArgv !== b.execArgv
    || a.urgency !== b.urgency
}

// ---------------------------------------------------------------- ingest

// The first-party history directory, concatenated one JSON object per
// line (same shape NotificationService.qml's own sweep reads with
// `awk 1 *.json`). A torn write from a crash mid-save is skipped
// rather than taking the rest of the sweep down with it.
function parseHistory(raw) {
  var lines = String(raw || "").split("\n")
  var out = []
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    try {
      var value = JSON.parse(line)
      if (!value || typeof value !== "object") continue
      var entry = entryFromRow(value)
      if (entry) out.push(entry)
    } catch (e) {
      // Not a whole object -- skip this line, keep the sweep going.
    }
  }
  return out
}

// Newest first, deduped by key, capped at `limit`. The order the card
// renders in.
function normalize(entries, limit) {
  var seen = {}
  var out = []
  var list = Array.isArray(entries) ? entries : []
  var sorted = list.slice().sort(function(a, b) {
    return (b.timestamp || 0) - (a.timestamp || 0)
  })
  for (var i = 0; i < sorted.length; i++) {
    var entry = sorted[i]
    if (!entry || !entry.key || seen[entry.key]) continue
    seen[entry.key] = true
    out.push(entry)
  }
  var max = Number(limit) || 0
  return max > 0 ? out.slice(0, max) : out
}

// Keys the user dismissed one at a time (the card's own per-row "x" --
// see NotificationService.qml's forgetOne), kept so a do-not-disturb
// history sweep or a stray live update doesn't quietly resurrect one
// of them. Deduped, oldest trimmed first once past `limit` -- these
// arrive in dismissal order, not sorted by the notification's own
// timestamp, so this is a plain cap rather than normalize()'s own
// newest-first sort.
function pruneForgottenKeys(keys, limit) {
  var seen = {}
  var out = []
  var list = Array.isArray(keys) ? keys : []
  for (var i = 0; i < list.length; i++) {
    var key = String(list[i] || "")
    if (!key || seen[key]) continue
    seen[key] = true
    out.push(key)
  }
  var max = Number(limit) || 0
  return max > 0 && out.length > max ? out.slice(out.length - max) : out
}

// ---------------------------------------------------------------- activation

// Validate a persisted omarchy-exec-argv hint (an action toast's own
// click, carried in the `execArgv` role the real service already
// writes into every snapshot -- confirmed by reading its own
// liveRowsForReplay directly, a plain data field, not something that
// needs the live Notification object behind it) into a runnable argv,
// or null. Structural only, and fails closed: a non-array, a
// non-string member, an empty program, or a leading-dash program argv
// would read as an option.
function parseExecArgv(value) {
  var text = String(value || "")
  if (!text) return null
  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return null
  }
  if (!Array.isArray(parsed) || parsed.length === 0) return null
  for (var i = 0; i < parsed.length; i++) {
    if (typeof parsed[i] !== "string") return null
  }
  if (!parsed[0] || parsed[0].charAt(0) === "-") return null
  return parsed
}

// Senders that never own a window, so there is nothing to bring
// forward once a row has no execArgv of its own to replay.
function isEphemeralApp(app) {
  var name = String(app || "")
  return name === "notify-send" || name === "omarchy-action"
}

// Browsers stamp their own name on every web notification, so the app
// name reads "Google Chrome" whether the sender was Slack, Gmail or a
// random tab.
function isChromiumDerived(app, appIcon) {
  var source = (String(app || "") + "\n" + String(appIcon || "")).toLowerCase()
  return source.indexOf("chrom") >= 0 || source.indexOf("brave") >= 0
    || source.indexOf("vivaldi") >= 0 || source.indexOf("microsoft-edge") >= 0
    || source.indexOf("opera") >= 0
}

// Chromium prefixes a web notification's body with the origin it came
// from, as a link or a bare host -- the only trace of the real sender
// left once "Google Chrome" is all the app name says, and also how its
// window is found: a Chromium web app's window class is
// "chrome-<host>__<path>-<profile>".
var LEADING_LINK_HOST = /^\s*<a\b[^>]*>\s*(?:https?:\/\/|www\.)?((?:[a-z0-9-]+\.)+[a-z]{2,})(?::\d+)?(?:\/[^<\s]*)?\s*<\/a>/i
var LEADING_BARE_HOST = /^\s*(?:https?:\/\/|www\.)?((?:[a-z0-9-]+\.)+[a-z]{2,})(?::\d+)?(?:\/\S*)?\s+/i

function originHost(body) {
  var text = String(body || "")
  var match = LEADING_LINK_HOST.exec(text) || LEADING_BARE_HOST.exec(text)
  return match ? match[1].toLowerCase() : ""
}

// A themed icon name -- "com.mitchellh.ghostty", not a file:// URL or a
// path -- is usually the sender's application id, which is also its
// window class. GLib applications (Ghostty among them) send no app
// name at all, and this is then all that identifies them.
function isIconName(value) {
  var s = String(value || "")
  return s.length > 0 && s.indexOf("/") < 0 && s.indexOf(":") < 0
}

function escapeRegex(text) {
  return String(text || "").replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

// The window-class hints a notification carries, most specific first,
// as case-insensitive regexes for omarchy-hyprland-focus-app to try in
// turn. This is the click-through this card actually ships: once a row
// has no execArgv of its own to replay, the best it can do -- without
// the toast-outliving retention this repo isn't taking on -- is bring
// the sender's own window forward.
function focusPatterns(entry) {
  var e = entry || {}
  var app = String(e.app || "").trim()
  var icon = String(e.appIcon || "").trim()
  var out = []
  function add(value) {
    if (value && out.indexOf(value) < 0) out.push(value)
  }
  if (isChromiumDerived(app, icon)) add(escapeRegex(originHost(e.body)))
  if (!isEphemeralApp(app)) {
    add(escapeRegex(app))
    // "Google Chrome" notifies under its display name while its window
    // class is google-chrome; the hyphenated form is what desktop
    // entries end up as.
    add(escapeRegex(app.replace(/\s+/g, "-")))
  }
  if (isIconName(icon)) add(escapeRegex(icon))
  return out
}

// ---------------------------------------------------------------- display

// Sender name for a row's own label. CLI tooling (notify-send) carries
// no useful app name, so the row just says so plainly instead of
// showing an empty pill.
function appLabel(entry) {
  var app = String((entry && entry.app) || "").trim()
  if (!app || app === "notify-send") return "Notification"
  return app
}

// The stored body may carry Pango markup and entities, since the
// daemon advertises both to senders. The card is one dim single-line
// row, not a rich text view, so the tags come out and the entities go
// back to their glyphs.
function bodyText(entry) {
  var body = String((entry && entry.body) || "")
  if (!body) return ""
  return body
    .replace(/<[^>]*>/g, "")
    .replace(/&lt;/g, "<")
    .replace(/&gt;/g, ">")
    .replace(/&quot;/g, "\"")
    .replace(/&apos;/g, "'")
    .replace(/&amp;/g, "&")
    .replace(/\s+/g, " ")
    .trim()
}

// Coarse relative age -- the card is scanned, not read for exact
// times, so the units stop at days.
function relativeTime(timestamp, now) {
  var then = Number(timestamp) || 0
  if (then <= 0) return ""

  var seconds = Math.floor(((Number(now) || Date.now()) - then) / 1000)
  // A clock that moved backwards (an NTP correction, a resume from
  // suspend) would otherwise print a negative age.
  if (seconds < 60) return "now"

  var minutes = Math.floor(seconds / 60)
  if (minutes < 60) return minutes + "m"

  var hours = Math.floor(minutes / 60)
  if (hours < 24) return hours + "h"

  var days = Math.floor(hours / 24)
  return days + "d"
}
