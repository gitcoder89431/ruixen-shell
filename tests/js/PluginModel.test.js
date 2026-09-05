"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.settings", "services", "PluginModel.js"));

check("pluginIsProtected: null row is protected", M.pluginIsProtected(null), true);
check("pluginIsProtected: ruixen.settings is always protected, canDisable or not", M.pluginIsProtected({ id: "ruixen.settings", canDisable: true }), true);
check("pluginIsProtected: ruixen.media is always protected, canDisable or not", M.pluginIsProtected({ id: "ruixen.media", canDisable: true }), true);
check("pluginIsProtected: a plugin the CLI itself marks canDisable: false is protected", M.pluginIsProtected({ id: "ruixen.bar", canDisable: false }), true);
check("pluginIsProtected: an ordinary disableable plugin is not protected", M.pluginIsProtected({ id: "ruixen.notch", canDisable: true }), false);

const raw = JSON.stringify([
  { id: "ruixen.notch", name: "Notch", canDisable: true },
  { id: "ruixen.bar", name: "Bar", canDisable: false },
  { id: "ruixen.settings", name: "Settings", canDisable: true },
  { id: "ruixen.stayawake", name: "Stay Awake", canDisable: true },
  { id: "omarchy.agents", name: "Agents", canDisable: true },
  { id: "ruixen.applauncher", name: "App Launcher", canDisable: true }
]);
const rows = M.parsePluginList(raw);
check("parsePluginList: scoped to ruixen.* ids only (omarchy.agents dropped)", rows.map(function(r) { return r.id; }).indexOf("omarchy.agents"), -1);
check("parsePluginList: ruixen.stayawake dropped entirely (redundant with pluginpins)", rows.map(function(r) { return r.id; }).indexOf("ruixen.stayawake"), -1);
check(
  "parsePluginList: protected plugins sort first, alphabetical within each group",
  rows.map(function(r) { return r.id; }),
  ["ruixen.bar", "ruixen.settings", "ruixen.applauncher", "ruixen.notch"]
);

check("parsePluginList: empty input yields an empty list, not a crash", M.parsePluginList(""), []);
check("parsePluginList: malformed JSON yields an empty list, not a throw", M.parsePluginList("not json"), []);
check("parsePluginList: a non-ruixen-only list yields an empty list", M.parsePluginList('[{"id":"omarchy.clock","name":"Clock","canDisable":true}]'), []);

summary();
