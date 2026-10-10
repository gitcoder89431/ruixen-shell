"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "extensions", "theme-browser", "ThemeCatalog.js"));

// ---- listCollections / collectionById --------------------------------

check("listCollections: Bjarneo first -- the original collection, direct request to rename it off '100 Themes'",
  M.listCollections()[0], { id: "bjarneo", label: "Bjarneo" });

check("listCollections: every later collection present, same {id,label} shape",
  M.listCollections().map(function(c) { return c.id; }),
  ["bjarneo", "coffee", "tea", "mineral", "spice", "various"]);

check("collectionById: a real id returns its real config",
  M.collectionById("coffee").repo, "coffee-themes");

check("collectionById: coffee's dark-equivalent JSON key is 'night', confirmed against the live catalog, not 'dark'",
  M.collectionById("coffee").darkKey, "night");

check("collectionById: Bjarneo alone still keys its dark variant as 'dark'",
  M.collectionById("bjarneo").darkKey, "dark");

check("collectionById: an unknown id falls back to the first collection (Bjarneo), not a throw",
  M.collectionById("made-up").id, "bjarneo");

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

check("parseThemesJs: bare-array legacy shape is returned as-is, no collection metadata attached (nothing live ships this anymore, kept as a defensive fallback only)",
  M.parseThemesJs(sampleJs),
  [{
    index: 1, name: "Synthwave", slug: "synthwave", motif: "sunset-grid", icons: "Yaru-purple",
    colors: { accent: "#d563fe" }, ansi: ["#190f2e", "#fe288f"]
  }]);

const bjarneo = M.collectionById("bjarneo");

const groupedSampleJs = 'window.THEMES = {"variants":[{"key":"dark"},{"key":"day"}],"themes":[{"index":1,'
  + '"name":"Synthwave","slug":"synthwave","motif":"sunset-grid","variants":{"dark":{"install":"synthwave",'
  + '"name":"Synthwave","icons":"Yaru-purple","colors":{"accent":"#d563fe"},"ansi":["#190f2e"]},'
  + '"day":{"install":"synthwave-day","name":"Synthwave Day","icons":"Yaru-purple","colors":{"accent":"#a720d0"},'
  + '"ansi":["#f7f5fe"]}}}]};\n';

check("parseThemesJs: grouped catalog defaults to the dark variant, Bjarneo's own motif resolved via MOTIF_LABELS",
  M.parseThemesJs(groupedSampleJs, bjarneo),
  [{
    index: 1, name: "Synthwave", baseName: "Synthwave", baseSlug: "synthwave",
    slug: "synthwave", darkSlug: "synthwave", daySlug: "synthwave-day",
    style: "sunset-grid", styleLabel: "Sunset Grid",
    icons: "Yaru-purple", colors: { accent: "#d563fe" }, ansi: ["#190f2e"],
    collectionId: "bjarneo"
  }]);

check("parseThemesJs: grouped catalog can flatten the light variant, darkSlug/daySlug stay resolved regardless of which is previewed",
  M.parseThemesJs(groupedSampleJs, bjarneo, "light"),
  [{
    index: 1, name: "Synthwave Day", baseName: "Synthwave", baseSlug: "synthwave",
    slug: "synthwave-day", darkSlug: "synthwave", daySlug: "synthwave-day",
    style: "sunset-grid", styleLabel: "Sunset Grid",
    icons: "Yaru-purple", colors: { accent: "#a720d0" }, ansi: ["#f7f5fe"],
    collectionId: "bjarneo"
  }]);

check("parseThemesJs: no collection passed defaults to Bjarneo",
  M.parseThemesJs(groupedSampleJs)[0].collectionId, "bjarneo");

const coffee = M.collectionById("coffee");
const coffeeSampleJs = 'window.THEMES = {"variants":[{"key":"night"},{"key":"day"}],'
  + '"categories":[{"key":"espresso","label":"Espresso drinks"}],"themes":[{"index":1,'
  + '"name":"Espresso Solo","slug":"espresso-solo","cat":"espresso","variants":{"night":{'
  + '"install":"espresso-solo-night","name":"Espresso Solo Night","icons":"Yaru-yellow",'
  + '"colors":{"accent":"#e4a249"},"ansi":["#160a05"]},"day":{"install":"espresso-solo-day",'
  + '"name":"Espresso Solo Day","icons":"Yaru-yellow","colors":{"accent":"#98630c"},'
  + '"ansi":["#fcf0e4"]}}}]};\n';

