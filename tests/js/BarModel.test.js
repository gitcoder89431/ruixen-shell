"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.bar", "BarModel.js"));

check("isPlainObject: a real object", M.isPlainObject({ id: "x" }), true);
check("isPlainObject: an array is not a plain object", M.isPlainObject([1, 2]), false);
check("isPlainObject: null is not a plain object", M.isPlainObject(null), false);

check("normalizePosition: valid value passes through", M.normalizePosition("bottom"), "bottom");
check("normalizePosition: invalid value falls back to top", M.normalizePosition("sideways"), "top");
check("normalizePosition: missing value falls back to top", M.normalizePosition(undefined), "top");

check("entryId: string entry", M.entryId("omarchy.clock"), "omarchy.clock");
check("entryId: object entry with id", M.entryId({ id: "omarchy.clock", format: "HH:mm" }), "omarchy.clock");
check("entryId: object entry with no id", M.entryId({ format: "HH:mm" }), "");
check("entryId: not an entry at all", M.entryId(42), "");

const layout = [{ id: "a" }, { id: "b" }, { id: "c" }];
check("entryIndex: finds the right position", M.entryIndex(layout, "b"), 1);
check("entryIndex: missing id returns -1", M.entryIndex(layout, "z"), -1);
check("entryIndex: non-array input returns -1", M.entryIndex(null, "a"), -1);

check("entriesBefore: entries ahead of the named one", M.entriesBefore(layout, "c"), [{ id: "a" }, { id: "b" }]);
check("entriesBefore: named entry is first -> empty", M.entriesBefore(layout, "a"), []);
check("entriesBefore: name not found -> empty", M.entriesBefore(layout, "z"), []);

check("entriesAfter: entries past the named one", M.entriesAfter(layout, "a"), [{ id: "b" }, { id: "c" }]);
check("entriesAfter: named entry is last -> empty", M.entriesAfter(layout, "c"), []);
check("entriesAfter: name not found -> empty", M.entriesAfter(layout, "z"), []);

check(
  "pinTrayToInner: moves tray to the front of the right section",
  M.pinTrayToInner([{ id: "a" }, { id: "omarchy.tray" }, { id: "b" }], "right"),
  [{ id: "omarchy.tray" }, { id: "a" }, { id: "b" }]
);
check(
  "pinTrayToInner: moves tray to the back of the left section",
  M.pinTrayToInner([{ id: "omarchy.tray" }, { id: "a" }], "left"),
  [{ id: "a" }, { id: "omarchy.tray" }]
);
check(
  "pinTrayToInner: no tray present -> untouched",
  M.pinTrayToInner([{ id: "a" }, { id: "b" }], "right"),
  [{ id: "a" }, { id: "b" }]
);

// --- reservedCenterRect (#28) ----------------------------------------
check(
  "reservedCenterRect: centered on a 1920px screen matches the real notch reservation live-verified on a real machine",
  M.reservedCenterRect(340, 1920, 34),
  { x: 790, y: 0, width: 340, height: 34 }
);
check(
  "reservedCenterRect: centered on an odd-width container rounds down, never off-screen",
  M.reservedCenterRect(340, 1921, 34),
  { x: 790.5, y: 0, width: 340, height: 34 }
);
check(
  "reservedCenterRect: a container narrower than the reserved width clamps to the full container, not negative x",
  M.reservedCenterRect(340, 200, 34),
  { x: 0, y: 0, width: 200, height: 34 }
);
check(
  "reservedCenterRect: zero-width container never throws, returns a zero rect",
  M.reservedCenterRect(340, 0, 34),
  { x: 0, y: 0, width: 0, height: 34 }
);
check(
  "reservedCenterRect: negative/garbage reservedWidth is clamped to zero, not subtracted",
  M.reservedCenterRect(-50, 1920, 34),
  { x: 960, y: 0, width: 0, height: 34 }
);
check(
  "reservedCenterRect: non-numeric inputs degrade to zero rather than NaN propagating",
  M.reservedCenterRect(undefined, undefined, undefined),
  { x: 0, y: 0, width: 0, height: 0 }
);

// Issue #7: moveModuleInConfig extracted verbatim from Bar.qml's own
// dropBarModule (drag-to-reorder's actual config mutation) -- pure
// data manipulation with no QML/Item dependency, now unit-testable
// without a live Quickshell instance.
function freshConfig() {
  return {
    bar: {
      layout: {
        left: [{ id: "a" }, { id: "b" }],
        center: [],
        right: [{ id: "c", opacity: 0.5 }, { id: "d" }]
      }
    }
  };
}

let cfg = freshConfig();
check("moveModuleInConfig: reorder within the same section", M.moveModuleInConfig(cfg, "left", "b", "left", "a"), true);
check("moveModuleInConfig: reorder within the same section result", cfg.bar.layout.left, [{ id: "b" }, { id: "a" }]);

cfg = freshConfig();
check("moveModuleInConfig: move to a different section, before a target", M.moveModuleInConfig(cfg, "left", "a", "right", "d"), true);
check("moveModuleInConfig: source section loses the moved entry", cfg.bar.layout.left, [{ id: "b" }]);
check("moveModuleInConfig: destination section gains it before the target, settings-free entry unchanged", cfg.bar.layout.right, [{ id: "c", opacity: 0.5 }, { id: "a" }, { id: "d" }]);

cfg = freshConfig();
check("moveModuleInConfig: move to a different section with no beforeName appends at the end", M.moveModuleInConfig(cfg, "left", "a", "right", ""), true);
check("moveModuleInConfig: appended at the end, inline settings on the sibling entry survive", cfg.bar.layout.right, [{ id: "c", opacity: 0.5 }, { id: "d" }, { id: "a" }]);

cfg = freshConfig();
check("moveModuleInConfig: dropping onto its own current position is a no-op", M.moveModuleInConfig(cfg, "left", "a", "left", "a"), false);
check("moveModuleInConfig: no-op leaves the section byte-for-byte unchanged", cfg.bar.layout.left, [{ id: "a" }, { id: "b" }]);

cfg = freshConfig();
check("moveModuleInConfig: unknown source id changes nothing", M.moveModuleInConfig(cfg, "left", "nonexistent", "right", "c"), false);
check("moveModuleInConfig: unknown source id leaves both sections untouched", [cfg.bar.layout.left, cfg.bar.layout.right], [[{ id: "a" }, { id: "b" }], [{ id: "c", opacity: 0.5 }, { id: "d" }]]);

cfg = { bar: {} };
check("moveModuleInConfig: missing layout entirely is created on demand, not a crash", M.moveModuleInConfig(cfg, "left", "a", "right", ""), false);
check("moveModuleInConfig: both sections exist afterward, empty", cfg.bar.layout, { left: [], right: [] });

summary();
