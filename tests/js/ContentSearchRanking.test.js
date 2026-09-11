"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "ContentSearchRanking.js"));

// ---- baseName ---------------------------------------------------------------

check("baseName: extracts the filename from a full path",
  M.baseName("/home/dev/notes/todo.md"), "todo.md");
check("baseName: a bare filename with no '/' returns itself",
  M.baseName("todo.md"), "todo.md");

// ---- collapseSnippet ----------------------------------------------------

check("collapseSnippet: collapses internal whitespace/newlines to single spaces",
  M.collapseSnippet("please   read\n(notes)   for  details\n", 80), "please read (notes) for details");
check("collapseSnippet: trims leading/trailing whitespace",
  M.collapseSnippet("   hello world   ", 80), "hello world");
check("collapseSnippet: truncates a long line with an ellipsis at the given limit",
  M.collapseSnippet("a".repeat(100), 80), "a".repeat(80) + "…");
check("collapseSnippet: a line at exactly the limit is not truncated",
  M.collapseSnippet("a".repeat(80), 80), "a".repeat(80));
check("collapseSnippet: defaults to an 80-char limit when none is given",
  M.collapseSnippet("a".repeat(100)), "a".repeat(80) + "…");
check("collapseSnippet: empty/undefined input returns an empty string, not a throw",
  M.collapseSnippet(undefined, 80), "");

// ---- dedupeByPath (issue #54) -----------------------------------------

function fakeMatch(path) {
  return { label: path, action: { path: path } }
}

check("dedupeByPath: no duplicates leaves the list untouched",
  M.dedupeByPath([fakeMatch("/a.txt"), fakeMatch("/b.txt")]),
  [fakeMatch("/a.txt"), fakeMatch("/b.txt")]);
check("dedupeByPath: the same real path from two different roots is deduped to one, "
  + "keeping the first-seen copy (order-preserving, not a re-sort)",
  M.dedupeByPath([fakeMatch("/shared/x.txt"), fakeMatch("/a.txt"), fakeMatch("/shared/x.txt")]),
  [fakeMatch("/shared/x.txt"), fakeMatch("/a.txt")]);
check("dedupeByPath: empty input returns an empty list, not a throw",
  M.dedupeByPath([]), []);

summary();
