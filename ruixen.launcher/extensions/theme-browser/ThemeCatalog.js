// Pure helpers for the Theme Browser extension -- bjarneo/100-themes
// (100 dark Omarchy themes) and its light companion bjarneo/100-themes-day
// (same hues, "-day" suffix, e.g. "synthwave" / "synthwave-day"). Kept
// here, not inline in ThemeBrowserContent.qml, so this is testable
// without a running QML engine -- same convention as every other *.js
// file in this plugin (FileSearchRanking.js, LauncherHelpers.js, ...).
//
// Each repo publishes its own assets/themes.js: a single static
// `window.THEMES = [...]` array covering every theme's real display
// name, slug, motif, icons, full colors (already Omarchy's own native
// theme schema, confirmed directly, no TOML parsing needed), and ansi
// set, in one file -- confirmed directly by reading it, and this
// repo's own gallery page (index.html) reads it the exact same way.
// Fetching this ONE file per variant replaces what would otherwise be
// a GitHub API catalog call plus a separate colors.toml fetch per
// theme: every theme's name/motif/colors is already in memory the
// moment this loads, no per-theme network round trip needed for any
// of it (only the actual preview.png/background images still need
// their own per-theme fetch).

// Real, human motif labels -- not a mechanical title-case of the slug
// itself, several genuinely differ (confirmed directly against the
// repo's own gallery page's MOTIFS dict in index.html): "blobs" reads
// as "Light Spots", "depths" as "Deep Water", "pixels" as "Pixel Art",
// "scanlines" as "VHS", "tubes" as "Neon Tubes". All 15 values that
// actually appear across the full 100-theme catalog are covered here
// (confirmed directly, not assumed complete).
var MOTIF_LABELS = {
  "sunset-grid": "Sunset Grid",
  "code-rain": "Code Rain",
  "nebula": "Nebula",
  "aurora": "Aurora",
  "skyline": "Skyline",
  "equalizer": "Equalizer",
  "waveform": "Waveform",
  "blobs": "Light Spots",
  "depths": "Deep Water",
  "embers": "Embers",
  "pixels": "Pixel Art",
  "scanlines": "VHS",
  "contours": "Contours",
  "tubes": "Neon Tubes",
  "planet": "Planet"
}

// Falls back to the raw motif slug itself for anything not in the
// table above (fails open to something visible rather than a blank
// field, in case upstream ever adds a new motif this hasn't been
// updated for yet).
function motifLabel(motif) {
  return MOTIF_LABELS[motif] || String(motif || "")
}

// Pulls the `window.THEMES = [...]` array literal out of a fetched
// assets/themes.js file's raw text and parses it as JSON -- the file
// is pure, safe-to-JSON-parse data (a plain array/object literal, no
// function calls or other real JS executed), confirmed by reading it
// directly rather than assumed. Malformed/empty input (a network
// failure's own error body, say) fails closed to an empty list rather
// than throwing.
function parseThemesJs(text) {
  var m = /window\.THEMES\s*=\s*(\[[\s\S]*\]);?/.exec(String(text || ""))
  if (!m) return []
  var data
  try {
    data = JSON.parse(m[1])
  } catch (e) {
    return []
  }
  return Array.isArray(data) ? data : []
}

// Case-insensitive substring match against the real display name
// (e.g. "Neon Wave", not the folder slug "neon-wave") -- operates on
// the full theme objects parseThemesJs returns, not bare strings.
function filterThemes(themes, query) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return themes
  var out = []
  for (var i = 0; i < themes.length; i++) {
    if (String(themes[i].name || "").toLowerCase().indexOf(q) !== -1) out.push(themes[i])
  }
  return out
}

// Reshaped into the exact same row object shape every other ResultsList
// model in this plugin already uses (id/providerId/icon/label/
// breadcrumb/kind/providerName/score/sectionLabel) -- same convention
// SettingsContent.qml's own sectionRows already documents: ResultRow
// itself never needs to know these came from the theme browser rather
// than a real search provider. label is the real display name; id
// keys off the real slug (stable, unique) rather than the display name
// (two themes could theoretically share a label, slugs never do).
function themeRows(themes) {
  var rows = []
  for (var i = 0; i < themes.length; i++) {
    rows.push({
      id: "theme:" + themes[i].slug,
      providerId: "theme-browser-entry",
      icon: "",
      label: themes[i].name,
      breadcrumb: "",
      kind: "",
      providerName: "",
      score: 0,
      sectionLabel: "Themes"
    })
  }
  return rows
}

// gh-pages static file URLs -- no git, no API rate limit, the same
// access path the upstream repo's own README documents
// (https://bjarneo.github.io/100-themes/synthwave/colors.toml),
// confirmed directly against that README's own aether:// example
// rather than guessed. Each repo serves its own gh-pages site under
// its own name.
function themesDataUrl(variant) {
  var repo = variant === "light" ? "100-themes-day" : "100-themes"
  return "https://bjarneo.github.io/" + repo + "/assets/themes.js"
}

// slug here is the REAL per-variant slug (e.g. "synthwave-day" for
// light, already the exact value that variant's own themes.js entry
// carries) -- callers already have the right one in hand from the
// loaded data, this never needs to derive it from a base name.
function themeFileUrl(slug, variant, relativePath) {
  var repo = variant === "light" ? "100-themes-day" : "100-themes"
  return "https://bjarneo.github.io/" + repo + "/" + slug + "/" + relativePath
}
