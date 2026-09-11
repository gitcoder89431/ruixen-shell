// Issue #58 (also relevant to #46/#52/#54/#55): a pure, testable state
// machine for the small fixed pool of reusable Process workers both
// FileSearchProvider.qml and FileContentSearchProvider.qml use for
// per-root searches (issue #54).
//
// Why this exists as a SEPARATE module rather than staying as ad hoc
// `currentRoot` properties on each worker (the shape both providers
// used before this issue): confirmed live with a standalone Quickshell
// harness that `running = false` is an ASYNC kill -- the killed
// process's own `onExited` fires on a LATER event-loop turn, well
// after the JS call that requested the stop has already returned. The
// previous code cleared each worker's own `currentRoot` synchronously
// the moment a stop was requested, which let the SAME worker be handed
// a brand-new root (for a new search) before the OLD process had
// actually died -- when that old process's own `onExited` finally
// fired, it read whatever root the worker had since been reassigned
// to, misattributing a killed invocation's exit code/output to a
// completely different (and still legitimately in-flight) search.
//
// The fix is a simple invariant this module exists to enforce and make
// testable in isolation: a slot is "busy" (unavailable for reassignment)
// from the moment it's assigned a root until its real completion is
// explicitly retire()'d -- requesting a stop does NOT free it early.
// Only retire() (called from the real Process.onExited handler, never
// from a stop request itself) returns the slot to the idle pool, and
// it always reports exactly the root that slot was actually processing,
// never a value some other, later call might have written in the
// meantime -- there IS no "meantime" a stopped-but-not-yet-retired slot
// can be reassigned during.

function createPool(size) {
  var slots = []
  for (var i = 0; i < size; i++) slots.push({ root: null, stopping: false })
  return { slots: slots }
}

function isBusy(pool, index) {
  return pool.slots[index].root !== null
}

// -1 (matching Array.indexOf's own "not found" convention) when every
// slot is currently busy -- including one that's merely "stopping" but
// not yet retired, which is exactly the state this module exists to
// keep unavailable.
function idleSlotIndex(pool) {
  for (var i = 0; i < pool.slots.length; i++) {
    if (!isBusy(pool, i)) return i
  }
  return -1
}

// Only valid on a currently-idle slot -- the caller (scheduleRootSearches
// in both providers) always checks idleSlotIndex/isBusy first, so this
// is a defensive no-op rather than a silent overwrite if that contract
// is ever violated, e.g. by a future refactor mistake.
function assign(pool, index, root) {
  if (isBusy(pool, index)) return false
  pool.slots[index].root = root
  pool.slots[index].stopping = false
  return true
}

// Marks a busy slot as "stopping" -- it remains busy (isBusy stays
// true) until retire() is actually called for it. A no-op on an
// already-idle slot (nothing to stop).
function requestStop(pool, index) {
  if (isBusy(pool, index)) pool.slots[index].stopping = true
}

function requestStopAll(pool) {
  for (var i = 0; i < pool.slots.length; i++) requestStop(pool, i)
}

// Called from the real Process.onExited handler once a worker's own
// invocation has genuinely finished (successfully, killed, or timed
// out -- any exit at all). Returns the root that slot was processing
// (null if it was already idle, which shouldn't happen in real use but
// is handled rather than trusted away), and frees the slot for reuse.
function retire(pool, index) {
  var root = pool.slots[index].root
  pool.slots[index].root = null
  pool.slots[index].stopping = false
  return root
}
