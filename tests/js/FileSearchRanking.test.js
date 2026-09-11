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
// Issue #59: a term found only in the path (not the basename at all)
// naturally lands in this same "no match in name" tier -- the QML-level
// wrapper (FileSearchProvider.qml's own scoreFile) relies on exactly
// this: once fd is matching against the FULL path (--full-path), a
// candidate whose basename doesn't contain a given term still scores
// here, below every real basename tier, rather than needing a whole
// separate "path-only" scoring branch.
check("scoreFile: a term absent from the basename entirely (a path-only match, "
  + "once the caller is matching full paths) scores in the same low tier as any other non-match",
  M.scoreFile("README.md", "ruixen", false, 2100) < M.scoreFile("README.md", "readme", false, 2100), true);

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

// ---- isLocalFstype (issue #53) -----------------------------------------

check("isLocalFstype: real local disk filesystems are local",
  [M.isLocalFstype("ext4"), M.isLocalFstype("btrfs"), M.isLocalFstype("xfs"),
    M.isLocalFstype("vfat"), M.isLocalFstype("exfat"), M.isLocalFstype("ntfs3")],
  [true, true, true, true, true, true]);
check("isLocalFstype: case-insensitive", M.isLocalFstype("BTRFS"), true);
check("isLocalFstype: 'fuseblk' (a FUSE filesystem backed by a real local "
  + "block device -- ntfs-3g, exfat-fuse) is local",
  M.isLocalFstype("fuseblk"), true);
check("isLocalFstype: bare 'fuse' and any fuse.<name> variant defaults to "
  + "remote -- no reliable way to tell a network FUSE mount from a local one "
  + "by name alone, so the conservative default wins",
  [M.isLocalFstype("fuse"), M.isLocalFstype("fuse.rclone"), M.isLocalFstype("fuse.sshfs")],
  [false, false, false]);
check("isLocalFstype: real network filesystems are remote",
  [M.isLocalFstype("nfs"), M.isLocalFstype("nfs4"), M.isLocalFstype("cifs"),
    M.isLocalFstype("smb3"), M.isLocalFstype("davfs")],
  [false, false, false, false, false]);
check("isLocalFstype: an unrecognized/exotic fstype defaults to remote (conservative), not local",
  M.isLocalFstype("some-exotic-future-fs"), false);
check("isLocalFstype: empty/undefined input defaults to remote, not a throw",
  [M.isLocalFstype(""), M.isLocalFstype(undefined)], [false, false]);

// ---- parseFileDimensions (issue #56) ---------------------------------------

check("parseFileDimensions: JPEG's own real `file` output (no spaces around x)",
  M.parseFileDimensions("huge.jpg: JPEG image data, JFIF standard 1.01, aspect ratio, density 1x1, segment length 16, baseline, precision 8, 8000x6000, components 3"),
  "8000 × 6000");
check("parseFileDimensions: PNG's own real `file` output (spaces around x)",
  M.parseFileDimensions("test.png: PNG image data, 800 x 600, 1-bit colormap, non-interlaced"),
  "800 × 600");
check("parseFileDimensions: GIF's own real `file` output",
  M.parseFileDimensions("test.gif: GIF image data, version 89a, 800 x 600"),
  "800 × 600");
check("parseFileDimensions: WebP's own real `file` output -- must not be confused by "
  + "the later non-numeric '[none]x[none]' scaling field",
  M.parseFileDimensions("test.webp: RIFF (little-endian) data, WebP image, VP8 encoding, 800x600, Scaling: [none]x[none], YUV color, decoders should clamp"),
  "800 × 600");
check("parseFileDimensions: BMP's own real `file` output -- must stop at the first "
  + "two numbers, not also swallow the trailing bit-depth number ('800 x 600 x 24')",
  M.parseFileDimensions("test.bmp: PC bitmap, Windows 98/2000 and newer format, 800 x 600 x 24, cbSize 1440138, bits offset 138"),
  "800 × 600");
