"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "OmarchyMenuParser.js"));

// ---- stripJsonc / parseMenuEntries -------------------------------------

check("stripJsonc: strips a full-line // comment, newline included",
  M.stripJsonc('{\n  // a comment\n  "a": 1\n}'), '{\n  "a": 1\n}');
check("stripJsonc: strips a trailing comma before a closing brace",
  M.stripJsonc('{"a": 1,\n}'), '{"a": 1\n}');
check("stripJsonc: strips a trailing comma before a closing bracket",
  M.stripJsonc('[1, 2,]'), '[1, 2]');
check("stripJsonc: a real comment + trailing comma together, matching the actual file's own shape",
  M.stripJsonc('{\n  // Root Menu\n  "apps": {"label":"Apps"},\n}'),
  '{\n  "apps": {"label":"Apps"}\n}');

check("parseMenuEntries: valid JSONC parses to the flat object",
  M.parseMenuEntries('{"a": {"label": "A"}}'), { a: { label: "A" } });
check("parseMenuEntries: invalid JSON returns an empty object, not a throw",
  M.parseMenuEntries("not json at all"), {});
check("parseMenuEntries: empty input returns an empty object",
  M.parseMenuEntries(""), {});

// ---- isExcludedFromLauncher ------------------------------------------------

check("isExcludedFromLauncher: shutdown/reboot/logout are excluded (end the whole session)",
  M.isExcludedFromLauncher("system.shutdown") && M.isExcludedFromLauncher("system.reboot") && M.isExcludedFromLauncher("system.logout"),
  true);
check("isExcludedFromLauncher: lock/suspend/hibernate/screensaver stay -- they pause, not end, the session",
  M.isExcludedFromLauncher("system.lock") || M.isExcludedFromLauncher("system.suspend")
    || M.isExcludedFromLauncher("system.hibernate") || M.isExcludedFromLauncher("system.screensaver"),
  false);
check("isExcludedFromLauncher: install./remove./setup.default. are NOT excluded (breadcrumbFor spells them out instead)",
  M.isExcludedFromLauncher("install.development.go") || M.isExcludedFromLauncher("remove.development.go")
    || M.isExcludedFromLauncher("setup.default.editor.neovim") || M.isExcludedFromLauncher("update.config.shell"),
  false);
check("isExcludedFromLauncher: an ordinary id is not excluded",
  M.isExcludedFromLauncher("trigger.capture.screenshot"), false);
check("isExcludedFromLauncher: an excluded prefix only matches at the very start, not anywhere in the id",
  M.isExcludedFromLauncher("some.system.shutdown.thing"), false);

// ---- actionableEntries --------------------------------------------------

const mixedEntries = {
  "system": { label: "System" },
  "system.lock": { label: "Lock", action: "omarchy-system-lock" },
  "system.shutdown": { label: "Shutdown", action: "omarchy-system-shutdown" },
  "apps": { label: "Apps", provider: "apps" },
  "style.bar": { label: "Menu Bar" }
};
check("actionableEntries: keeps only entries with a real action string",
  M.actionableEntries(mixedEntries), { "system.lock": { label: "Lock", action: "omarchy-system-lock" } });
check("actionableEntries: a provider-kind entry is excluded (out of scope for this plugin)",
  Object.keys(M.actionableEntries(mixedEntries)).indexOf("apps"), -1);
check("actionableEntries: a pure category node (no action, no provider) is excluded",
  Object.keys(M.actionableEntries(mixedEntries)).indexOf("system"), -1);
check("actionableEntries: an otherwise-actionable excluded id (session-ender) is dropped too",
  Object.keys(M.actionableEntries(mixedEntries)).indexOf("system.shutdown"), -1);

// ---- breadcrumbFor ----------------------------------------------------------

const breadcrumbEntries = {
  "trigger": { label: "Trigger" },
  "trigger.capture": { label: "Capture" },
  "trigger.capture.screenshot": { label: "Screenshot", action: "omarchy-capture-screenshot" },
  "install": { label: "Install" },
  "install.development": { label: "Development" },
  "remove": { label: "Remove", aliases: ["uninstall"] },
  "remove.development": { label: "Development" }
};
check("breadcrumbFor: a 2-deep id returns its full root-to-parent chain, not just the immediate parent",
  M.breadcrumbFor(breadcrumbEntries, "trigger.capture.screenshot"), "Trigger › Capture");
