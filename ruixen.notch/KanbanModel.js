// Pure helpers for the notch's own Kanban tab (4th dashboard tab,
// KanbanContent.qml) -- kept out of QML so they can be reasoned about
// and tested on their own, matching this repo's own BarModel.js/
// NotificationModel.js pattern.
//
// Deliberately fixed at exactly 3 columns, not a dynamic N-column
// board -- direct request ("less dynamic fill stuff to worry about"):
// only a column's own LABEL is editable (rename Todo -> whatever),
// never the count. This sidesteps an entire class of Layout-collapse
// bugs this session already hit repeatedly elsewhere in this same
// plugin (reserved space for a hidden/absent item not actually
// collapsing) by never having a variable number of columns to lay out
// in the first place.
//
// Agent-native by design -- direct request ("i feel like its easier
// if you just set it up agent native... id tell you to manage and
// update it"): every mutation here is a plain pure function meant to
// be driven by KanbanService.qml's own IpcHandler functions
// (addCard/moveCard/removeCard/renameColumn), the same
// `omarchy-shell ruixen.notch <fn> ...` mechanism already proven for
// setDoNotDisturb/debugOpenDashboard elsewhere in this plugin. The UI
// itself still supports the same actions by hand (click a column
// header to rename, click a card's arrow to advance/regress it), but
// that's the secondary path, not the primary one.

var COLUMN_IDS = ["todo", "in-progress", "done"]
var DEFAULT_LABELS = { "todo": "Todo", "in-progress": "In Progress", "done": "Done" }

function isColumnId(id) {
  return COLUMN_IDS.indexOf(id) >= 0
}

function defaultColumns() {
  return COLUMN_IDS.map(function(id) {
    return { id: id, label: DEFAULT_LABELS[id] }
  })
}

// Always exactly 3 entries, fixed ids, in fixed order -- a malformed,
// short, or reordered persisted store still comes back as a valid
// board rather than a crash or a board with the wrong column count.
function normalizeColumns(raw) {
  var byId = {}
  if (Array.isArray(raw)) {
    for (var i = 0; i < raw.length; i++) {
      var c = raw[i]
      if (c && isColumnId(c.id)) byId[c.id] = String(c.label || DEFAULT_LABELS[c.id])
    }
  }
  return COLUMN_IDS.map(function(id) {
    return { id: id, label: byId[id] || DEFAULT_LABELS[id] }
  })
}

function renameColumn(columns, columnId, label) {
  var list = normalizeColumns(columns)
  var text = String(label || "").trim()
  if (!isColumnId(columnId) || !text) return list
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === columnId) list[i] = { id: columnId, label: text }
  }
  return list
}

// A plain, collision-safe-enough (not cryptographic) id -- the same
// day-to-day informality this repo's own rowKey/entry ids already use
// elsewhere, not a UUID library dependency for something this low-
// stakes. `seed` lets a test pin the random half for a deterministic
// expectation; real callers just omit it.
function makeCardId(now, seed) {
  var rand = seed !== undefined ? seed : Math.random()
  return "card-" + (Number(now) || 0) + "-" + Math.floor(rand * 1e6)
}

// null on a blank title -- nothing to store, matches entryFromRow's
// own "not a real notification" null-return convention.
function entryFromInput(title, columnId, now, seed) {
  var text = String(title || "").trim()
  if (!text) return null
  return {
    id: makeCardId(now, seed),
    column: isColumnId(columnId) ? columnId : COLUMN_IDS[0],
    title: text,
    createdAt: Number(now) || 0
  }
}

// A malformed card (no id, no title) is dropped rather than carried
// forward as a broken entry the UI would render blank.
function normalizeCards(raw) {
  var out = []
  if (!Array.isArray(raw)) return out
  for (var i = 0; i < raw.length; i++) {
    var c = raw[i]
    if (!c || typeof c.id !== "string" || !c.title) continue
    out.push({
      id: c.id,
      column: isColumnId(c.column) ? c.column : COLUMN_IDS[0],
      title: String(c.title),
      createdAt: Number(c.createdAt) || 0
    })
  }
  return out
}

function addCard(cards, card) {
  var list = normalizeCards(cards)
  if (card) list.push(card)
  return list
}

// No-op (cards unchanged) on an unknown card id or an invalid column
// -- fails closed rather than silently dropping/corrupting a card.
function moveCard(cards, cardId, columnId) {
  var list = normalizeCards(cards)
  if (!isColumnId(columnId)) return list
  for (var i = 0; i < list.length; i++) {
    if (list[i].id === cardId) {
      list[i] = { id: list[i].id, column: columnId, title: list[i].title, createdAt: list[i].createdAt }
    }
  }
  return list
}

function removeCard(cards, cardId) {
  return normalizeCards(cards).filter(function(c) { return c.id !== cardId })
}

// Oldest-first within a column -- the order cards were actually added
// in, matching a real board's own left-to-right/top-to-bottom reading
// order rather than an arbitrary storage order.
function cardsInColumn(cards, columnId) {
  return normalizeCards(cards)
    .filter(function(c) { return c.column === columnId })
    .sort(function(a, b) { return (a.createdAt || 0) - (b.createdAt || 0) })
}

// The manual "advance"/"send back" arrow on a card -- clamped at
// either end (a card already in the last column has no next), not a
// wrap-around back to the first column.
function nextColumnId(columnId) {
  var idx = COLUMN_IDS.indexOf(columnId)
  if (idx < 0) return COLUMN_IDS[0]
  return COLUMN_IDS[Math.min(idx + 1, COLUMN_IDS.length - 1)]
}

function prevColumnId(columnId) {
  var idx = COLUMN_IDS.indexOf(columnId)
  if (idx < 0) return COLUMN_IDS[0]
  return COLUMN_IDS[Math.max(idx - 1, 0)]
}

// Column-specific empty-state copy -- direct request ("no cards
// doesnt good... more agentic tool"): a flat "No cards" everywhere
// reads as placeholder UI copy, not a real status. Each column's own
// empty message reads as an actual status instead -- an empty Todo is
// genuinely good news ("no further tasks"), an empty Done just hasn't
// shipped anything yet, neither of which "No cards" conveys. Keyed by
// the fixed column ids directly rather than DEFAULT_LABELS, since a
// renamed column (renameColumn only touches the label, never the id)
// should still show the right status for what that column actually
// means.
var EMPTY_STATE_LABELS = {
  "todo": "No further tasks",
  "in-progress": "Nothing in progress",
  "done": "Nothing completed yet"
}

function emptyStateLabel(columnId) {
  return EMPTY_STATE_LABELS[columnId] || "No cards"
}
