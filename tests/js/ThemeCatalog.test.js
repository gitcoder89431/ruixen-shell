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

check("parseThemesJs: malformed JS fails closed to an empty list, not a throw",
  M.parseThemesJs("not a themes file"), []);

check("parseThemesJs: empty input fails closed to an empty list",
  M.parseThemesJs(""), []);

check("parseThemesJs: valid JSON but not an array fails closed to an empty list",
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

// ---- themeRows ---------------------------------------------------------------

check("themeRows: shape matches every other ResultsList model in this plugin, label is the real display name, id keys off the slug",
  M.themeRows([{ name: "Neon Wave", slug: "neon-wave" }]),
  [{
    id: "theme:neon-wave",
    providerId: "theme-browser-entry",
    icon: "",
    label: "Neon Wave",
    breadcrumb: "",
    kind: "",
    providerName: "",
    score: 0,
    sectionLabel: "Themes"
  }]);

check("themeRows: empty input yields an empty list", M.themeRows([]), []);

// ---- themesDataUrl / themeFileUrl ----------------------------------------

check("themesDataUrl: dark variant points at the 100-themes repo's own gh-pages site",
  M.themesDataUrl("dark"), "https://bjarneo.github.io/100-themes/assets/themes.js");

check("themesDataUrl: light variant points at the 100-themes-day repo",
  M.themesDataUrl("light"), "https://bjarneo.github.io/100-themes-day/assets/themes.js");

check("themeFileUrl: dark variant, real slug used as-is",
  M.themeFileUrl("synthwave", "dark", "preview.png"),
  "https://bjarneo.github.io/100-themes/synthwave/preview.png");

check("themeFileUrl: light variant, real slug used as-is (already carries its own -day suffix)",
  M.themeFileUrl("synthwave-day", "light", "preview.png"),
  "https://bjarneo.github.io/100-themes-day/synthwave-day/preview.png");

summary();