check("breadcrumbFor: an install/remove pair sharing one parent label reads unambiguous either way",
  M.breadcrumbFor(breadcrumbEntries, "install.development.go"), "Install › Development");
check("breadcrumbFor: ...and the remove side clearly says Remove, no title-override lookup needed",
  M.breadcrumbFor(breadcrumbEntries, "remove.development.go"), "Remove › Development");
check("breadcrumbFor: a root-level id has an empty breadcrumb",
  M.breadcrumbFor(breadcrumbEntries, "trigger"), "");
check("breadcrumbFor: a missing ancestor is skipped rather than crashing or inserting a blank segment",
  M.breadcrumbFor({}, "a.b.c"), "");

// ---- mergeUserOverrides -------------------------------------------------

check("mergeUserOverrides: a user-only id is added outright",
  M.mergeUserOverrides({ "a": { label: "A" } }, { "b": { label: "B" } }),
  { "a": { label: "A" }, "b": { label: "B" } });
check("mergeUserOverrides: a user field overrides the matching default field, others survive",
  M.mergeUserOverrides({ "a": { label: "A", icon: "x", action: "run-a" } }, { "a": { label: "A2" } }),
  { "a": { label: "A2", icon: "x", action: "run-a" } });
check("mergeUserOverrides: no user entries at all leaves the defaults untouched",
  M.mergeUserOverrides({ "a": { label: "A" } }, {}), { "a": { label: "A" } });
check("mergeUserOverrides: no defaults at all still picks up user-only entries",
  M.mergeUserOverrides({}, { "a": { label: "A" } }), { "a": { label: "A" } });

// ---- guard batching -------------------------------------------------------

check("buildGuardScript: one when + one checked, batched into one script",
  M.buildGuardScript({
    "system.suspend": { when: "! omarchy-toggle-enabled suspend-off" },
    "setup.network.dns.dhcp": { checked: '[[ "$(omarchy-dns)" == "DHCP" ]]' }
  }),
  'if { ! omarchy-toggle-enabled suspend-off; } >/dev/null 2>&1; then echo system.suspend:w:1; else echo system.suspend:w:0; fi\n' +
  'if { [[ "$(omarchy-dns)" == "DHCP" ]]; } >/dev/null 2>&1; then echo setup.network.dns.dhcp:c:1; else echo setup.network.dns.dhcp:c:0; fi');
check("buildGuardScript: an entry with neither when nor checked contributes nothing",
  M.buildGuardScript({ "system.lock": { action: "omarchy-system-lock" } }), "");
check("buildGuardScript: no entries at all yields an empty script (caller skips spawning bash)",
  M.buildGuardScript({}), "");

check("parseGuardOutput: parses id:tag:0|1 lines back into a map",
  M.parseGuardOutput("system.suspend:w:1\nsetup.network.dns.dhcp:c:0"),
  { "system.suspend": { when: true }, "setup.network.dns.dhcp": { checked: false } });
check("parseGuardOutput: an id containing dots is preserved whole (only the last two colon-segments are tag/value)",
  M.parseGuardOutput("style.bar.position.top:w:1"), { "style.bar.position.top": { when: true } });
check("parseGuardOutput: blank lines are ignored", M.parseGuardOutput("\n\nsystem.lock:w:1\n\n"),
  { "system.lock": { when: true } });
check("parseGuardOutput: empty output yields an empty map", M.parseGuardOutput(""), {});

check("isVisible: no when field is always visible", M.isVisible("x", {}, {}), true);
check("isVisible: when evaluated true is visible",
  M.isVisible("system.suspend", { when: "..." }, { "system.suspend": { when: true } }), true);
check("isVisible: when evaluated false is hidden",
  M.isVisible("system.suspend", { when: "..." }, { "system.suspend": { when: false } }), false);
check("isVisible: has a when field but no guard result yet defaults to visible (fail-open, not stuck hidden)",
  M.isVisible("system.suspend", { when: "..." }, {}), true);

// ---- scoreEntry -----------------------------------------------------------

check("scoreEntry: exact label match scores highest",
  M.scoreEntry({ label: "Lock" }, "lock"), 10000);
check("scoreEntry: label prefix match scores above a substring match",
  M.scoreEntry({ label: "Lock Screen" }, "lock") > M.scoreEntry({ label: "Screen Lock" }, "lock"), true);
