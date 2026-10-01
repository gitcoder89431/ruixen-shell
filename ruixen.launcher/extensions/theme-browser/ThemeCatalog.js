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

// style is a motif slug (e.g. "sunset-grid"), or "" for "every style" --
// same "no filter selected" sentinel this file's own installedSlugFor-
// adjacent conventions already use elsewhere.
function filterByStyle(themes, style) {
  if (!style) return themes
  var out = []
  for (var i = 0; i < themes.length; i++) {
    if (themes[i].motif === style) out.push(themes[i])
  }
  return out
}

// Direct follow-up ("im thinking about making that between All and
// Installed") -- the left-panel equivalent of Wallpapers' own "All
// Types" dropdown became an installed-only toggle instead (a real
// browse/manage distinction now that install is real), not a third
// kind of style filter. enabled false is a no-op so this composes with
// filterByStyle/filterThemes above in any order without special-casing
// "the toggle is off" at each call site.
//
// Checks BOTH variants' slugs, not just whichever one is currently
// being previewed -- a real live bug, caught live: gated on the
// previewed variant alone, toggling Dark -> Light while "Installed"
// was active found zero of the (dark-only-installed) themes still
// installed under THAT variant's own slug, emptying the list outright.
// Worse than a plain empty state too -- the right panel (Dark/Light
// toggle included) only shows once a theme is selected, so an emptied
// list took the one control that could undo this down with it,
// leaving no way back except this dropdown itself. "Installed" here
// means the THEME is installed, in whichever variant, not "is this
// exact preview installed" -- matches how a person would actually ask
// the question, and can't be emptied out from under itself by the
// Dark/Light toggle again.
function filterByInstalled(themes, installedSlugs, enabled) {
  if (!enabled) return themes
  var out = []
  for (var i = 0; i < themes.length; i++) {
    var theme = themes[i]
    var anyVariantInstalled = !!(installedSlugs && (installedSlugs[installedSlugFor(theme, "dark")] || installedSlugs[installedSlugFor(theme, "light")]))
    if (anyVariantInstalled) out.push(theme)
  }
  return out
}

// Direct follow-up ("how would we order this... click name chip to
// order it from z-a and then Style so it orders it by subtitles
// instead") -- the upstream catalog's own order is just whatever index
// its author curated it in (Synthwave=1, Neon Wave=2, ...), not
// alphabetical, so left on its own it reads as arbitrary. sortKey picks
// which field to compare ("name", the real display name, or "style",
// the same motif label the breadcrumb subtitle already shows);
// direction is "asc" or "desc" (anything else behaves as "asc", same
// fail-open-to-the-sane-default convention motifLabel's own fallback
// uses). localeCompare so "Neon Wave" vs "Nebula" sorts the same way a
// human skimming the list would expect, not raw UTF-16 code-unit order.
function sortThemes(themes, sortKey, direction) {
  var out = themes.slice()
  var dir = direction === "desc" ? -1 : 1
  out.sort(function(a, b) {
    var av = sortKey === "style" ? motifLabel(a.motif) : String(a.name || "")
    var bv = sortKey === "style" ? motifLabel(b.motif) : String(b.name || "")
    return dir * av.localeCompare(bv)
  })
  return out
}

// The distinct motifs actually present in the given theme list, each
// shaped as {id, label, path} -- same {id, label, path} shape this
// plugin's own sourceFilterList Repeater model (Launcher.qml's
// wallpaperTypeOptions/fileSearchProvider sources) already uses, kept
// here even though the Style filter is now a cycling chip (direct
// follow-up: "the types... moved to the stuff below it like how file
// search has these chips") rather than a dropdown, since
// cycleStyleFilter (ThemeBrowserContent.qml) still needs an ordered
// list of real options to cycle through. Sorted by label, same
// alphabetical-for-browsing reasoning sortThemes uses above.
function styleOptions(themes) {
  var seen = {}
  var out = []
  for (var i = 0; i < themes.length; i++) {
    var motif = themes[i].motif
    if (!motif || seen[motif]) continue
    seen[motif] = true
    out.push({ id: motif, label: motifLabel(motif), path: motif })
  }
  out.sort(function(a, b) { return a.label.localeCompare(b.label) })
  return out
}

// The real installed-theme folder name to check for a given base theme
// + variant -- "-day" only ever applies to the light companion repo's
// own copy (same rule themeFileUrl/themeSlugFor-equivalent logic uses
// elsewhere in this file).
function installedSlugFor(theme, variant) {
  return variant === "light" ? theme.slug + "-day" : theme.slug
}

