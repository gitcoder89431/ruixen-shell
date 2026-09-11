import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Provider: matches INSIDE file contents (ripgrep), not filenames --
// the "search by context" follow-up to FileSearchProvider's own
// filename-only matching. A separate file, not folded into
// FileSearchProvider, because the underlying tool and result shape are
// both genuinely different (a path + line number + line text, not just
// a path) -- same "one new file, small isolated addition" convention
// every other provider here already follows.
//
// Results from this provider and FileSearchProvider's own are merged
// into ONE list by Launcher.qml (both tagged "Search Files"), not a
// separate mode/fallback -- direct design call: score band below (see
// contentMatchScore) keeps every content match ranked below every
// filename match, so a query with real filename hits reads exactly as
// before, and a query with NONE falls through to content matches
// instead of "No Results" -- reducing that dead end without ever
// skipping a real content search to get there (accuracy stays whole;
// this is a ranking decision, not a "only search content when
// filename hits are sparse" shortcut, which would have meant this
// provider sometimes just not running at all).
//
// homeDir/extraRoots are NOT independently discovered here -- Launcher.qml
// binds both straight from FileSearchProvider's own already-discovered
// values (same refreshRoots() call, same mounted-drive list), so there's
// one source of truth for "what counts as a search root," not two
// mount-discovery implementations that could disagree.
Item {
  id: root

  readonly property string providerName: "File Contents"
  readonly property bool ready: true

  property string query: ""
  property string sourceFilter: ""
  property string homeDir: ""
  property var extraRoots: []

  property string pendingQuery: ""
  property var lastResults: []

  // Confirmed live (this exact query -- rg's own glob semantics differ
  // from fd's): a bare directory name ("go") excludes it at ANY depth,
  // gitignore-style, but a multi-segment pattern ("go/pkg/mod" or
  // "go/pkg/mod/**", fd's own excludeDirs entry) silently matches
  // NOTHING for rg -- confirmed both forms leaked real go/pkg/mod
  // results through before landing on this. Excluding the whole go/
  // tree here (not just pkg/mod) is deliberately broader than
  // FileSearchProvider's own list -- vendored Go module source is
  // exactly the kind of noisy, non-personal content nobody wants
  // surfacing in a content search, more so than in a filename search.
  readonly property var excludeDirs: ["node_modules", "vendor", "target", "go"]

  // Debounced separately from (and longer than) FileSearchProvider's
  // own 150ms -- measured directly, not guessed: ripgrep content-
  // searching this machine's real ~24GB/134k-file $HOME runs ~100-150ms
  // warm-cache for a realistic specific query, up to ~1.8s cold-cache
  // for the single most common word imaginable ("the"). Firing that on
  // every keystroke the way fd's own near-instant search can afford to
  // would be wasteful; 400ms means content results "stream in" a beat
  // after the already-fast filename results, not block them.
  onQueryChanged: {
    var q = root.query.trim()
    if (!q) {
      debounceTimer.stop()
      root.lastResults = []
      return
    }
    debounceTimer.restart()
  }
  onSourceFilterChanged: if (root.query.trim()) debounceTimer.restart()

  function search(query) {
    return root.query.trim() ? root.lastResults : []
  }

  Timer {
    id: debounceTimer
    interval: 400
    repeat: false
    onTriggered: root.runSearch(root.query.trim())
  }

  readonly property int displayLimit: 15

  // Flat, deliberately below FileSearchProvider's own scoreFile() floor
  // (its weakest real match -- a long filename matching nowhere near
  // the start -- still lands well above this) so a content match NEVER
  // outranks a filename match, only fills in around/after them.
  readonly property int contentMatchScore: 1500

  function runSearch(query) {
    if (!root.homeDir) return
    root.pendingQuery = query
    // -F/--fixed-strings -- issue #47: rg treats the pattern as a regex
    // by default (same mismatch as fd's own default in
    // FileSearchProvider -- see its own comment), so an ordinary query
    // like "(notes)" or "*.json" would either match nothing or throw an
    // invalid-pattern error instead of searching for that literal text.
    var args = ["rg", "--json", "-i", "-F", "--max-count", "1", "--max-filesize", "5M"]
    for (var i = 0; i < root.excludeDirs.length; i++) args.push("-g", "!" + root.excludeDirs[i])
    args.push("--", query)
    if (root.sourceFilter) {
      args.push(root.sourceFilter)
    } else {
      args.push(root.homeDir)
      for (var i = 0; i < root.extraRoots.length; i++) args.push(root.extraRoots[i])
    }
    // Same real-world failure this shares extraRoots with
    // FileSearchProvider to avoid duplicating (see its own runSearch()
    // comment for the full reasoning): a network mount (rclone) among
    // extraRoots that's still establishing its remote connection right
    // after boot can stall rg's traversal of EVERY root in this one
    // combined invocation, not just that mount's own. rg does more I/O
    // per file than fd's own stat/listing (it reads content), so a
    // slightly longer bound than fd's 3s here.
    searchProc.command = ["timeout", "4"].concat(args)
    searchProc.running = true
  }

  function resultFor(path, lineNumber, lineText) {
    var slash = path.lastIndexOf("/")
    var name = slash === -1 ? path : path.substring(slash + 1)
    // Collapse the matched line to one clean, trimmed line -- rg's own
    // lines.text carries a trailing newline (and occasionally embedded
    // ones for odd files), neither of which belongs in a single-line
    // row breadcrumb.
    var snippet = lineText.replace(/\s+/g, " ").trim()
    if (snippet.length > 80) snippet = snippet.substring(0, 80) + "…"
    return {
      id: "content:" + path + ":" + lineNumber,
      providerId: "file-content-search",
      // fa-file (U+F15B) -- content matches are always files, rg
      // never matches inside a directory, so no folder-vs-file branch
      // is needed the way FileSearchProvider's own resultFor() has one.
      icon: "",
      label: name,
      // The matched line itself, not a parent-folder path -- this IS
      // the "search by context" feature made visible: why this row
      // matched, not just where the file lives (still available via
      // the details panel's own "Where" field once selected).
      breadcrumb: "Line " + lineNumber + ": " + snippet,
      kind: "File",
      providerName: root.providerName,
      score: root.contentMatchScore,
      action: { type: "open", path: path }
    }
  }

  Process {
    id: searchProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (root.pendingQuery !== root.query.trim()) return
        var lines = text.split("\n").filter(function(l) { return l.length > 0 })
        var out = []
        for (var i = 0; i < lines.length && out.length < root.displayLimit; i++) {
          var obj
          try { obj = JSON.parse(lines[i]) } catch (e) { continue }
          if (!obj || obj.type !== "match") continue
          out.push(root.resultFor(obj.data.path.text, obj.data.line_number, obj.data.lines.text))
        }
        root.lastResults = out
      }
    }
  }

  // Same as FileSearchProvider's own activate() -- xdg-open already
  // does the right thing for a file's default app; this doesn't (yet)
  // try to open an editor at the specific matched line, a genuinely
  // separate feature (needs a real per-app "open at line" convention)
  // rather than something to bolt on here speculatively.
  function activate(result) {
    Util.execArgv(["xdg-open", result.action.path])
  }
}
