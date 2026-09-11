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

summary();
