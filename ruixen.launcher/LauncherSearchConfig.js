// Issue #61: configurable Search Files locations/exclusions. Config
// schema, parsing, and effective-root computation live here so
// ruixen.launcher (which CONSUMES the config to build its real search
// root set) and ruixen.settings (which reads/writes it via its own
// "Launcher" settings page) agree on exactly the same rules -- neither
// one re-derives "what does this config actually mean" independently.
//
// Duplicated byte-identical between the two plugin folders -- the same
// "third copy" convention AppLibrary.qml/AppSearch.js already
// established between ruixen.notch/ruixen.pinnedapps/ruixen.launcher:
// Omarchy's plugin loader rejects symlinks inside a plugin folder, so
// there is no way to share one real file across two installed plugins.
// Kept in sync via tests/launcher-search-config-relay.sh.
//
// Mount discovery here (flattenMountTree/isMountCandidate/
// discoverMountedRoots below) is a SEPARATE, smaller copy of the same
// idea FileSearchRanking.js's own discoverExtraRoots() already
// implements for ruixen.launcher's real search-time mount refresh --
// not reused directly, again because of the plugin-boundary
// constraint, and kept deliberately minimal (just enough for a
// settings checklist) rather than importing that file's own fuller
// local-vs-remote classification, which the checklist doesn't need.

var CONFIG_VERSION = 1

// Issue #60's own existing hardcoded exclusions (FileSearchProvider.qml's
// excludeDirs + FileContentSearchProvider.qml's own, plus ".git", which
// issue #60 already added unconditionally to both) -- seeded as the
// default excludeNames list so a fresh config represents EXACTLY
// today's real behavior, not a narrower or broader one.
function defaultConfig() {
  return {
    version: CONFIG_VERSION,
    includeHome: true,
    includeMountedRoots: true,
    roots: [],
    disabledAutoRoots: [],
    excludePaths: [],
    excludeNames: ["node_modules", "vendor", "target", "go", ".git"]
  }
}

// Never throws, and never discards the whole file over one bad field --
// a hand-edit that breaks just one value (wrong type, malformed JSON
// entirely) falls back to that field's own default rather than losing
// every other already-configured root/exclusion alongside it. Unknown
// keys are silently ignored (forward-compatible with a future version
// adding new fields this code doesn't know about yet), and `version`
// is always normalized to the current CONFIG_VERSION on the way out --
// this module owns exactly one schema shape, not a migration chain.
function parseSearchConfig(jsonText) {
  var raw
  try {
    raw = JSON.parse(jsonText)
  } catch (e) {
    raw = null
  }
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) raw = {}

  function strArray(v, fallback) {
    if (!Array.isArray(v)) return fallback
    var out = []
    for (var i = 0; i < v.length; i++) {
      if (typeof v[i] === "string" && v[i].trim()) out.push(v[i].trim())
    }
    return out
  }

  var d = defaultConfig()
  return {
    version: CONFIG_VERSION,
    includeHome: typeof raw.includeHome === "boolean" ? raw.includeHome : d.includeHome,
    includeMountedRoots: typeof raw.includeMountedRoots === "boolean" ? raw.includeMountedRoots : d.includeMountedRoots,
    roots: strArray(raw.roots, d.roots),
    disabledAutoRoots: strArray(raw.disabledAutoRoots, d.disabledAutoRoots),
    excludePaths: strArray(raw.excludePaths, d.excludePaths),
    excludeNames: strArray(raw.excludeNames, d.excludeNames)
  }
}

function serializeSearchConfig(config) {
  return JSON.stringify(config, null, 2) + "\n"
}

// Deliberately minimal expansion -- only a LEADING "~" (the whole
// string) or "~/" is ever substituted with homeDir. Never $(...),
// backticks, environment variables, or any other shell syntax --
// config values are pure data, never evaluated as anything.
function expandHome(path, homeDir) {
  var p = String(path || "")
  if (p === "~") return homeDir || p
  if (p.indexOf("~/") === 0 && homeDir) return homeDir + p.substring(1)
  return p
}