check("parseThemesJs: Coffee's own 'night' dark-key is honored, not hardcoded 'dark'",
  M.parseThemesJs(coffeeSampleJs, coffee),
  [{
    index: 1, name: "Espresso Solo Night", baseName: "Espresso Solo", baseSlug: "espresso-solo",
    slug: "espresso-solo-night", darkSlug: "espresso-solo-night", daySlug: "espresso-solo-day",
    style: "espresso", styleLabel: "Espresso drinks",
    icons: "Yaru-yellow", colors: { accent: "#e4a249" }, ansi: ["#160a05"],
    collectionId: "coffee"
  }]);

check("parseThemesJs: Coffee's install slug is explicitly suffixed for BOTH variants -- the old bare-dark-plus-'-day' trick would have broken this",
  M.parseThemesJs(coffeeSampleJs, coffee)[0].darkSlug, "espresso-solo-night");

check("parseThemesJs: a style id with no entry in the collection's own lookup falls back to the raw id, not MOTIF_LABELS",
  M.parseThemesJs(
    'window.THEMES = {"variants":[{"key":"night"},{"key":"day"}],"categories":[],"themes":[{"index":1,'
    + '"name":"X","slug":"x","cat":"unknown-cat","variants":{"night":{"install":"x-night","colors":{},"ansi":[]},'
    + '"day":{"install":"x-day","colors":{},"ansi":[]}}}]};\n',
    coffee)[0].styleLabel,
  "unknown-cat");

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

// ---- filterByCollection -----------------------------------------------

const multiCollectionThemes = [
  { name: "Synthwave", collectionId: "bjarneo" },
  { name: "Espresso Solo", collectionId: "coffee" },
  { name: "Earl Grey", collectionId: "tea" }
];

check("filterByCollection: empty/falsy id returns every theme, untouched order (the 'All' case)",
  M.filterByCollection(multiCollectionThemes, ""), multiCollectionThemes);

check("filterByCollection: a real id keeps only that collection's themes",
  M.filterByCollection(multiCollectionThemes, "coffee"),
  [{ name: "Espresso Solo", collectionId: "coffee" }]);

check("filterByCollection: an id matching nothing returns an empty list",
  M.filterByCollection(multiCollectionThemes, "spice"), []);

// ---- filterByStyle ---------------------------------------------------------

const styleThemes = [
  { name: "Synthwave", slug: "synthwave", style: "sunset-grid" },
  { name: "Hacker", slug: "hacker", style: "code-rain" },
  { name: "Neon Wave", slug: "neon-wave", style: "sunset-grid" }
];

check("filterByStyle: empty/falsy style returns every theme, untouched order (the 'All Styles' case)",
  M.filterByStyle(styleThemes, ""), styleThemes);

check("filterByStyle: a real style id keeps only themes sharing it",
  M.filterByStyle(styleThemes, "sunset-grid"),
  [{ name: "Synthwave", slug: "synthwave", style: "sunset-grid" },
   { name: "Neon Wave", slug: "neon-wave", style: "sunset-grid" }]);

check("filterByStyle: a style matching nothing returns an empty list",
  M.filterByStyle(styleThemes, "scanlines"), []);

// ---- filterByInstalled -------------------------------------------------------

const installThemes = [
  { name: "Abyss", darkSlug: "abyss", daySlug: "abyss-day" },
  { name: "Synthwave", darkSlug: "synthwave", daySlug: "synthwave-day" }
];

check("filterByInstalled: disabled is a no-op, untouched order, regardless of installedSlugs",
  M.filterByInstalled(installThemes, {}, false), installThemes);

check("filterByInstalled: enabled keeps only installed themes (dark slug installed)",
  M.filterByInstalled(installThemes, { "synthwave": true }, true),
  [{ name: "Synthwave", darkSlug: "synthwave", daySlug: "synthwave-day" }]);

