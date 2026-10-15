"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "extensions", "theme-browser", "ThemePins.js"));

const synthwave = { collectionId: "bjarneo", baseSlug: "synthwave" };
const sameSlugOtherCollection = { collectionId: "coffee", baseSlug: "synthwave" };

check("pinKey: namespaced by collectionId, not just baseSlug", M.pinKey(synthwave), "bjarneo:synthwave");
check("pinKey: two collections sharing a baseSlug get distinct keys",
  M.pinKey(synthwave) !== M.pinKey(sameSlugOtherCollection), true);
check("pinKey: null theme", M.pinKey(null), "");

check("isPinned: false for an empty stats object", M.isPinned({}, synthwave), false);
check("togglePinned: pins, keyed by collectionId+baseSlug", Object.keys(M.togglePinned({}, synthwave)), [M.pinKey(synthwave)]);
check("togglePinned: value is a plain true, not a snapshot -- themes are a permanent catalog, nothing to preserve",
  M.togglePinned({}, synthwave)[M.pinKey(synthwave)], true);
check("togglePinned: pinning twice unpins", M.togglePinned(M.togglePinned({}, synthwave), synthwave), {});
check("isPinned: true once pinned", M.isPinned(M.togglePinned({}, synthwave), synthwave), true);
check("togglePinned: pinning one collection's theme doesn't affect another collection's same-named one",
  M.isPinned(M.togglePinned({}, synthwave), sameSlugOtherCollection), false);

summary();
