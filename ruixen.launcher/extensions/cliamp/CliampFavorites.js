// Our own favorite + "last played" layer for Cliamp Radio, entirely
// independent of cliamp's own IPC favorite system -- direct follow-up:
// "in the search result i can only play it, is there a way to tab to
// play and favorite it as well". Investigated live first: cliamp's own
// provider.favorite only ever takes {provider, playlist} -- a catalog
// id -- and provider.search's raw results carry nothing but
// title/path, no id of any kind (confirmed against the raw JSON and
// cliamp's own `remote capabilities` listing). Playing a search hit via
// track.play doesn't hand back a reusable id either (status's own
// "playlist" field afterward is just whatever was playing before,
// unrelated to the track just played -- confirmed live). So cliamp's
// own favorite system can never reach a search hit; this plugin keeps
// its own small JSON layer instead; see CliampContent.qml's own header
// for why that replaces cliamp's native favorites entirely rather than
// running two different "favorite" concepts side by side.
//
// Keyed by station NAME, not a catalog id or URL -- provider.catalog
// itself never exposes a station's stream URL either (confirmed live,
// just id/name/favoritable/provider), so name is the only identity
// genuinely stable across both catalog browse and search for the same
// station. Same {id: stat} shape and Object.assign immutable-update
// convention LauncherFrecency.js already uses for this plugin's other
// local JSON state, so a QML caller can assign the result straight to
// a property and get real change notification.

// cliamp's own "★ " favorite-row prefix, stripped so a station found
// via catalog (which may still carry it, from cliamp's own persisted
// favorites file) and the same station found via search resolve to
// the same key.
function favoriteKey(name) {
  var s = String(name || "")
  if (s.indexOf("★ ") === 0) s = s.slice(2)
  return s.trim()
}

function isFavorite(stats, name) {
  var entry = (stats && stats[favoriteKey(name)]) || null
  return !!(entry && entry.favorite)
}

function lastPlayedAt(stats, name) {
  var entry = (stats && stats[favoriteKey(name)]) || null
  return (entry && entry.lastPlayedAt) || 0
}

function toggleFavorite(stats, name) {
  var key = favoriteKey(name)
  if (key === "") return stats
  var next = Object.assign({}, stats)
  var prev = next[key] || { favorite: false, lastPlayedAt: 0 }
  next[key] = { favorite: !prev.favorite, lastPlayedAt: prev.lastPlayedAt || 0 }
  return next
}

function recordPlayed(stats, name) {
  var key = favoriteKey(name)
  if (key === "") return stats
  var next = Object.assign({}, stats)
  var prev = next[key] || { favorite: false, lastPlayedAt: 0 }
  next[key] = { favorite: prev.favorite || false, lastPlayedAt: Date.now() }
  return next
}

// Takes whatever CliampStations.bucketCatalog/searchRows already
// shaped (name/id/label fields, no favorite concept of its own) and
// layers favorite/lastPlayedAt on top from OUR state, plus the
// star-vs-note icon that used to come from cliamp's own p.favorite.
// Catalog rows split into a "Favorites" section (ahead of "Stations"),
// same grouping this panel already had -- just driven by our own data
// now. Search rows stay one "Search Results" section (a favorited hit
// splitting into its own section there would just fragment a single
// query's results for little benefit), the star icon is the only
// visible difference.
function applyFavoriteState(rows, stats, accentColor, searchMode) {
  var list = rows || []
  var favorites = []
  var rest = []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var row = list[i]
    var favorite = isFavorite(stats, row.fullName)
    var next = Object.assign({}, row, {
      favorite: favorite,
      lastPlayedAt: lastPlayedAt(stats, row.fullName),
      icon: favorite ? "" : "",
      iconColor: favorite ? accentColor : ""
    })
    if (searchMode) {
      next.sectionLabel = "Search Results"
      out.push(next)
    } else if (favorite) {
      next.sectionLabel = "Favorites"
      favorites.push(next)
    } else {
      next.sectionLabel = "Stations"
      rest.push(next)
    }
  }
  return searchMode ? out : favorites.concat(rest)
}

// "Just now" / "5m ago" / "3h ago" / "2d ago", a plain date past a
// week -- coarser than the Now Playing card's own live elapsed clock
// (that one answers "how long has this been on", this answers "when
// did I last listen"), minutes not seconds, no live ticking needed.
function formatLastPlayed(epochMs) {
  if (!epochMs) return ""
  var deltaMs = Math.max(0, Date.now() - epochMs)
  var mins = Math.floor(deltaMs / 60000)
  if (mins < 1) return "Just now"
  if (mins < 60) return mins + "m ago"
  var hours = Math.floor(mins / 60)
  if (hours < 24) return hours + "h ago"
  var days = Math.floor(hours / 24)
  if (days < 7) return days + "d ago"
  var d = new Date(epochMs)
  var months = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
  return months[d.getMonth()] + " " + d.getDate() + ", " + d.getFullYear()
}
