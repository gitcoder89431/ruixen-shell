// Pure last-action-wins generation comparison, extracted out of
// Service.qml's own acceptsGeneration() so the actual decision logic
// can be unit-tested directly (tests/js/GenerationGuard.test.js, via
// the same node+vm harness BarModel.js/Model.js already use) instead
// of only reachable through a live Quickshell IPC round-trip. No
// Qt/Quickshell global referenced here, same as those two files --
// safe to load standalone in a plain JS sandbox.
//
// Direct review finding ("Make wallpaper selection generations survive
// Notch reloads", #22): ruixen.wallpaper (this service) stays loaded
// and keeps its own selectGeneration for its entire process lifetime,
// but ruixen.notch's own WallpapersContent instance can be destroyed
// and recreated independently (disable/re-enable, a plugin reload) --
// a freshly created client used to always start counting from 0 again,
// so its first several real clicks after a reload could be rejected as
// "older than what this service already saw" from the PREVIOUS
// client's lifetime. Service.qml's own comment on selectGeneration
// still explains the original cross-Process race this whole mechanism
// exists for; this file is only the comparison half of it.
//
// The fix lives on the CLIENT side (WallpapersContent.qml seeds its
// own counter from Date.now() at creation, not 0 -- see its own
// comment), not here -- this function's own contract is unchanged:
// given the currently tracked generation and a candidate value, decide
// whether the candidate is new enough to adopt. It has no idea whether
// the candidate came from a counter seeded at 0 or at a timestamp; it
// just needs "not older than the last one accepted" to keep holding
// for both.
//
// Returns the new generation to adopt if the candidate is accepted, or
// null if it's genuinely stale and must not overwrite the current one.
// A non-numeric/malformed candidate is treated as trusted but inert --
// accepted (matches every real caller's own generation string), but
// the tracked generation itself is left exactly as it was, so the
// caller's next re-assignment of it is a harmless no-op rather than
// corrupting state with NaN.
//
// parseFloat, not parseInt -- generations are plain JS Numbers on the
// wire (String(realNumber) in WallpapersContent.qml), and a
// Date.now()-seeded value is always a whole number in practice, but
// parseFloat is the honest match for "this is a Number, not
// necessarily an integer" rather than silently truncating anything
// that isn't.
function acceptGeneration(currentGeneration, generationText) {
  var gen = parseFloat(generationText)
  if (isNaN(gen)) return currentGeneration
  if (gen < currentGeneration) return null
  return gen
}
