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
// Omits fields with no value (track/index/total all missing on a
// stopped, empty player), so every read here has its own default
// rather than assuming the field exists. Read-only status for the
// right panel's "Now Playing" line -- the notch's own MPRIS-driven
// media controls are the real transport surface (cliamp registers
// org.mpris.MediaPlayer2.cliamp the moment it starts, confirmed live),
// so this extension never needs play/pause/volume state, only what's
// on air right now.
function parseStatus(text) {
  try {
    var parsed = JSON.parse(String(text || ""))
    if (!parsed || parsed.ok !== true) return null
    var track = parsed.track || null
    return {
      state: parsed.state || "stopped",
      title: track ? (track.title || "") : "",
      artist: track ? (track.artist || "") : "",
      station: track ? (track.station || "") : ""
    }
  } catch (e) {
    return null
  }
}

// Cliamp's own IPC never returns station metadata as separate fields
// (no bitrate/country/art -- confirmed live, including a direct check
// of its MPRIS Metadata, which only ever carries trackid/title/url for
// a radio stream). What's embedded in a catalog/search row's own name
// string -- "MANGORADIO [128k] · Germany" -- is genuinely all
// there is, so this just pulls it back apart for the right panel
// instead of fabricating fields cliamp doesn't provide.
function parseStationMeta(label) {
  var raw = String(label || "")
  var country = ""
  var rest = raw
  var dotIdx = raw.lastIndexOf(" · ")
  if (dotIdx >= 0) {
    country = raw.slice(dotIdx + 3)
    rest = raw.slice(0, dotIdx)
  }
  var bitrate = ""
  var bracket = rest.match(/\[(\d+k)\]/)
  if (bracket) {
    bitrate = bracket[1]
    rest = (rest.slice(0, bracket.index) + rest.slice(bracket.index + bracket[0].length)).trim()
  }
  return { name: rest, country: country, bitrate: bitrate }
}
