// Pinned Bjarneo Themes rows -- direct follow-up ("i noticed we have no
// tab support for the left panel. can we do it anyways for consistency,
// we can do Install Pin and Uninstall if installed for the tab"). Much
// closer to CliampFavorites.js's own favorite layer than to
// ClipboardHistory.js's own pin layer: a theme catalog entry is
// permanent (never trimmed out from under it the way a clipboard entry
// or a live history index can be), so there's no "survive deletion"
// case to design around here -- this is purely a pin-to-the-top
// preference, so the stored value is a plain boolean, not a snapshot of
// the theme's own data.
//
// Keyed by collectionId + ":" + baseSlug, not theme.slug (= the dark
// variant's own real install folder name) -- same compound-key
// precedent ThemeBrowserContent.qml's own lightThemesBySlug already
// uses, for the same reason: install slugs are never confirmed unique
// ACROSS different collections, only within one. One key per theme
// regardless of which variant (dark/light) is currently being
// previewed -- pinning is a property of the theme, not of whichever
// variant chip happens to be selected when you press it.
function pinKey(theme) {
  return theme ? (theme.collectionId + ":" + theme.baseSlug) : ""
}

function isPinned(pinStats, theme) {
  var k = pinKey(theme)
  return !!(k && pinStats && pinStats[k])
}

function togglePinned(pinStats, theme) {
  var k = pinKey(theme)
  if (k === "") return pinStats
  var next = Object.assign({}, pinStats)
  if (next[k]) delete next[k]
  else next[k] = true
  return next
}