check("scoreEntry: an alias match still scores (positive), just lower than a label match",
  M.scoreEntry({ label: "Setup", aliases: ["settings"] }, "settings") > 0, true);
check("scoreEntry: no match at all scores negative (excluded by the caller)",
  M.scoreEntry({ label: "Lock" }, "xyz"), -1);
check("scoreEntry: empty query scores negative (nothing to rank against)",
  M.scoreEntry({ label: "Lock" }, ""), -1);

// ---- Keybind hints -----------------------------------------------------

check("parseKeybindingsOutput: parses '<keybind>→<label>' lines, trims padding",
  M.parseKeybindingsOutput("SUPER + K                           → Keybindings\nSUPER CTRL + L                      → Lock system"),
  [{ keybind: "SUPER + K", label: "Keybindings" }, { keybind: "SUPER CTRL + L", label: "Lock system" }]);
check("parseKeybindingsOutput: a line with no arrow is skipped",
  M.parseKeybindingsOutput("not a real line\nSUPER + Z → Screenshot"), [{ keybind: "SUPER + Z", label: "Screenshot" }]);
check("parseKeybindingsOutput: blank input yields an empty list", M.parseKeybindingsOutput(""), []);

check("parsePersonalBindings: parses labeled o.bind() calls",
  M.parsePersonalBindings('o.bind("SUPER + R", "Ruixen Launcher", "omarchy-shell shell toggle ruixen.launcher")\n' +
    'o.bind("SUPER + SHIFT + Z", "Screenshot", "omarchy-capture-screenshot")'),
  [{ keybind: "SUPER + R", label: "Ruixen Launcher" }, { keybind: "SUPER + SHIFT + Z", label: "Screenshot" }]);
check("parsePersonalBindings: an unlabeled bind (nil, not a quoted string) is skipped",
  M.parsePersonalBindings('o.bind("SUPER + Q", nil, "some-command")'), []);
check("parsePersonalBindings: no real o.bind() calls yields an empty list",
  M.parsePersonalBindings("-- o.bind(\"X\", \"Y\", \"Z\") commented out"), []);

check("formatKeybind: collapses ' + ' spacing to a bare '+'",
  M.formatKeybind("SUPER + SHIFT + Z"), "SUPER+SHIFT+Z");
check("formatKeybind: empty input stays empty", M.formatKeybind(""), "");

check("labelsFuzzyMatch: exact match (case-insensitive)", M.labelsFuzzyMatch("Lock", "lock"), true);
check("labelsFuzzyMatch: a shorter label matches as a whole word inside a longer one",
  M.labelsFuzzyMatch("Lock", "Lock system") && M.labelsFuzzyMatch("Theme", "Theme menu"), true);
check("labelsFuzzyMatch: a substring that isn't a whole word does NOT match",
  M.labelsFuzzyMatch("Lock", "Unlock") || M.labelsFuzzyMatch("Lock", "Clock"), false);
check("labelsFuzzyMatch: unrelated labels don't match", M.labelsFuzzyMatch("Theme", "Wallpaper"), false);

check("buildKeybindIndex: a personal entry wins over a stock entry sharing the same exact label",
  M.buildKeybindIndex(
    [{ keybind: "SUPER + SHIFT + S", label: "Screenshot" }],
    [{ keybind: "SUPER + SHIFT + Z", label: "Screenshot" }]
  ),
  { screenshot: "SUPER+SHIFT+Z" });
check("buildKeybindIndex: a stock-only label is still indexed",
  M.buildKeybindIndex([{ keybind: "SUPER + K", label: "Keybindings" }], []),
  { keybindings: "SUPER+K" });
check("buildKeybindIndex: no entries at all yields an empty index",
  M.buildKeybindIndex([], []), {});

check("keybindFor: exact index hit",
  M.keybindFor("Screenshot", { screenshot: "SUPER+SHIFT+Z" }, []), "SUPER+SHIFT+Z");
check("keybindFor: falls back to a fuzzy scan of the stock list when the exact index misses",
  M.keybindFor("Lock", {}, [{ keybind: "SUPER CTRL + L", label: "Lock system" }]), "SUPER CTRL+L");
check("keybindFor: no match anywhere returns an empty string, not undefined",
  M.keybindFor("Nonexistent Thing", {}, [{ keybind: "SUPER + K", label: "Keybindings" }]), "");
check("keybindFor: empty label returns an empty string",
  M.keybindFor("", {}, []), "");

summary();
