"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.notch", "NotificationModel.js"));

// ---- identity / entryFromRow ----------------------------------------

check("rowKey: matches the real service's own history filename shape",
  M.rowKey({ timestamp: 1700000000000, originalId: 7 }), "1700000000000-7.json");
check("rowKey: falls back to .id when originalId is absent (a stored/history row)",
  M.rowKey({ timestamp: 5, id: 3 }), "5-3.json");
check("rowKey: missing fields still produce a stable key, not a crash",
  M.rowKey({}), "0-0.json");

check("entryFromRow: null row yields null (nothing to store)", M.entryFromRow(null), null);
check("entryFromRow: a row with no summary/body/app is not a real notification",
  M.entryFromRow({ timestamp: 1 }), null);
check("entryFromRow: a real row is captured as an unread snapshot",
  M.entryFromRow({ timestamp: 10, originalId: 1, app: "Slack", summary: "New message", body: "hi", execArgv: "" }),
  { key: "10-1.json", app: "Slack", appIcon: "", summary: "New message", body: "hi", glyph: "", execArgv: "", urgency: 1, timestamp: 10, unread: true });

check("entryChanged: identical content is unchanged",
  M.entryChanged({ summary: "a", body: "b", app: "c", appIcon: "d", glyph: "e", execArgv: "f", urgency: 1 },
    { summary: "a", body: "b", app: "c", appIcon: "d", glyph: "e", execArgv: "f", urgency: 1 }), false);
check("entryChanged: a body edit in place (e.g. a download's percentage) is a change",
  M.entryChanged({ summary: "a", body: "50%" }, { summary: "a", body: "51%" }), true);
check("entryChanged: either side missing counts as changed", M.entryChanged(null, {}), true);

// ---- ingest -----------------------------------------------------------

const historyRaw = [
  JSON.stringify({ timestamp: 2, originalId: 2, app: "A", summary: "two" }),
  "not json at all",
  JSON.stringify({ timestamp: 1, originalId: 1, app: "B", summary: "one" }),
  ""
].join("\n");
const historyEntries = M.parseHistory(historyRaw);
check("parseHistory: a malformed line is skipped, the rest of the sweep still lands",
  historyEntries.map(function(e) { return e.summary; }), ["two", "one"]);
check("parseHistory: empty input yields an empty list, not a crash", M.parseHistory(""), []);

check("normalize: newest first",
  M.normalize([{ key: "a", timestamp: 1 }, { key: "b", timestamp: 5 }], 10).map(function(e) { return e.key; }),
  ["b", "a"]);
check("normalize: deduped by key, first (newest, since already sorted) wins",
  M.normalize([{ key: "a", timestamp: 5, summary: "new" }, { key: "a", timestamp: 1, summary: "old" }], 10)
    .map(function(e) { return e.summary; }), ["new"]);
check("normalize: capped at limit",
  M.normalize([{ key: "a", timestamp: 1 }, { key: "b", timestamp: 2 }, { key: "c", timestamp: 3 }], 2).length, 2);
check("normalize: a non-array input yields an empty list, not a crash", M.normalize(null, 10), []);

check("pruneForgottenKeys: deduped, order preserved", M.pruneForgottenKeys(["a", "b", "a", "c"], 10), ["a", "b", "c"]);
check("pruneForgottenKeys: oldest (front) trimmed first once past limit", M.pruneForgottenKeys(["a", "b", "c", "d"], 2), ["c", "d"]);
check("pruneForgottenKeys: a non-array input yields an empty list, not a crash", M.pruneForgottenKeys(null, 10), []);
check("pruneForgottenKeys: empty/blank entries are dropped", M.pruneForgottenKeys(["a", "", "b"], 10), ["a", "b"]);

// ---- activation ---------------------------------------------------------

