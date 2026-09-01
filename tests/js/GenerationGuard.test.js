// Covers "[P1/P2] Make wallpaper selection generations survive Notch
// reloads" (#22): unit tests for GenerationGuard.js's own
// acceptGeneration(), the pure comparison logic
// ruixen.wallpaper/Service.qml's acceptsGeneration() delegates to. Run
// via tests/js-model-tests.sh (node tests/js/*.test.js), same harness
// BarModel.test.js/Model.test.js already use.
"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness.js");

const GenerationGuard = loadModule(
  path.join(__dirname, "..", "..", "ruixen.wallpaper", "GenerationGuard.js")
);

// --- A plain strictly-increasing sequence still works exactly like
// the original int-based counter did -----------------------------
let gen = -1;
gen = GenerationGuard.acceptGeneration(gen, "0");
check("first-ever call: 0 accepted from the -1 sentinel", gen, 0);
gen = GenerationGuard.acceptGeneration(gen, "1");
check("sequential: 1 accepted after 0", gen, 1);
gen = GenerationGuard.acceptGeneration(gen, "2");
check("sequential: 2 accepted after 1", gen, 2);

// --- A strictly older candidate is rejected -----------------------
check(
  "older candidate rejected (null, current generation NOT returned as the new value)",
  GenerationGuard.acceptGeneration(gen, "1"),
  null
);

// --- An EQUAL candidate is accepted (matches the original `<` check,
// not `<=` -- two independent callers racing to confirm the SAME
// generation must not deadlock each other out) --------------------
check(
  "equal candidate accepted (not rejected as 'not newer')",
  GenerationGuard.acceptGeneration(5, "5"),
  5
);

// --- A malformed/non-numeric candidate is accepted but inert: the
// caller's own re-assignment of it is a no-op, not corruption -------
check(
  "NaN candidate: returns the current generation unchanged, not NaN itself",
  GenerationGuard.acceptGeneration(7, "not-a-number"),
  7
);
check(
  "empty-string candidate: same inert behavior",
  GenerationGuard.acceptGeneration(7, ""),
  7
);

// --- The actual #22 scenario: a fresh client seeded from a
// Date.now()-scale value is accepted as the FIRST call even though
// the service is already sitting on a much "later-looking" plain
// int-based generation from a previous client's lifetime -----------
const oldClientFinalGeneration = 15; // old WallpapersContent instance reached 15 before being destroyed
const newClientFirstGeneration = 1788259581351; // Date.now()-seeded fresh instance's first click
check(
  "#22: a Date.now()-seeded fresh client's first click is never rejected as stale",
  GenerationGuard.acceptGeneration(oldClientFinalGeneration, String(newClientFirstGeneration)),
  newClientFirstGeneration
);

// --- The guard itself still correctly rejects a GENUINELY stale
// message once the service has already moved on to a Date.now()-scale
// generation -- #22 doesn't weaken the actual ordering guarantee, it
// only fixes the client-reset false negative ------------------------
const serviceAtNewScale = 1788259581351;
check(
  "a genuinely older message is still rejected once the service is at Date.now() scale",
  GenerationGuard.acceptGeneration(serviceAtNewScale, "1788259581350"),
  null
);

// --- Two clicks landing in the same instant (same generation value,
// e.g. two rapid IPC calls dispatched from the same select() tick)
// both get accepted -- last one applied wins by arrival order, same
// as the equal-candidate case above, not a special #22 behavior ----
check(
  "same-instant candidate accepted (last arrival wins, not rejected as equal-so-stale)",
  GenerationGuard.acceptGeneration(newClientFirstGeneration, String(newClientFirstGeneration)),
  newClientFirstGeneration
);

summary();
