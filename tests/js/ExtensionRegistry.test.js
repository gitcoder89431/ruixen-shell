"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "extensions", "ExtensionRegistry.js"));

const EXPECTED_IDS = ["wallpapers", "settings", "theme-browser", "clipboard", "cliamp", "wallpaper-shuffle", "kanban"];

// ---- shape: every entry has the fields every consumer relies on -------------

check("every entry has a unique id, providerId and omarchyActionId",
  M.EXTENSIONS.every(function(e) { return e.id && e.providerId && e.omarchyActionId && e.label; }), true);
check("ids() lists every entry, in declaration order", M.ids(), EXPECTED_IDS);
check("no duplicate ids", new Set(M.ids()).size, M.ids().length);
check("no duplicate providerIds", new Set(M.EXTENSIONS.map(function(e) { return e.providerId; })).size, M.EXTENSIONS.length);
check("no duplicate omarchyActionIds", new Set(M.EXTENSIONS.map(function(e) { return e.omarchyActionId; })).size, M.EXTENSIONS.length);

// ---- isValidId ----------------------------------------------------------------

check("isValidId: true for a real id", M.isValidId("cliamp"), true);
check("isValidId: false for an unknown id", M.isValidId("not-a-real-extension"), false);
check("isValidId: false for undefined (an unparseable/missing payload.extension)", M.isValidId(undefined), false);

// ---- byId / byProviderId / byOmarchyActionId ----------------------------------

check("byId: finds the real entry", M.byId("wallpaper-shuffle").providerId, "wallpaper-shuffle-extension");
check("byId: null for an unknown id", M.byId("nope"), null);
check("byProviderId: finds the real entry", M.byProviderId("settings-extension").id, "settings");
check("byProviderId: null for an unknown providerId", M.byProviderId("nope"), null);
check("byOmarchyActionId: finds the real entry", M.byOmarchyActionId("ruixen.theme-browser").id, "theme-browser");
check("byOmarchyActionId: null for an unknown omarchyActionId", M.byOmarchyActionId("nope"), null);

// ---- usesSourceFilter: matches the exact pre-registry OR-chain (#104) --------
// Launcher.qml's own SearchHeader.showSourceFilter used to be:
// `root.filesMode || root.activeExtensionId === "wallpapers" ||
// root.activeExtensionId === "theme-browser" || root.activeExtensionId === "cliamp"`

check("usesSourceFilter: wallpapers", M.usesSourceFilter("wallpapers"), true);
check("usesSourceFilter: theme-browser", M.usesSourceFilter("theme-browser"), true);
check("usesSourceFilter: cliamp", M.usesSourceFilter("cliamp"), true);
check("usesSourceFilter: settings", M.usesSourceFilter("settings"), false);
check("usesSourceFilter: clipboard", M.usesSourceFilter("clipboard"), false);
check("usesSourceFilter: wallpaper-shuffle", M.usesSourceFilter("wallpaper-shuffle"), false);
check("usesSourceFilter: empty activeExtensionId (plain search mode)", M.usesSourceFilter(""), false);

// ---- keybindLookupLabel: direct follow-up ("how does the keybind for
// our stuff... update it so it has the kbd helper on the launcher") --
// every entry needs one now, not just settings, or extensionRow() never
// even calls omarchyActionsProvider.keybindFor() for it regardless of
// whether the user has a real keybind bound. -------------------------

check("every entry declares a non-empty keybindLookupLabel",
  M.EXTENSIONS.every(function(e) { return !!e.keybindLookupLabel; }), true);
check("every entry's keybindLookupLabel matches its own row label, except settings",
  M.EXTENSIONS.filter(function(e) { return e.id !== "settings"; })
    .every(function(e) { return e.keybindLookupLabel === e.label; }), true);
check("settings deliberately uses \"Ruixen Settings\", not its own bare \"Settings\" label (collision-prone)",
  M.byId("settings").keybindLookupLabel, "Ruixen Settings");

// ---- settings is the only entry with this special-case field ---------

check("only settings declares supportsSection",
  M.EXTENSIONS.filter(function(e) { return e.supportsSection; }).map(function(e) { return e.id; }),
  ["settings"]);

// ---- icon glyphs are the exact original Nerd Font codepoints, not placeholders

const EXPECTED_ICON_CODEPOINTS = {
  "wallpapers": 0xf03e,
  "settings": 0xf013,
  "theme-browser": 0xf1fc,
  "clipboard": 0xf0ea,
  "cliamp": 0xf001,
  "wallpaper-shuffle": 0xf074,
  // Same glyph the notch's own Kanban dashboard tab already uses
  // (fa-columns) -- not "the original row builder" (this extension is
  // new), just cross-checked here the same byte-safe way every other
  // icon already is.
  "kanban": 0xf0db
};
check("every icon is a single real character, codepoint matching the original row builder it replaced",
  M.EXTENSIONS.map(function(e) { return [e.id, e.icon.length === 1 && e.icon.codePointAt(0)]; }),
  Object.keys(EXPECTED_ICON_CODEPOINTS).map(function(id) { return [id, EXPECTED_ICON_CODEPOINTS[id]]; }));

summary();
