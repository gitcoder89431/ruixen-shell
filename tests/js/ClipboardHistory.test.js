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

check("rows: empty query returns every supported entry",
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

const kind = (t) => M.parseHistory(JSON.stringify([{ type: "text", text: t }]))[0].type;
check("looksLikeLink: filenames are not links", ["README.md", "main.py", "install.sh", "Node.js"].map(kind), ["text", "text", "text", "text"]);
check("looksLikeLink: www and known-TLD domains are links", ["www.example.org", "github.com", "example.dev/x"].map(kind), ["link", "link", "link"]);
check("looksLikeLink: multi-line text is not a link", kind("example.com\nmore"), "text");
check("looksLikeLink: huge text is not scanned as a link", kind("a.com/" + "x".repeat(5000)), "text");

check("entryKey: stable across a shifted history index",
  M.entryKey(M.parseHistory(JSON.stringify([{ type: "text", text: "a" }, { type: "text", text: "b" }]))[1]),
  M.entryKey(M.parseHistory(JSON.stringify([{ type: "text", text: "new" }, { type: "text", text: "a" }, { type: "text", text: "b" }]))[2]));

check("previewText: truncates long text", M.previewText("x".repeat(100), 10).indexOf("truncated") !== -1, true);
check("previewText: short text untouched", M.previewText("hi", 10), "hi");

check("matches: search is case-insensitive over precomputed text",
  M.rows(M.parseHistory(JSON.stringify([{ type: "text", text: "Hello World" }])), "WORLD", "#fff").length, 1);

check("pathsToProbe: skips known, dedups, honors limit",
  M.pathsToProbe([
    { type: "image", path: "/a" }, { type: "image", path: "/a" },
    { type: "image", path: "/b" }, { type: "text", path: "" },
    { type: "image", path: "/c" }, { type: "image", path: "/d" }
  ], { "/b": "1x1" }, 2),
  ["/a", "/c"]);

check("mergeDimensions: merges by path and stays bounded",
  Object.keys(M.mergeDimensions({ "/a": "1x1", "/b": "2x2" }, { "/c": "3x3" }, 2)),
  ["/b", "/c"]);

summary();
