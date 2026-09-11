"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "LauncherSearchConfig.js"));

// ---- defaultConfig / parseSearchConfig -------------------------------------

check("defaultConfig: represents today's real behavior exactly -- Home and "
  + "mounted roots both included, no custom roots/exclusions, the existing "
  + "hardcoded excludeNames seeded as the starting list",
  M.defaultConfig(),
  {
    version: 1,
    includeHome: true,
    includeMountedRoots: true,
    roots: [],
    disabledAutoRoots: [],
    excludePaths: [],
    excludeNames: ["node_modules", "vendor", "target", "go", ".git"]
  });

check("parseSearchConfig: a well-formed config round-trips exactly",
  M.parseSearchConfig(JSON.stringify({
    version: 1, includeHome: false, includeMountedRoots: true,
    roots: ["~/Work"], disabledAutoRoots: ["/mnt/Backup"],
    excludePaths: ["~/VMs"], excludeNames: ["node_modules", ".venv"]
  })),
  {
    version: 1, includeHome: false, includeMountedRoots: true,
    roots: ["~/Work"], disabledAutoRoots: ["/mnt/Backup"],
    excludePaths: ["~/VMs"], excludeNames: ["node_modules", ".venv"]
  });

check("parseSearchConfig: malformed JSON falls back to the full default, not a throw",
  M.parseSearchConfig("not json"), M.defaultConfig());
check("parseSearchConfig: empty string falls back to the full default",
  M.parseSearchConfig(""), M.defaultConfig());
check("parseSearchConfig: a JSON array (wrong top-level shape) falls back to the full default",
  M.parseSearchConfig("[1,2,3]"), M.defaultConfig());

check("parseSearchConfig: one bad field (wrong type) falls back to just THAT field's "
  + "default, not the whole file -- a hand-edit typo shouldn't lose every other setting",
  M.parseSearchConfig(JSON.stringify({ includeHome: "yes", roots: ["~/Work"] })),
  Object.assign(M.defaultConfig(), { includeHome: true, roots: ["~/Work"] }));

check("parseSearchConfig: a non-array where an array is expected falls back to that field's default",
  M.parseSearchConfig(JSON.stringify({ roots: "not-an-array" })).roots, []);

check("parseSearchConfig: array entries are trimmed and empty/non-string entries are dropped",
  M.parseSearchConfig(JSON.stringify({ roots: ["  ~/Work  ", "", 42, null, "~/Play"] })).roots,
  ["~/Work", "~/Play"]);

check("parseSearchConfig: an unknown extra key is silently ignored, not an error",
  M.parseSearchConfig(JSON.stringify({ includeHome: false, someFutureField: 123 })).includeHome, false);

check("parseSearchConfig: version is always normalized to the current schema version "
  + "regardless of what a stored file says",
  M.parseSearchConfig(JSON.stringify({ version: 999 })).version, 1);

// ---- serializeSearchConfig --------------------------------------------------

check("serializeSearchConfig: round-trips through parseSearchConfig unchanged",
  M.parseSearchConfig(M.serializeSearchConfig(M.defaultConfig())), M.defaultConfig());

// ---- normalizePath / expandHome ---------------------------------------------

check("expandHome: a bare '~' expands to homeDir exactly",
  M.expandHome("~", "/home/dev"), "/home/dev");
check("expandHome: a leading '~/' expands, the rest of the path is untouched",
  M.expandHome("~/Work/notes", "/home/dev"), "/home/dev/Work/notes");
check("expandHome: an absolute path with no '~' is left alone",
  M.expandHome("/mnt/Documents", "/home/dev"), "/mnt/Documents");
check("expandHome: '~' NOT followed by '/' (e.g. '~foo') is left alone -- "
  + "only a bare '~' or a leading '~/' are ever substituted",
  M.expandHome("~foo/bar", "/home/dev"), "~foo/bar");
check("expandHome: never evaluates shell syntax -- a literal $(...) or backtick "
  + "string passes through completely unchanged, as plain data",
  M.expandHome("$(rm -rf /)", "/home/dev"), "$(rm -rf /)");

check("normalizePath: strips a single trailing slash",
  M.normalizePath("/mnt/Documents/", "/home/dev"), "/mnt/Documents");
check("normalizePath: the bare root '/' is left as '/', not stripped to empty",
  M.normalizePath("/", "/home/dev"), "/");
check("normalizePath: expands '~' AND strips a trailing slash in one pass",
  M.normalizePath("~/Work/", "/home/dev"), "/home/dev/Work");

