"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.shelf", "ShelfModel.js"));

// ---- paths ----------------------------------------------------------

check("normalizePath: absolute path is kept", M.normalizePath("/home/me/a.txt"), "/home/me/a.txt");
check("normalizePath: file URL is decoded", M.normalizePath("file:///home/me/a%20b.txt"), "/home/me/a b.txt");
check("normalizePath: file://localhost URL works", M.normalizePath("file://localhost/tmp/x"), "/tmp/x");
check("normalizePath: ~/ expands with a home", M.normalizePath("~/notes.md", "/home/me"), "/home/me/notes.md");
check("normalizePath: ~/ without a home is rejected", M.normalizePath("~/notes.md"), "");
check("normalizePath: relative path is rejected", M.normalizePath("notes.md"), "");
check("normalizePath: http URL is rejected", M.normalizePath("https://example.com/a.png"), "");
check("normalizePath: root is rejected", M.normalizePath("/"), "");
check("normalizePath: newline/tab/NUL are rejected", ["/a\nb", "/a\tb", "/a\0b"].map((p) => M.normalizePath(p)), ["", "", ""]);
check("normalizePath: trailing and doubled slashes collapse", M.normalizePath("/home//me/dir//"), "/home/me/dir");
check("normalizePath: bad percent-encoding in a URL is rejected", M.normalizePath("file:///bad%zz"), "");
check("normalizePath: blank and undefined are rejected", [M.normalizePath(""), M.normalizePath(undefined)], ["", ""]);

check("baseName/dirName/extension",
  [M.baseName("/a/b/c.TXT"), M.dirName("/a/b/c.TXT"), M.extension("/a/b/c.TXT"), M.dirName("/c.txt")],
  ["c.TXT", "/a/b", "txt", "/"]);
check("extension: dotfiles and trailing dots have none", [M.extension("/a/.bashrc"), M.extension("/a/x.")], ["", ""]);
check("isImagePath", [M.isImagePath("/a/p.PNG"), M.isImagePath("/a/p.txt")], [true, false]);

check("uriFor: spaces and reserved characters are percent-encoded",
  M.uriFor("/home/me/a b#1?.txt"), "file:///home/me/a%20b%231%3F.txt");
check("uriList: CRLF separated", M.uriList(["/a", "/b c"]), "file:///a\r\nfile:///b%20c");
check("uriFor round-trips through fileUrlToPath", M.fileUrlToPath(M.uriFor("/x/ü ñ/100%.txt")), "/x/ü ñ/100%.txt");

// ---- add / remove ----------------------------------------------------

let r = M.addPaths([], ["/a/one.txt", "file:///a/two%20x.txt", "relative", "/a/one.txt"], "user", 1000, "/home/me");
check("addPaths: valid kept in order, dup in batch skipped, bad counted", [r.items.map((i) => i.path), r.rejected], [["/a/one.txt", "/a/two x.txt"], 1]);
check("addPaths: ids are unique inside one millisecond", new Set(r.items.map((i) => i.id)).size, 2);
check("addPaths: source and name recorded", [r.items[1].source, r.items[1].name], ["user", "two x.txt"]);
check("addPaths: unknown source falls back to user", M.addPaths([], ["/a"], "robot", 1).items[0].source, "user");

const base = r.items;
r = M.addPaths(base, ["/a/three.txt"], "agent", 2000);
check("addPaths: newest goes first", r.items.map((i) => i.path), ["/a/three.txt", "/a/one.txt", "/a/two x.txt"]);
check("addPaths: agent source recorded", r.items[0].source, "agent");

r = M.addPaths(r.items, ["/a/two x.txt"], "agent", 3000);
check("addPaths: re-adding moves to the front, no duplicate", r.items.map((i) => i.path), ["/a/two x.txt", "/a/three.txt", "/a/one.txt"]);
check("addPaths: re-adding keeps the original source and id", [r.items[0].source, r.added.length], ["user", 1]);

const many = Array.from({ length: 250 }, (_, i) => "/f/" + i);
check("addPaths: capped at MAX_ITEMS, oldest dropped", [M.addPaths([], many, "user", 1).items.length, M.addPaths([], many, "user", 1).items[0].path], [200, "/f/0"]);

check("removeItem: by id", M.removeItem(base, base[0].id).map((i) => i.path), ["/a/two x.txt"]);
check("removeItem: by path", M.removeItem(base, "/a/one.txt").map((i) => i.path), ["/a/two x.txt"]);
check("removeItem: unknown changes nothing", M.removeItem(base, "nope").length, 2);
check("removeItem: blank changes nothing", M.removeItem(base, "").length, 2);
check("clearItems", M.clearItems(), []);

// ---- persistence -----------------------------------------------------

check("normalizeItems: junk input is an empty list", [M.normalizeItems(null), M.normalizeItems("x"), M.normalizeItems({})], [[], [], []]);
check("normalizeItems: drops malformed and duplicate paths",
  M.normalizeItems([null, 4, { path: "rel" }, { path: "/a" }, { path: "/a" }, { path: "/b", source: "agent", id: "keep", addedAt: 5 }]).map((i) => [i.path, i.source]),
  [["/a", "user"], ["/b", "agent"]]);
