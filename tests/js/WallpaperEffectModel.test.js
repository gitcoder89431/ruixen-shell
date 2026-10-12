"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness.js");
for (const folder of ["ruixen.launcher/extensions/wallpapers"]) {
  const model = loadModule(path.join(__dirname, "../..", folder, "WallpaperEffectModel.js"));
  const current = "/Pictures/JG-Artwork/piano-at-the-library.png";
  const entries = [
    {kind:"image", real:current},
    {kind:"image", real:"/theme/jg-visual-arts-piano-at-the-library.png"},
    {kind:"video", real:"/theme/movie.mp4"},
    {kind:"image", real:"/theme/winding-road.jpg"}
  ];
  check(folder + ": skips current artwork, renamed duplicate, and video", model.nextPreviewArtwork(current, entries), "/theme/winding-road.jpg");
  check(folder + ": initial empty current still picks an image", model.nextPreviewArtwork("", entries), current);
  check(folder + ": tolerates malformed entries", model.nextPreviewArtwork(current, [null,{kind:"image"},entries[3]]), "/theme/winding-road.jpg");
  check(folder + ": handles an empty collection", model.nextPreviewArtwork(current, []), "");
  check(folder + ": no different artwork returns fallback", model.nextPreviewArtwork(current, entries.slice(0, 2)), "");
}
summary();
