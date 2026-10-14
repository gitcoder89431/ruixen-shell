// Pure helpers for the Theme Browser extension -- browses several of
// bjarneo's community Omarchy theme collections (100-themes, and the
// later coffee/tea/mineral/spice/various collections, each its own
// repo), kept here rather than inline in ThemeBrowserContent.qml so
// this is testable without a running QML engine -- same convention as
// every other *.js file in this plugin (FileSearchRanking.js,
// LauncherHelpers.js, ...).
//
// Each repo publishes its own assets/themes.js: a single static
// `window.THEMES = {...}` object covering every theme's real display
// name, slug, style/category, full colors (already Omarchy's own
// native theme schema, confirmed directly, no TOML parsing needed),
// and ansi set, in one file -- confirmed directly by fetching each
// collection's live gh-pages output and diffing it, not assumed from
// the repo name alone. Fetching this ONE file per collection replaces
// what would otherwise be a GitHub API catalog call plus a separate
// colors.toml fetch per theme: every theme's name/style/colors is
// already in memory the moment this loads, no per-theme network round
// trip needed for any of it (only the actual preview.png/background
// images still need their own per-theme fetch).

// --- Collections ---------------------------------------------------------
//
// All six confirmed directly (gh-pages reachable, same window.THEMES
// shape, same per-theme file layout: colors.toml/icons.theme/
// preview.png/backgrounds/) before being added here -- not assumed
// from "probably the same shape" alone. Two real differences per
// collection, not just the repo name:
//
// - darkKey: which JSON variant key is this collection's own "dark"
//   entry. 100-themes calls it "dark" (and also ships high-contrast/
//   day-high-contrast/oled variants this browser doesn't surface);
//   every later collection calls it "night" instead -- confirmed
//   directly against all five, not assumed from "night" being the
//   obvious name.
// - styleField/styleListField: which per-theme field holds its own
//   style/category, and which top-level field (if any) is this
//   collection's own {key,label} lookup for it. 100-themes ships a
//   flat "motif" string with no lookup of its own (hence MOTIF_LABELS
//   below, a table this file maintains itself against the upstream
//   gallery's own labels). Coffee/tea/mineral/spice ship "cat" plus
//   their own top-level "categories" lookup. various-themes calls the
//   same idea "pattern"/"patterns" instead -- genuinely a different
//   field name, not a typo to normalize away.
var COLLECTIONS = [
  { id: "bjarneo", label: "Bjarneo", repo: "100-themes", darkKey: "dark", styleField: "motif", styleListField: null },
  { id: "coffee", label: "Coffee", repo: "coffee-themes", darkKey: "night", styleField: "cat", styleListField: "categories" },
  { id: "tea", label: "Tea", repo: "tea-themes", darkKey: "night", styleField: "cat", styleListField: "categories" },
  { id: "mineral", label: "Mineral", repo: "mineral-themes", darkKey: "night", styleField: "cat", styleListField: "categories" },
  { id: "spice", label: "Spice", repo: "spice-themes", darkKey: "night", styleField: "cat", styleListField: "categories" },
  { id: "various", label: "Various", repo: "various-themes", darkKey: "night", styleField: "pattern", styleListField: "patterns" }
]

// {id, label} pairs in the order above -- Bjarneo first (the original
// collection, direct request: "the first collection instead of
// calling it 100 themes just call it Bjarneo"), same shape as
// styleOptions' own entries so the Collection chip can reuse the exact
// same cycling-chip pattern Style already uses.
function listCollections() {
  var out = []
  for (var i = 0; i < COLLECTIONS.length; i++) out.push({ id: COLLECTIONS[i].id, label: COLLECTIONS[i].label })
  return out
}

function collectionById(id) {
  for (var i = 0; i < COLLECTIONS.length; i++) {
    if (COLLECTIONS[i].id === id) return COLLECTIONS[i]
  }
  return COLLECTIONS[0]
}

