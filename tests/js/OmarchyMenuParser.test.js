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

check("isExcludedFromLauncher: an install.* id is excluded",
  M.isExcludedFromLauncher("install.development.go"), true);
check("isExcludedFromLauncher: a remove.* id is excluded",
  M.isExcludedFromLauncher("remove.development.go"), true);
check("isExcludedFromLauncher: update.config.* (resets a real config file) is excluded",
  M.isExcludedFromLauncher("update.config.shell"), true);
check("isExcludedFromLauncher: setup.default.* (sets a system default) is excluded",
  M.isExcludedFromLauncher("setup.default.editor.neovim"), true);
check("isExcludedFromLauncher: shutdown/reboot/logout are excluded (end the whole session)",
  M.isExcludedFromLauncher("system.shutdown") && M.isExcludedFromLauncher("system.reboot") && M.isExcludedFromLauncher("system.logout"),
  true);
check("isExcludedFromLauncher: lock/suspend/hibernate/screensaver stay -- they pause, not end, the session",
  M.isExcludedFromLauncher("system.lock") || M.isExcludedFromLauncher("system.suspend")
    || M.isExcludedFromLauncher("system.hibernate") || M.isExcludedFromLauncher("system.screensaver"),
  false);
check("isExcludedFromLauncher: an ordinary id is not excluded",
  M.isExcludedFromLauncher("trigger.capture.screenshot"), false);
check("isExcludedFromLauncher: an excluded prefix only matches at the very start, not anywhere in the id",
  M.isExcludedFromLauncher("some.install.thing"), false);

// ---- actionableEntries --------------------------------------------------

const mixedEntries = {
  "system": { label: "System" },
  "system.lock": { label: "Lock", action: "omarchy-system-lock" },
  "apps": { label: "Apps", provider: "apps" },
  "style.bar": { label: "Menu Bar" },
  "remove.development.go": { label: "Go", action: "omarchy-remove-dev-env go" }
};
check("actionableEntries: keeps only entries with a real action string",
  M.actionableEntries(mixedEntries), { "system.lock": { label: "Lock", action: "omarchy-system-lock" } });
check("actionableEntries: a provider-kind entry is excluded (out of scope for this plugin)",
  Object.keys(M.actionableEntries(mixedEntries)).indexOf("apps"), -1);
check("actionableEntries: a pure category node (no action, no provider) is excluded",
  Object.keys(M.actionableEntries(mixedEntries)).indexOf("system"), -1);
check("actionableEntries: an otherwise-actionable excluded-subtree entry is dropped too",
  Object.keys(M.actionableEntries(mixedEntries)).indexOf("remove.development.go"), -1);

// ---- rootLabelFor -----------------------------------------------------------

const rootLabelEntries = {
  "trigger": { label: "Trigger" },
  "trigger.capture": { label: "Capture" },
  "trigger.capture.screenshot": { label: "Screenshot", action: "omarchy-capture-screenshot" }
};
check("rootLabelFor: the entry's own top-level root label, not its immediate parent's",
  M.rootLabelFor(rootLabelEntries, "trigger.capture.screenshot"), "Trigger");
check("rootLabelFor: a root-level id is its own root",
  M.rootLabelFor(rootLabelEntries, "trigger"), "Trigger");
check("rootLabelFor: a missing root yields an empty string, not a crash",
  M.rootLabelFor({}, "a.b.c"), "");

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

summary();
