// Pure data-shaping for the Cliamp Radio extension. CliampContent.qml owns
// every Process/IPC call and all real state; these just turn cliamp's raw
// IPC JSON into the row shape ResultsList/ResultRow (filesMode: true)
// already expects elsewhere in this plugin (icon/label/sectionLabel), same
// split ClipboardHistory.js already uses for its own entries.

// cliamp prefixes a favorited catalog entry's own name with "★ " --
// stripped here so the row's real label never double-stars (the star
// becomes this row's icon/iconColor instead, same favorite-indicator
// convention as this launcher's other starred/dotted rows).
function stripStar(name) {
  var s = String(name || "")
  return s.indexOf("★ ") === 0 ? s.slice(2) : s
}

// provider.catalog (radio) returns the curated station list PLUS a
// duplicate "f:<n>" entry for every favorited station already present
// under its own "c:<n>" id -- both carry the same starred name. Kept to
// one row per station (favorite id wins, since it's cliamp's own stable
// favorite identity -- see radio.md) rather than showing the same
// station twice.
function bucketCatalog(playlists, accentColor) {
  var seen = {}
  var favorites = []
  var stations = []
  var list = playlists || []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    var name = stripStar(p.name)
    if (seen[name]) continue
    seen[name] = true
    var favorite = !!p.favorite || String(p.name || "").indexOf("★") === 0
    var row = {
      providerId: "cliamp-station",
      stationId: p.id,
      label: name,
      icon: favorite ? "" : "",
      iconColor: favorite ? accentColor : undefined,
      favorite: favorite,
      favoritable: !!p.favoritable,
      sectionLabel: favorite ? "Favorites" : "Stations"
    }
    if (favorite) favorites.push(row)
    else stations.push(row)
  }
  return favorites.concat(stations)
}

// provider.search results are raw tracks (title/path), not catalog
// playlist ids -- cliamp has no "favorite a search hit" operation, so
// these rows are play-only (track.play, see CliampContent.qml).
function searchRows(tracks) {
  var list = tracks || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var t = list[i]
    out.push({
      providerId: "cliamp-track",
      trackTitle: t.title || "",
      trackPath: t.path || "",
      label: t.title || t.path || "Unknown station",
      icon: "",
      favoritable: false,
      sectionLabel: "Search Results"
    })
  }
  return out
}

// `cliamp remote call <op> --params '...' --wait` prints one JSON
// envelope on success, but a FAILED job prints a plain text line
// instead (confirmed live: "job failed (internal_error): operation
// failed (invalid catalog index)") -- not JSON at all. Both shapes
// collapse to the same { ok, result|error } here so every caller has
// one failure path to check, not two.
function parseJobResult(text) {
  var raw = String(text || "").trim()
  try {
    var parsed = JSON.parse(raw)
    if (parsed && parsed.ok && parsed.job && parsed.job.state === "succeeded" && parsed.job.result)
      return { ok: true, result: parsed.job.result }
    return { ok: false, error: (parsed && parsed.error) || raw || "cliamp request failed" }
  } catch (e) {
    return { ok: false, error: raw || "cliamp request failed" }
  }
}

// `cliamp status --json` -- plain CLI, not the remote-call envelope.
// Omits fields with no value (track/volume/position/index all missing
// on a stopped, empty player), so every read here has its own default
// rather than assuming the field exists.
function parseStatus(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (!parsed || parsed.ok !== true) return null
    var track = parsed.track || null
    return {
      state: parsed.state || "stopped",
      title: track ? (track.title || "") : "",
      artist: track ? (track.artist || "") : "",
      station: track ? (track.station || "") : "",
      volume: typeof parsed.volume === "number" ? parsed.volume : null,
      index: typeof parsed.index === "number" ? parsed.index : -1,
      total: typeof parsed.total === "number" ? parsed.total : 0
    }
  } catch (e) {
    return null
  }
}
