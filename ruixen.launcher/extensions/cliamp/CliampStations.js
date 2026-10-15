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

// Drops the " · <Country>" suffix cliamp's own catalog/search names
// carry -- direct follow-up: the list row should read as station name
// + bitrate only ("MANGORADIO [128k]"), country stays available in the
// right panel's own dedicated field (see CliampStationPanel.qml, which
// parses it back out of a row's own fullName) instead of cluttering
// every row in a compact list.
function stripCountry(name) {
  var s = String(name || "")
  var dotIdx = s.lastIndexOf(" · ")
  return dotIdx >= 0 ? s.slice(0, dotIdx) : s
}

// provider.catalog (radio) returns the curated station list PLUS a
// duplicate "f:<n>" entry for every station cliamp's OWN favorites
// file already has under its own "c:<n>" id -- both carry the same
// name. Kept to one row per station (first occurrence wins; both ids
// load the same station either way) rather than showing it twice. No
// favorite concept of its own anymore -- CliampFavorites.
// applyFavoriteState layers favorite/lastPlayedAt/icon on afterward
// (see CliampContent.qml's own header for why this plugin keeps its
// own favorite layer instead of cliamp's native one).
//
// "l:<n>" entries (one exists today: "l:0"/"cliamp radio") are skipped
// entirely -- that's cliamp's own bundled multi-station bouquet, but
// provider.tracks only ever hands back ONE track for it whose path is
// itself an M3U URL (confirmed live), never the individual stations
// inside. parseBundledPlaylist below fetches and expands that M3U
// directly instead, so the real stations it contains (Lofi, Omarchy,
// the NCS family, etc.) show up as their own rows rather than one dead
// "cliamp radio" entry that can't actually be played station-by-station
// from here.
function bucketCatalog(playlists) {
  var seen = {}
  var out = []
  var list = playlists || []
  for (var i = 0; i < list.length; i++) {
    var p = list[i]
    if (String(p.id || "").indexOf("l:") === 0) continue
    var name = stripStar(p.name)
    if (seen[name]) continue
    seen[name] = true
    out.push({
      providerId: "cliamp-station",
      stationId: p.id,
      label: stripCountry(name),
      fullName: name,
      // breadcrumb/kind stay "" rather than undefined -- filesMode:
      // true hides both in ResultRow, but their own text bindings
      // still evaluate regardless of visible, and ResultRow.qml
      // otherwise logs "Unable to assign [undefined] to QString" for
      // every row (confirmed live). Same empty-string convention
      // ThemeCatalog.js's own rows already use for the identical
      // reason.
      breadcrumb: "",
      kind: ""
    })
  }
  return out
}

// Distinct countries present in the current catalog fetch, sorted
// alphabetically -- the only pool of country data cliamp genuinely
// has. Direct follow-up: a Country dropdown in the search row's own
// top-right spot (replacing the Enter-key hint there, same control
// Wallpapers'/Theme Browser's own "All Types"/"All" dropdowns already
// use), rather than a full chip row -- country would be the only
// dimension here, unlike the theme browser's own Collection+Styles.
// A station with no country at all (not every curated entry has one)
// is simply excluded from the option list -- there's no sensible
// catch-all bucket for "unknown" to filter by.
function countryOptions(playlists) {
  var list = playlists || []
  var seen = {}
  var out = []
  for (var i = 0; i < list.length; i++) {
    var meta = parseStationMeta(stripStar(list[i].name || ""))
    if (meta.country === "" || seen[meta.country]) continue
    seen[meta.country] = true
    out.push(meta.country)
  }
  out.sort()
  return out
}

// Keeps only rows whose own parsed country matches -- "" (the
// dropdown's own "All Countries" sentinel) is a no-op. Only ever
// called against catalog rows: provider.search results never carry a
// country suffix at all (confirmed live, see searchRows' own header
// below), so CliampContent.qml never applies this while a search
// query is active -- there would be nothing for it to match against.
function filterByCountry(rows, country) {
  if (!country) return rows
  var list = rows || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    if (parseStationMeta(list[i].fullName).country === country) out.push(list[i])
  }
  return out
}

// cliamp's own curated station bouquet, fetched and expanded straight
// from its M3U rather than through cliamp's IPC -- see bucketCatalog's
// own comment above for why. Standard M3U shape: a "#EXTINF:-1,<Title>"
// line immediately followed by the stream URL on the next line; any
// other "#"-prefixed line (just "#EXTM3U" here) is skipped. Same
// cliamp-track row shape searchRows below already produces, so these
// play/favorite through the exact same path as a search hit -- no
// stationId of their own, just a title + a playable URL. The `bundled`
// flag is what lets CliampFavorites.applyFavoriteState put these in
// their own "Stations" section instead of lumping them in with the
// plain world-radio "Catalogues" list -- direct correction: "make it
// Favorites Stations and Catalogues as the groups", three sections,
// not two (an earlier pass here had Stations/Catalogues backwards from
// that correction too -- CliampFavorites.js's own header comment
// already carries the fixed version, this one just hadn't caught up).
function parseBundledPlaylist(text) {
  var lines = String(text || "").split("\n")
  var out = []
  var pendingTitle = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line.indexOf("#EXTINF:") === 0) {
      var comma = line.indexOf(",")
      pendingTitle = comma >= 0 ? line.slice(comma + 1).trim() : ""
      continue
    }
    if (line === "" || line.indexOf("#") === 0) continue
    if (pendingTitle !== "") {
      out.push({
        providerId: "cliamp-track",
        bundled: true,
        trackTitle: pendingTitle,
        trackPath: line,
        label: pendingTitle,
        fullName: pendingTitle,
        breadcrumb: "",
        kind: ""
      })
    }
    pendingTitle = ""
  }
  return out
}

