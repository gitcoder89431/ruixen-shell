// Issue #104: one source of truth for Launcher.qml's own full-screen
// extensions (Settings, Wallpapers Effects, Theme Browser, Clipboard
// History, Cliamp Radio, Wallpaper Shuffle) -- before this, a new
// extension needed edits scattered across a payload-validation OR-chain,
// a near-identical row-builder function, a frecency-boost map, a 12-way
// if-chain matching either its providerId or its synthetic search-result
// id, and a source-filter OR-chain, all independently. Same style as
// this plugin's other plain-JS modules (LauncherFrecency.js,
// LauncherHelpers.js): top-level var/function declarations only, no
// module.exports -- QML's `import "X.js" as X` exposes those directly,
// and tests/js/harness.js's loadModule() does the same for node tests.
//
// Each extension's own content Item (wallpapersContent, settingsContent,
// ...) is still a real, separately-imported QML component wired by hand
// once in Launcher.qml's own extensionContentById -- that one-line-per-
// extension wiring is unavoidable without dynamic QML loading, which
// this issue explicitly says not to force. tests/launcher-extension-
// registry-consistency.sh pins that map's keys against EXTENSIONS below
// so the two can never silently drift apart.
//
// icon is the exact Nerd Font glyph each row already used, copied byte-
// for-byte from the row-builder function it replaced (programmatically
// extracted and cross-checked by codepoint -- see
// tests/js/ExtensionRegistry.test.js's own icon-codepoint check -- never
// hand-retyped, since a Nerd Font private-use-area glyph renders
// invisibly in plain text and a typo would be silent).
var EXTENSIONS = [
  {
    id: "wallpapers",
    providerId: "wallpapers-extension",
    omarchyActionId: "ruixen.wallpapers",
    label: "Wallpapers Effects",
    icon: "",
    usesSourceFilter: true,
    // Direct follow-up ("how does the keybind for our stuff... update
    // it so it has the kbd helper on the launcher"): this landing row
    // used to be one of several with no keybindLookupLabel at all (only
    // "settings" originally had one) -- extensionRow() only ever calls
    // omarchyActionsProvider.keybindFor() when this is set, so no other
    // row could ever show a hint regardless of whether the user had one
    // bound. Matches the row's own label exactly -- see
    // docs/KEYBINDS.md's matching recipe, which uses this same string.
    keybindLookupLabel: "Wallpapers Effects"
  },
  {
    id: "settings",
    providerId: "settings-extension",
    omarchyActionId: "ruixen.settings",
    label: "Settings",
    icon: "",
    usesSourceFilter: false,
    // "Ruixen Settings", not bare "Settings" -- deliberately distinct
    // from the plain, more collision-prone row label (see
    // omarchyActionsProvider's own "Ruixen Settings" synthetic search
    // row, which already looks up the identical label, so both rows
    // read the same real binding -- "a user has to bind them right,
    // they shouldnt be hardcoded").
    keybindLookupLabel: "Ruixen Settings",
    // Settings is the only extension deep-linkable to a sub-page via
    // `{"extension":"settings","section":"..."}` -- see Launcher.qml's
    // own open() comment.
    supportsSection: true
  },
  {
    id: "theme-browser",
    providerId: "theme-browser-extension",
    omarchyActionId: "ruixen.theme-browser",
    label: "Bjarneo Themes",
    icon: "",
    usesSourceFilter: true,
    keybindLookupLabel: "Bjarneo Themes"
  },
  {
    id: "clipboard",
    providerId: "clipboard-extension",
    omarchyActionId: "ruixen.clipboard",
    label: "Clipboard History",
    icon: "",
    usesSourceFilter: false,
    keybindLookupLabel: "Clipboard History"
  },
  {
    id: "cliamp",
    providerId: "cliamp-extension",
    omarchyActionId: "ruixen.cliamp",
    label: "Cliamp Radio",
    icon: "",
    usesSourceFilter: true,
    keybindLookupLabel: "Cliamp Radio"
  },
  {
    id: "wallpaper-shuffle",
    providerId: "wallpaper-shuffle-extension",
    omarchyActionId: "ruixen.wallpaper-shuffle",
    label: "Wallpaper Shuffle",
    icon: "",
    usesSourceFilter: false,
    keybindLookupLabel: "Wallpaper Shuffle"
  },
  {
    id: "kanban",
    providerId: "kanban-extension",
    omarchyActionId: "ruixen.kanban",
    label: "Kanban Board",
    // Same glyph the notch's own Kanban dashboard tab already uses
    // (bars/widgets/ruixen.notch/Overlay.qml) -- one board, one icon,
    // recognizable across both surfaces.
    icon: "",
    usesSourceFilter: false,
    keybindLookupLabel: "Kanban Board"
  }
]

function ids() {
  return EXTENSIONS.map(function(e) { return e.id })
}

function isValidId(id) {
  return ids().indexOf(id) >= 0
}

function byId(id) {
  for (var i = 0; i < EXTENSIONS.length; i++) {
    if (EXTENSIONS[i].id === id) return EXTENSIONS[i]
  }
  return null
}

function byProviderId(providerId) {
  for (var i = 0; i < EXTENSIONS.length; i++) {
    if (EXTENSIONS[i].providerId === providerId) return EXTENSIONS[i]
  }
  return null
}

function byOmarchyActionId(omarchyActionId) {
  for (var i = 0; i < EXTENSIONS.length; i++) {
    if (EXTENSIONS[i].omarchyActionId === omarchyActionId) return EXTENSIONS[i]
  }
  return null
}

function usesSourceFilter(id) {
  var entry = byId(id)
  return !!(entry && entry.usesSourceFilter)
}
