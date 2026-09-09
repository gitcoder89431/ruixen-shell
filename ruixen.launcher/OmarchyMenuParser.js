// Studied directly from Omarchy's own real
// /usr/share/omarchy/shell/plugins/menu/MenuModel.js (MIT,
// github.com/omacom/omarchy) -- NOT imported. That file is a private,
// unversioned implementation detail of the stock menu plugin, exactly
// the class of undocumented-internal dependency ruixen-shell's own
// Omarchy v4.0.3 migration (issue #38) spent a whole session getting
// away from. This is a from-scratch reimplementation of just the two
// pieces worth reusing (JSONC stripping, batched when/checked guard
// evaluation), reading the real, stable, DOCUMENTED Omarchy config file
// (/usr/share/omarchy/default/omarchy/omarchy-menu.jsonc) directly
// instead of depending on Omarchy's own shell-side code at all.

// JSONC -> JSON: strip full-line "//" comments and trailing commas
// before a closing "}"/"]" -- the two things the real file's own header
// comment says it relies on ("JSONC is used for Neovim-friendly
// highlighting, comments, and trailing commas").
function stripJsonc(raw) {
  return String(raw || "")
    .replace(/^\s*\/\/[^\n]*(\n|$)/gm, "")
    .replace(/,(\s*[}\]])/g, "$1")
}

// Flat {id: {icon, label, aliases, action, provider, when, checked}}
// object -- ids are already dotted-hierarchy strings in the real file
// (e.g. "trigger.capture.screenshot"), no tree-building needed.
function parseMenuEntries(raw) {
  var parsed
  try {
    parsed = JSON.parse(stripJsonc(raw))
  } catch (e) {
    return {}
  }
  return (parsed && typeof parsed === "object") ? parsed : {}
}

// Whole subtrees deliberately kept OUT of the launcher, left to the
// native Omarchy root menu (SUPER+SPACE) instead -- direct feedback
// after live-testing found these too easy to fire by accident from a
// fast, fuzzy-matched, flat list with no per-action confirmation of
// their own:
//   - "install."/"remove." -- installs or uninstalls real software
//     (confirmed live: activating "remove.development.go" ran `mise
//     uninstall go --all` on a real installed toolchain, no prompt).
//   - "update.config." -- omarchy-refresh-shell and its siblings reset
//     a real config file (shell.json, hyprland.lua, ...) to Omarchy's
//     stock default, instantly (it does keep a .bak copy, but the live
//     shell still reverts on the spot).
//   - "setup.default." -- sets a system default (editor/browser/
//     terminal/agent) under a plain product-name label (e.g. "Neovim")
//     that reads exactly like "launch this app" -- surprised a real
//     user live ("neovim didnt open neovim it just sets it as the
//     default editor"). Low-risk/reversible, but still not what a
//     quick command palette should be doing on one Enter press --
//     neither macOS Spotlight nor Raycast expose this kind of action.
//   - "system.shutdown"/"system.reboot"/"system.logout" -- end the
//     whole session (closes every app, no confirmation of their own
//     either). "system.lock"/"system.suspend"/"system.hibernate"/
//     "system.screensaver" stay -- they pause rather than end it.
var EXCLUDED_ID_PREFIXES = [
  "install.",
  "remove.",
  "update.config.",
  "setup.default.",
  "system.shutdown",
  "system.reboot",
  "system.logout"
]

function isExcludedFromLauncher(id) {
  var s = String(id || "")
  for (var i = 0; i < EXCLUDED_ID_PREFIXES.length; i++) {
    if (s.indexOf(EXCLUDED_ID_PREFIXES[i]) === 0) return true
  }
  return false
}

