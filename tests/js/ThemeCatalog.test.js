"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "extensions", "theme-browser", "ThemeCatalog.js"));

// ---- motifLabel ---------------------------------------------------------

check("motifLabel: a plain motif with no special-case label", M.motifLabel("aurora"), "Aurora");
check("motifLabel: a motif whose real label genuinely differs from its own slug (not a mechanical title-case)",
  M.motifLabel("blobs"), "Light Spots");
check("motifLabel: the all-caps exception", M.motifLabel("scanlines"), "VHS");
check("motifLabel: an unknown motif falls back to the raw slug itself, not a blank field",
  M.motifLabel("some-future-motif"), "some-future-motif");
check("motifLabel: empty/undefined input fails to an empty string, not a throw", M.motifLabel(), "");

// ---- parseThemesJs --------------------------------------------------------

const sampleJs = 'window.THEMES = [{"index":1,"name":"Synthwave","slug":"synthwave",'
  + '"motif":"sunset-grid","icons":"Yaru-purple","colors":{"accent":"#d563fe"},'
  + '"ansi":["#190f2e","#fe288f"]}];\n';

check("parseThemesJs: real-shaped file, full object preserved",
  M.parseThemesJs(sampleJs),
  [{
    index: 1, name: "Synthwave", slug: "synthwave", motif: "sunset-grid", icons: "Yaru-purple",
    colors: { accent: "#d563fe" }, ansi: ["#190f2e", "#fe288f"]
  }]);

const groupedSampleJs = 'window.THEMES = {"variants":[{"key":"dark"},{"key":"day"}],"themes":[{"index":1,'
  + '"name":"Synthwave","slug":"synthwave","motif":"sunset-grid","variants":{"dark":{"install":"synthwave",'
  + '"name":"Synthwave","icons":"Yaru-purple","colors":{"accent":"#d563fe"},"ansi":["#190f2e"]},'
  + '"day":{"install":"synthwave-day","name":"Synthwave Day","icons":"Yaru-purple","colors":{"accent":"#a720d0"},'
  + '"ansi":["#f7f5fe"]}}}]};\n';

check("parseThemesJs: grouped upstream catalog defaults to the dark variant",
  M.parseThemesJs(groupedSampleJs),
  [{
    index: 1, name: "Synthwave", base: "Synthwave", night: "synthwave", slug: "synthwave",
    motif: "sunset-grid", icons: "Yaru-purple", colors: { accent: "#d563fe" }, ansi: ["#190f2e"]
  }]);

check("parseThemesJs: grouped upstream catalog can flatten the day variant",
  M.parseThemesJs(groupedSampleJs, "day"),
  [{
    index: 1, name: "Synthwave Day", base: "Synthwave", night: "synthwave", slug: "synthwave-day",
    motif: "sunset-grid", icons: "Yaru-purple", colors: { accent: "#a720d0" }, ansi: ["#f7f5fe"]
  }]);

check("parseThemesJs: malformed JS fails closed to an empty list, not a throw",
  M.parseThemesJs("not a themes file"), []);

check("parseThemesJs: empty input fails closed to an empty list",
  M.parseThemesJs(""), []);

check("parseThemesJs: valid JSON but not an array or grouped catalog fails closed to an empty list",
  M.parseThemesJs("window.THEMES = {\"oops\": true};"), []);

// ---- filterThemes ---------------------------------------------------------

const themes = [
  { name: "Abyss", slug: "abyss" },
  { name: "Synthwave", slug: "synthwave" },
  { name: "Hacker", slug: "hacker" },
  { name: "Neon Wave", slug: "neon-wave" }
];

check("filterThemes: empty query returns every theme, untouched order",
  M.filterThemes(themes, ""), themes);

check("filterThemes: case-insensitive substring match against the real display name",
  M.filterThemes(themes, "NEON"), [{ name: "Neon Wave", slug: "neon-wave" }]);

check("filterThemes: matches the display name, not the slug (a query only the slug would match finds nothing)",
  M.filterThemes(themes, "neon-wave"), []);

check("filterThemes: a query matching nothing returns an empty list",
  M.filterThemes(themes, "zzz"), []);

check("filterThemes: whitespace-only query behaves like empty (returns everything)",
  M.filterThemes(themes, "   "), themes);

// ---- filterByStyle ---------------------------------------------------------

const motifThemes = [
  { name: "Synthwave", slug: "synthwave", motif: "sunset-grid" },
  { name: "Hacker", slug: "hacker", motif: "code-rain" },
  { name: "Neon Wave", slug: "neon-wave", motif: "sunset-grid" }
];

