"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "LauncherQueryOperators.js"));

// ---- parseQuery: the issue's own worked examples ---------------------------

check("parseQuery: the issue's own worked example, verbatim",
  M.parseQuery("type:image in:Home sunset"),
  { text: "sunset", type: "image", source: "Home" });

check("parseQuery: kind: is an alias for type:",
  M.parseQuery("kind:folder projects"),
  { text: "projects", type: "folder" });

check("parseQuery: in:\"quoted value with spaces\" report",
  M.parseQuery("in:\"Google Drive\" quarterly report"),
  { text: "quarterly report", source: "Google Drive" });

check("parseQuery: name: with a value glued directly to it -- since name has no "
  + "real parameter of its own, the value becomes real search text, not a discarded operand",
  M.parseQuery("name:architecture"),
  { text: "architecture", scope: "names" });

check("parseQuery: content: behaves the same way as name:",
  M.parseQuery("content:candidateBudget"),
  { text: "candidateBudget", scope: "contents" });

check("parseQuery: hidden:true ssh -- hidden IS a real boolean parameter, its value "
  + "is consumed, not added to the text",
  M.parseQuery("hidden:true ssh"),
  { text: "ssh", hidden: true });

// ---- individual operators in isolation --------------------------------------

check("parseQuery: source: is an alias for in:",
  M.parseQuery("source:Home invoice"),
  { text: "invoice", source: "Home" });

check("parseQuery: hidden:false",
  M.parseQuery("hidden:false ssh"),
  { text: "ssh", hidden: false });

check("parseQuery: operator keys are case-insensitive",
  M.parseQuery("TYPE:image IN:Home sunset"),
  { text: "sunset", type: "image", source: "Home" });

check("parseQuery: multiple operators combine into one structured result",
  M.parseQuery("type:image in:Home hidden:true sunset"),
  { text: "sunset", type: "image", source: "Home", hidden: true });

check("parseQuery: plain text with no operators at all is untouched",
  M.parseQuery("just a plain search"),
  { text: "just a plain search" });

check("parseQuery: empty/undefined input returns empty text, not a throw",
  [M.parseQuery(""), M.parseQuery(undefined)],
  [{ text: "" }, { text: "" }]);

check("parseQuery: whitespace-only input returns empty text",
  M.parseQuery("   \t  "), { text: "" });

// ---- graceful degradation ----------------------------------------------------

check("parseQuery: an unrecognized operator key is left as ordinary literal text, "
  + "not silently dropped or misapplied",
  M.parseQuery("foo:bar sunset"),
  { text: "foo:bar sunset" });

check("parseQuery: hidden: with a non-boolean value degrades to literal text entirely "
  + "(does not silently default hidden to false)",
  M.parseQuery("hidden:maybe ssh"),
  { text: "hidden:maybe ssh" });

check("parseQuery: type:/in: with NOTHING after the colon (immediately followed by "
  + "whitespace) degrades to literal text -- an empty value isn't a real filter",
  M.parseQuery("type: sunset"),
  { text: "type: sunset" });

check("parseQuery: an unterminated quoted value degrades that whole token to literal "
  + "text rather than swallowing the rest of the query as part of the value",
  M.parseQuery("in:\"Google Drive report"),
  { text: "in:\"Google Drive report" });

check("parseQuery: name:/content: with nothing attached (bare, followed by whitespace) "
  + "still validly sets scope with no text glued",
  [M.parseQuery("name: architecture"), M.parseQuery("content: candidateBudget")],
  [{ text: "architecture", scope: "names" }, { text: "candidateBudget", scope: "contents" }]);

// ---- ordering / determinism ---------------------------------------------------

check("parseQuery: result keys are always in the SAME fixed order regardless of "
  + "the order operators appeared in the input -- equivalent queries produce "
  + "structurally identical (not just semantically equal) results",
  JSON.stringify(M.parseQuery("in:Home type:image sunset")),
  JSON.stringify(M.parseQuery("type:image in:Home sunset")));

check("parseQuery: a query written with operators in a totally different order "
  + "still resolves to the same fields",
  M.parseQuery("sunset type:image in:Home"),
  { text: "sunset", type: "image", source: "Home" });

check("parseQuery: the same operator repeated -- the LAST occurrence wins",
  M.parseQuery("type:image type:video sunset"),
  { text: "sunset", type: "video" });

// ---- safety: never shell syntax, never evaluated -----------------------------

check("parseQuery: a literal $(...) inside a quoted operator value passes through "
  + "as plain data, never evaluated",
  M.parseQuery("in:\"$(rm -rf /)\" report"),
  { text: "report", source: "$(rm -rf /)" });

check("parseQuery: a leading dash in the free text is preserved as plain text, "
  + "never interpreted as a flag",
  M.parseQuery("--dangerous-flag"),
  { text: "--dangerous-flag" });

check("parseQuery: Unicode and apostrophes in free text and quoted values survive untouched",
  M.parseQuery("in:\"café's docs\" résumé"),
  { text: "résumé", source: "café's docs" });

// ---- resolveCategoryOperator --------------------------------------------------

const CATEGORIES = ["Folders", "Documents", "Images", "Video", "Audio", "Archives", "Code/Text"];

check("resolveCategoryOperator: exact case-insensitive match",
  resolveCat("images"), "Images");
check("resolveCategoryOperator: an accepted singular alias resolves to its real plural category",
  resolveCat("image"), "Images");
check("resolveCategoryOperator: 'Code/Text' matches case-insensitively as typed",
  resolveCat("code/text"), "Code/Text");
check("resolveCategoryOperator: an unrecognized value resolves to null, not a throw "
  + "or a silent fallback to 'All'",
  resolveCat("nonsense"), null);

function resolveCat(v) { return M.resolveCategoryOperator(v, CATEGORIES); }

// ---- resolveSourceOperator ----------------------------------------------------

const SOURCES = [
  { id: "/home/dev", label: "Home", path: "/home/dev" },
  { id: "/mnt/Work Drive", label: "Work Drive", path: "/mnt/Work Drive" }
];

check("resolveSourceOperator: matches by label, case-insensitively",
  M.resolveSourceOperator("home", SOURCES), "/home/dev");
check("resolveSourceOperator: matches a multi-word label",
  M.resolveSourceOperator("Work Drive", SOURCES), "/mnt/Work Drive");
check("resolveSourceOperator: matches by bare path too",
  M.resolveSourceOperator("/home/dev", SOURCES), "/home/dev");
check("resolveSourceOperator: an unrecognized source resolves to null",
  M.resolveSourceOperator("Nonexistent Drive", SOURCES), null);
check("resolveSourceOperator: an empty sources list never throws",
  M.resolveSourceOperator("Home", []), null);

summary();