// ---- isUnderAnyExcludedPath --------------------------------------------------

check("isUnderAnyExcludedPath: an exact excluded path matches",
  M.isUnderAnyExcludedPath("/home/dev/VMs", ["~/VMs"], "/home/dev"), true);
check("isUnderAnyExcludedPath: a real SUBTREE of an excluded path matches",
  M.isUnderAnyExcludedPath("/home/dev/VMs/win11/disk.qcow2", ["~/VMs"], "/home/dev"), true);
check("isUnderAnyExcludedPath: a path that merely shares a PREFIX (not a real subtree) does not match -- "
  + "'/home/dev/VMs-old' is not under '/home/dev/VMs'",
  M.isUnderAnyExcludedPath("/home/dev/VMs-old/notes.txt", ["~/VMs"], "/home/dev"), false);
check("isUnderAnyExcludedPath: an unrelated path matches nothing",
  M.isUnderAnyExcludedPath("/home/dev/Projects", ["~/VMs"], "/home/dev"), false);
check("isUnderAnyExcludedPath: no exclusions configured never matches",
  M.isUnderAnyExcludedPath("/home/dev/anything", [], "/home/dev"), false);

// ---- computeEffectiveExtraRoots -----------------------------------------------

function auto(path, fstype) { return { path: path, fstype: fstype }; }

check("computeEffectiveExtraRoots: default config includes every auto-discovered root, no custom roots",
  M.computeEffectiveExtraRoots(M.defaultConfig(), [auto("/mnt/USB", "vfat")], "/home/dev"),
  [{ path: "/mnt/USB", fstype: "vfat" }]);

check("computeEffectiveExtraRoots: includeMountedRoots false excludes EVERY auto-discovered "
  + "root outright, even ones not individually disabled",
  M.computeEffectiveExtraRoots(
    Object.assign(M.defaultConfig(), { includeMountedRoots: false }),
    [auto("/mnt/USB", "vfat")], "/home/dev"),
  []);

check("computeEffectiveExtraRoots: a specific disabledAutoRoots entry excludes just that "
  + "one mount, others still included",
  M.computeEffectiveExtraRoots(
    Object.assign(M.defaultConfig(), { disabledAutoRoots: ["/mnt/Backup"] }),
    [auto("/mnt/USB", "vfat"), auto("/mnt/Backup", "ext4")], "/home/dev"),
  [{ path: "/mnt/USB", fstype: "vfat" }]);

check("computeEffectiveExtraRoots: a custom root is included, with an empty (unknown) fstype",
  M.computeEffectiveExtraRoots(
    Object.assign(M.defaultConfig(), { roots: ["~/Work"] }),
    [], "/home/dev"),
  [{ path: "/home/dev/Work", fstype: "" }]);

check("computeEffectiveExtraRoots: an excluded subtree removes a matching auto-discovered root",
  M.computeEffectiveExtraRoots(
    Object.assign(M.defaultConfig(), { excludePaths: ["/mnt/USB"] }),
    [auto("/mnt/USB", "vfat")], "/home/dev"),
  []);

check("computeEffectiveExtraRoots: an excluded subtree removes a matching custom root too -- "
  + "exclusions apply uniformly regardless of how the root was added",
  M.computeEffectiveExtraRoots(
    Object.assign(M.defaultConfig(), { roots: ["~/VMs/scratch"], excludePaths: ["~/VMs"] }),
    [], "/home/dev"),
  []);

check("computeEffectiveExtraRoots: the same real path added as both an auto-discovered root "
  + "and a custom root is deduped to one entry, keeping the auto-discovered copy's own REAL "
  + "fstype rather than the custom root's unknown one",
  M.computeEffectiveExtraRoots(
    Object.assign(M.defaultConfig(), { roots: ["/mnt/USB"] }),
    [auto("/mnt/USB", "vfat")], "/home/dev"),
  [{ path: "/mnt/USB", fstype: "vfat" }]);

check("computeEffectiveExtraRoots: Home itself is never duplicated into this list even if "
  + "somehow configured as a custom root -- it's handled entirely separately via includeHome",
  M.computeEffectiveExtraRoots(
    Object.assign(M.defaultConfig(), { roots: ["~"] }),
    [], "/home/dev"),
  []);

check("computeEffectiveExtraRoots: no auto-discovered roots and no custom roots yields an "
  + "empty list, not a throw",
  M.computeEffectiveExtraRoots(M.defaultConfig(), [], "/home/dev"), []);
