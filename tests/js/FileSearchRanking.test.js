"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "FileSearchRanking.js"));

// ---- scoreFile ------------------------------------------------------------

check("scoreFile: exact name match scores highest",
  M.scoreFile("readme.md", "readme.md", false, 2100), 10000);
check("scoreFile: prefix match scores above a substring match",
  M.scoreFile("shellconfig", "shell", false, 2100) > M.scoreFile("dhh-shell", "shell", false, 2100), true);
check("scoreFile: no match at all still returns a real (low) score, not negative -- "
  + "fd itself already filtered to real matches, this only ever RANKS what fd returned",
  M.scoreFile("unrelated", "shell", false, 2100) > 0, true);
check("scoreFile: a directory gets dirBonus added on top of the same base score",
  M.scoreFile("shell", "shell", true, 2100), M.scoreFile("shell", "shell", false, 2100) + 2100);
check("scoreFile: dirBonus closes the real prefix-vs-substring gap -- a directory "
  + "substring match (dhh-shell) outranks a file prefix match (shellconfig) for 'shell'",
  M.scoreFile("dhh-shell", "shell", true, 2100) > M.scoreFile("shellconfig", "shell", false, 2100), true);
check("scoreFile: case-insensitive", M.scoreFile("README.MD", "readme.md", false, 0), 10000);

// ---- parseRawPath -----------------------------------------------------------

check("parseRawPath: a plain file path (no trailing slash) is not a directory",
  M.parseRawPath("/home/dev/notes.txt"),
  { isDir: false, path: "/home/dev/notes.txt", name: "notes.txt", dir: "/home/dev" });
check("parseRawPath: fd's own trailing '/' marks a directory match and gets stripped",
  M.parseRawPath("/home/dev/projects/"),
  { isDir: true, path: "/home/dev/projects", name: "projects", dir: "/home/dev" });
check("parseRawPath: a root-level file (no '/' at all) has an empty dir",
  M.parseRawPath("notes.txt"),
  { isDir: false, path: "notes.txt", name: "notes.txt", dir: "" });

// ---- abbreviateHome ---------------------------------------------------------

check("abbreviateHome: a path under homeDir gets the ~ abbreviation",
  M.abbreviateHome("/home/dev/notes", "/home/dev"), "~/notes");
check("abbreviateHome: a path NOT under homeDir is left alone (e.g. a mounted USB drive)",
  M.abbreviateHome("/run/media/dev/USB", "/home/dev"), "/run/media/dev/USB");
check("abbreviateHome: empty homeDir leaves the path untouched",
  M.abbreviateHome("/home/dev/notes", ""), "/home/dev/notes");

summary();
