"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "AppSearch.js"));

function app(name, id, genericName) {
  return { name: name, id: id, genericName: genericName || "", comment: "", keywords: [] };
}

// ---- fuzzyScore: existing tier behavior, unchanged by frecency --------------

check("fuzzyScore: a direct name-prefix match scores in the top tier",
  M.fuzzyScore(app("Discord", "com.discordapp.Discord"), "disc") > 9000, true);
check("fuzzyScore: no match at all returns -1",
  M.fuzzyScore(app("Discord", "com.discordapp.Discord"), "zzz"), -1);
check("fuzzyScore: shorter name-prefix match outranks a longer one with no frecency data -- "
  + "the exact case frecency exists to override",
  M.fuzzyScore(app("Disc", "disc"), "dis") > M.fuzzyScore(app("Discord", "com.discordapp.Discord"), "dis"), true);
check("fuzzyScore: omitting frecencyLookup entirely behaves identically to before it existed",
  M.fuzzyScore(app("Discord", "com.discordapp.Discord"), "dis"),
  M.fuzzyScore(app("Discord", "com.discordapp.Discord"), "dis", null, 0));

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

// ---- fuzzyScore + frecency: the actual "dis" vs "disc" reorder -------------

check("fuzzyScore: a frequently/recently launched app can outrank a shorter, unused literal match "
  + "within the same tier -- the reported 'dis should rank Discord over Disc' case",
  (function() {
    var now = Date.now();
    var stats = { discord: { count: 15, lastUsed: now } };
    var lookup = function(entry) { return stats[entry.id] || null };
    return M.fuzzyScore(app("Discord", "discord"), "dis", lookup, now)
      > M.fuzzyScore(app("Disc", "disc"), "dis", lookup, now);
  })(), true);
check("fuzzyScore: frecency never turns a non-match into a match",
  M.fuzzyScore(app("Discord", "discord"), "zzz", function() { return { count: 20, lastUsed: Date.now() } }, Date.now()),
  -1);

// ---- sortedEntries: frecency reorders the final list, not just raw scores --

check("sortedEntries: a launched-often app sorts above an unused shorter-name match for the same query",
  (function() {
    var now = Date.now();
    var values = [app("Disc", "disc"), app("Discord", "discord")];
    var stats = { discord: { count: 15, lastUsed: now } };
    var lookup = function(entry) { return stats[entry.id] || null };
    var rows = M.sortedEntries(values, "dis", null, lookup, now);
    return rows.map(function(r) { return r.entry.id });
  })(), ["discord", "disc"]);
check("sortedEntries: omitting frecencyLookup keeps the original (pre-frecency) order",
  (function() {
    var values = [app("Disc", "disc"), app("Discord", "discord")];
    var rows = M.sortedEntries(values, "dis");
    return rows.map(function(r) { return r.entry.id });
  })(), ["disc", "discord"]);

summary();