// Strips a single trailing slash (except the bare root "/" itself) so
// the same real directory typed two different ways ("~/Work" vs
// "~/Work/") doesn't get treated as two different roots for dedup
// purposes.
function normalizePath(path, homeDir) {
  var p = expandHome(path, homeDir)
  if (p.length > 1 && p.charAt(p.length - 1) === "/") p = p.substring(0, p.length - 1)
  return p
}

function isUnderAnyExcludedPath(path, excludePaths, homeDir) {
  for (var i = 0; i < excludePaths.length; i++) {
    var ex = normalizePath(excludePaths[i], homeDir)
    if (!ex) continue
    if (path === ex || path.indexOf(ex + "/") === 0) return true
  }
  return false
}

// Issue #64: isUnderAnyExcludedPath above only ever filtered the ROOT
// LIST itself (a whole mount/custom root that IS or is under an
// exclusion never gets added as a root at all) -- it says nothing about
// constraining fd/rg's own traversal WITHIN a root that stays active,
// e.g. excluding "~/VMs" while Home ("~") is still an enabled root.
// Filtering only the root list is insufficient for that case: Home
// remains a valid, still-searched root, and fd/rg can freely recurse
// into ~/VMs unless told not to.
//
// fd and rg's own glob-exclude semantics were confirmed live to NOT be
// interchangeable for anchoring an absolute subtree (the issue's own
// explicit warning, verified rather than assumed):
//   - fd's `--exclude` with a leading "/" anchors to the SEARCH ROOT
//     argument itself, independent of the process's own cwd --
//     `fd --exclude '/VMs' . /tmp/x` only ever excludes /tmp/x/VMs, never
//     /tmp/x/keep/VMs, regardless of which directory fd was launched from.
//   - rg's `-g` glob anchoring instead follows plain gitignore semantics
//     relative to the PROCESS's own cwd, NOT the search-root positional
//     argument -- the identical pattern `-g '!/VMs'` given the exact same
//     root argument matched nothing at all when rg's cwd differed from
//     that root. Pairing an ABSOLUTE glob (the full escaped path) with
//     cwd forced to "/" made it anchor correctly regardless of which
//     root is being searched -- see FileContentSearchProvider.qml's own
//     comment on its worker Process objects for where that cwd is set.
var GLOB_SPECIAL_RE = /[\\*?\[\]]/g

// Escapes fd/ripgrep's shared gitignore-style glob metacharacters (\, *,
// ?, [, ]) so a literal excluded name/path segment that happens to
// contain one of them can't be misread as glob syntax -- e.g. a real
// directory literally named "foo[bar]" must exclude exactly that, not
// match "foo" followed by a single character from the class "bar".
function escapeGlobLiteral(text) {
  return String(text || "").replace(GLOB_SPECIAL_RE, "\\$&")
}

// Translates ONE configured excludePaths entry into what it means for
// ONE specific worker root -- null if the exclusion has no bearing on
// this root at all (lies outside it entirely, so this worker needs no
// extra argument for it), { skip: true } if the exclusion IS this root
// exactly (the caller should skip launching a worker for it altogether
// rather than spawning fd/rg only to exclude everything beneath it --
// see runSearch()'s own use of rootExactlyExcluded below), or glob-
// escaped fragments for a genuine subtree exclusion under this root:
// `relative` (fd's own anchoring input, leading "/", root-relative) and
// `absolute` (rg's own anchoring input, paired with cwd "/") are both
// derived from the same containment check so the two providers can
// never disagree about which paths are actually excluded.
function excludeInfoForRoot(excludedPath, rootPath, homeDir) {
  var ex = normalizePath(excludedPath, homeDir)
  var rootNorm = normalizePath(rootPath, homeDir)
  if (!ex || !rootNorm) return null
  if (ex === rootNorm) return { skip: true }
  if (ex.indexOf(rootNorm + "/") !== 0) return null
  return {
    skip: false,
    relative: escapeGlobLiteral(ex.substring(rootNorm.length)),
    absolute: escapeGlobLiteral(ex)
  }
}

