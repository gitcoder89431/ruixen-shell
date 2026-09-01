// Tiny shared harness for testing the plain-JS "model" files QML
// plugins import directly (BarModel.js, Model.js, ...). Those files
// have no `module.exports` -- they're loaded via QML's own `import
// "X.js" as X` mechanism, which just exposes every top-level
// declaration as a property on the imported namespace, no CommonJS
// wrapper involved. Confirmed directly: neither file references any
// Qt/Quickshell global, so they're safe to run standalone -- this
// just needs a way to pull their top-level functions out without
// adding a stray module.exports to a file QML also loads for real.
// vm.runInNewContext does exactly that: evaluate the file's own
// source text in a fresh sandbox, then read back whatever it
// declared.
"use strict";
const fs = require("fs");
const vm = require("vm");

function loadModule(path) {
  const source = fs.readFileSync(path, "utf8");
  const sandbox = {};
  vm.createContext(sandbox);
  vm.runInContext(source, sandbox, { filename: path });
  return sandbox;
}

let pass = 0;
let failCount = 0;

function check(desc, got, want) {
  const gotStr = JSON.stringify(got);
  const wantStr = JSON.stringify(want);
  if (gotStr === wantStr) {
    console.log("ok   - " + desc);
    pass++;
  } else {
    console.log("FAIL - " + desc);
    console.log("       got:  " + gotStr);
    console.log("       want: " + wantStr);
    failCount++;
  }
}

function summary() {
  console.log("\n" + pass + " passed, " + failCount + " failed");
  process.exit(failCount === 0 ? 0 : 1);
}

module.exports = { loadModule, check, summary };