check("filterByStyle: empty/falsy style returns every theme, untouched order (the 'All Styles' case)",
  M.filterByStyle(motifThemes, ""), motifThemes);

check("filterByStyle: a real motif keeps only themes sharing it",
  M.filterByStyle(motifThemes, "sunset-grid"),
  [{ name: "Synthwave", slug: "synthwave", motif: "sunset-grid" },
   { name: "Neon Wave", slug: "neon-wave", motif: "sunset-grid" }]);

check("filterByStyle: a motif matching nothing returns an empty list",
  M.filterByStyle(motifThemes, "scanlines"), []);

// ---- filterByInstalled -------------------------------------------------------

const installThemes = [
  { name: "Abyss", slug: "abyss" },
  { name: "Synthwave", slug: "synthwave" }
];

check("filterByInstalled: disabled is a no-op, untouched order, regardless of installedSlugs",
  M.filterByInstalled(installThemes, {}, false), installThemes);

check("filterByInstalled: enabled keeps only installed themes (dark slug installed)",
  M.filterByInstalled(installThemes, { "synthwave": true }, true),
  [{ name: "Synthwave", slug: "synthwave" }]);

check("filterByInstalled: enabled also matches on just the LIGHT slug being installed -- a real live bug, caught live: this used to be gated on whichever variant was currently being previewed, so toggling Dark -> Light while a dark-only-installed theme's list was filtered to Installed emptied it outright, taking the Dark/Light toggle (only reachable with a theme selected) down with it",
  M.filterByInstalled(installThemes, { "synthwave-day": true }, true),
  [{ name: "Synthwave", slug: "synthwave" }]);

check("filterByInstalled: a theme installed in BOTH variants is still only listed once",
  M.filterByInstalled(installThemes, { "synthwave": true, "synthwave-day": true }, true),
  [{ name: "Synthwave", slug: "synthwave" }]);

check("filterByInstalled: enabled with nothing installed returns an empty list",
  M.filterByInstalled(installThemes, {}, true), []);

// ---- sortThemes -------------------------------------------------------------

check("sortThemes: name/asc -- alphabetical by display name, not the upstream curated index order",
  M.sortThemes([{ name: "Synthwave" }, { name: "Abyss" }, { name: "Neon Wave" }], "name", "asc"),
  [{ name: "Abyss" }, { name: "Neon Wave" }, { name: "Synthwave" }]);

check("sortThemes: name/desc -- reverse alphabetical (\"order it from z-a\")",
  M.sortThemes([{ name: "Abyss" }, { name: "Neon Wave" }, { name: "Synthwave" }], "name", "desc"),
  [{ name: "Synthwave" }, { name: "Neon Wave" }, { name: "Abyss" }]);

check("sortThemes: style/asc -- orders by the motif's real label, not the theme's own name",
  M.sortThemes(
    [{ name: "Zeta", motif: "aurora" }, { name: "Alpha", motif: "tubes" }],
    "style", "asc"),
  [{ name: "Zeta", motif: "aurora" }, { name: "Alpha", motif: "tubes" }]);

check("sortThemes: an unrecognized direction fails open to ascending, not a throw",
  M.sortThemes([{ name: "B" }, { name: "A" }], "name", "sideways"),
  [{ name: "A" }, { name: "B" }]);

check("sortThemes: does not mutate the input array",
  (function() { var src = [{ name: "B" }, { name: "A" }]; M.sortThemes(src, "name", "asc"); return src; })(),
  [{ name: "B" }, { name: "A" }]);

// ---- styleOptions -------------------------------------------------------------

check("styleOptions: one entry per distinct motif, shaped like every other sourceFilterList model (id/label/path)",
  M.styleOptions([{ motif: "code-rain" }, { motif: "sunset-grid" }, { motif: "code-rain" }]),
  [{ id: "code-rain", label: "Code Rain", path: "code-rain" },
   { id: "sunset-grid", label: "Sunset Grid", path: "sunset-grid" }]);

check("styleOptions: sorted by label, not first-seen order",
  M.styleOptions([{ motif: "tubes" }, { motif: "aurora" }]),
  [{ id: "aurora", label: "Aurora", path: "aurora" },
   { id: "tubes", label: "Neon Tubes", path: "tubes" }]);

check("styleOptions: themes with no motif are skipped, not turned into a blank entry",
  M.styleOptions([{ motif: "" }, { }, { motif: "planet" }]),
  [{ id: "planet", label: "Planet", path: "planet" }]);

check("styleOptions: empty input yields an empty list", M.styleOptions([]), []);