check("computeEffectiveExtraRoots: a null/undefined autoDiscoveredRoots list is treated as empty",
  M.computeEffectiveExtraRoots(M.defaultConfig(), undefined, "/home/dev"), []);

// ---- discoverMountedRoots (settings checklist) -------------------------------

function findmntFixture(filesystems) {
  return JSON.stringify({ filesystems: filesystems });
}

check("discoverMountedRoots: a real mount convention (/mnt) is kept, with its fstype",
  M.discoverMountedRoots(findmntFixture([{ target: "/mnt/usb", fstype: "ext4" }])),
  [{ path: "/mnt/usb", fstype: "ext4" }]);
check("discoverMountedRoots: real system mounts (/, /boot) are excluded",
  M.discoverMountedRoots(findmntFixture([{ target: "/", fstype: "btrfs" }, { target: "/boot", fstype: "vfat" }])),
  []);
check("discoverMountedRoots: malformed JSON returns an empty list, not a throw",
  M.discoverMountedRoots("not json"), []);

// ---- escapeGlobLiteral (issue #64) ------------------------------------------

check("escapeGlobLiteral: a plain name with no special characters is unchanged",
  M.escapeGlobLiteral("node_modules"), "node_modules");
check("escapeGlobLiteral: glob metacharacters (\\, *, ?, [, ]) are each backslash-escaped",
  M.escapeGlobLiteral("foo[bar]*?\\baz"), "foo\\[bar\\]\\*\\?\\\\baz");
check("escapeGlobLiteral: a leading ! is left alone -- only * ? [ ] \\ are glob-special here",
  M.escapeGlobLiteral("!important"), "!important");
check("escapeGlobLiteral: null/undefined is treated as an empty string, not a throw",
  M.escapeGlobLiteral(undefined), "");

// ---- excludeInfoForRoot / rootExactlyExcluded (issue #64) -------------------

check("excludeInfoForRoot: an exclusion equal to the worker root itself is a full skip",
  M.excludeInfoForRoot("/home/dev/VMs", "/home/dev/VMs", "/home/dev"),
  { skip: true });
check("excludeInfoForRoot: ~ expansion applies before the equality check",
  M.excludeInfoForRoot("~/VMs", "/home/dev/VMs", "/home/dev"),
  { skip: true });
check("excludeInfoForRoot: a genuine subtree under the root returns root-relative and "
  + "absolute glob fragments",
  M.excludeInfoForRoot("/home/dev/VMs", "/home/dev", "/home/dev"),
  { skip: false, relative: "/VMs", absolute: "/home/dev/VMs" });
check("excludeInfoForRoot: an exclusion outside this root entirely has no effect on it",
  M.excludeInfoForRoot("/mnt/USB/VMs", "/home/dev", "/home/dev"), null);
check("excludeInfoForRoot: a sibling directory sharing a name PREFIX is not treated as "
  + "under the root -- /home/dev/Work must not swallow /home/dev/Workspace",
  M.excludeInfoForRoot("/home/dev/Workspace", "/home/dev/Work", "/home/dev"), null);
check("excludeInfoForRoot: the returned fragments are glob-escaped, not just substringed",
  M.excludeInfoForRoot("/home/dev/foo[bar]", "/home/dev", "/home/dev"),
  { skip: false, relative: "/foo\\[bar\\]", absolute: "/home/dev/foo\\[bar\\]" });
check("excludeInfoForRoot: a trailing slash on either input doesn't change the outcome",
  M.excludeInfoForRoot("/home/dev/VMs/", "/home/dev/", "/home/dev"),
  { skip: false, relative: "/VMs", absolute: "/home/dev/VMs" });

check("rootExactlyExcluded: true when the root exactly matches a configured exclusion",
  M.rootExactlyExcluded("/home/dev/VMs", ["/home/dev/VMs"], "/home/dev"), true);
check("rootExactlyExcluded: false for a root that's merely a PARENT of an exclusion "
  + "(the exclusion is a subtree of it, not equal to it -- this root should still run, "
  + "just with that subtree excluded)",
  M.rootExactlyExcluded("/home/dev", ["/home/dev/VMs"], "/home/dev"), false);
check("rootExactlyExcluded: false for a root with no matching exclusion at all",
  M.rootExactlyExcluded("/home/dev", ["/mnt/USB"], "/home/dev"), false);
check("rootExactlyExcluded: false when excludePaths is empty",
  M.rootExactlyExcluded("/home/dev", [], "/home/dev"), false);

summary();
