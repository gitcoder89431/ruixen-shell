import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import "OmarchyMenuParser.js" as OmarchyMenuParser

// Provider: every directly-executable Omarchy menu action, searchable
// by label/alias, filtered by its own real "when" visibility guard.
// Reads /usr/share/omarchy/default/omarchy/omarchy-menu.jsonc directly
// -- a real, stable, DOCUMENTED Omarchy config file, not an internal
// implementation detail (see OmarchyMenuParser.js's own header for why
// that distinction matters and what is deliberately NOT imported).
Item {
  id: root

  readonly property string providerName: "Omarchy Actions"
  property bool ready: false

  readonly property string menuPath: (Quickshell.env("OMARCHY_PATH") || "/usr/share/omarchy") + "/default/omarchy/omarchy-menu.jsonc"
  // Real, documented, hot-reloading user customization point (confirmed
  // in Omarchy's own SKILL.md config-path table and the native
  // Menu.qml) -- entries added here merge on top of the packaged
  // defaults via OmarchyMenuParser.mergeUserOverrides, same as the
  // native menu's own mergeMenuSources. Missing entirely is the normal
  // case (most users never touch it), not an error.
  readonly property string userMenuPath: Quickshell.env("HOME") + "/.config/omarchy/extensions/omarchy-menu.jsonc"

  // Raw parsed maps from each source, before merging -- kept separate
  // so either file can finish loading (or fail) independently and
  // rebuildEntries() below just re-merges whatever's currently known.
  property var defaultEntries: ({})
  property var userEntries: ({})
  // Full flat {id: entry} map, defaults merged with user overrides --
  // needed so breadcrumbFor() can look up any ancestor's own label.
  property var allEntries: ({})
  // Subset of allEntries with a real "action" string -- what search()
  // actually offers as results.
  property var actionable: ({})
  // {id: {when, checked}} -- see OmarchyMenuParser.parseGuardOutput.
  property var guardResults: ({})

  // Both FileViews' own onLoaded can fire more than once during startup
  // (the implicit preload when `path` resolves, plus the explicit
  // .reload() call in Component.onCompleted -- same double-fire already
  // documented in ruixen.notch/NotificationService.qml's own
  // loadStore()) and each needs the OTHER to have at least settled
  // (loaded or failed) once before the first real merge+guard-evaluate
  // pass. defaultSettled/userSettled track that; rebuildEntries() is a
  // no-op until both are true, and safely re-runs (parsing is cheap,
  // idempotent) on any later change to either file.
  property bool defaultSettled: false
  property bool userSettled: false

  // Existing Omarchy keybind hints, shown after a row's own subtitle --
  // see keybindFor() and OmarchyMenuParser.js's own "Keybind hints"
  // section header for the full design. Both loaded ONCE at provider
  // startup (keybindProc ~200ms measured live, bindingsFile is a plain
  // local file read), never re-run per keystroke -- rebuildKeybindIndex()
  // just re-merges whatever's currently known, same settle-independently
  // pattern as defaultEntries/userEntries above.
  property var stockKeybindEntries: []
  property var personalKeybindEntries: []
  property var keybindIndex: ({})

  function rebuildKeybindIndex() {
    root.keybindIndex = OmarchyMenuParser.buildKeybindIndex(root.stockKeybindEntries, root.personalKeybindEntries)
  }

  function keybindFor(label) {
    return OmarchyMenuParser.keybindFor(label, root.keybindIndex, root.stockKeybindEntries)
  }

  // Issue #72's own live profiling found this running TWICE per open:
  // menuFile.onLoaded and userMenuFile.onLoaded each call rebuildEntries()
  // independently, and since defaultSettled/userSettled are usually
  // already true by a SECOND refresh (first refresh already set them),
  // BOTH calls pass the settled gate and redo the full rebuild --
  // measured live at ~123ms of blocking, synchronous JS each (merging
  // entries, building the 150+-condition guard script text), landing
  // squarely inside the 140ms opening fade/scale animation and
  // extending past it -- ~240ms of main-thread work across two
  // redundant passes, competing directly with the animation's own
  // frames. Qt.callLater() here -- not calling doRebuildEntries()
  // directly -- coalesces multiple rebuildEntries() calls arriving
  // before the deferred slot actually runs into exactly one real
  // execution, same de-duplication Qt.callLater already gives any
  // other function reference. Doesn't matter that the two onLoaded
  // firings aren't in the exact same tick (they measured ~124ms apart
  // live) -- SCHEDULING is now non-blocking either way, so the second
  // file's own already-pending onLoaded gets a chance to arrive before
  // the deferred rebuild actually starts, rather than being stuck
  // behind the first rebuild's own ~123ms of blocking work the way it
  // was before.
  function rebuildEntries() {
    Qt.callLater(root.doRebuildEntries)
  }

  function doRebuildEntries() {
    if (!root.defaultSettled || !root.userSettled) return
    root.allEntries = OmarchyMenuParser.mergeUserOverrides(root.defaultEntries, root.userEntries)
    root.actionable = OmarchyMenuParser.actionableEntries(root.allEntries)
    var script = OmarchyMenuParser.buildGuardScript(root.actionable)
    if (script.length === 0) {
      root.ready = true
      return
    }
    // .exec(), not command=...;running=true -- issue #46's own fix
    // applies here too: refresh() (issue #50) can call rebuildEntries()
    // again while a previous guard-eval run is still in flight (rapid
    // launcher open/close), and the old command=...;running=true pattern
    // would silently no-op a re-run in that case.
    guardProc.exec(["bash", "-c", script])
  }

  // Ruixen Settings has no manifest kind "menu" entry of its own, and
  // Super+R no longer opens it directly once this plugin owns that key
  // -- one synthetic row here keeps it reachable from the palette too,
  // same real toggle command its own keybind already used. Not a third
  // provider, just one more entry alongside the real Omarchy ones.
  //
  // The 5 below are real Hyprland window-management binds too -- but
  // unlike every Command above, they live ONLY in
  // .../hypr/bindings/tiling.lua as physical keybinds, never in
  // omarchy-menu.jsonc, so OmarchyActionsProvider's own actionable-entry
  // scan never sees them. Direct request: "so raycast has this like
  // window management commands... can we make them show up." A small
  // curated 5 (not tiling.lua's full ~40 binds -- most of those are
  // muscle-memory keys like resize-a-little/a-lot or workspace-move, not
  // "search and fire once" commands): the two real fullscreen modes, the
  // one plain toggle-tiled-fullscreen script, and the float/pin pair.
  // Each `action` is the EXACT same command its own real keybind already
  // runs (copied verbatim from tiling.lua, not reimplemented) --
  // either a real standalone script, or `hyprctl dispatch '<lua expr>'`
  // for the ones tiling.lua fires via a Lua dispatch call directly
  // (confirmed live: this Hyprland build's own `dispatch` subcommand
  // evaluates its argument as Lua -- `hyprctl dispatch 'hl.dsp...'` is
  // the real, working shell equivalent of what the keybind itself runs,
  // not a guess).
  //
  // Each also carries its own explicit `keybind` field rather than
  // relying on keybindFor()'s own label-fuzzy-matching -- "Float & Pin"
  // and "Toggle Floating/Tiling" are deliberately shorter, nicer labels
  // than tiling.lua's own ("Pop window out (float & pin)", "Toggle
  // window floating/tiling"), which don't satisfy keybindFor's own
  // whole-word-PREFIX rule (see labelsFuzzyMatch's own header for why
  // that rule is deliberately narrow). Hardcoding the real keybind text
  // directly (already known, read straight from tiling.lua) sidesteps
  // that mismatch entirely rather than contorting the shared label
  // matcher for 2 rows.
  readonly property var syntheticEntries: ({
    "ruixen.settings": {
      // fa-gear (U+F013) -- matches ruixen.settingsbutton's own bar
      // icon and this plugin's own Settings extension header, so the
      // palette row and what it opens read as the same thing.
      icon: "",
      label: "Settings",
      // A short tagline, same spirit as a .desktop file's own
      // GenericName= (e.g. "Streaming/Recording Software") -- a
      // couple of words, not a feature list. Not a breadcrumb (there's
      // no omarchy-menu.jsonc chain to walk for a synthetic entry),
      // just plain text describing what this opens. "Ruixen", not
      // "Shell Control" -- direct follow-up: matches wallpapersRow()'s
      // own "Ruixen" breadcrumb in Launcher.qml, so both extension
      // rows read as the same family of thing.
      breadcrumb: "Ruixen",
      // "Extension", not "Application" or the provider's own default
      // "Command" -- direct follow-up: "switch the thrid column
      // instead of applications just call it extension, its pretty
      // much the same thing in the extensions group." Matches
      // settingsRow()/wallpapersRow()'s own kind in Launcher.qml
      // (both "Extension") -- this row opens the exact same Settings
      // extension, just reachable by typing "settings"/"preferences"
      // instead of picking it off the landing list.
      kind: "Extension",
      aliases: ["settings", "preferences"],
      // Looked up live via keybindFor(), NOT hardcoded -- direct
      // correction: "keybinds are like actual config source... user
      // starts with nothing untill they run the keybind command then
      // it shows up". A user who hasn't bound anything (or comments
      // this bind back out) should see no hint at all, not a stale
      // combo baked into this file; one who rebinds it to a different
      // combo should see THAT combo without a code change. keybindIndex
      // already merges bindingsFile's own real, live parse of
      // ~/.config/hypr/bindings.lua (root.personalKeybindEntries, see
      // that FileView's own comment) with Omarchy's stock keybinds, so
      // this is the exact same real-config-driven lookup every other
      // entry's own keybind hint already goes through -- looked up by
      // "Ruixen Settings", the label bindings.lua's own o.bind() call
      // actually uses (this row's own DISPLAYED label is just
      // "Settings" now, a separate, cosmetic choice -- see label
      // above). A readonly property binding, not a one-time value:
      // this whole syntheticEntries object re-evaluates automatically
      // once keybindIndex finishes loading (a few hundred ms after
      // this plugin starts) or changes later (refresh() re-parses
      // bindingsFile every time this extension opens).
      keybind: root.keybindFor("Ruixen Settings"),
      // Documentation only, not actually run for this specific row --
      // Launcher.qml's own activateSelected() special-cases result.id
      // "omarchy:ruixen.settings" BEFORE reaching provider.activate(),
      // jumping straight to activeExtensionId = "settings" in-process
      // instead. Shelling this exact command out for real would hit
      // shell.toggle()'s own isPluginOpen(id) ? hide(id) : summon(id)
      // branch and just close this already-open launcher (toggling
      // itself) rather than opening Settings. Kept accurate here
      // anyway (matches bindings.lua's Super+Shift+R and
      // ruixen.settingsbutton's own bar icon) so nothing reading this
      // field sees a stale reference to the old ruixen.settings plugin.
      action: "omarchy-shell shell toggle ruixen.launcher '{\"extension\":\"settings\"}'"
    },
    // Same "typed-query discoverability" gap Settings' own entry above
    // was built to close -- direct report: "we need wallpaper and
    // setting to show up too" (on Wallpapers specifically: it had NO
    // synthetic entry at all, so typing "wallpaper" found nothing --
    // wallpapersRow() in Launcher.qml only ever appears on the empty-
    // query landing list, same real limitation settingsRow() has).
    "ruixen.wallpapers": {
      // fa-image (U+F03E) -- matches wallpapersRow()'s own icon in
      // Launcher.qml and ruixen.notch's own Wallpapers tab, so the
      // palette row and what it opens read as the same thing.
      icon: "",
      label: "Wallpapers",
      breadcrumb: "Ruixen",
      kind: "Extension",
      aliases: ["wallpaper", "background"],
      // No known bound keybind today, but looked up live the same way
      // Settings' own row is -- if one ever gets added to
      // bindings.lua under this exact label, it shows up here with no
      // code change needed.
      keybind: root.keybindFor("Wallpapers"),
      // Documentation only, not actually run -- same self-toggle-
      // closes-itself reason Settings' own action field's comment
      // documents. Launcher.qml's activateSelected() special-cases
      // this row's id and jumps straight to activeExtensionId =
      // "wallpapers" in-process instead.
      action: "omarchy-shell shell toggle ruixen.launcher '{\"extension\":\"wallpapers\"}'"
    },
    "window.fullscreen": {
      icon: "", // fa-expand
      label: "Full Screen",
      breadcrumb: "Window Management",
      kind: "Command",
      aliases: ["maximize"],
      keybind: "SUPER + F",
      action: "hyprctl dispatch 'hl.dsp.window.fullscreen({mode=\"fullscreen\"})'"
    },
    "window.tiled-fullscreen": {
      icon: "", // fa-th
      label: "Tiled Full Screen",
      breadcrumb: "Window Management",
      kind: "Command",
      aliases: [],
      keybind: "SUPER + CTRL + F",
      action: "omarchy-hyprland-window-tiled-fullscreen-toggle"
    },
    "window.full-width": {
      icon: "", // fa-window-maximize
      label: "Full Width",
      breadcrumb: "Window Management",
      kind: "Command",
      aliases: [],
      keybind: "SUPER + ALT + F",
      action: "hyprctl dispatch 'hl.dsp.window.fullscreen({mode=\"maximized\"})'"
    },
    "window.float-and-pin": {
      icon: "", // fa-thumbtack
      label: "Float & Pin",
      breadcrumb: "Window Management",
      kind: "Command",
      aliases: ["pop out", "pip"],
      keybind: "SUPER + O",
      action: "omarchy-hyprland-window-pop"
    },
    "window.toggle-floating": {
      icon: "", // fa-window-restore
      label: "Toggle Floating/Tiling",
      breadcrumb: "Window Management",
      kind: "Command",
      aliases: ["float"],
      keybind: "SUPER + T",
      action: "hyprctl dispatch 'hl.dsp.window.float({action=\"toggle\"})'"
    }
  })

  // A handful of real, always-visible entries picked as the launcher's
  // empty-query "Suggestions" -- deliberately small and hand-picked
  // rather than "most frequently used" (no usage tracking exists), so
  // the palette isn't blank the instant it opens. synthetic entries are
  // referenced by their syntheticEntries key, real ones by their real
  // omarchy-menu.jsonc id. system.reboot/system.shutdown added per
  // direct request ("on raycast there have shutdown and reboot
  // commands, i guess we can put these back in? they are kinda useful")
  // -- both were already real, always-actionable (no `when` guard)
  // omarchy-menu.jsonc entries, reachable by typing "reboot"/"shutdown"
  // the whole time; this just also pins them here so they show up
  // without typing anything, same as Raycast's own default system
  // commands.
  readonly property var suggestedIds: [
    "ruixen.settings",
    "trigger.capture.screenshot",
    "system.lock",
    "system.reboot",
    "system.shutdown",
    "style.theme",
    "style.background"
  ]

  // breadcrumb is the launcher's per-row subtitle (e.g. "Remove ›
  // Development", "Setup › Defaults › Editor") -- the entry's full
  // ancestor chain via breadcrumbFor(), root down to its immediate
  // parent. syntheticEntries override it outright (e.g. "Shell
  // Control" -- not part of the real omarchy-menu.jsonc tree, so
  // there's no chain to walk). kind defaults to "Command" (every real
  // omarchy-menu.jsonc entry fires a one-shot action), but a synthetic
  // entry can override it (Ruixen Settings says "Application" -- it
  // opens a panel, not a command) -- see Launcher.qml's own row
  // delegate for how breadcrumb/kind combine ("Remove › Development ·
  // Command").
  function breadcrumbFor(id, entry) {
    return entry.breadcrumb || OmarchyMenuParser.breadcrumbFor(root.allEntries, id)
  }

  function resultFor(id, entry, score) {
    return {
      id: "omarchy:" + id,
      providerId: "omarchy-actions",
      icon: entry.icon || "",
      label: entry.label || id,
      breadcrumb: root.breadcrumbFor(id, entry),
      kind: entry.kind || "Command",
      providerName: root.providerName,
      score: score,
      keybind: entry.keybind || root.keybindFor(entry.label || id),
      action: { type: "shell", command: entry.action }
    }
  }

  function search(query) {
    var q = String(query || "").trim()
    if (!q) return []
    var out = []
    for (var id in root.actionable) {
      var entry = root.actionable[id]
      if (!OmarchyMenuParser.isVisible(id, entry, root.guardResults)) continue
      var score = OmarchyMenuParser.scoreEntry(entry, q, root.breadcrumbFor(id, entry))
      if (score < 0) continue
      out.push(root.resultFor(id, entry, score))
    }
    for (var sid in root.syntheticEntries) {
      var sentry = root.syntheticEntries[sid]
      var sscore = OmarchyMenuParser.scoreEntry(sentry, q, root.breadcrumbFor(sid, sentry))
      if (sscore < 0) continue
      out.push(root.resultFor(sid, sentry, sscore))
    }
    return out
  }

  function suggestions() {
    var out = []
    for (var i = 0; i < root.suggestedIds.length; i++) {
      var id = root.suggestedIds[i]
      var entry = root.syntheticEntries[id] || root.actionable[id]
      if (!entry) continue
      if (!OmarchyMenuParser.isVisible(id, entry, root.guardResults)) continue
      out.push(root.resultFor(id, entry, 0))
    }
    return out
  }

  // The rest of the empty-query tray, below Suggestions -- every other
  // actionable entry (real ones only, no synthetic rows), alphabetical
  // by label since there's no query to score against. excludeIds keeps
  // whatever's already shown in Suggestions from appearing twice;
  // limit keeps this to whatever room is left in the fixed-height tray
  // (see Launcher.qml's own sections property).
  function browse(excludeIds, limit) {
    var exclude = {}
    for (var i = 0; i < excludeIds.length; i++) exclude[excludeIds[i]] = true
    var out = []
    for (var id in root.actionable) {
      if (exclude[id]) continue
      var entry = root.actionable[id]
      if (!OmarchyMenuParser.isVisible(id, entry, root.guardResults)) continue
      out.push(root.resultFor(id, entry, 0))
    }
    out.sort(function(a, b) { return a.label.localeCompare(b.label) })
    return typeof limit === "number" ? out.slice(0, limit) : out
  }

  function activate(result) {
    Util.execDetached(result.action.command)
  }

  // onLoaded/onLoadFailed below used to early-return once
  // defaultSettled/userSettled was already true -- fine for the startup
  // double-fire they were built for (the implicit preload plus the
  // explicit Component.onCompleted reload always load the SAME content,
  // so processing it twice was only ever wasted, not wrong), but issue
  // #50 needs a DELIBERATE later reload (refresh(), below) to actually
  // reprocess, which that same guard would silently swallow. Settled
  // flags still get set (rebuildEntries() itself stays gated on both
  // being true at least once), just never block reprocessing again.
  FileView {
    id: menuFile
    path: root.menuPath
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.defaultSettled = true
      root.defaultEntries = OmarchyMenuParser.parseMenuEntries(text())
      root.rebuildEntries()
    }
    // The packaged default is expected to always exist -- a failure
    // here is real (Omarchy itself missing/broken), not the normal
    // "no user file" case userMenuFile's own onLoadFailed handles.
    onLoadFailed: {
      root.defaultSettled = true
      root.ready = true
    }
  }

  FileView {
    id: userMenuFile
    path: root.userMenuPath
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.userSettled = true
      root.userEntries = OmarchyMenuParser.parseMenuEntries(text())
      root.rebuildEntries()
    }
    // No ~/.config/omarchy/extensions/omarchy-menu.jsonc at all is the
    // normal case (most users never touch it) -- not an error, just an
    // empty override map. Also reached on refresh() if the user deletes
    // their override file after it once existed -- userEntries reset to
    // empty rather than left stale, so a removed override actually
    // disappears on the next launcher open instead of lingering forever.
    onLoadFailed: {
      root.userSettled = true
      root.userEntries = ({})
      root.rebuildEntries()
    }
  }

  Process {
    id: guardProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.guardResults = OmarchyMenuParser.parseGuardOutput(text)
        root.ready = true
      }
    }
  }

  // Real, stable, documented Omarchy command -- see OmarchyMenuParser.js's
  // own "Keybind hints" header for why this and not hyprctl. Fire-and-
  // forget at startup, same one-shot-Process convention as guardProc
  // above; keybinds simply aren't shown until this lands (a few hundred
  // ms), never blocks root.ready. Re-run via .exec() from refresh()
  // below (issue #50) -- a personal keybind changed since startup should
  // show up the next time the launcher opens, not only after a full
  // shell restart.
  Process {
    id: keybindProc
    running: false
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.stockKeybindEntries = OmarchyMenuParser.parseKeybindingsOutput(text)
        root.rebuildKeybindIndex()
      }
    }
  }

  // The only reliable, text-parseable source of which keybind is the
  // user's own PERSONAL override (see parsePersonalBindings's own
  // comment). Missing entirely would be unusual on this setup but is
  // handled the same "just an empty list" way userMenuFile's own
  // onLoadFailed treats a missing user menu override file.
  FileView {
    id: bindingsFile
    path: Quickshell.env("HOME") + "/.config/hypr/bindings.lua"
    watchChanges: false
    printErrors: false
    onLoaded: {
      root.personalKeybindEntries = OmarchyMenuParser.parsePersonalBindings(text())
      root.rebuildKeybindIndex()
    }
  }

  // Issue #50: re-evaluates guard/visibility state and reloads every
  // user-owned override source, called from Launcher.qml's own open()
  // path (an open/session boundary, not per-keystroke). The FileView
  // reloads genuinely are cheap (local file reads), but keybindProc
  // and the guard-eval script rebuildEntries() spawns are real
  // subprocess work -- keybindProc alone measured ~200ms live (see its
  // own comment), and the guard script runs 150+ real shell conditions
  // in one bash process. This was called "Cheap" here before, which
  // was wrong in practice: direct report after the open animation
  // shipped ("theres a small jumpyness... a 20% jump in CPU usage from
  // opening it") traced back to this running in full on EVERY open,
  // including a rapid open/close/open within the same few seconds,
  // where none of installed packages/guard truth values/personal
  // keybinds could plausibly have changed anyway.
  //
  // minRefreshIntervalMs throttles actually doing this work -- still
  // real "reflects state since last full shell restart" freshness (the
  // whole point of issue #50), just not on a timescale finer than a
  // human could have plausibly gone and changed any of it in. A
  // rapid-fire reopen now costs nothing beyond the guard results
  // already sitting in memory from the last real refresh.
  readonly property int minRefreshIntervalMs: 30000
  property double lastRefreshAt: 0

  function refresh() {
    var now = Date.now()
    if (now - root.lastRefreshAt < root.minRefreshIntervalMs) return
    root.lastRefreshAt = now
    menuFile.reload()
    userMenuFile.reload()
    keybindProc.exec(["omarchy", "menu", "keybindings", "--print"])
    bindingsFile.reload()
  }

  Component.onCompleted: root.refresh()
}