check("filterByInstalled: enabled also matches on just the LIGHT slug being installed -- a real live bug, caught live: this used to be gated on whichever variant was currently being previewed, so toggling Dark -> Light while a dark-only-installed theme's list was filtered to Installed emptied it outright, taking the Dark/Light toggle (only reachable with a theme selected) down with it",
  M.filterByInstalled(installThemes, { "synthwave-day": true }, true),
  [{ name: "Synthwave", darkSlug: "synthwave", daySlug: "synthwave-day" }]);

check("filterByInstalled: a theme installed in BOTH variants is still only listed once",
  M.filterByInstalled(installThemes, { "synthwave": true, "synthwave-day": true }, true),
  [{ name: "Synthwave", darkSlug: "synthwave", daySlug: "synthwave-day" }]);

check("filterByInstalled: enabled with nothing installed returns an empty list",
  M.filterByInstalled(installThemes, {}, true), []);

// ---- sortThemes -------------------------------------------------------------

check("sortThemes: name/asc -- alphabetical by display name, not the upstream curated index order",
  M.sortThemes([{ name: "Synthwave" }, { name: "Abyss" }, { name: "Neon Wave" }], "name", "asc"),
  [{ name: "Abyss" }, { name: "Neon Wave" }, { name: "Synthwave" }]);

check("sortThemes: name/desc -- reverse alphabetical (\"order it from z-a\")",
  M.sortThemes([{ name: "Abyss" }, { name: "Neon Wave" }, { name: "Synthwave" }], "name", "desc"),
  [{ name: "Synthwave" }, { name: "Neon Wave" }, { name: "Abyss" }]);

check("sortThemes: style/asc -- orders by the already-resolved styleLabel, not the theme's own name",
  M.sortThemes(
    [{ name: "Zeta", styleLabel: "Aurora" }, { name: "Alpha", styleLabel: "Neon Tubes" }],
    "style", "asc"),
  [{ name: "Zeta", styleLabel: "Aurora" }, { name: "Alpha", styleLabel: "Neon Tubes" }]);

check("sortThemes: an unrecognized direction fails open to ascending, not a throw",
  M.sortThemes([{ name: "B" }, { name: "A" }], "name", "sideways"),
  [{ name: "A" }, { name: "B" }]);

check("sortThemes: does not mutate the input array",
  (function() { var src = [{ name: "B" }, { name: "A" }]; M.sortThemes(src, "name", "asc"); return src; })(),
  [{ name: "B" }, { name: "A" }]);

// ---- styleOptions -------------------------------------------------------------

check("styleOptions: one entry per distinct style, shaped like every other sourceFilterList model (id/label/path), reading the already-resolved styleLabel directly",
  M.styleOptions([{ style: "code-rain", styleLabel: "Code Rain" }, { style: "sunset-grid", styleLabel: "Sunset Grid" }, { style: "code-rain", styleLabel: "Code Rain" }]),
  [{ id: "code-rain", label: "Code Rain", path: "code-rain" },
   { id: "sunset-grid", label: "Sunset Grid", path: "sunset-grid" }]);

check("styleOptions: sorted by label, not first-seen order",
  M.styleOptions([{ style: "tubes", styleLabel: "Neon Tubes" }, { style: "aurora", styleLabel: "Aurora" }]),
  [{ id: "aurora", label: "Aurora", path: "aurora" },
   { id: "tubes", label: "Neon Tubes", path: "tubes" }]);

check("styleOptions: themes with no style are skipped, not turned into a blank entry",
  M.styleOptions([{ style: "" }, { }, { style: "planet", styleLabel: "Planet" }]),
  [{ id: "planet", label: "Planet", path: "planet" }]);

check("styleOptions: works across collections in one combined list -- a Coffee category and a Bjarneo motif are both just 'style/styleLabel' by the time this sees them",
  M.styleOptions([{ style: "espresso", styleLabel: "Espresso drinks" }, { style: "aurora", styleLabel: "Aurora" }]),
  [{ id: "aurora", label: "Aurora", path: "aurora" },
   { id: "espresso", label: "Espresso drinks", path: "espresso" }]);

