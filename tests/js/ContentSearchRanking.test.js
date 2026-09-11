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

summary();