// Real, human motif labels -- not a mechanical title-case of the slug
// itself, several genuinely differ (confirmed directly against
// 100-themes' own gallery page's MOTIFS dict in index.html): "blobs"
// reads as "Light Spots", "depths" as "Deep Water", "pixels" as
// "Pixel Art", "scanlines" as "VHS", "tubes" as "Neon Tubes". All 15
// values that actually appear across the full 100-theme catalog are
// covered here (confirmed directly, not assumed complete). Only
// 100-themes needs this table -- every later collection ships its own
// {key,label} lookup directly in its own themes.js (see
// styleLabelFor), so this is Bjarneo-specific, not a generic fallback
// for every collection.
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

// Builds the {id: label} lookup a collection's own themes.js ships for
// its style field (data.categories / data.patterns, per collection's
// own styleListField) -- null when the collection has no lookup of
// its own (Bjarneo, which uses MOTIF_LABELS instead) or the data
// doesn't actually have that field (fails open to the raw id rather
// than throwing on a malformed/future catalog shape).
function buildStyleLookup(data, collection) {
  if (!collection.styleListField) return null
  var list = data && data[collection.styleListField]
  if (!Array.isArray(list)) return null
  var map = {}
  for (var i = 0; i < list.length; i++) {
    var entry = list[i]
    if (entry && entry.key) map[entry.key] = entry.label || entry.key
  }
  return map
}

function styleLabelFor(collection, lookup, styleId) {
  if (!styleId) return ""
  if (lookup && lookup[styleId]) return lookup[styleId]
  if (!collection.styleListField) return motifLabel(styleId)
  return String(styleId)
}