check("styleOptions: empty input yields an empty list", M.styleOptions([]), []);

// ---- installedSlugFor -----------------------------------------------------

check("installedSlugFor: dark variant reads the resolved darkSlug directly, no suffix guessing",
  M.installedSlugFor({ darkSlug: "synthwave", daySlug: "synthwave-day" }, "dark"), "synthwave");
check("installedSlugFor: light variant reads the resolved daySlug directly",
  M.installedSlugFor({ darkSlug: "synthwave", daySlug: "synthwave-day" }, "light"), "synthwave-day");
check("installedSlugFor: a collection where BOTH variants are suffixed (Coffee) still resolves correctly -- the old bare-slug-plus-'-day' trick would have produced 'espresso-solo-night-day' here",
  M.installedSlugFor({ darkSlug: "espresso-solo-night", daySlug: "espresso-solo-day" }, "light"),
  "espresso-solo-day");
check("installedSlugFor: a missing slug fails closed to an empty string, not undefined",
  M.installedSlugFor({}, "dark"), "");

// ---- themeRows ---------------------------------------------------------------

check("themeRows: shape matches every other ResultsList model in this plugin, label is the real display name, id keys off the slug, breadcrumb reads styleLabel directly",
  M.themeRows([{ name: "Neon Wave", slug: "neon-wave", styleLabel: "", darkSlug: "neon-wave", daySlug: "neon-wave-day", colors: {} }], {}, "dark", "#888888"),
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

check("themeRows: breadcrumb is the theme's own resolved style label",
  M.themeRows([{ name: "Espresso Solo", slug: "espresso-solo-night", styleLabel: "Espresso drinks", darkSlug: "espresso-solo-night", daySlug: "espresso-solo-day", colors: {} }], {}, "dark", "#888888")[0].breadcrumb,
  "Espresso drinks");

check("themeRows: an installed theme (dark variant) gets its own real green, not the muted fallback",
  M.themeRows([{ name: "Hacker", slug: "hacker", darkSlug: "hacker", daySlug: "hacker-day", colors: { green: "#39ff14" } }], { "hacker": true }, "dark", "#888888")[0].iconColor,
  "#39ff14");

check("themeRows: installed status is checked against the CURRENTLY PREVIEWED variant's own resolved slug, not always the dark one",
  M.themeRows([{ name: "Hacker", slug: "hacker-day", darkSlug: "hacker", daySlug: "hacker-day", colors: { green: "#39ff14" } }], { "hacker-day": true }, "light", "#888888")[0].iconColor,
  "#39ff14");

check("themeRows: that same installed set does NOT mark it installed while still previewing dark",
  M.themeRows([{ name: "Hacker", slug: "hacker", darkSlug: "hacker", daySlug: "hacker-day", colors: { green: "#39ff14" } }], { "hacker-day": true }, "dark", "#888888")[0].iconColor,
  "#888888");

check("themeRows: a theme with no green of its own falls back to a plain hardcoded green, not undefined",
  M.themeRows([{ name: "Hacker", slug: "hacker", darkSlug: "hacker", daySlug: "hacker-day", colors: {} }], { "hacker": true }, "dark", "#888888")[0].iconColor,
  "#3ecf5b");

check("themeRows: empty input yields an empty list", M.themeRows([], {}, "dark", "#888888"), []);

check("themeRows: no currentSlug passed at all -- every row still gets the plain brush, not a throw",
  M.themeRows([{ name: "Hacker", slug: "hacker", darkSlug: "hacker", daySlug: "hacker-day", colors: {} }], { "hacker": true }, "dark", "#888888")[0].icon,
  "");

check("themeRows: the real active theme gets its own distinct check-circle glyph, not just a color",
  M.themeRows([{ name: "Hacker", slug: "hacker", darkSlug: "hacker", daySlug: "hacker-day", colors: {} }], { "hacker": true }, "dark", "#888888", "hacker")[0].icon,
  "");

check("themeRows: currentSlug is matched against the PREVIEWED variant's own resolved slug, not the dark one",
  M.themeRows([{ name: "Hacker", slug: "hacker-day", darkSlug: "hacker", daySlug: "hacker-day", colors: {} }], { "hacker-day": true }, "light", "#888888", "hacker-day")[0].icon,
  "");

check("themeRows: a currentSlug that matches a DIFFERENT row's variant leaves this one with the plain brush",
  M.themeRows([{ name: "Hacker", slug: "hacker", darkSlug: "hacker", daySlug: "hacker-day", colors: {} }], { "hacker": true }, "dark", "#888888", "hacker-day")[0].icon,
  "");

check("themeRows: current is still colored by install status like any other row (installed here, so green)",
  M.themeRows([{ name: "Hacker", slug: "hacker", darkSlug: "hacker", daySlug: "hacker-day", colors: { green: "#39ff14" } }], { "hacker": true }, "dark", "#888888", "hacker")[0].iconColor,
  "#39ff14");

// ---- themesDataUrl / themeFileUrl ----------------------------------------

check("themesDataUrl: Bjarneo points at its own gh-pages catalog",
  M.themesDataUrl(bjarneo), "https://bjarneo.github.io/100-themes/assets/themes.js");

check("themesDataUrl: Coffee points at ITS own repo's catalog, not Bjarneo's",
  M.themesDataUrl(coffee), "https://bjarneo.github.io/coffee-themes/assets/themes.js");

check("themesDataUrl: no collection passed defaults to Bjarneo",
  M.themesDataUrl(), "https://bjarneo.github.io/100-themes/assets/themes.js");

check("themeFileUrl: Bjarneo dark variant uses its own 'dark' folder name",
  M.themeFileUrl(bjarneo, "synthwave", "dark", "preview.png"),
  "https://raw.githubusercontent.com/bjarneo/100-themes/main/synthwave/dark/preview.png");

check("themeFileUrl: Bjarneo light variant uses the universal 'day' folder name",
  M.themeFileUrl(bjarneo, "synthwave", "light", "preview.png"),
  "https://raw.githubusercontent.com/bjarneo/100-themes/main/synthwave/day/preview.png");

check("themeFileUrl: Coffee's dark-equivalent variant uses ITS own 'night' folder name, not 'dark'",
  M.themeFileUrl(coffee, "espresso-solo", "dark", "preview.png"),
  "https://raw.githubusercontent.com/bjarneo/coffee-themes/main/espresso-solo/night/preview.png");

check("themeFileUrl: Coffee light variant still uses the universal 'day' folder name",
  M.themeFileUrl(coffee, "espresso-solo", "light", "preview.png"),
  "https://raw.githubusercontent.com/bjarneo/coffee-themes/main/espresso-solo/day/preview.png");

check("themeFileUrl: built from the theme's real base slug, never an installed slug's own suffix",
  M.themeFileUrl(coffee, "espresso-solo", "dark", "colors.toml"),
  "https://raw.githubusercontent.com/bjarneo/coffee-themes/main/espresso-solo/night/colors.toml");

// ---- isSafeThemeSlug ---------------------------------------------------

check("isSafeThemeSlug: a real catalog slug passes", M.isSafeThemeSlug("synthwave"), true);
check("isSafeThemeSlug: a real light-variant slug passes", M.isSafeThemeSlug("synthwave-day"), true);
check("isSafeThemeSlug: a real Coffee night-variant slug passes", M.isSafeThemeSlug("espresso-solo-night"), true);
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

check("backgroundsApiUrl: Bjarneo dark variant points at its own repo's contents API",
  M.backgroundsApiUrl(bjarneo, "synthwave", "dark"),
  "https://api.github.com/repos/bjarneo/100-themes/contents/synthwave/dark/backgrounds");

check("backgroundsApiUrl: Bjarneo light variant uses the universal 'day' folder name",
  M.backgroundsApiUrl(bjarneo, "synthwave", "light"),
  "https://api.github.com/repos/bjarneo/100-themes/contents/synthwave/day/backgrounds");

check("backgroundsApiUrl: Coffee dark-equivalent variant points at ITS own repo under ITS own 'night' folder",
  M.backgroundsApiUrl(coffee, "espresso-solo", "dark"),
  "https://api.github.com/repos/bjarneo/coffee-themes/contents/espresso-solo/night/backgrounds");

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
