"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

// Separate from PluginModel.test.js (which covers ruixen.settings' own
// copy) -- ruixen.launcher's copy has one deliberate difference: it
// self-locks ruixen.launcher (the plugin THIS Settings extension renders
// from), not ruixen.settings, which is just an ordinary row here.
const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "services", "PluginModel.js"));

check("pluginIsProtected: null row is protected", M.pluginIsProtected(null), true);
check("pluginIsProtected: ruixen.launcher is always protected, canDisable or not", M.pluginIsProtected({ id: "ruixen.launcher", canDisable: true }), true);
check("pluginIsProtected: ruixen.media is always protected, canDisable or not", M.pluginIsProtected({ id: "ruixen.media", canDisable: true }), true);
check("pluginIsProtected: ruixen.settings is NOT self-locked here -- it's just another row", M.pluginIsProtected({ id: "ruixen.settings", canDisable: true }), false);
check("pluginIsProtected: a plugin the CLI itself marks canDisable: false is protected", M.pluginIsProtected({ id: "ruixen.bar", canDisable: false }), true);
check("pluginIsProtected: an ordinary disableable plugin is not protected", M.pluginIsProtected({ id: "ruixen.notch", canDisable: true }), false);

const raw = JSON.stringify([
  { id: "ruixen.notch", name: "Notch", canDisable: true },
  { id: "ruixen.bar", name: "Bar", canDisable: false },
  { id: "ruixen.launcher", name: "Launcher", canDisable: true },
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
  ["ruixen.bar", "ruixen.launcher", "ruixen.applauncher", "ruixen.notch", "ruixen.settings"]
);

check("parsePluginList: empty input yields an empty list, not a crash", M.parsePluginList(""), []);
check("parsePluginList: malformed JSON yields an empty list, not a throw", M.parsePluginList("not json"), []);
check("parsePluginList: a non-ruixen-only list yields an empty list", M.parsePluginList('[{"id":"omarchy.clock","name":"Clock","canDisable":true}]'), []);

summary();