// provider.search results are raw tracks (title/path only, no id of
// any kind -- confirmed live). Same no-favorite-concept-of-its-own
// shape as bucketCatalog above; CliampFavorites.applyFavoriteState
// layers favorite/lastPlayedAt/icon on both the same way.
function searchRows(tracks) {
  var list = tracks || []
  var out = []
  for (var i = 0; i < list.length; i++) {
    var t = list[i]
    var fullName = t.title || t.path || "Unknown station"
    out.push({
      providerId: "cliamp-track",
      trackTitle: t.title || "",
      trackPath: t.path || "",
      label: stripCountry(fullName),
      fullName: fullName,
      breadcrumb: "",
      kind: ""
    })
  }
  return out
}

// `cliamp remote call <op> --params '...' --wait` prints one JSON
// envelope on SUCCESS to stdout, but EVERY failure -- "cliamp is not
// running (no socket at ...)" (no daemon at all) just as much as
// "job failed (<kind>): ..." (daemon up, the operation itself errored,
// confirmed live: a stale catalog index, and a real radio-browser.info
// network timeout building the station catalog) -- goes to stderr as a
// plain line, not stdout (confirmed live with stdout/stderr captured
// separately: stdout is empty in both failure cases). A Process bound
// to only `stdout: StdioCollector` therefore sees empty text for every
// failure and can never actually read the error, which is why this
// takes both streams -- stdout tried first for the success envelope,
// stderr read for the error text otherwise.
//
// The two failure shapes still need telling apart (CliampContent.qml
// auto-starts/bails only on the first, never the second -- treating a
// transient network blip the same as "not running" would spawn a
// redundant daemon on the first occurrence and incorrectly bail the
// whole extension on a second one), which is what notRunning encodes.
function parseJobResult(stdoutText, stderrText) {
  var out = String(stdoutText || "").trim()
  if (out !== "") {
    try {
      var parsed = JSON.parse(out)
      if (parsed && parsed.ok && parsed.job && parsed.job.state === "succeeded" && parsed.job.result)
        return { ok: true, result: parsed.job.result }
    } catch (e) {
      // Falls through to the stderr-based error below.
    }
  }
  var err = String(stderrText || "").trim() || out || "cliamp request failed"
  return { ok: false, notRunning: err.indexOf("is not running") >= 0, error: err }
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
      station: track ? (track.station || "") : "",
      // Seconds since this station was tuned in -- confirmed live it
      // climbs monotonically while playing rather than resetting per
      // ICY title change, so it's an honest "how long you've been
      // listening" counter, not a per-song position a continuous radio
      // stream has no real concept of anyway (no duration to show a
      // progress bar against).
      position: typeof parsed.position === "number" ? parsed.position : 0,
      // A global player setting, not per-station -- cliamp reports the
      // active preset here regardless of what's selected in the list,
      // same read path CliampStationPanel's own EQ row uses to show
      // which chip is currently active. "Custom" (hand-tuned bands,
      // not any named preset) is a real value cliamp itself reports,
      // not a failure -- falling back to "Flat" only covers a status
      // read from a build old enough to omit the field entirely.
      eqPreset: parsed.eq_preset || "Flat"
    }
  } catch (e) {
    return null
  }
}

// Flags whichever row matches cliamp's own currently-playing station
// name with playingIndicator -- ResultRow.qml's own opt-in animated
// three-bar equalizer, standing in for the row's usual icon (star or
// plain note). Direct follow-up: "a play icon that shows the station
// that is playing in the left panel instead of the music note too
// when active", then two more rounds on shape/alignment that never
// quite landed, settling on reusing the exact same "something's
// playing" visual the Now Playing avatar already uses elsewhere in
// this panel rather than a third different static indicator. Only
// while actually playing, not paused/stopped -- "when active" was the
// request's own wording, and a row staying marked "playing" while
// cliamp sits paused on it would be misleading; nowPlayingStation is
// passed in already blanked out by the caller for that case rather
// than checked again here, same as CliampStationPanel.qml's own
// "playing" gate. Overrides a favorite's star too, same as everywhere
// else in this panel the currently-audible thing takes precedence
// over the merely-saved one.
//
// Matched through parseStationMeta's own name field, not a raw
// fullName comparison -- confirmed live a catalog row's own name
// ("Dance Wave! [128k] · Hungary") never comes back that way in
// status's station field (just "Dance Wave!", bare), so comparing
// untrimmed fullName would silently never match any catalog row that
// carries a bitrate/country suffix at all.
function markNowPlaying(rows, nowPlayingStation) {
  var list = rows || []
  var target = String(nowPlayingStation || "").trim()
  if (target === "") return list
  var out = []
  for (var i = 0; i < list.length; i++) {
    var row = list[i]
    var cleanName = parseStationMeta(row.fullName).name
    if (cleanName === target) {
      out.push(Object.assign({}, row, { playingIndicator: true }))
    } else {
      out.push(row)
    }
  }
  return out
}

// mm:ss, or h:mm:ss past the first hour -- used for the right panel's
// live-ticking "how long you've been listening" clock (see
// CliampStationPanel.qml), not a real track position/duration since a
// radio stream has neither.
function formatElapsed(totalSeconds) {
  var s = Math.max(0, Math.floor(totalSeconds || 0))
  var h = Math.floor(s / 3600)
  var m = Math.floor((s % 3600) / 60)
  var sec = s % 60
  var mm = h > 0 ? String(m).padStart(2, "0") : String(m)
  var ss = String(sec).padStart(2, "0")
  return h > 0 ? (h + ":" + mm + ":" + ss) : (mm + ":" + ss)
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
