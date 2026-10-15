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

// trackPath, when the caller has one (a search-hit row always does,
// a catalog row never does -- it only has a stationId, which isn't
// stable enough across daemon restarts to store), is kept so a
// favorite that only ever exists via search can still be synthesized
// into a playable row later (see applyFavoriteState below) -- direct
// report: favorited "Nightride FM - Datawave" (search-only, cliamp's
// own curated catalog never carries it at all, confirmed live) never
// showed up in Favorites, because there was no catalog row for it
// to attach to and nothing to play it back with if there had been.
function toggleFavorite(stats, name, trackPath) {
  var key = favoriteKey(name)
  if (key === "") return stats
  var next = Object.assign({}, stats)
  var prev = next[key] || { favorite: false, lastPlayedAt: 0, trackPath: "" }
  next[key] = {
    favorite: !prev.favorite,
    lastPlayedAt: prev.lastPlayedAt || 0,
    trackPath: trackPath || prev.trackPath || ""
  }
  return next
}

function recordPlayed(stats, name, trackPath) {
  var key = favoriteKey(name)
  if (key === "") return stats
  var next = Object.assign({}, stats)
  var prev = next[key] || { favorite: false, lastPlayedAt: 0, trackPath: "" }
  next[key] = {
    favorite: prev.favorite || false,
    lastPlayedAt: Date.now(),
    trackPath: trackPath || prev.trackPath || ""
  }
  return next
}

// Takes whatever CliampStations.bucketCatalog/searchRows/
// parseBundledPlaylist already shaped (name/id/label fields, no
// favorite concept of its own) and layers favorite/lastPlayedAt on top
// from OUR state, plus the star/headphones/globe icon that used to come
// from cliamp's own p.favorite. Non-search rows split into three
// sections: "Favorites" (any favorited row, catalog or bundled alike)
// ahead of "Stations" (cliamp's own bundled bouquet, row.bundled --
// these are named, curated stations: Lofi, Meditative, Omarchy, the
// NCS family) ahead of "Catalogues" (the plain world radio-browser.info
// list, everything else) -- direct correction: "the stations are lofi
// meditative etc, the catalogues are... everything else", the exact
// opposite of an earlier pass's own labeling. Rows arrive already
// ordered bundled-then-catalog (see CliampContent.qml's own rows
// pipeline), so each section's rows stay contiguous once favorites
// are pulled out -- required for ResultsList's own section.property
// grouping to render one header per section rather than re-opening it
// every time the label flips back. Search rows stay one "Search
// Results" section (a favorited hit splitting into its own section
// there would just fragment a single query's results for little
// benefit) -- a search hit never carries row.bundled, so it reads as a
// Catalogues-style globe row there, same as it would in the normal list.
//
// Direct follow-up ("can you give them a diffirent icons then stations
// in catalogues"): a non-favorite row's icon used to be the same plain
// music note regardless of section -- headphones for a Stations row
// (row.bundled), a globe for a Catalogues one, so the two sections read
// apart at a glance even before the section header itself scrolls into
// view. Favorite always wins (the star), same as before.
function applyFavoriteState(rows, stats, accentColor, searchMode) {
  var list = rows || []
  var favorites = []
  var rest = []
  var out = []
  var seenFavoriteKeys = {}
  for (var i = 0; i < list.length; i++) {
    var row = list[i]
    var favorite = isFavorite(stats, row.fullName)
    if (favorite) seenFavoriteKeys[favoriteKey(row.fullName)] = true
    var next = Object.assign({}, row, {
      favorite: favorite,
      lastPlayedAt: lastPlayedAt(stats, row.fullName),
      icon: favorite ? "" : (row.bundled ? "" : ""),
      iconColor: favorite ? accentColor : ""
    })
    if (searchMode) {
      next.sectionLabel = "Search Results"
      out.push(next)
    } else if (favorite) {
      next.sectionLabel = "Favorites"
      favorites.push(next)
    } else {
      next.sectionLabel = row.bundled ? "Stations" : "Catalogues"
      rest.push(next)
    }
  }

  // A favorite that never showed up in this catalog fetch at all --
  // direct report: favoriting a search-only station (cliamp's own
  // curated catalog never carries it, confirmed live) "shows the
  // favorite icon but not showing up on radio home top list", since
  // there was no catalog row for it to attach favorite state to.
  // Synthesized here instead, straight from what favoriting/playing it
  // already recorded -- same track.play path playSelected() already
  // uses for any other search-hit row, so it's genuinely playable
  // from Favorites, not just a dead entry with a star on it.
  if (!searchMode) {
    for (var key in stats) {
      if (!stats[key] || !stats[key].favorite || seenFavoriteKeys[key]) continue
      favorites.push({
        providerId: "cliamp-track",
        trackTitle: key,
        trackPath: stats[key].trackPath || "",
        label: key,
        fullName: key,
        breadcrumb: "",
        kind: "",
        favorite: true,
        lastPlayedAt: stats[key].lastPlayedAt || 0,
        icon: "",
        iconColor: accentColor,
        sectionLabel: "Favorites"
      })
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
