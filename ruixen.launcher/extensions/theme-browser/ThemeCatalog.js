// Pure helpers for the Theme Browser extension -- bjarneo/100-themes
// (100 dark Omarchy themes) and its light companion bjarneo/100-themes-day
// (same hues, "-day" suffix, e.g. "synthwave" / "synthwave-day"). Kept
// here, not inline in ThemeBrowserContent.qml, so this is testable
// without a running QML engine -- same convention as every other *.js
// file in this plugin (FileSearchRanking.js, LauncherHelpers.js, ...).
//
// Both repos' colors.toml is already Omarchy's own native theme schema
// byte-for-byte (confirmed directly by reading it, not guessed) -- no
// translation step, parseColorsToml below just reads the same flat
// key = "value" lines every theme in both repos uses, verified
// identical across all 100 before writing this (one md5 of each
// theme's own sorted key list, all 100 the same hash).

// Non-theme folders at the root of bjarneo/100-themes (confirmed
// directly: every real theme folder has a colors.toml, these two
// don't) -- excluded so neither ever shows up as a fake "theme" in the
// catalog.
var NON_THEME_DIRS = ["assets", "tools"]

// GitHub's Contents API response for a repo's root -- an array of
// {name, type, ...}. Scoped to type === "dir" (a real theme is a
// folder), minus the two non-theme folders above. Malformed/empty
// input (a network failure's own error body, say) fails closed to an
// empty list rather than throwing -- the caller's own "could not load
// the catalog" state is what should show, not a crash.
function parseContentsListing(jsonText) {
  var entries
  try {
    entries = JSON.parse(jsonText)
  } catch (e) {
    return []
  }
  if (!Array.isArray(entries)) return []
  var names = []
  for (var i = 0; i < entries.length; i++) {
    var e = entries[i]
    if (!e || e.type !== "dir" || !e.name) continue
    if (NON_THEME_DIRS.indexOf(e.name) !== -1) continue
    names.push(e.name)
  }
  names.sort()
  return names
}

// Every key colors.toml actually has is a plain top-level
// `key = "value"` or `key = value` line (hyprland_active_border/
// hyprland_inactive_border are quoted strings too, same as every
// color) -- no nested tables, no arrays, confirmed directly against
// all 100 themes before writing this, so a real TOML parser would be
// pure overhead. Lines that don't match (blank lines, this format
// never has comments) are silently skipped.
function parseColorsToml(text) {
  var result = {}
  var lines = String(text || "").split("\n")
  for (var i = 0; i < lines.length; i++) {
    var m = /^([a-z_]+)\s*=\s*"([^"]*)"/.exec(lines[i])
    if (m) result[m[1]] = m[2]
  }
  return result
}

// Case-insensitive substring match against the base (dark) theme name
// only -- "-day" is a presentation detail (the variant toggle in the
// detail panel), never something to type separately in the search box.
function filterThemeNames(names, query) {
  var q = String(query || "").trim().toLowerCase()
  if (q === "") return names
  var out = []
  for (var i = 0; i < names.length; i++) {
    if (names[i].toLowerCase().indexOf(q) !== -1) out.push(names[i])
  }
  return out
}

// Reshaped into the exact same row object shape every other ResultsList
// model in this plugin already uses (id/providerId/icon/label/
// breadcrumb/kind/providerName/score/sectionLabel) -- same convention
// SettingsContent.qml's own sectionRows already documents: ResultRow
// itself never needs to know these came from the theme browser rather
// than a real search provider.
function themeRows(names) {
  var rows = []
  for (var i = 0; i < names.length; i++) {
    rows.push({
      id: "theme:" + names[i],
      providerId: "theme-browser-entry",
      icon: "",
      label: names[i],
      breadcrumb: "",
      kind: "",
      providerName: "",
      score: 0,
      sectionLabel: "Themes"
    })
  }
  return rows
}

// The real per-variant slug/URL path segment -- "day" maps a dark base
// name to its light companion repo's own folder name ("synthwave" ->
// "synthwave-day"); "dark" is already the real folder name as-is.
function themeSlugFor(name, variant) {
  return variant === "light" ? name + "-day" : name
}

// gh-pages static file URLs -- no git, no API rate limit, the same
// access path the upstream repo's own README documents
// (https://bjarneo.github.io/100-themes/<slug>/colors.toml), confirmed
// directly against that README's own aether:// example rather than
// guessed. Each repo serves its own gh-pages site under its own name.
function themeFileUrl(name, variant, relativePath) {
  var repo = variant === "light" ? "100-themes-day" : "100-themes"
  var slug = themeSlugFor(name, variant)
  return "https://bjarneo.github.io/" + repo + "/" + slug + "/" + relativePath
}

function contentsApiUrl() {
  return "https://api.github.com/repos/bjarneo/100-themes/contents/"
}