// ---- installedSlugFor -----------------------------------------------------

check("installedSlugFor: dark variant is the plain theme slug",
  M.installedSlugFor({ slug: "synthwave" }, "dark"), "synthwave");
check("installedSlugFor: light variant appends -day",
  M.installedSlugFor({ slug: "synthwave" }, "light"), "synthwave-day");

// ---- themeRows ---------------------------------------------------------------

check("themeRows: shape matches every other ResultsList model in this plugin, label is the real display name, id keys off the slug",
  M.themeRows([{ name: "Neon Wave", slug: "neon-wave", colors: {} }], {}, "dark", "#888888"),
  [{
    id: "theme:neon-wave",
    providerId: "theme-browser-entry",
    icon: "",
    iconColor: "#888888",
    label: "Neon Wave",
    breadcrumb: "",
    kind: "",
    providerName: "",
    score: 0,
    sectionLabel: "Themes"
  }]);

check("themeRows: an installed theme (dark variant) gets its own real green, not the muted fallback",
  M.themeRows([{ name: "Hacker", slug: "hacker", colors: { green: "#39ff14" } }], { "hacker": true }, "dark", "#888888")[0].iconColor,
  "#39ff14");

check("themeRows: installed status is checked against the CURRENTLY PREVIEWED variant's own slug, not always the dark one",
  M.themeRows([{ name: "Hacker", slug: "hacker", colors: { green: "#39ff14" } }], { "hacker-day": true }, "light", "#888888")[0].iconColor,
  "#39ff14");

check("themeRows: that same installed set does NOT mark it installed while still previewing dark",
  M.themeRows([{ name: "Hacker", slug: "hacker", colors: { green: "#39ff14" } }], { "hacker-day": true }, "dark", "#888888")[0].iconColor,
  "#888888");

check("themeRows: a theme with no green of its own falls back to a plain hardcoded green, not undefined",
  M.themeRows([{ name: "Hacker", slug: "hacker", colors: {} }], { "hacker": true }, "dark", "#888888")[0].iconColor,
  "#3ecf5b");

check("themeRows: empty input yields an empty list", M.themeRows([], {}, "dark", "#888888"), []);

check("themeRows: no currentSlug passed at all -- every row still gets the plain brush, not a throw",
  M.themeRows([{ name: "Hacker", slug: "hacker", colors: {} }], { "hacker": true }, "dark", "#888888")[0].icon,
  "");

check("themeRows: the real active theme gets its own distinct check-circle glyph, not just a color",
  M.themeRows([{ name: "Hacker", slug: "hacker", colors: {} }], { "hacker": true }, "dark", "#888888", "hacker")[0].icon,
  "");

check("themeRows: currentSlug is matched against the PREVIEWED variant's own slug, not the bare theme slug",
  M.themeRows([{ name: "Hacker", slug: "hacker", colors: {} }], { "hacker-day": true }, "light", "#888888", "hacker-day")[0].icon,
  "");

check("themeRows: a currentSlug that matches a DIFFERENT row's variant leaves this one with the plain brush",
  M.themeRows([{ name: "Hacker", slug: "hacker", colors: {} }], { "hacker": true }, "dark", "#888888", "hacker-day")[0].icon,
  "");

check("themeRows: current is still colored by install status like any other row (installed here, so green)",
  M.themeRows([{ name: "Hacker", slug: "hacker", colors: { green: "#39ff14" } }], { "hacker": true }, "dark", "#888888", "hacker")[0].iconColor,
  "#39ff14");

// ---- themesDataUrl / themeFileUrl ----------------------------------------

check("themesDataUrl: dark variant points at the unified 100-themes gh-pages catalog",
  M.themesDataUrl("dark"), "https://bjarneo.github.io/100-themes/assets/themes.js");

check("themesDataUrl: light variant also uses the unified catalog",
  M.themesDataUrl("light"), "https://bjarneo.github.io/100-themes/assets/themes.js");

check("themeFileUrl: dark variant, real slug used as-is",
  M.themeFileUrl("synthwave", "dark", "preview.png"),
  "https://raw.githubusercontent.com/bjarneo/100-themes/main/synthwave/dark/preview.png");

check("themeFileUrl: light variant maps Omarchy's installed -day slug to upstream's day folder",
  M.themeFileUrl("synthwave-day", "light", "preview.png"),
  "https://raw.githubusercontent.com/bjarneo/100-themes/main/synthwave/day/preview.png");

// ---- isSafeThemeSlug ---------------------------------------------------