// Pulls the `window.THEMES = ...` literal out of a fetched
// assets/themes.js file's raw text and parses it as JSON -- the file
// is pure, safe-to-JSON-parse data (a plain array/object literal, no
// function calls or other real JS executed), confirmed by reading it
// directly rather than assumed. Malformed/empty input (a network
// failure's own error body, say) fails closed to an empty list rather
// than throwing.
//
// Two real shapes seen from upstream: a bare array (the original,
// single-variant-per-entry format) and the current grouped
// {variants, themes} object (every theme carries all its own variants
// inline, keyed by each one's own real JSON key -- "dark"/"day" for
// Bjarneo, "night"/"day" for every later collection). The bare-array
// branch is kept only as a defensive fallback for that older shape --
// every collection actually live today uses the grouped one -- and
// never carries collection/variant metadata the way the grouped
// branch does, since there is none to carry.
//
// collection (a COLLECTIONS entry, or null to default to Bjarneo) says
// which JSON key counts as "dark" and which field holds this
// collection's own style/category. previewVariant is "dark" or
// "light" -- the UI's own two-state naming, translated to this
// collection's real dark-equivalent JSON key internally rather than
// assuming every collection calls it "dark" the way Bjarneo does.
function parseThemesJs(text, collection, previewVariant) {
  var m = /window\.THEMES\s*=\s*([\s\S]*?)\s*;?\s*$/.exec(String(text || ""))
  if (!m) return []
  var data
  try {
    data = JSON.parse(m[1])
  } catch (e) {
    return []
  }
  if (Array.isArray(data)) return data
  if (!data || !Array.isArray(data.themes)) return []

  var coll = collection || COLLECTIONS[0]
  var darkKey = coll.darkKey || "dark"
  var wantsLight = previewVariant === "light" || previewVariant === "day"
  var styleLookup = buildStyleLookup(data, coll)

  var out = []
  for (var i = 0; i < data.themes.length; i++) {
    var base = data.themes[i] || {}
    var variants = base.variants || {}
    var dark = variants[darkKey]
    var day = variants.day
    var variant = wantsLight ? day : dark
    if (!variant) continue
    var styleId = base[coll.styleField] || ""
    out.push({
      index: base.index,
      name: variant.name || base.name || "",
      baseName: base.name || "",
      baseSlug: base.slug || "",
      slug: variant.install || "",
      darkSlug: dark ? (dark.install || "") : "",
      daySlug: day ? (day.install || "") : "",
      style: styleId,
      styleLabel: styleLabelFor(coll, styleLookup, styleId),
      icons: variant.icons || base.icons || "",
      colors: variant.colors || {},
      ansi: variant.ansi || [],
      collectionId: coll.id
    })
  }
  return out
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

// collectionId is a real collection id (see COLLECTIONS), or "" for
// "every collection" -- same no-filter-selected sentinel styleFilter's
// own conventions already use.
function filterByCollection(themes, collectionId) {
  if (!collectionId) return themes
  var out = []
  for (var i = 0; i < themes.length; i++) {
    if (themes[i].collectionId === collectionId) out.push(themes[i])
  }
  return out
}

// style is a style/category id (a motif slug for Bjarneo, a cat/
// pattern id for every later collection -- already normalized onto
// theme.style by parseThemesJs, so this never needs to know which),
// or "" for "every style".
function filterByStyle(themes, style) {
  if (!style) return themes
  var out = []
  for (var i = 0; i < themes.length; i++) {
    if (themes[i].style === style) out.push(themes[i])
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
// the same real label styleLabel already carries -- resolved once at
// parse time now, not recomputed here); direction is "asc" or "desc"
// (anything else behaves as "asc", same fail-open-to-the-sane-default
// convention motifLabel's own fallback uses). localeCompare so "Neon
// Wave" vs "Nebula" sorts the same way a human skimming the list would
// expect, not raw UTF-16 code-unit order.
function sortThemes(themes, sortKey, direction) {
  var out = themes.slice()
  var dir = direction === "desc" ? -1 : 1
  out.sort(function(a, b) {
    var av = sortKey === "style" ? String(a.styleLabel || "") : String(a.name || "")
    var bv = sortKey === "style" ? String(b.styleLabel || "") : String(b.name || "")
    return dir * av.localeCompare(bv)
  })
  return out
}

// The distinct styles actually present in the given theme list, each
// shaped as {id, label, path} -- same {id, label, path} shape this
// plugin's own sourceFilterList Repeater model (Launcher.qml's
// wallpaperTypeOptions/fileSearchProvider sources) already uses, kept
// here even though the Style filter is now a cycling chip (direct
// follow-up: "the types... moved to the stuff below it like how file
// search has these chips") rather than a dropdown, since
// cycleStyleFilter (ThemeBrowserContent.qml) still needs an ordered
// list of real options to cycle through. Reads theme.style/styleLabel
// directly -- both already resolved per-collection by parseThemesJs,
// so this never needs to know whether a given row came from Bjarneo's
// motif or some other collection's cat/pattern field. Sorted by label,
// same alphabetical-for-browsing reasoning sortThemes above uses.
function styleOptions(themes) {
  var seen = {}
  var out = []
  for (var i = 0; i < themes.length; i++) {
    var id = themes[i].style
    if (!id || seen[id]) continue
    seen[id] = true
    out.push({ id: id, label: themes[i].styleLabel || String(id), path: id })
  }
  out.sort(function(a, b) { return a.label.localeCompare(b.label) })
  return out
}

// The real installed-theme folder name for a given theme + variant --
// a plain lookup now, not a guess: darkSlug/daySlug are each resolved
// directly from that variant's own real `install` field at parse time
// (see parseThemesJs), so this needs no per-collection suffix rule of
// its own. Real bug this replaces: the old version assumed every
// collection's dark variant installs as the bare slug and its light
// variant as that same slug + "-day" -- true for Bjarneo (dark:
// "synthwave", day: "synthwave-day"), but every later collection
// suffixes BOTH variants explicitly (night: "espresso-solo-night",
// day: "espresso-solo-day"), which the old bare-slug-plus-suffix trick
// would have silently mangled.
function installedSlugFor(theme, variant) {
  return variant === "light" ? (theme.daySlug || "") : (theme.darkSlug || "")
}

// Reshaped into the exact same row object shape every other ResultsList
// model in this plugin already uses (id/providerId/icon/label/
// breadcrumb/kind/providerName/score/sectionLabel) -- same convention
// SettingsContent.qml's own sectionRows already documents: ResultRow
// itself never needs to know these came from the theme browser rather
// than a real search provider. label is the real display name; id
// keys off the real slug (stable, unique) rather than the display name
// (two themes could theoretically share a label, slugs never do).
// breadcrumb is the theme's own real style label (e.g. "Sunset Grid",
// or "Espresso drinks" for a Coffee theme) -- same subtitle-beside-
// the-name treatment the landing list's own Omarchy Actions/Ruixen
// rows already get from ResultRow.qml, direct follow-up ("similar to
// ruixen launcher home... a small subtitle after the theme name for
// the style"). Only rendered when the caller's own ResultsList/
// ResultRow is NOT in filesMode -- see ThemeBrowserContent.qml's own
// comment on why this extension deliberately isn't.
//
// icon/iconColor -- direct follow-up ("lets make the icons useful, so
// it is surface if not installed, but if the theme is installed so can
// it be theme green"). Same fa-paint-brush glyph the landing list's own
// Themes extension row uses (ExtensionRegistry.js's theme-browser entry
// -- U+F1FC; fa-palette, U+F53F, tried first, rendered as a broken/
// missing glyph live, confirmed not just assumed before settling on
// this one), so the two read as the same feature. Muted when the variant currently
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
      breadcrumb: theme.styleLabel || "",
      kind: "",
      providerName: "",
      score: 0,
      sectionLabel: "Themes"
    })
  }
  return rows
}

