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
check("fuzzyScore: shorter name-prefix match outranks a longer one with no frecency boost -- "
  + "the exact case frecency exists to override",
  M.fuzzyScore(app("Disc", "disc"), "dis") > M.fuzzyScore(app("Discord", "com.discordapp.Discord"), "dis"), true);
check("fuzzyScore: omitting frecencyBoostFor entirely behaves identically to before it existed",
  M.fuzzyScore(app("Discord", "com.discordapp.Discord"), "dis"),
  M.fuzzyScore(app("Discord", "com.discordapp.Discord"), "dis", null));

// ---- fuzzyScore + frecency: the actual "dis" vs "disc" reorder -------------
// frecencyBoostFor is a plain (entry) -> number function here -- the
// actual frecency math (decay, count cap, ...) lives in
// LauncherFrecency.js and is covered by its own test file; this file
// only needs to prove fuzzyScore/sortedEntries correctly ADD whatever
// number that callback returns.

check("fuzzyScore: a boosted app can outrank a shorter, unboosted literal match "
  + "within the same tier -- the reported 'dis should rank Discord over Disc' case",
  M.fuzzyScore(app("Discord", "discord"), "dis", function() { return 500 })
    > M.fuzzyScore(app("Disc", "disc"), "dis", function() { return 0 }), true);
check("fuzzyScore: frecency never turns a non-match into a match",
  M.fuzzyScore(app("Discord", "discord"), "zzz", function() { return 600 }), -1);

// ---- sortedEntries: frecency reorders the final list, not just raw scores --

check("sortedEntries: a boosted app sorts above an unboosted shorter-name match for the same query",
  (function() {
    var values = [app("Disc", "disc"), app("Discord", "discord")];
    var boostFor = function(entry) { return entry.id === "discord" ? 500 : 0 };
    var rows = M.sortedEntries(values, "dis", null, boostFor);
    return rows.map(function(r) { return r.entry.id });
  })(), ["discord", "disc"]);
check("sortedEntries: omitting frecencyBoostFor keeps the original (pre-frecency) order",
  (function() {
    var values = [app("Disc", "disc"), app("Discord", "discord")];
    var rows = M.sortedEntries(values, "dis");
    return rows.map(function(r) { return r.entry.id });
  })(), ["disc", "discord"]);

summary();
