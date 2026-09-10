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

// Only "ends the whole session outright" actions are excluded now --
// closes every app with no confirmation of its own, and no breadcrumb
// wording could make that less abrupt. "system.lock"/"suspend"/
// "hibernate"/"screensaver" stay -- they pause rather than end it.
//
// install./remove./update.config./setup.default. used to be excluded
// too (installs/removes real software, resets a real config file,
// sets a system default under a bare product-name label) -- reversed
// once breadcrumbFor() below started spelling out the full ancestor
// path instead of a single truncated category level. The actual
// reported confusion (a live Go uninstall from one Enter press,
// Neovim silently becoming the default editor) was a LABELING problem
// -- "Remove › Development" and "Setup › Defaults › Editor" say
// plainly what they do, matching the confirmed real-world precedent of
// Vicinae's own omarchy-menu extension, which shows exactly this full
// breadcrumb and nothing else (no confirm step, no exclusion) and
// still reads as clear rather than confusing.
var EXCLUDED_ID_PREFIXES = [
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

// Every ancestor's own label, root down to the immediate parent, joined
// "Root › ... › Parent" -- e.g. "remove.development.go" ->
// "Remove › Development", "setup.default.editor.neovim" ->
// "Setup › Defaults › Editor". Confirmed live nesting never exceeds 3
// levels (70 of ~275 actionable entries sit at depth 3, none deeper),
// so this never grows unreasonably long. Deliberately the FULL chain,
// not just the immediate parent -- Vicinae's own omarchy-menu
// extension does exactly this (their pathFor) and it's what makes
// "Remove › Development" read as obviously a removal without any
// separate title-override lookup; a single truncated level ("just
// "Development") is what caused the original confusion.
function breadcrumbFor(allEntries, id) {
  var labels = []
  var current = String(id || "")
  while (true) {
    var dot = current.lastIndexOf(".")
    if (dot === -1) break
    current = current.substring(0, dot)
    var node = allEntries[current]
    if (node && node.label) labels.unshift(String(node.label))
  }
  return labels.join(" › ")
}

// Same per-id shallow-merge semantics as Omarchy's own real
// mergeMenuSources (studied directly, not imported -- see this file's
// own header for why): defaults first, then userEntries -- a field the
// user's own entry supplies overrides the matching default field, an
// id-only-in-userEntries is added outright, everything else from the
// default survives untouched. ~/.config/omarchy/extensions/omarchy-
// menu.jsonc is a real, documented, hot-reloading Omarchy user
// customization point (confirmed in Omarchy's own SKILL.md config-path
// table and the native Menu.qml, not a Vicinae invention) -- entries
// added there should be just as searchable here as the packaged
// defaults.
function mergeUserOverrides(defaultEntries, userEntries) {
  var merged = {}
  for (var id in defaultEntries) merged[id] = defaultEntries[id]
  for (var uid in userEntries) {
    var prior = merged[uid] || {}
    var next = {}
    for (var k in prior) next[k] = prior[k]
    for (var k2 in userEntries[uid]) next[k2] = userEntries[uid][k2]
    merged[uid] = next
  }
  return merged
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

// ---- Keybind hints --------------------------------------------------------
//
// Many Omarchy Actions/Applications rows already have a real Hyprland
// keybind configured -- surfacing it after the row's own subtitle saves a
// trip to Omarchy's own keybindings menu. `omarchy menu keybindings
// --print` is the data source: a real, stable, documented Omarchy command
// (confirmed live, not an internal implementation detail) that already
// merges the packaged default binds AND the user's own personal
// ~/.config/hypr/bindings.lua customizations into one flat list -- one
// process at provider startup (~200ms measured live), never re-run per
// keystroke.

// "<keybind, space-padded>→<label>" per line (confirmed live: 227 lines
// on a real machine) -- split on the arrow, trim both sides.
function parseKeybindingsOutput(stdout) {
  var out = []
  var lines = String(stdout || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var arrow = lines[i].indexOf("→")
    if (arrow === -1) continue
    var keybind = lines[i].substring(0, arrow).trim()
    var label = lines[i].substring(arrow + 1).trim()
    if (keybind && label) out.push({ keybind: keybind, label: label })
  }
  return out
}

// Parses the user's own real ~/.config/hypr/bindings.lua for labeled
// o.bind("<keybind>", "<label>", "<command>") calls. Strips Lua's own
// "--" line comments first -- this file has real commented-out o.bind()
// lines on this dev machine (confirmed live: only 3 of several o.bind()
// calls are actually uncommented), which a bare regex scan would
// otherwise pick up as real bindings. An unlabeled bind (its label
// argument is the bare word `nil`, not a quoted string) can't be matched
// by label at all, so it's skipped rather than guessed at. This is the
// ONLY reliable, text-parseable source of which keybind is the user's
// own PERSONAL override -- confirmed live that `hyprctl binds -j` routes
// every real bind through an opaque internal __lua dispatcher with
// numeric args, not usable for this.
function parsePersonalBindings(luaSource) {
  var out = []
  var stripped = String(luaSource || "").replace(/--.*$/gm, "")
  var re = /o\.bind\(\s*"([^"]+)"\s*,\s*"([^"]+)"\s*,/g
  var m
  while ((m = re.exec(stripped)) !== null) {
    out.push({ keybind: m[1].trim(), label: m[2].trim() })
  }
  return out
}

// "SUPER + SHIFT + Z" -> "SUPER+SHIFT+Z" -- same information without the
// column-padding-friendly spacing `omarchy menu keybindings --print`'s
// own layout needs, which reads as wasted width in a single narrow
// row-trailing hint.
function formatKeybind(keybind) {
  return String(keybind || "").replace(/\s*\+\s*/g, "+")
}

function escapeRegExp(s) {
  return s.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
}

// A menu entry's own label and the keybindings list's own label for the
// SAME action are often not identical (confirmed live: "Lock" vs "Lock
// system", "Theme" vs "Theme menu") -- exact equality misses real
// matches. A whole-word containment check in either direction catches
// both without also matching unrelated labels that merely share a
// substring (e.g. "Lock" must not match "Unlock" or "Clock").
function labelsFuzzyMatch(a, b) {
  var la = String(a || "").toLowerCase().trim()
  var lb = String(b || "").toLowerCase().trim()
  if (!la || !lb) return false
  if (la === lb) return true
  if (lb.length > la.length && new RegExp("\\b" + escapeRegExp(la) + "\\b").test(lb)) return true
  if (la.length > lb.length && new RegExp("\\b" + escapeRegExp(lb) + "\\b").test(la)) return true
  return false
}

// {labelLower: keybind} exact-match lookup -- personal entries are added
// FIRST and win outright over a stock entry sharing the same exact label
// (direct product decision: when both a personal and a stock/default
// keybind exist for the same action, show ONLY the personal one -- "we
// def dont have space for both"). Real example on this machine: the
// packaged default binds Screenshot to one combo, the user's own
// bindings.lua rebinds it to another under the SAME label "Screenshot" --
// this index resolves that to the personal one. Fuzzy (non-exact) label
// matches fall through to keybindFor's own scan of stockEntries below,
// since the personal list here is small and hand-written to match
// exactly, not worth fuzzy-matching itself.
function buildKeybindIndex(stockEntries, personalEntries) {
  var index = {}
  var stock = Array.isArray(stockEntries) ? stockEntries : []
  var personal = Array.isArray(personalEntries) ? personalEntries : []
  for (var i = 0; i < personal.length; i++) {
    var key = personal[i].label.toLowerCase()
    if (!index[key]) index[key] = formatKeybind(personal[i].keybind)
  }
  for (var j = 0; j < stock.length; j++) {
    var key2 = stock[j].label.toLowerCase()
    if (!index[key2]) index[key2] = formatKeybind(stock[j].keybind)
  }
  return index
}

// Given an entry's own label: exact lookup in `index` first (covers
// every personal override and any stock label that matched exactly),
// falling back to a fuzzy scan of the raw stock list only when nothing
// matched exactly. Returns "" (no hint) rather than undefined/null --
// Launcher.qml's own row delegate treats a falsy keybind as "don't show
// this element" either way, but a stable empty string keeps every
// resultFor() row shape identical.
// "SUPER+SHIFT+Z" -> ["SUPER", "SHIFT", "Z"] -- one array entry per key
// cap Launcher.qml's own row delegate renders as its own small bordered
// chip (see keySymbol below for what goes inside each one). Splits on
// ANY run of spaces or "+", not just "+" -- confirmed live the two real
// sources format multi-modifier combos differently: bindings.lua's own
// o.bind() spells every key " + "-joined ("SUPER + SHIFT + Z"), but
// `omarchy menu keybindings --print`'s own stock list only puts a "+"
// before the FINAL key, space-joining multiple modifiers before it
// ("SUPER CTRL + L") -- a plain split("+") left "SUPER CTRL" as one
// unrecognized chip instead of two real keycaps, caught live via
// screenshot.
function keybindParts(formattedKeybind) {
  var s = String(formattedKeybind || "").trim()
  return s ? s.split(/[\s+]+/).filter(function(part) { return part.length > 0 }) : []
}

// A handful of modifier keys get a real symbol instead of their bare
// name -- the familiar ⌘/⇧/⌃/⌥ modifier-symbol convention (direct
// request: the command-key glyph reads cleaner here than a literal
// Windows-logo one), so a 3-key combo reads as key CAPS at a glance
// rather than an acronym to sound out. Everything else (a letter,
// digit, or named key like SPACE/TAB) passes through as its own
// uppercase text -- there's no equally universal symbol for those, and
// spelling them out plainly is already clear.
function keySymbol(part) {
  var p = String(part || "").trim().toUpperCase()
  if (p === "SUPER") return "⌘"
  if (p === "SHIFT") return "⇧"
  if (p === "CTRL") return "⌃"
  if (p === "ALT") return "⌥"
  return p
}

function keybindFor(label, index, stockEntries) {
  var key = String(label || "").toLowerCase().trim()
  if (!key) return ""
  if (index && index[key]) return index[key]
  var stock = Array.isArray(stockEntries) ? stockEntries : []
  for (var i = 0; i < stock.length; i++) {
    if (labelsFuzzyMatch(label, stock[i].label)) return formatKeybind(stock[i].keybind)
  }
  return ""
}
