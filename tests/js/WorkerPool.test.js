"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "WorkerPool.js"));

// ---- createPool / isBusy / idleSlotIndex -----------------------------------

check("createPool: every slot starts idle",
  [M.isBusy(M.createPool(4), 0), M.isBusy(M.createPool(4), 1)], [false, false]);
check("idleSlotIndex: finds the first idle slot",
  M.idleSlotIndex(M.createPool(3)), 0);
check("idleSlotIndex: -1 when every slot is busy",
  (function() {
    var p = M.createPool(2);
    M.assign(p, 0, "a"); M.assign(p, 1, "b");
    return M.idleSlotIndex(p);
  })(), -1);

// ---- assign -----------------------------------------------------------------

check("assign: a fresh idle slot becomes busy with the given root",
  (function() { var p = M.createPool(1); M.assign(p, 0, "rootA"); return M.isBusy(p, 0); })(), true);
check("assign: returns true on success",
  M.assign(M.createPool(1), 0, "rootA"), true);
check("assign: refuses to overwrite an already-busy slot (defensive no-op, not a silent clobber)",
  (function() {
    var p = M.createPool(1);
    M.assign(p, 0, "rootA");
    var ok = M.assign(p, 0, "rootB");
    return [ok, M.retire(p, 0)];
  })(), [false, "rootA"]);

// ---- requestStop / requestStopAll -- the core #58 invariant ----------------

check("requestStop: a busy slot stays busy after a stop is requested -- "
  + "issue #58's own core fix: stopping must NOT free the slot early",
  (function() {
    var p = M.createPool(1);
    M.assign(p, 0, "rootA");
    M.requestStop(p, 0);
    return M.isBusy(p, 0);
  })(), true);
check("requestStop: an idle slot has nothing to stop (no-op, doesn't throw)",
  (function() { var p = M.createPool(1); M.requestStop(p, 0); return M.isBusy(p, 0); })(), false);
check("requestStopAll: stops every currently-busy slot, leaves idle ones untouched",
  (function() {
    var p = M.createPool(3);
    M.assign(p, 0, "a"); M.assign(p, 2, "c");
    M.requestStopAll(p);
    return [M.isBusy(p, 0), M.isBusy(p, 1), M.isBusy(p, 2)];
  })(), [true, false, true]);

// ---- retire -------------------------------------------------------------------

check("retire: returns the root that slot was actually processing, and frees it",
  (function() {
    var p = M.createPool(1);
    M.assign(p, 0, "rootA");
    var root = M.retire(p, 0);
    return [root, M.isBusy(p, 0)];
  })(), ["rootA", false]);
check("retire: an already-idle slot returns null rather than a stale/previous root",
  M.retire(M.createPool(1), 0), null);
check("retire: a slot that was requestStop()'d still reports its own real root on retirement, "
  + "not something a caller assumed instead",
  (function() {
    var p = M.createPool(1);
    M.assign(p, 0, "rootA");
    M.requestStop(p, 0);
    return M.retire(p, 0);
  })(), "rootA");

// ---- the exact issue #58 regression scenario, end to end -------------------
// A killed worker's own real exit event must NEVER be attributable to a
// root some OTHER, later invocation was reassigned to on the same slot
// -- because that reassignment can only happen via assign(), and
// assign() is a no-op on a slot that hasn't been retire()'d yet, no
// matter how many stops were requested against it in the meantime.

check("issue #58: rapid replacement on the same slot -- root A is stopped for "
  + "a new search (root B), but the slot MUST stay unavailable for B until "
  + "A's own real completion retires it; only then can B be assigned, and "
  + "A's own retirement always reports 'rootA', never 'rootB'",
  (function() {
    var p = M.createPool(1);
    // query A starts on root A
    M.assign(p, 0, "rootA");
    // query B arrives before A's process has actually exited -- the
    // caller requests a stop, but (correctly) cannot yet hand the slot
    // to B
    M.requestStop(p, 0);
    var canAssignBBeforeARetires = M.assign(p, 0, "rootB");
    var idleBeforeARetires = M.idleSlotIndex(p);
    // A's real onExited finally fires
    var retiredRoot = M.retire(p, 0);
    // NOW the slot is legitimately free for B
    var canAssignBAfterARetires = M.assign(p, 0, "rootB");
    return {
      canAssignBBeforeARetires: canAssignBBeforeARetires,
      idleBeforeARetires: idleBeforeARetires,
      retiredRoot: retiredRoot,
      canAssignBAfterARetires: canAssignBAfterARetires
    };
  })(),
  {
    canAssignBBeforeARetires: false,
    idleBeforeARetires: -1,
    retiredRoot: "rootA",
    canAssignBAfterARetires: true
  });

summary();