check("isSafeThemeSlug: a real catalog slug passes", M.isSafeThemeSlug("synthwave"), true);
check("isSafeThemeSlug: a real light-variant slug passes", M.isSafeThemeSlug("synthwave-day"), true);
check("isSafeThemeSlug: path traversal is rejected, not just slashes",
  M.isSafeThemeSlug("../../etc"), false);
check("isSafeThemeSlug: a bare slash is rejected", M.isSafeThemeSlug("a/b"), false);
check("isSafeThemeSlug: a leading dot is rejected (same rule omarchy-theme-install itself enforces)",
  M.isSafeThemeSlug(".hidden"), false);
check("isSafeThemeSlug: a leading dash is rejected", M.isSafeThemeSlug("-x"), false);
check("isSafeThemeSlug: empty/undefined fails closed", M.isSafeThemeSlug(""), false);
check("isSafeThemeSlug: empty/undefined fails closed (no arg at all)", M.isSafeThemeSlug(), false);
check("isSafeThemeSlug: a shell metacharacter is rejected", M.isSafeThemeSlug("a;rm -rf ~"), false);

// ---- backgroundsApiUrl ---------------------------------------------------

check("backgroundsApiUrl: dark variant points at the 100-themes repo's own contents API",
  M.backgroundsApiUrl("synthwave", "dark"),
  "https://api.github.com/repos/bjarneo/100-themes/contents/synthwave/dark/backgrounds");

check("backgroundsApiUrl: light variant maps Omarchy's installed -day slug to upstream's day folder",
  M.backgroundsApiUrl("synthwave-day", "light"),
  "https://api.github.com/repos/bjarneo/100-themes/contents/synthwave/day/backgrounds");

// ---- parseBackgroundsListing ---------------------------------------------------

const realListing = JSON.stringify([
  { name: "0-omarchy-wordmark.jpg", type: "file", download_url: "https://raw.example/0-omarchy-wordmark.jpg" },
  { name: "1-sunset-grid.jpg", type: "file", download_url: "https://raw.example/1-sunset-grid.jpg" }
]);

check("parseBackgroundsListing: real-shaped listing, just {name, url} pairs kept",
  M.parseBackgroundsListing(realListing),
  [{ name: "0-omarchy-wordmark.jpg", url: "https://raw.example/0-omarchy-wordmark.jpg" },
   { name: "1-sunset-grid.jpg", url: "https://raw.example/1-sunset-grid.jpg" }]);

check("parseBackgroundsListing: a 404's own {message: 'Not Found'} object fails closed to an empty list",
  M.parseBackgroundsListing(JSON.stringify({ message: "Not Found" })), []);

check("parseBackgroundsListing: malformed JSON fails closed to an empty list, not a throw",
  M.parseBackgroundsListing("not json"), []);

check("parseBackgroundsListing: a non-file entry (nested dir) is skipped, not a throw",
  M.parseBackgroundsListing(JSON.stringify([{ name: "sub", type: "dir" }])), []);

check("parseBackgroundsListing: an entry missing download_url is skipped",
  M.parseBackgroundsListing(JSON.stringify([{ name: "x.jpg", type: "file" }])), []);

// ---- isSafeBackgroundFilename ---------------------------------------------------

check("isSafeBackgroundFilename: a real catalog filename passes",
  M.isSafeBackgroundFilename("1-sunset-grid.jpg"), true);
check("isSafeBackgroundFilename: path traversal is rejected",
  M.isSafeBackgroundFilename("../../colors.toml"), false);
check("isSafeBackgroundFilename: a bare slash is rejected (can't escape backgrounds/)",
  M.isSafeBackgroundFilename("sub/evil.jpg"), false);
check("isSafeBackgroundFilename: a leading dot is rejected", M.isSafeBackgroundFilename(".hidden"), false);
check("isSafeBackgroundFilename: a leading dash is rejected", M.isSafeBackgroundFilename("-x.jpg"), false);
check("isSafeBackgroundFilename: empty/undefined fails closed", M.isSafeBackgroundFilename(""), false);
check("isSafeBackgroundFilename: empty/undefined fails closed (no arg at all)", M.isSafeBackgroundFilename(), false);

check("parseBackgroundsListing: an entry whose name is path traversal is dropped, not trusted just because type/download_url look real",
  M.parseBackgroundsListing(JSON.stringify([
    { name: "../../colors.toml", type: "file", download_url: "https://raw.example/evil" },
    { name: "1-sunset-grid.jpg", type: "file", download_url: "https://raw.example/real.jpg" }
  ])),
  [{ name: "1-sunset-grid.jpg", url: "https://raw.example/real.jpg" }]);

summary();