// Whether `path`, about to be searched as a WHOLE worker root, exactly
// matches one of the configured excludePaths entries -- reuses
// excludeInfoForRoot's own normalization so this can never disagree with
// the per-root subtree logic above about what "exactly excluded" means.
function rootExactlyExcluded(path, excludePaths, homeDir) {
  for (var i = 0; i < excludePaths.length; i++) {
    var info = excludeInfoForRoot(excludePaths[i], path, homeDir)
    if (info && info.skip) return true
  }
  return false
}

// The one function both search providers actually consume (via
// FileSearchProvider.qml's own effectiveExtraRoots) -- everything
// EXCEPT Home: enabled auto-discovered mounts (skipping anything in
// disabledAutoRoots) plus the user's own custom roots, minus anything
// under an excluded subtree, deduped by normalized path with the
// FIRST-seen entry's own fstype winning (a real auto-discovered mount's
// own known fstype beats a custom root added at the same path with an
// unknown one). Home itself stays a separate, simpler
// config.includeHome boolean the caller checks directly -- it has no
// fstype of its own to carry, and folding it into this same merged
// list would need inventing one.
function computeEffectiveExtraRoots(config, autoDiscoveredRoots, homeDir) {
  var seen = ({})
  var out = []
  function add(path, fstype) {
    var norm = normalizePath(path, homeDir)
    if (!norm || norm === homeDir || seen[norm]) return
    if (isUnderAnyExcludedPath(norm, config.excludePaths, homeDir)) return
    seen[norm] = true
    out.push({ path: norm, fstype: fstype || "" })
  }
  if (config.includeMountedRoots) {
    var disabled = ({})
    for (var i = 0; i < config.disabledAutoRoots.length; i++) {
      disabled[normalizePath(config.disabledAutoRoots[i], homeDir)] = true
    }
    for (var j = 0; j < (autoDiscoveredRoots || []).length; j++) {
      var r = autoDiscoveredRoots[j]
      if (disabled[normalizePath(r.path, homeDir)]) continue
      add(r.path, r.fstype)
    }
  }
  for (var k = 0; k < config.roots.length; k++) add(config.roots[k], "")
  return out
}

// ---- mount discovery for the settings checklist (see this file's own
// header for why this is a separate, smaller copy rather than reusing
// FileSearchRanking.js's own discoverExtraRoots) ---------------------

function flattenMountTree(node, out) {
  if (node && typeof node.target === "string") out.push({ path: node.target, fstype: String(node.fstype || "") })
  if (node && Array.isArray(node.children)) {
    for (var i = 0; i < node.children.length; i++) flattenMountTree(node.children[i], out)
  }
}

function isMountCandidate(path) {
  return path.indexOf("/mnt/") === 0 || path.indexOf("/media/") === 0 || path.indexOf("/run/media/") === 0
}

// Same findmnt --json -> candidate-list pipeline as FileSearchRanking.js's
// own discoverExtraRoots -- real mounts only (see isMountCandidate),
// deduped, malformed/empty JSON returns an empty list rather than
// throwing.
function discoverMountedRoots(findmntJsonText) {
  var targets = []
  try {
    var data = JSON.parse(findmntJsonText)
    var top = (data && Array.isArray(data.filesystems)) ? data.filesystems : []
    for (var i = 0; i < top.length; i++) flattenMountTree(top[i], targets)
  } catch (e) {
    return []
  }
  var seen = ({})
  var roots = []
  for (var j = 0; j < targets.length; j++) {
    var target = targets[j].path
    if (isMountCandidate(target) && !seen[target]) {
      seen[target] = true
      roots.push({ path: target, fstype: targets[j].fstype })
    }
  }
  return roots
}
