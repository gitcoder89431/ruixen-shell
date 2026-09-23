"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "LauncherFrecency.js"));

// ---- frecencyBoost ----------------------------------------------------------

check("frecencyBoost: no stat at all is zero boost",
  M.frecencyBoost(null, Date.now()), 0);
check("frecencyBoost: a stat with zero count is zero boost",
  M.frecencyBoost({ count: 0, lastUsed: Date.now() }, Date.now()), 0);
check("frecencyBoost: recent + frequent scores higher than recent + rare",
  M.frecencyBoost({ count: 20, lastUsed: Date.now() }, Date.now())
    > M.frecencyBoost({ count: 1, lastUsed: Date.now() }, Date.now()), true);
check("frecencyBoost: an old launch decays toward a smaller boost than a fresh one, same count",
  M.frecencyBoost({ count: 10, lastUsed: Date.now() - 60 * 86400000 }, Date.now())
    < M.frecencyBoost({ count: 10, lastUsed: Date.now() }, Date.now()), true);
check("frecencyBoost: usage count is capped -- 1000 launches boosts no harder than 20",
  M.frecencyBoost({ count: 1000, lastUsed: Date.now() }, Date.now()),
  M.frecencyBoost({ count: 20, lastUsed: Date.now() }, Date.now()));

// ---- recordLaunch -----------------------------------------------------------

check("recordLaunch: a brand new id starts at count 1",
  M.recordLaunch({}, "style.theme").hasOwnProperty("style.theme")
    && M.recordLaunch({}, "style.theme")["style.theme"].count, 1);
check("recordLaunch: an existing id increments its count, keeping others untouched",
  (function() {
    var stats = { "style.theme": { count: 3, lastUsed: 111 }, "style.background": { count: 9, lastUsed: 222 } };
    var next = M.recordLaunch(stats, "style.theme");
    return [next["style.theme"].count, next["style.background"].count];
  })(), [4, 9]);
check("recordLaunch: an empty id is a no-op, returning the same stats untouched",
  M.recordLaunch({ a: { count: 1, lastUsed: 1 } }, ""),
  { a: { count: 1, lastUsed: 1 } });
check("recordLaunch: does not mutate the object passed in -- returns a new one",
  (function() {
    var stats = { a: { count: 1, lastUsed: 1 } };
    M.recordLaunch(stats, "a");
    return stats.a.count;
  })(), 1);

summary();
