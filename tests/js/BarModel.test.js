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

summary();
