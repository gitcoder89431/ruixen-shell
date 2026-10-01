"use strict";
const path = require("path");
const { loadModule, check, summary } = require("./harness");

const M = loadModule(path.join(__dirname, "..", "..", "ruixen.launcher", "extensions", "theme-browser", "ThemeCatalog.js"));

// ---- parseContentsListing ---------------------------------------------------

check("parseContentsListing: real-shaped response, dirs only, sorted",
  M.parseContentsListing(JSON.stringify([
    { name: "synthwave", type: "dir" },
    { name: "abyss", type: "dir" },
    { name: "README.md", type: "file" }
  ])),
  ["abyss", "synthwave"]);

check("parseContentsListing: assets and tools are excluded even though they're real dirs",
  M.parseContentsListing(JSON.stringify([
    { name: "assets", type: "dir" },
    { name: "tools", type: "dir" },
    { name: "hacker", type: "dir" }
  ])),
  ["hacker"]);

check("parseContentsListing: malformed JSON fails closed to an empty list, not a throw",
  M.parseContentsListing("not json"), []);

check("parseContentsListing: a JSON value that isn't an array fails closed to an empty list",
  M.parseContentsListing(JSON.stringify({ message: "rate limited" })), []);

check("parseContentsListing: an entry missing its own name is skipped",
  M.parseContentsListing(JSON.stringify([{ type: "dir" }, { name: "ok", type: "dir" }])),
  ["ok"]);

// ---- parseColorsToml ---------------------------------------------------------

check("parseColorsToml: real shape, every key extracted",
  M.parseColorsToml('mode = "dark"\n\naccent = "#8593fd"\nbackground = "#000614"\n'),
  { mode: "dark", accent: "#8593fd", background: "#000614" });

check("parseColorsToml: the hyprland border strings parse the same as any other quoted value",
  M.parseColorsToml('hyprland_active_border = "rgba(17eeecee) rgba(8593fdee) 45deg"\n'),
  { hyprland_active_border: "rgba(17eeecee) rgba(8593fdee) 45deg" });

check("parseColorsToml: blank input yields an empty object, not a throw",
  M.parseColorsToml(""), {});

check("parseColorsToml: a line that doesn't match key = \"value\" is silently skipped",
  M.parseColorsToml('not a real line\naccent = "#ffffff"\n'),
  { accent: "#ffffff" });

// ---- filterThemeNames ---------------------------------------------------------

const names = ["abyss", "synthwave", "hacker", "neon-tokyo"];

check("filterThemeNames: empty query returns every name, untouched order",
  M.filterThemeNames(names, ""), names);

check("filterThemeNames: case-insensitive substring match",
  M.filterThemeNames(names, "NEON"), ["neon-tokyo"]);

check("filterThemeNames: a query matching nothing returns an empty list",
  M.filterThemeNames(names, "zzz"), []);

check("filterThemeNames: whitespace-only query behaves like empty (returns everything)",
  M.filterThemeNames(names, "   "), names);

// ---- themeRows ---------------------------------------------------------------

check("themeRows: shape matches every other ResultsList model in this plugin",
  M.themeRows(["abyss"]),
  [{
    id: "theme:abyss",
    providerId: "theme-browser-entry",
    icon: "",
    label: "abyss",
    breadcrumb: "",
    kind: "",
    providerName: "",
    score: 0,
    sectionLabel: "Themes"
  }]);

check("themeRows: empty input yields an empty list", M.themeRows([]), []);

// ---- themeSlugFor / themeFileUrl / contentsApiUrl ----------------------------

check("themeSlugFor: dark variant is the plain theme name", M.themeSlugFor("synthwave", "dark"), "synthwave");
check("themeSlugFor: light variant appends -day", M.themeSlugFor("synthwave", "light"), "synthwave-day");

check("themeFileUrl: dark variant points at the 100-themes repo's own gh-pages site",
  M.themeFileUrl("synthwave", "dark", "colors.toml"),
  "https://bjarneo.github.io/100-themes/synthwave/colors.toml");

check("themeFileUrl: light variant points at the 100-themes-day repo, slug suffixed",
  M.themeFileUrl("synthwave", "light", "colors.toml"),
  "https://bjarneo.github.io/100-themes-day/synthwave-day/colors.toml");

check("contentsApiUrl: the GitHub Contents API root for bjarneo/100-themes",
  M.contentsApiUrl(), "https://api.github.com/repos/bjarneo/100-themes/contents/");

summary();
