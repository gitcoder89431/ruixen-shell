// Frecency: a small, bounded ranking boost for anything actually
// activated (not just searched) often/recently -- shared by every
// launcher provider that wants one (apps via AppSearch.js, Omarchy
// Actions via OmarchyMenuParser.js, ...). Direct request: typing "dis"
// should rank Discord (opened daily) above a rarely-used app that
// merely matches more literally, and separately, "theme" should rank
// Change Theme above Install Theme once it's the one actually used --
// same underlying need, two different providers with their own id
// schemes and their own scoring tiers, so this file only knows about a
// generic {count, lastUsed} stat -- no I/O, no notion of what "an
// entry" even is for a given provider. Each provider keeps its own
// small {id: stat} object (its own state file, its own id scheme) and
// calls frecencyBoost(stat, nowMs) with whatever it looked up for a
// given candidate.
//
// Capped well under the gap between any given provider's own scoring
// tiers, so a heavily-used entry can win a close contest within its
// own tier (the "dis"/"theme" cases above) without a stale, once-used
// entry leapfrogging a genuinely stronger textual match elsewhere.
var FRECENCY_COUNT_CAP = 20
var FRECENCY_MAX_BOOST = 600
var FRECENCY_DAY_MS = 86400000

function frecencyDecay(ageMs) {
  if (ageMs <= FRECENCY_DAY_MS) return 1.0
  if (ageMs <= 7 * FRECENCY_DAY_MS) return 0.7
  if (ageMs <= 30 * FRECENCY_DAY_MS) return 0.4
  return 0.15
}

function frecencyBoost(stat, nowMs) {
  if (!stat || !stat.count) return 0
  var count = Math.min(stat.count, FRECENCY_COUNT_CAP)
  var age = Math.max(0, (nowMs || 0) - (stat.lastUsed || 0))
  return Math.round((count / FRECENCY_COUNT_CAP) * FRECENCY_MAX_BOOST * frecencyDecay(age))
}

// Pure -- returns a NEW stats object rather than mutating the one
// passed in, same convention every other config mutator in this repo
// follows (Object.assign({}, ...)), so a QML caller can assign the
// result straight to a property and get real change notification.
function recordLaunch(stats, id) {
  var key = String(id || "")
  if (!key) return stats
  var next = Object.assign({}, stats)
  var prev = next[key] || { count: 0, lastUsed: 0 }
  next[key] = { count: prev.count + 1, lastUsed: Date.now() }
  return next
}