check("parseFileDimensions: no recognizable dimensions (e.g. a non-image file) returns an empty string",
  M.parseFileDimensions("notes.txt: ASCII text"), "");
check("parseFileDimensions: empty/undefined input returns an empty string, not a throw",
  M.parseFileDimensions(undefined), "");

// ---- tokenizeQuery / primaryCandidateTerm / pathSatisfiesAllTerms (issue #59) --

check("tokenizeQuery: splits on whitespace into literal terms",
  M.tokenizeQuery("ruixen readme"), ["ruixen", "readme"]);
check("tokenizeQuery: collapses repeated/leading/trailing whitespace",
  M.tokenizeQuery("  ruixen   readme  "), ["ruixen", "readme"]);
check("tokenizeQuery: a single-word query is a one-element array",
  M.tokenizeQuery("readme"), ["readme"]);
check("tokenizeQuery: empty/whitespace-only input returns an empty array",
  [M.tokenizeQuery(""), M.tokenizeQuery("   ")], [[], []]);
check("tokenizeQuery: undefined input returns an empty array, not a throw",
  M.tokenizeQuery(undefined), []);

check("primaryCandidateTerm: picks the single term outright",
  M.primaryCandidateTerm(["readme"]), "readme");
check("primaryCandidateTerm: picks the LONGEST term across multiple",
  M.primaryCandidateTerm(["a", "architecture"]), "architecture");
check("primaryCandidateTerm: a tie in length keeps the FIRST (leftmost) term",
  M.primaryCandidateTerm(["ruixen", "readme"]), "ruixen");
check("primaryCandidateTerm: empty input returns an empty string, not a throw",
  M.primaryCandidateTerm([]), "");

check("pathSatisfiesAllTerms: every term present somewhere in the path (case-insensitive)",
  M.pathSatisfiesAllTerms("/home/dev/Projects/ruixen-shell/README.md", ["ruixen", "readme"]), true);
check("pathSatisfiesAllTerms: a missing term (not anywhere in the path) fails",
  M.pathSatisfiesAllTerms("/home/dev/Other/README.md", ["ruixen", "readme"]), false);
check("pathSatisfiesAllTerms: a term satisfied only in the parent directory "
  + "(not the filename itself) still counts -- this is the whole point of full-path matching",
  M.pathSatisfiesAllTerms("/home/dev/Projects/ruixen-shell/docs/architecture.md", ["ruixen", "architecture"]), true);
check("pathSatisfiesAllTerms: an empty terms list is trivially satisfied",
  M.pathSatisfiesAllTerms("/home/dev/notes.txt", []), true);

// ---- isMountCandidate / discoverExtraRoots (issue #48/#52) -----------------

check("isMountCandidate: real mount conventions (/mnt, /media, /run/media) are candidates",
  [M.isMountCandidate("/mnt/usb"), M.isMountCandidate("/media/dev/USB"), M.isMountCandidate("/run/media/dev/USB")],
  [true, true, true]);
check("isMountCandidate: real system mounts are never candidates",
  [M.isMountCandidate("/"), M.isMountCandidate("/boot"), M.isMountCandidate("/var/log"), M.isMountCandidate("/proc")],
  [false, false, false, false]);

function findmntFixture(filesystems) {
  return JSON.stringify({ filesystems: filesystems });
}

check("discoverExtraRoots: a real extra root (with its fstype) is kept",
  M.discoverExtraRoots(findmntFixture([{ target: "/mnt/usb", fstype: "ext4" }])),
  [{ path: "/mnt/usb", fstype: "ext4" }]);
check("discoverExtraRoots: real system mounts (/, /boot, tmpfs, proc) are excluded entirely",
  M.discoverExtraRoots(findmntFixture([
    { target: "/", fstype: "btrfs" },
    { target: "/boot", fstype: "vfat" },
    { target: "/run", fstype: "tmpfs" },
    { target: "/proc", fstype: "proc" }
  ])), []);