check("normalizeItems: keeps a good id, repairs a missing/duplicate one",
  (() => { const l = M.normalizeItems([{ path: "/a", id: "x" }, { path: "/b", id: "x" }, { path: "/c" }]); return [l[0].id, l[1].id !== "x", l[2].id !== ""]; })(),
  ["x", true, true]);
check("normalizeItems: capped", M.normalizeItems(many.map((p) => ({ path: p }))).length, 200);

// ---- stat + listing --------------------------------------------------

const stat = M.parseStatOutput("/a/one.txt\tregular file\t12\t1700000000\n/a/dir\tdirectory\t4096\t1700000001\n/a/empty\tregular empty file\t0\t1\n/a/sock\tsocket\t0\t2\ngarbage line\n");
check("parseStatOutput: kinds", [stat["/a/one.txt"].kind, stat["/a/dir"].kind, stat["/a/empty"].kind, stat["/a/sock"].kind], ["file", "folder", "file", "other"]);
check("parseStatOutput: size and mtime", [stat["/a/one.txt"].size, stat["/a/one.txt"].mtime], [12, 1700000000]);
check("parseStatOutput: garbage and empty are ignored", [Object.keys(stat).length, Object.keys(M.parseStatOutput("")).length], [4, 0]);

const items = [
  { id: "i1", path: "/a/one.txt", name: "one.txt", source: "user", addedAt: 1 },
  { id: "i2", path: "/a/gone.txt", name: "gone.txt", source: "agent", addedAt: 2 },
  { id: "i3", path: "/a/new.txt", name: "new.txt", source: "agent", addedAt: 3 }
];
const listed = M.listEntries(items, stat, { "/a/one.txt": true, "/a/gone.txt": true });
check("listEntries: existing file reports kind and size", [listed[0].exists, listed[0].kind, listed[0].size], [true, "file", 12]);
check("listEntries: a checked path with no stat is missing", [listed[1].exists, listed[1].kind, listed[1].size], [false, "missing", null]);
check("listEntries: an unchecked path is unknown, not missing", [listed[2].exists, listed[2].kind], [null, "unknown"]);
check("listEntries: source passes through for agents", listed.map((l) => l.source), ["user", "agent", "agent"]);

check("countLabel", [M.countLabel(1), M.countLabel(0), M.countLabel(5)], ["1 item", "0 items", "5 items"]);

// ---- addMany's IPC argument ------------------------------------------

check("parsePathsArg: newline-delimited batch", M.parsePathsArg("/a\n/b c\n/d#1 (2).txt"), ["/a", "/b c", "/d#1 (2).txt"]);
check("parsePathsArg: single path", M.parsePathsArg("/only"), ["/only"]);
check("parsePathsArg: trailing newline, CRLF and blank lines are dropped", M.parsePathsArg("/a\r\n\n/b\n"), ["/a", "/b"]);
check("parsePathsArg: empty / blank / missing is an empty batch", [M.parsePathsArg(""), M.parsePathsArg("  \n "), M.parsePathsArg(undefined), M.parsePathsArg(null)], [[], [], [], []]);
check("parsePathsArg: commas and semicolons are NOT delimiters (they are legal in paths)", M.parsePathsArg("/a,b;c"), ["/a,b;c"]);
check("parsePathsArg: a leading [ still parses a JSON array for in-process callers", M.parsePathsArg('["/a","/b"]'), ["/a", "/b"]);
check("parsePathsArg: a one-element JSON array is an array, not a scalar", M.parsePathsArg('["/only"]'), ["/only"]);
check("parsePathsArg: bracketed text that isn't a JSON array is rejected, not guessed at", [M.parsePathsArg("[not json"), M.parsePathsArg("[]x")], [null, null]);
check("parsePathsArg: JSON elements are coerced to strings", M.parsePathsArg("[1,\"/a\"]"), ["1", "/a"]);

// Round trip through what the notch relay sends (file:// URLs, awkward names).
const awkward = ["/tmp/dir with spaces/file #1 (2).txt", "/tmp/ü ñ/100%.txt", "/tmp/a,b;c.txt", "/tmp/plain"];
check("round trip: joinPathsArg -> parsePathsArg is lossless for awkward paths", M.parsePathsArg(M.joinPathsArg(awkward)), awkward);
check("round trip: URLs survive and normalize to the same paths",
  M.parsePathsArg(M.joinPathsArg(awkward.map(M.uriFor))).map((u) => M.normalizePath(u)), awkward);
check("round trip: end to end through addPaths, bad entries counted not lost",
  (() => { const r = M.addPaths([], M.parsePathsArg(M.joinPathsArg(["/ok/a", "relative/b", "/ok/c"])), "user", 1); return [r.items.map((i) => i.path), r.rejected]; })(),
  [["/ok/a", "/ok/c"], 1]);
check("joinPathsArg: empty / missing", [M.joinPathsArg([]), M.joinPathsArg(undefined)], ["", ""]);

summary();