// Reshaped into the exact same row object shape every other ResultsList
// model in this plugin already uses (id/providerId/icon/label/
// breadcrumb/kind/providerName/score/sectionLabel) -- same convention
// SettingsContent.qml's own sectionRows already documents: ResultRow
// itself never needs to know these came from the theme browser rather
// than a real search provider. label is the real display name; id
// keys off the real slug (stable, unique) rather than the display name
// (two themes could theoretically share a label, slugs never do).
// breadcrumb is the motif's real label (e.g. "Sunset Grid") -- same
// subtitle-beside-the-name treatment the landing list's own Omarchy
// Actions/Ruixen rows already get from ResultRow.qml, direct follow-up
// ("similar to ruixen launcher home... a small subtitle after the
// theme name for the style"). Only rendered when the caller's own
// ResultsList/ResultRow is NOT in filesMode -- see
// ThemeBrowserContent.qml's own comment on why this extension
// deliberately isn't.
//
// icon/iconColor -- direct follow-up ("lets make the icons useful, so
// it is surface if not installed, but if the theme is installed so can
// it be theme green"). Same fa-paint-brush glyph the landing list's own
// Themes extension row uses (Launcher.qml's themeBrowserRow -- U+F1FC;
// fa-palette, U+F53F, tried first, rendered as a broken/missing glyph
// live, confirmed not just assumed before settling on this one), so
// the two read as the same feature. Muted when the variant currently
// being previewed (installedSlugs/variant) isn't installed under
// ~/.config/omarchy/themes, or tinted with THIS theme's own real green
// (from its own colors, already in memory -- no extra fetch) once it
// is -- plain installed/not-installed is a color difference on the
// same glyph, not a shape one, same as this project's own existing
// semantic-good/bad status-color conventions elsewhere (see
// ruixen.power/ruixen.peripherals's own battery coloring) -- just
// without a `bar` facade available in here to read that convention's
// own token through, so this falls back to a plain hardcoded green
// when a theme's own colors.green is somehow missing.
//
// Direct follow-up once install actually shipped: "icons color isnt
// enough to tell" installed apart from the one theme actually active
// right now -- both read as the same green brush. currentSlug (the
// REAL active theme's own installedSlugFor-shaped name, read from
// ~/.local/state/omarchy/current/theme.name) gets its own distinct
// glyph (fa-check-circle, U+F058 -- confirmed rendering live before
// settling on it, same discipline as the brush swap above) instead of
// another color on the same brush, so "installed" and "the one that's
// actually on right now" stay tellable apart at a glance, not just on
// close inspection of a color. installedSlugs is a plain {slug: true}
// set (ThemeBrowserContent.qml's own refreshInstalledThemes result);
// mutedColor is the caller's real muted token (root.muted), plumbed
// through since this is a pure JS file with no QML property access of
// its own.
function themeRows(themes, installedSlugs, variant, mutedColor, currentSlug) {
  var rows = []
  for (var i = 0; i < themes.length; i++) {
    var theme = themes[i]
    var slug = installedSlugFor(theme, variant)
    var installed = !!(installedSlugs && installedSlugs[slug])
    var isCurrent = !!currentSlug && currentSlug === slug
    var themeGreen = (theme.colors && theme.colors.green) || "#3ecf5b"
    rows.push({
      id: "theme:" + theme.slug,
      providerId: "theme-browser-entry",
      icon: isCurrent ? "" : "",
      iconColor: installed ? themeGreen : mutedColor,
      label: theme.name,
      breadcrumb: motifLabel(theme.motif),
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

// --- Stage 2: install -------------------------------------------------
//
// Direct follow-up ("so when i press enter it installs it right and
// then switches to it too, if already installed it works as a theme
// switcher?"). Confirmed directly against a real install: each theme's
// own colors object (already parsed from assets/themes.js) is a 1:1
// match for omarchy's own colors.toml schema, but the repo ALSO
// publishes a real colors.toml directly per theme (plus icons.theme,
// preview.png, and a backgrounds/ folder), so installing just curls
// those real files straight into ~/.config/omarchy/themes/<slug>/
// rather than re-serializing the JSON ourselves -- the theme's own
// hyprland_active_border/hyprland_inactive_border fields, which
// assets/themes.js doesn't carry at all, only exist in the real file.
// omarchy-theme-set (Omarchy's own, already-installed CLI) then does
// everything a real theme switch needs -- background selection,
// Hyprland/terminal/GTK/VSCode retheme, shell IPC -- so this never
// reimplements any of that, only stages the files it reads.

// Same character class omarchy-theme-install itself enforces on a
// theme name before using it as a directory -- applied here BEFORE any
// path is built from a theme's own `slug` field, which originates from
// a third-party network response (assets/themes.js) rather than
// anything the user typed. Fails closed (false) on anything else,
// including the empty string, so a compromised/malformed feed can
// never turn into a path-traversal write under ~/.config/omarchy/themes.
function isSafeThemeSlug(slug) {
  return /^[a-z0-9_][a-z0-9._+-]*$/.test(String(slug || ""))
}

// GitHub's Contents API for a theme's own backgrounds/ folder -- the
// one piece per theme that assets/themes.js never carries at all (it's
// real image files, not data), so unlike colors.toml/icons.theme/
// preview.png (flat, predictable gh-pages paths -- see themeFileUrl)
// this needs an actual directory listing first to learn each
// background's real filename (confirmed directly: they're index-
// prefixed and differ per theme, e.g. "1-sunset-grid.jpg", never a
// fixed name this could guess). One listing call per actual INSTALL
// (never during browsing), well inside GitHub's unauthenticated rate
// limit for how infrequently a real install happens.
function backgroundsApiUrl(slug, variant) {
  var repo = variant === "light" ? "100-themes-day" : "100-themes"
  return "https://api.github.com/repos/bjarneo/" + repo + "/contents/" + slug + "/backgrounds"
}

// Parses that listing into just {name, url} pairs this needs to
// download each file -- fails closed to an empty list (no backgrounds
// to fetch, not a fatal install error) for a 404 (a theme with no
// backgrounds/ folder at all -- the API returns a plain {message:
// "Not Found"} object, not an array, same "valid JSON but not an
// array" shape parseThemesJs already guards against), malformed JSON,
// or an entry missing its own download_url (a nested directory inside
// backgrounds/, say, which this never expects but shouldn't choke on).
function parseBackgroundsListing(jsonText) {
  var data
  try { data = JSON.parse(jsonText) } catch (e) { return [] }
  if (!Array.isArray(data)) return []
  var out = []
  for (var i = 0; i < data.length; i++) {
    var item = data[i]
    if (item && item.type === "file" && item.name && item.download_url) out.push({ name: item.name, url: item.download_url })
  }
  return out
}
