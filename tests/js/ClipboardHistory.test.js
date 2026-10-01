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

const one = (t) => M.parseHistory(JSON.stringify([{ type: "text", text: t }]))[0];
const fact = (e, label) => (e.facts.find((f) => f.label === label) || {}).value;

check("classify: hex color", one("#1e1e2e").subtype, "color");
check("classify: short hex, rgb(), hsl() are colors", ["#fff", "rgb(10, 20, 30)", "hsl(120, 50%, 50%)", "#11223344"].map((t) => one(t).subtype), ["color", "color", "color", "color"]);
check("color: facts for #1e1e2e", [fact(one("#1e1e2e"), "Hex"), fact(one("#1e1e2e"), "RGB")], ["#1E1E2E", "rgb(30, 30, 46)"]);
check("color: swatch is QML #AARRGGBB", one("#1e1e2e").swatch, "#ff1e1e2e");
check("color: alpha is reported", fact(one("#ff000080"), "Alpha"), "50%");
check("color: out-of-range rgb is plain text", one("rgb(300, 0, 0)").subtype, "plain");
check("color: color-like words are not colors", ["#hashtag", "#12", "red"].map((t) => one(t).subtype), ["plain", "plain", "plain"]);
check("color: row icon uses the swatch", M.rows(M.parseHistory(JSON.stringify([{ type: "text", text: "#ff0000" }])), "", "#89b4fa")[0].iconColor, "#ffff0000");

check("classify: email", one("dev@example.com").subtype, "email");
check("email: domain fact", fact(one("Dev@Example.COM"), "Domain"), "example.com");
check("email: sentences are not emails", one("mail me at dev@example.com please").subtype, "plain");

check("classify: absolute and home paths", ["/etc/hosts", "~/notes/todo.md", "/home/a b/c.txt"].map((t) => one(t).subtype), ["path", "path", "path"]);
check("path: facts", [fact(one("~/notes/todo.md"), "Name"), fact(one("~/notes/todo.md"), "Extension")], ["todo.md", "md"]);
check("path: not a path when multi-line, root-only or protocol-relative", ["/a\n/b", "/", "//cdn.example.com/x"].map((t) => one(t).subtype), ["plain", "plain", "plain"]);
check("path: expandHome", M.expandHome("~/a/b", "/home/me"), "/home/me/a/b");

check("classify: json object and array", [one('{"a":1,"b":[1,2]}').subtype, one("[1,2,3]").subtype], ["json", "json"]);
check("json: structure facts", [fact(one('{"a":1,"b":2}'), "Structure"), fact(one("[1]"), "Structure")], ["Object, 2 keys", "Array, 1 item"]);
check("json: preview is pretty-printed", one('{"a":1}').preview, '{\n  "a": 1\n}');
check("json: invalid json stays plain", one("{not json").subtype, "plain");

check("secret: known token shapes", ["ghp_" + "a".repeat(36), "sk-" + "x1".repeat(16), "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxIn0.sig"].map((t) => one(t).secret), [true, true, true]);
check("secret: high-entropy mixed token", one("aZ3kQ9xLm2PqR7vT1wYb5NcD").secret, true);
check("secret: ordinary things are not secrets", ["hello world this is text", "https://example.com/aZ3kQ9xLm2PqR7vT1wYb5NcD", "/home/me/some/long/path/name", "da39a3ee5e6b4b0d3255bfef95601890afd80709", "ThisIsJustACamelCaseSentenceHere"].map((t) => one(t).secret), [false, false, false, false, false]);
check("secret: row title is masked", one("ghp_" + "a".repeat(36)).title, "Possible secret (40 chars)");
check("secret: text is not searchable", M.rows(M.parseHistory(JSON.stringify([{ type: "text", text: "ghp_" + "a".repeat(36) }])), "ghp_", "#fff").length, 0);
check("secret: still pastes as plain text", one("ghp_" + "a".repeat(36)).type, "text");

check("link: host/scheme/params facts", [fact(one("https://example.com/p?a=1&b=2"), "Host"), fact(one("https://example.com/p?a=1&b=2"), "Scheme"), fact(one("https://example.com/p?a=1&b=2"), "Parameters")], ["example.com", "https", "2"]);
check("text: multi-line gets a Lines fact", fact(one("a\nb\nc"), "Lines"), "3");

summary();
