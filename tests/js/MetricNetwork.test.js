"use strict";
const fs = require("fs");
const path = require("path");
const vm = require("vm");
const assert = require("assert");
// Exercise the production stream handler rather than duplicating its formulas.
const qml = fs.readFileSync(path.join(__dirname,"../../bars/widgets/ruixen.notch/MetricsContent.qml"),"utf8");
const start = qml.indexOf('var parts = String(text || "").split("---\\n")');
const end = qml.indexOf("\n",qml.indexOf("root.prevNetSample = {",start));
assert(start>=0 && end>start);
let clock = 1000;
const root = {};
const context = vm.createContext({root, Date:{now:()=>clock}, isFinite});
vm.runInContext("function apply(text){"+qml.slice(start,end)+"}",context);
function sample(iface,rx,tx) {
  context.text="default via 192.0.2.1 dev "+iface+"\n---\n"+iface+": "+rx+" 0 0 0 0 0 0 0 "+tx+" 0 0 0 0 0 0 0\n";
  vm.runInContext("apply(text)",context);
}
sample("test.1",100,200);
assert.equal(root.netRxRate,0);
clock=2000; sample("test.1",1124,2248);
assert.equal(root.netRxRate,1024);
assert.equal(root.netTxRate,2048);
clock=3000; sample("other0",1000000,2000000);
assert.equal(root.netRxRate,0);
assert.equal(root.netTxRate,0);
clock=4000; sample("other0",10,20);
assert.equal(root.netRxRate,0);
context.text="\n---\n";
vm.runInContext("apply(text)",context);
assert.equal(root.prevNetSample,null);
assert.equal(root.netInterface,"");
assert.equal(root.netRxTotalBytes,0);
assert.equal(root.netTxTotalBytes,0);
// A similarly named interface must not match a dotted VLAN name.
context.text="default via 192.0.2.1 dev test.1\n---\ntestx1: 100 0 0 0 0 0 0 0 200\n";
vm.runInContext("apply(text)",context);
assert.equal(root.prevNetSample,null);
assert.equal(root.netRxTotalBytes,0);
// Malformed counters must clear a valid sample, not show NaN or stale totals.
sample("test.1",100,200);
sample("test.1","invalid",200);
assert.equal(root.prevNetSample,null);
assert.equal(root.netRxRate,0);
assert.equal(root.netTxRate,0);
assert.equal(root.netRxTotalBytes,0);
assert.equal(root.netTxTotalBytes,0);
console.log("7 passed, 0 failed");