// --- Stage 1: browse ----------------------------------------------------
//
// gh-pages static file URLs -- no git, no API rate limit, the same
// access path 100-themes' own README documents
// (https://bjarneo.github.io/100-themes/synthwave/colors.toml),
// confirmed directly against that README's own aether:// example
// rather than guessed, and confirmed the same pattern holds for every
// later collection by fetching each one's own live gh-pages output
// directly. Each repo serves its own gh-pages site under its own name.
function themesDataUrl(collection) {
  var coll = collection || COLLECTIONS[0]
  return "https://bjarneo.github.io/" + coll.repo + "/assets/themes.js"
}

// baseSlug is the theme's own real repo folder name (theme.baseSlug,
// e.g. "synthwave" or "espresso-solo") -- NOT an installed slug like
// "espresso-solo-night", which only Omarchy's local folder uses and
// has no fixed relationship to the upstream path once a collection
// suffixes its dark variant too (see installedSlugFor's own comment).
// variant is "dark"/"light"; the real upstream folder name under that
// base (collection.darkKey, or "day") is resolved from the collection
// config, not guessed from the installed slug's own suffix the way
// this used to work.
function themeFileUrl(collection, baseSlug, variant, relativePath) {
  var coll = collection || COLLECTIONS[0]
  var key = variant === "light" ? "day" : (coll.darkKey || "dark")
  return "https://raw.githubusercontent.com/bjarneo/" + coll.repo + "/main/"
    + baseSlug + "/" + key + "/" + relativePath
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
function backgroundsApiUrl(collection, baseSlug, variant) {
  var coll = collection || COLLECTIONS[0]
  var key = variant === "light" ? "day" : (coll.darkKey || "dark")
  return "https://api.github.com/repos/bjarneo/" + coll.repo + "/contents/"
    + baseSlug + "/" + key + "/backgrounds"
}

// Same character class isSafeThemeSlug enforces on a theme's own slug,
// applied here too -- a real gap, caught on review: unlike the slug,
// which gets checked before it's ever used to build a path, a
// background's own `name` was going straight from this API response
// into "backgrounds/" + name with nothing standing in the way of a
// "../../colors.toml"-shaped entry writing outside that folder
// entirely. No reason the two should be held to different standards --
// both are a third-party network response about to become part of a
// filesystem path.
function isSafeBackgroundFilename(name) {
  return /^[A-Za-z0-9_][A-Za-z0-9._-]*$/.test(String(name || ""))
}

// Parses that listing into just {name, url} pairs this needs to
// download each file -- fails closed to an empty list (no backgrounds
// to fetch, not a fatal install error) for a 404 (a theme with no
// backgrounds/ folder at all -- the API returns a plain {message:
// "Not Found"} object, not an array, same "valid JSON but not an
// array" shape parseThemesJs already guards against), malformed JSON,
// an entry missing its own download_url (a nested directory inside
// backgrounds/, say, which this never expects but shouldn't choke on),
// or an entry whose own name fails isSafeBackgroundFilename.
function parseBackgroundsListing(jsonText) {
  var data
  try { data = JSON.parse(jsonText) } catch (e) { return [] }
  if (!Array.isArray(data)) return []
  var out = []
  for (var i = 0; i < data.length; i++) {
    var item = data[i]
    if (item && item.type === "file" && item.name && item.download_url && isSafeBackgroundFilename(item.name))
      out.push({ name: item.name, url: item.download_url })
  }
  return out
}
