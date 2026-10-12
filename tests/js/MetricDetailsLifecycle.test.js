"use strict";
const assert = require("assert");
const fs = require("fs");
const path = require("path");
const vm = require("vm");

// Run the actual QML handlers with a fake asynchronous Process. This is a
// lifecycle test, not a second implementation of the generation rules.
const qml = fs.readFileSync(path.join(__dirname,
  "../../bars/widgets/ruixen.notch/MetricDetailsPanel.qml"), "utf8");
function body(marker) {
  const markerAt = qml.indexOf(marker);
  assert(markerAt >= 0, "Missing production handler: " + marker);
  const start = qml.indexOf("{", markerAt + marker.length);
  let depth = 1;
  let end = start + 1;
  for (; depth && end < qml.length; end++) {
    if (qml[end] === "{") depth++;
    if (qml[end] === "}") depth--;
  }
  assert.equal(depth, 0, "Unclosed production handler");
  return qml.slice(start + 1, end - 1);
}
const refreshBody = body("function refresh()");
const changedBody = body("onKindChanged:");
const resultBody = body("onStreamFinished:");
const exitBody = body("onExited: (code, status) =>");
const pollExpression = qml.match(/Timer\s*\{[^}]*running:\s*([^\n]+)/)[1];

function harness() {
  const deferred = [];
  const state = {
    kind: "cpu", active: true, generation: 0, requestedGeneration: -1,
    requestedKind: "", queuedKind: "", rows: [], summaries: [], note: "",
    errorText: "", checkedAt: "", relativeBars: false,
    reader: {running: false, command: []},
    Qt: {
      callLater: fn => deferred.push(fn),
      resolvedUrl: () => ({toString: () => "file:///tmp/plugin%20dir/metric-details.py"}),
      formatTime: () => "12:00:00"
    }
  };
  state.root = state;
  Object.defineProperty(state, "visible", {get: () => state.kind !== ""});
  const context = vm.createContext(state);
  vm.runInContext("function refresh(){" + refreshBody + "}\n" +
    "function changed(){" + changedBody + "}\n" +
    "function result(text){" + resultBody + "}\n" +
    "function exited(code,status){" + exitBody + "}", context);
  return {
    state,
    refresh: () => state.refresh(),
    select: kind => {
      state.kind = kind;
      state.changed();
      while (deferred.length) deferred.shift()();
    },
    publish: rows => state.result(JSON.stringify({rows, summaries: [], note: "snapshot"})),
    finish: code => {state.reader.running = false; state.exited(code, 0);},
    polling: () => vm.runInContext(pollExpression, context)
  };
}

let passed = 0;
function test(name, fn) {
  fn();
  passed++;
  console.log("ok - " + name);
}
test("starts the helper with a decoded plugin path", () => {
  const h = harness(); h.refresh();
  assert.deepEqual(Array.from(h.state.reader.command),
    ["python3", "/tmp/plugin dir/metric-details.py", "cpu"]);
  assert.equal(h.state.reader.running, true);
});
test("publishes the current request and update time", () => {
  const h = harness(); h.refresh(); h.publish([{label: "current"}]);
  assert.equal(h.state.rows[0].label, "current");
  assert.equal(h.state.checkedAt, "12:00:00");
});
test("page switch rejects old results and waits for the real worker exit", () => {
  const h = harness(); h.refresh(); h.select("memory");
  h.publish([{label: "old CPU"}]);
  assert.equal(h.state.rows.length, 0);
  assert.equal(h.state.requestedKind, "cpu");
  h.finish(0);
  assert.equal(h.state.requestedKind, "memory");
  assert.equal(h.state.reader.running, true);
});
test("CPU to memory to CPU rejects an old CPU result by generation", () => {
  const h = harness(); h.refresh(); h.select("memory"); h.select("cpu");
  h.publish([{label: "stale CPU"}]);
  assert.equal(h.state.rows.length, 0);
  h.finish(0); h.publish([{label: "fresh CPU"}]);
  assert.equal(h.state.rows[0].label, "fresh CPU");
});
test("closing and reopening the same page rejects the previous request", () => {
  const h = harness(); h.refresh(); h.select(""); h.select("cpu");
  h.publish([{label: "before close"}]);
  assert.equal(h.state.rows.length, 0);
  h.finish(0); h.publish([{label: "after reopen"}]);
  assert.equal(h.state.rows[0].label, "after reopen");
});
test("repeated refreshes coalesce to one follow-up request", () => {
  const h = harness(); h.refresh();
  h.refresh(); h.refresh(); h.refresh();
  h.finish(0);
  assert.equal(h.state.reader.running, true);
  assert.equal(h.state.queuedKind, "");
  h.finish(0);
  assert.equal(h.state.reader.running, false);
});
test("closing clears queued work and prevents another worker", () => {
  const h = harness(); h.refresh(); h.refresh(); h.select("");
  assert.equal(h.state.queuedKind, "");
  h.publish([{label: "closed"}]); h.finish(0);
  assert.equal(h.state.rows.length, 0);
  assert.equal(h.state.reader.running, false);
});
test("inactive tab rejects results and queued refreshes", () => {
  const h = harness(); h.refresh(); h.refresh(); h.state.active = false;
  h.publish([{label: "inactive"}]); h.finish(0);
  assert.equal(h.state.rows.length, 0);
  assert.equal(h.state.reader.running, false);
});
test("stale worker errors cannot poison the new page", () => {
  const h = harness(); h.refresh(); h.select("gpu"); h.finish(1);
  assert.equal(h.state.errorText, "");
  assert.equal(h.state.requestedKind, "gpu");
});
test("current worker failures and malformed output are reported", () => {
  const h = harness(); h.refresh(); h.state.result("broken JSON");
  assert.equal(h.state.errorText, "Unable to read system details");
  h.finish(1);
  assert.equal(h.state.errorText, "Details helper failed");
});
test("page switch clears previous presentation and comparison mode", () => {
  const h = harness(); h.state.relativeBars = true;
  h.state.rows = [{label: "old"}]; h.state.errorText = "old error";
  h.state.checkedAt = "old time"; h.select("gpu");
  assert.equal(h.state.relativeBars, false);
  assert.equal(h.state.rows.length, 0);
  assert.equal(h.state.errorText, "");
  assert.equal(h.state.checkedAt, "");
});
test("polling requires both an active tab and a visible detail page", () => {
  const h = harness(); assert.equal(h.polling(), true);
  h.state.active = false; assert.equal(h.polling(), false);
  h.state.active = true; h.select(""); assert.equal(h.polling(), false);
});
console.log("\n" + passed + " passed, 0 failed");