check("discoverExtraRoots: a mount with a space in its path survives real findmnt --json "
  + "escaping (issue #48 -- the old -P-based parser hex-escaped this and broke it)",
  M.discoverExtraRoots(findmntFixture([{ target: "/mnt/Google Drive", fstype: "fuse.rclone" }])),
  [{ path: "/mnt/Google Drive", fstype: "fuse.rclone" }]);
check("discoverExtraRoots: nested children (a bind mount/submount under an already-listed "
  + "mount) are walked and included",
  M.discoverExtraRoots(findmntFixture([
    { target: "/mnt/usb", fstype: "ext4", children: [{ target: "/mnt/usb/nested", fstype: "ext4" }] }
  ])),
  [{ path: "/mnt/usb", fstype: "ext4" }, { path: "/mnt/usb/nested", fstype: "ext4" }]);
check("discoverExtraRoots: the exact same target appearing twice (a duplicate root) is "
  + "deduped to one entry, keeping the first-seen copy",
  M.discoverExtraRoots(findmntFixture([
    { target: "/mnt/usb", fstype: "ext4" },
    { target: "/mnt/usb", fstype: "ext4" }
  ])),
  [{ path: "/mnt/usb", fstype: "ext4" }]);
check("discoverExtraRoots: malformed JSON (a real findmnt failure) returns an empty list, not a throw",
  M.discoverExtraRoots("not json"), []);
check("discoverExtraRoots: empty/no filesystems returns an empty list",
  M.discoverExtraRoots(findmntFixture([])), []);

// ---- mergeRootResults (issue #54) ------------------------------------------

function fakeResult(path, score) {
  return { label: path, score: score, action: { path: path } }
}

check("mergeRootResults: merges results from multiple roots into one ranked list",
  M.mergeRootResults({
    "/home/dev": [fakeResult("/home/dev/a.txt", 100), fakeResult("/home/dev/b.txt", 50)],
    "/mnt/usb": [fakeResult("/mnt/usb/c.txt", 200)]
  }, 30),
  [fakeResult("/mnt/usb/c.txt", 200), fakeResult("/home/dev/a.txt", 100), fakeResult("/home/dev/b.txt", 50)]);

check("mergeRootResults: a root that hasn't reported yet (not present as a key) contributes nothing -- "
  + "this is exactly what lets a fast root's results show before a slow one finishes",
  M.mergeRootResults({ "/home/dev": [fakeResult("/home/dev/a.txt", 100)] }, 30),
  [fakeResult("/home/dev/a.txt", 100)]);

check("mergeRootResults: a root reporting an empty array (genuinely no matches there) doesn't break the merge",
  M.mergeRootResults({ "/home/dev": [fakeResult("/home/dev/a.txt", 100)], "/mnt/usb": [] }, 30),
  [fakeResult("/home/dev/a.txt", 100)]);

check("mergeRootResults: duplicate real paths across two roots are deduped, keeping the first-seen copy",
  M.mergeRootResults({
    "/home/dev": [fakeResult("/shared/x.txt", 100)],
    "/mnt/bind": [fakeResult("/shared/x.txt", 100)]
  }, 30).length, 1);

check("mergeRootResults: sorts by score BEFORE capping to displayLimit, not the other way around",
  M.mergeRootResults({
    "/home/dev": [fakeResult("/home/dev/low.txt", 1), fakeResult("/home/dev/high.txt", 9999)]
  }, 1),
  [fakeResult("/home/dev/high.txt", 9999)]);

check("mergeRootResults: no roots at all yields an empty list, not a throw",
  M.mergeRootResults({}, 30), []);

// ---- classifyFdExitCode (issue #55) -----------------------------------

check("classifyFdExitCode: exit 0 is success even with zero matches -- fd's own convention",
  M.classifyFdExitCode(0), "success");
check("classifyFdExitCode: exit 124 (our own `timeout` wrapper) is a timeout",
  M.classifyFdExitCode(124), "timeout");
check("classifyFdExitCode: any other non-zero exit is a real fd error (e.g. a vanished root path)",
  [M.classifyFdExitCode(1), M.classifyFdExitCode(2)], ["error", "error"]);

summary();
