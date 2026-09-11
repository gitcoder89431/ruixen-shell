"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "LauncherHelpers.js"));

// ---- disambiguateLabels -----------------------------------------------------

check("disambiguateLabels: a name with no duplicate is left untouched",
  M.disambiguateLabels([{ label: "unique.txt", action: { path: "/home/dev/dog/unique.txt" } }]),
  [{ label: "unique.txt", action: { path: "/home/dev/dog/unique.txt" } }]);

check("disambiguateLabels: two files sharing a bare name get prefixed with their real parent folder",
  M.disambiguateLabels([
    { label: "notes.txt", action: { path: "/home/dev/dog/notes.txt" } },
    { label: "notes.txt", action: { path: "/home/dev/cats/notes.txt" } }
  ]),
  [
    { label: "dog/notes.txt", action: { path: "/home/dev/dog/notes.txt" } },
    { label: "cats/notes.txt", action: { path: "/home/dev/cats/notes.txt" } }
  ]);

// Issue #52's own bug: a content-search row's own breadcrumb is "Line N:
// <snippet>", not a directory -- disambiguation must derive the parent
// from action.path, never from breadcrumb, or a snippet containing "/"
// could get sliced into the label instead of a real folder name.
check("disambiguateLabels: a duplicate content-search row (breadcrumb is a snippet, not a path) "
  + "still disambiguates correctly from its own real path, ignoring breadcrumb entirely",
  M.disambiguateLabels([
    { label: "config.go", breadcrumb: "Line 12: var path = a/b/c/config.go", action: { path: "/home/dev/app/config.go" } },
    { label: "config.go", action: { path: "/home/dev/lib/config.go" } }
  ]),
  [
    { label: "app/config.go", breadcrumb: "Line 12: var path = a/b/c/config.go", action: { path: "/home/dev/app/config.go" } },
    { label: "lib/config.go", action: { path: "/home/dev/lib/config.go" } }
  ]);

check("disambiguateLabels: a row with no action.path at all is left untouched rather than throwing",
  M.disambiguateLabels([{ label: "x" }, { label: "x" }]),
  [{ label: "x" }, { label: "x" }]);

// ---- baseName (issue #62) ---------------------------------------------------

check("baseName: extracts the filename from a full path",
  M.baseName("/home/dev/notes/todo.md"), "todo.md");
check("baseName: a bare filename with no '/' returns itself",
  M.baseName("todo.md"), "todo.md");
check("baseName: a directory path (no trailing slash) returns its own last segment",
  M.baseName("/home/dev/Projects"), "Projects");

// ---- formatSize -------------------------------------------------------------

check("formatSize: bytes under 1024 shown as a bare byte count", M.formatSize(512), "512 B");
check("formatSize: kilobytes", M.formatSize(2048), "2.0 KB");
check("formatSize: megabytes", M.formatSize(5 * 1024 * 1024), "5.0 MB");
check("formatSize: gigabytes", M.formatSize(3 * 1024 * 1024 * 1024), "3.0 GB");

// ---- parentDirOf --------------------------------------------------------

check("parentDirOf: a path under homeDir gets the ~ abbreviation",
  M.parentDirOf("/home/dev/notes/todo.md", "/home/dev"), "~/notes");
check("parentDirOf: a path not under homeDir (a mounted drive) is left as a full path",
  M.parentDirOf("/run/media/dev/USB/file.txt", "/home/dev"), "/run/media/dev/USB");
check("parentDirOf: a root-level file has an empty parent dir",
  M.parentDirOf("notes.txt", "/home/dev"), "");

summary();
