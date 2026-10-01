"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "extensions", "clipboard", "ClipboardHistory.js"));

const sample = JSON.stringify([
  { type: "text", text: "hello\nworld" },
  { type: "text", text: "https://example.com/path?q=1" },
  { type: "image", path: "/home/dev/.local/state/omarchy/clipboard-images/abc.png", mime: "image/png", capturedAt: "Monday 09:35" },
  { type: "unknown", text: "ignored" }
]);

const entries = M.parseHistory(sample);

check("parseHistory: keeps supported entries only", entries.length, 3);
check("parseHistory: text entry keeps source history index", entries[0].sourceIndex, 0);
check("parseHistory: link entry keeps source history index", entries[1].sourceIndex, 1);
check("parseHistory: image entry keeps original history index", entries[2].sourceIndex, 2);
check("parseHistory: text summary collapses whitespace", entries[0].title, "hello world");
check("parseHistory: URL-shaped text is classified as a link", entries[1].type, "link");
check("parseHistory: link uses link icon", entries[1].icon, "\uf0c1");
check("parseHistory: image title keeps basename for metadata/search", entries[2].title, "abc.png");
check("parseHistory: malformed JSON fails closed", M.parseHistory("not json"), []);

check("rows: empty query returns both entries",
  M.rows(entries, "", "#89b4fa").map((r) => r.label),
  ["hello world", "https://example.com/path?q=1", "Image"]);

check("rows: image label uses dimensions when available",
  M.rows(entries, "", "#89b4fa", { "/home/dev/.local/state/omarchy/clipboard-images/abc.png": "1600x1200" }).map((r) => r.label),
  ["hello world", "https://example.com/path?q=1", "Image (1600x1200)"]);

check("rows: query matches text content",
  M.rows(entries, "world", "#89b4fa").map((r) => r.id),
  ["clipboard:0"]);

check("rows: query matches image mime/path",
  M.rows(entries, "png", "#89b4fa").map((r) => r.id),
  ["clipboard:2"]);

check("parseHistory: bare domains are classified as links",
  M.parseHistory(JSON.stringify([{ type: "text", text: "example.com/docs" }]))[0].type,
  "link");

summary();