// Only entries with a literal, directly-runnable "action" string --
// skips "provider"-kind entries (dynamic Omarchy-internal submenus like
// "apps"/"fonts", out of scope for this plugin), pure category/folder
// nodes (children only, no action of their own), and anything under
// EXCLUDED_ID_PREFIXES.
function actionableEntries(allEntries) {
  var out = {}
  for (var id in allEntries) {
    var entry = allEntries[id]
    if (entry && typeof entry.action === "string" && entry.action.length > 0 && !isExcludedFromLauncher(id))
      out[id] = entry
  }
  return out
}

// The entry's own top-level root label -- one of Omarchy's own fixed,
// real menu categories (Apps, Learn, Trigger, Style, Setup, Update,
// About, System -- Install/Remove never reach here, filtered out by
// actionableEntries above). Used as the launcher's per-row "kind" tag:
// a single mechanical lookup is enough since the ids that used to need
// deeper disambiguation (install vs. remove, "Default Editor" vs. a
// bare "Editor") are exactly the ones now excluded entirely.
function rootLabelFor(allEntries, id) {
  var rootId = String(id || "").split(".")[0]
  var root = allEntries[rootId]
  return (root && root.label) ? String(root.label) : ""
}

// Batches every when/checked shell expression into ONE bash script
// (confirmed live against the real file: ~152 "when" + ~43 "checked" --
// avoids spawning 150+ separate processes for what's currently ~195
// real conditions). Same shape as Omarchy's own real guardScript, a
// from-scratch reimplementation of the same idea, not a copy.
function guardLine(id, tag, expression) {
  return "if { " + expression + "; } >/dev/null 2>&1; then echo " + id + ":" + tag + ":1; else echo " + id + ":" + tag + ":0; fi"
}

function buildGuardScript(actionable) {
  var lines = []
  for (var id in actionable) {
    var entry = actionable[id]
    if (entry.when) lines.push(guardLine(id, "w", entry.when))
    if (entry.checked) lines.push(guardLine(id, "c", entry.checked))
  }
  return lines.join("\n")
}

// Parses "id:tag:0|1" lines back into {[id]: {when: bool, checked:
// bool}}. Entry ids never contain a literal colon (confirmed: they're
// built from JSON object keys split on "."), so splitting on ":" and
// treating the last two segments as tag/value is unambiguous. An id
// with no when/checked at all simply never appears here -- isVisible()
// below treats "absent" as "no condition, always visible".
function parseGuardOutput(stdout) {
  var results = {}
  var lines = String(stdout || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (!line) continue
    var parts = line.split(":")
    if (parts.length < 3) continue
    var id = parts.slice(0, parts.length - 2).join(":")
    var tag = parts[parts.length - 2]
    var value = parts[parts.length - 1] === "1"
    if (!results[id]) results[id] = {}
    if (tag === "w") results[id].when = value
    else if (tag === "c") results[id].checked = value
  }
  return results
}

function isVisible(id, entry, guardResults) {
  if (!entry.when) return true
  var result = guardResults[id]
  return result ? result.when !== false : true
}

// Scoring against label + aliases, same 0-10000 scale convention
// AppSearch.js's own fuzzyScore uses so Launcher.qml's per-section
// sort (byScoreDesc) is meaningful across both providers. Simpler than
// AppSearch.js's own algorithm (no acronym fallback) since Omarchy menu
// labels/aliases are short, curated strings, not free-form app names.
function scoreEntry(entry, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return -1
  var label = String(entry.label || "").toLowerCase()
  var aliases = Array.isArray(entry.aliases) ? entry.aliases : []

  if (label === q) return 10000
  var labelIndex = label.indexOf(q)
  if (labelIndex === 0) return 9000 - label.length
  if (labelIndex > 0) return 7000 - labelIndex * 10 - label.length

  for (var i = 0; i < aliases.length; i++) {
    var alias = String(aliases[i] || "").toLowerCase()
    if (alias === q) return 8500
    var aliasIndex = alias.indexOf(q)
    if (aliasIndex === 0) return 7500 - alias.length
    if (aliasIndex > 0) return 6000 - aliasIndex * 10 - alias.length
  }

  return -1
}