check("parseExecArgv: a real argv round-trips", M.parseExecArgv(JSON.stringify(["firefox", "https://x"])), ["firefox", "https://x"]);
check("parseExecArgv: empty/missing value is null", M.parseExecArgv(""), null);
check("parseExecArgv: malformed JSON is null, not a throw", M.parseExecArgv("not json"), null);
check("parseExecArgv: a non-array value is null", M.parseExecArgv('"just a string"'), null);
check("parseExecArgv: a non-string member fails closed", M.parseExecArgv(JSON.stringify(["ok", 5])), null);
check("parseExecArgv: a leading-dash program (would read as an option) fails closed", M.parseExecArgv(JSON.stringify(["-rf", "/"])), null);

check("isEphemeralApp: notify-send has no window to bring forward", M.isEphemeralApp("notify-send"), true);
check("isEphemeralApp: a real app is not ephemeral", M.isEphemeralApp("Slack"), false);

check("isChromiumDerived: Google Chrome itself", M.isChromiumDerived("Google Chrome", ""), true);
check("isChromiumDerived: Brave too", M.isChromiumDerived("Brave Browser", ""), true);
check("isChromiumDerived: a native app is not", M.isChromiumDerived("Slack", ""), false);

check("originHost: a leading link host is extracted", M.originHost("<a href=\"https://app.slack.com/x\">app.slack.com</a> sent a message"), "app.slack.com");
check("originHost: a bare host prefix is extracted", M.originHost("mail.google.com wants to notify you"), "mail.google.com");
check("originHost: no host present yields empty string", M.originHost("just a plain message"), "");

check("isIconName: a themed icon id is a name", M.isIconName("com.mitchellh.ghostty"), true);
check("isIconName: a file path is not a name", M.isIconName("/usr/share/icons/x.png"), false);
check("isIconName: empty is not a name", M.isIconName(""), false);

check("focusPatterns: a Chromium web app also tries its origin host's window class",
  M.focusPatterns({ app: "Google Chrome", appIcon: "", body: "<a href=\"https://app.slack.com\">app.slack.com</a> hi" }),
  ["app\\.slack\\.com", "Google Chrome", "Google-Chrome"]);
check("focusPatterns: an ephemeral sender contributes nothing but its icon name",
  M.focusPatterns({ app: "notify-send", appIcon: "com.example.App" }), ["com\\.example\\.App"]);
check("focusPatterns: a single-word app's plain and hyphenated forms are identical, so only one is kept",
  M.focusPatterns({ app: "Slack", appIcon: "" }), ["Slack"]);
check("focusPatterns: a multi-word app tries both its plain and hyphenated window-class forms",
  M.focusPatterns({ app: "My App", appIcon: "" }), ["My App", "My-App"]);

// ---- display ------------------------------------------------------------

check("appLabel: notify-send reads as a plain 'Notification'", M.appLabel({ app: "notify-send" }), "Notification");
check("appLabel: a real app name is used as-is", M.appLabel({ app: "Slack" }), "Slack");
check("appLabel: empty app also falls back", M.appLabel({ app: "" }), "Notification");

check("bodyText: markup tags are stripped", M.bodyText({ body: "<b>hi</b> there" }), "hi there");
check("bodyText: entities are decoded back to their glyphs", M.bodyText({ body: "Tom &amp; Jerry &lt;3&gt;" }), "Tom & Jerry <3>");
check("bodyText: internal whitespace/newlines collapse to single spaces", M.bodyText({ body: "line one\n\nline two" }), "line one line two");

// timestamp 0 is the "no timestamp" sentinel (same as entryFromRow's
// own `Number(r.timestamp) || 0`), so every real case below anchors on
// a genuine, non-zero epoch instant rather than 0 itself.
var epoch = 1700000000000;
check("relativeTime: just now", M.relativeTime(epoch, epoch + 5000), "now");
check("relativeTime: minutes", M.relativeTime(epoch, epoch + 90 * 1000), "1m");
check("relativeTime: hours", M.relativeTime(epoch, epoch + 2 * 3600 * 1000), "2h");
check("relativeTime: days", M.relativeTime(epoch, epoch + 3 * 24 * 3600 * 1000), "3d");
check("relativeTime: a clock that moved backwards never prints a negative age", M.relativeTime(epoch, epoch - 10000), "now");
check("relativeTime: no timestamp yields an empty string", M.relativeTime(0, Date.now()), "");

summary();
