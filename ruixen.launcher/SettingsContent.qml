import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "LauncherSearchConfig.js" as LauncherSearchConfig

// Layout-only shell for the "Settings" extension -- direct request:
// "lets do the Settings as Extension so Settings 2nd Column Ruixen and
// type extension? itll be similar to the 2 panel layout where we have
// the Profile Launcher Bluetooth menu options on the left panel, then
// enter to go into the right panel where we have toggles and inputs
// and options. dont build out the whole thing yet... just start with
// the layout first then we can work on the panels?" -- deliberately
// navigation + chrome only: a left category list and a right panel
// that opens straight onto Profile ("we can land in the profile
// page"). Direct follow-up landed Profile's own REAL content --
// avatar/username/DiceBear picker, ported byte-for-byte in spirit from
// ruixen.settings/GeneralContent.qml + the matching backend block in
// ruixen.settings/Settings.qml (avatarCollections/selectAvatar/the
// avatar.json state file) -- plugin folders can't share a file across
// install locations (same reason AppLibrary.qml/AppSearch.js already
// exist three times over, and LauncherSearchConfig.js twice), so this
// is a second, independent copy of that exact same mechanism, reading
// and writing the exact same real files (~/.face.icon, ~/.local/state/
// ruixen/avatar.json) -- picking an avatar here is visible in
// ruixen.notch's own UserAvatar too, same as picking one there is.
// Every OTHER category still gets the plain header + description
// treatment -- that's explicit later work, one category at a time.
//
// Direct follow-up chain after the first pass hand-rolled its own row
// visuals and its own margins: "it looks too much different than the
// file search, lets have some design consistency"; then, after a
// Loader/Component-based attempt at sharing that quietly broke font
// propagation: "why did you port it over from the ruixen settings
// menu... wouldnt it be a lot easier to just make a list of stuff like
// a list component from file search thats shared?" -- so the category
// list below IS ResultsList/ResultRow, the exact same component Search
// Files itself renders through (filesMode: true, same icon+label-only
// row), not a second implementation of "a list of rows". Only the
// outer 2-panel split (list width/detail width/divider) comes from
// ExtensionTwoPanel.qml, and even that owns geometry only -- every
// color/font binding below is a plain, direct binding off this file's
// own root, same as every other file in this plugin.
Item {
  id: root

  property color textColor: "#ffffff"
  property color muted: Qt.rgba(1, 1, 1, 0.5)
  property color accent: "#3ecf5b"
  property string fontFamily: "JetBrainsMono Nerd Font"
  property bool active: false
  // Fed from the outer SearchHeader/root.query, same single-search-box
  // convention Wallpapers already established ("we dont need two
  // search box, use the launcher for wallpaper search input") -- direct
  // follow-up: "does search work for menu items on the left too?"
  property string searchText: ""

  // --- Profile: avatar/username, ported from ruixen.settings -- see
  // this file's own header comment for why this is a second, real copy
  // rather than a shared import. Every property/function/Process name
  // below matches ruixen.settings/Settings.qml's own naming exactly,
  // so the two stay easy to compare/keep in sync by hand.
  readonly property string username: {
    var u = Quickshell.env("USER") || "user"
    return u.charAt(0).toUpperCase() + u.slice(1)
  }
  property string hardwareName: ""
  property int avatarCacheBust: 0
  property bool avatarBusy: false
  readonly property var avatarCollections: [
    { id: "gradient", label: "Gradient" },
    { id: "bottts-neutral", label: "Bottts", version: "10.x", format: "svg" },
    { id: "pixel-art", label: "Pixel Art" },
    { id: "pixelbot", label: "Pixelbot", version: "10.x", format: "svg" },
    { id: "identicon", label: "Identicon" },
    { id: "thumbs", label: "Thumbs" },
    { id: "sprouts", label: "Sprouts", version: "10.x", format: "svg" },
    { id: "critters", label: "Critters", version: "10.x", format: "svg" },
    { id: "moods", label: "Moods", version: "10.x", format: "svg" }
  ]
  property string avatarCollection: "gradient"
  property bool avatarStateLoaded: false
  readonly property string avatarStatePath: Quickshell.env("HOME") + "/.local/state/ruixen/avatar.json"

  function loadAvatarState(raw) {
    if (root.avatarStateLoaded) return
    try {
      var parsed = JSON.parse(raw)
      if (parsed && typeof parsed.collection === "string") {
        var known = false
        for (var i = 0; i < root.avatarCollections.length; i++) {
          if (root.avatarCollections[i].id === parsed.collection) { known = true; break }
        }
        if (known) root.avatarCollection = parsed.collection
      }
    } catch (e) {}
    root.avatarStateLoaded = true
  }

  // Single entry point for every avatar-picker button -- "gradient"
  // deletes ~/.face.icon, any real DiceBear slug fetches a random
  // avatar from that collection.
  function selectAvatar(collection) {
    if (root.avatarBusy) return
    root.avatarBusy = true
    root.avatarCollection = collection
    var target = Quickshell.env("HOME") + "/.face.icon"
    if (collection === "gradient") {
      avatarProc.command = ["bash", "-c", "rm -f '" + target + "'"]
    } else {
      var seed = Math.random().toString(36).slice(2) + Date.now()
      var entry = null
      for (var i = 0; i < root.avatarCollections.length; i++) {
        if (root.avatarCollections[i].id === collection) { entry = root.avatarCollections[i]; break }
      }
      var version = (entry && entry.version) || "9.x"
      var format = (entry && entry.format) || "png"
      var url = "https://api.dicebear.com/" + version + "/" + collection + "/" + format + "?seed=" + seed
      avatarProc.command = ["bash", "-c", "curl -fsL '" + url + "' -o '" + target + "'"]
    }
    avatarProc.running = true
  }

  Process {
    id: identityProc
    command: ["fastfetch", "--format", "json", "-s", "Host"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var data = JSON.parse(text)
          for (var i = 0; i < data.length; i++) {
            if (data[i].type === "Host") root.hardwareName = data[i].result.name || ""
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: ensureAvatarStateDirProc
    command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/ruixen"]
  }

  FileView {
    id: avatarStateFile
    path: root.avatarStatePath
    watchChanges: false
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadAvatarState(text())
    onLoadFailed: root.loadAvatarState("")
  }

  Process {
    id: avatarProc
    stdout: StdioCollector { waitForEnd: true }
    onExited: {
      root.avatarBusy = false
      root.avatarCacheBust = root.avatarCacheBust + 1
      avatarStateFile.setText(JSON.stringify({ collection: root.avatarCollection }, null, 2) + "\n")
      // Tells ruixen.notch's own UserAvatar to re-read the file too --
      // it's a separate keepLoaded:true plugin process, so it has no
      // other way to know ~/.face.icon just changed.
      avatarNotifyProc.command = ["omarchy-shell", "-q", "ruixen.notch", "refreshAvatar"]
      avatarNotifyProc.running = true
    }
  }

  Process {
    id: avatarNotifyProc
  }

  // --- Profile: Window Curvature (Sharp/Rounded). First ported
  // byte-for-byte from ruixen.settings (cornerCurvature/
  // setCornerCurvature), which shells out to the real hyprland/
  // ruixen-lookfeel.sh SCRIPT via a required git checkout path
  // (ruixenRepoPath) -- direct follow-up caught the real problem with
  // that: "this makes it not really workable as standalone launcher
  // right, cause it still relies on the lookandfeel from the
  // ruixen-shell?"
  //
  // Fix, not a workaround: ruixen-lookfeel.sh's OWN header comment
  // (confirmed by reading the real script directly) already documents
  // that its lua TARGETS live at a stable, install-time-deployed path
  // -- $HOME/.local/share/ruixen-shell/hyprland -- specifically so
  // toggling look'n'feel "stopped [working] the moment the checkout
  // that ran install.sh was moved or deleted" (issue #15). Only the
  // SCRIPT FILE ITSELF stays checkout-relative; the actual lua content
  // it symlinks to is already checkout-independent. So this reimplements
  // just the script's own small symlink-swap+reload sequence directly
  // (~6 lines, confirmed against the real script's own apply()),
  // pointed at that same already-stable deployed directory -- no lua
  // files duplicated (there's exactly one real copy on disk, shared by
  // both this and the real ruixen.settings page), no ruixenRepoPath,
  // no git-checkout dependency of any kind. "Off" (stock Omarchy, no
  // border/blur/shadow) isn't offered here either, same as the real
  // page -- a much bigger toggle than corner shape alone, stays
  // CLI-only (`ruixen-lookfeel off`).
  //
  // This IS a second, independent copy of the orchestration logic
  // (matching every other "plugin folders can't share a file" case in
  // this repo) -- direct follow-up accepted that explicitly: "we can
  // have two copies... just build 2 for now till we phase out the old
  // settings, than it should be easier to decide [on one]." Once
  // ruixen.settings' own General page is retired, this becomes the
  // only copy left, naturally converging without any migration step --
  // and even today, the only thing duplicated is this orchestration
  // sequence, not the real theming data both copies point at.
  //
  // Clicking either option ends in a full `omarchy restart shell` --
  // this launcher's own process included -- same as the real script
  // always has (ruixen.frame-widget's own corner mask only reads which
  // variant is active at its own startup, so a plain `hyprctl reload`
  // alone could never pick up a live switch). Expected, not a bug.
  property string cornerCurvature: "rounded"
  readonly property string looknfeelTarget: Quickshell.env("HOME") + "/.config/hypr/looknfeel.lua"
  readonly property string looknfeelDataDir: Quickshell.env("HOME") + "/.local/share/ruixen-shell/hyprland"

  Process {
    id: cornerCurvatureReadProc
    command: ["bash", "-c", "readlink \"" + Quickshell.env("HOME") + "/.config/hypr/looknfeel.lua\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        root.cornerCurvature = String(text || "").indexOf("looknfeel.square.lua") >= 0 ? "sharp" : "rounded"
      }
    }
  }

  Process {
    id: cornerCurvatureWriteProc
    stdout: StdioCollector { waitForEnd: true }
  }

  function setCornerCurvature(curvature) {
    if (curvature !== "sharp" && curvature !== "rounded") return
    root.cornerCurvature = curvature
    var target = root.looknfeelTarget
    var src = root.looknfeelDataDir + "/" + (curvature === "sharp" ? "looknfeel.square.lua" : "looknfeel.ruixen.lua")
    // Same three steps as ruixen-lookfeel.sh's own apply(): back up a
    // real (non-symlink) file rather than clobber it, swap the symlink
    // + reload Hyprland, then always attempt the shell restart last
    // (the trailing `|| true` matches the real script -- a failed
    // restart shouldn't be treated as this whole action having failed).
    cornerCurvatureWriteProc.command = ["bash", "-c",
      "target='" + target + "'; " +
      "if [ -e \"$target\" ] && [ ! -L \"$target\" ]; then mv \"$target\" \"$target.bak.$(date +%s)\"; fi; " +
      "ln -sf '" + src + "' \"$target\" && hyprctl reload >/dev/null; " +
      "omarchy restart shell >/dev/null 2>&1 || true"]
    cornerCurvatureWriteProc.running = true
  }

  // --- Profile: Window Spacing (Comfy/Tight), ported from
  // ruixen.settings -- same naming as Settings.qml's own
  // spacingProfile/setSpacingProfile. Unlike Window Curvature, this
  // doesn't shell out to a real script or need a repo checkout -- a
  // plain text file + `hyprctl reload`, so no ruixenRepoPath guard
  // here either. Applies under both Sharp and Rounded curvature (both
  // looknfeel.ruixen.lua and looknfeel.square.lua read this same
  // file), so this card's own availability never depends on
  // cornerCurvature's current value.
  property string spacingProfile: "comfy"
  readonly property string spacingProfilePath: Quickshell.env("HOME") + "/.local/state/ruixen/spacing-profile"

  Process {
    id: spacingProfileReadProc
    command: ["bash", "-c", "cat \"" + root.spacingProfilePath + "\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var v = String(text || "").trim()
        root.spacingProfile = (v === "tight") ? v : "comfy"
      }
    }
  }

  Process {
    id: spacingProfileWriteProc
    stdout: StdioCollector { waitForEnd: true }
  }

  function setSpacingProfile(profile) {
    if (profile !== "comfy" && profile !== "tight") return
    root.spacingProfile = profile
    spacingProfileWriteProc.command = ["bash", "-c",
      "printf '%s' '" + profile + "' > \"" + root.spacingProfilePath + "\" && hyprctl reload"]
    spacingProfileWriteProc.running = true
  }

  // --- Profile: Animation Style (Calm/Bubbly/Snappy), ported from
  // ruixen.settings -- same naming as Settings.qml's own
  // animationProfile/setAnimationProfile. Same plain-text-file +
  // `hyprctl reload` shape as Window Spacing, no repo checkout
  // dependency -- the actual curve/speed values live in
  // hyprland/looknfeel.ruixen.lua, which reads this same file directly;
  // this side's only job is writing the chosen profile. Calm first
  // (the real app's own default), then Bubbly, then Snappy -- matches
  // ruixen.settings/GeneralContent.qml's own model order exactly, not
  // alphabetical.
  property string animationProfile: "calm"
  readonly property string animationProfilePath: Quickshell.env("HOME") + "/.local/state/ruixen/animation-profile"

  Process {
    id: animationProfileReadProc
    command: ["bash", "-c", "cat \"" + root.animationProfilePath + "\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var v = String(text || "").trim()
        root.animationProfile = (v === "bubbly" || v === "snappy") ? v : "calm"
      }
    }
  }

  Process {
    id: animationProfileWriteProc
    stdout: StdioCollector { waitForEnd: true }
  }

  function setAnimationProfile(profile) {
    if (profile !== "bubbly" && profile !== "calm" && profile !== "snappy") return
    root.animationProfile = profile
    animationProfileWriteProc.command = ["bash", "-c",
      "printf '%s' '" + profile + "' > \"" + root.animationProfilePath + "\" && hyprctl reload"]
    animationProfileWriteProc.running = true
  }

  // --- Bar: Bar Layout (Floating/Docked), ported from ruixen.settings
  // -- same naming as Settings.qml's own barMode/setBarMode. Plain
  // shell.json read/write via python3 (same mechanism, no repo
  // checkout dependency -- already standalone-safe as ported). Full
  // `omarchy restart shell`, not just a config reload -- same real
  // reason Window Curvature's own restart exists: ruixen.frame-widget
  // only reads bar.docked once at its own startup, so a plain reload
  // would leave it stale against a live Floating/Docked switch.
  property string barMode: "floating"

  Process {
    id: barModeReadProc
    command: ["bash", "-c", "python3 -c \"import json; d=json.load(open('" + Quickshell.env("HOME") + "/.config/omarchy/shell.json')); print('docked' if d.get('bar',{}).get('docked') is True else 'floating')\" 2>/dev/null || echo floating"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.barMode = String(text || "floating").trim() === "docked" ? "docked" : "floating"
    }
  }

  Process {
    id: barModeWriteProc
    stdout: StdioCollector { waitForEnd: true }
  }

  function setBarMode(mode) {
    if (mode !== "docked" && mode !== "floating") return
    root.barMode = mode
    var home = Quickshell.env("HOME")
    var path = home + "/.config/omarchy/shell.json"
    var value = mode === "docked" ? "True" : "False"
    barModeWriteProc.command = ["bash", "-c",
      "python3 -c \"import json; p='" + path + "'; d=json.load(open(p)); d.setdefault('bar', {})['docked'] = " + value + "; json.dump(d, open(p, 'w'), indent=2)\" && omarchy restart shell >/dev/null 2>&1 || true"]
    barModeWriteProc.running = true
  }

  // --- Launcher: Include Home / Auto-include Mounted Drives, ported
  // from ruixen.settings/Settings.qml's own launcherSearchConfig block
  // -- same naming (setLauncherIncludeHome/setLauncherIncludeMountedRoots).
  // Reads/writes the exact same file (~/.local/state/ruixen/
  // launcher-search-config.json) FileSearchProvider.qml already
  // watches (watchChanges: true) to build its own real search roots --
  // no new plumbing needed on that side, a save here just takes effect
  // the next search. LauncherSearchConfig.js itself is already a
  // second copy in this exact plugin folder (FileSearchProvider.qml's
  // own import), not a new one -- this is the first time anything in
  // ruixen.launcher WRITES that file rather than only reading it.
  //
  // Scoped to just the two toggles for this pass, not the full page
  // (mounted-drives checklist, custom roots, path/name exclusions) --
  // those are their own, genuinely different list-editing UI, real
  // follow-on work rather than a same-shape extension of this one.
  property var launcherSearchConfig: LauncherSearchConfig.defaultConfig()
  readonly property string launcherSearchConfigPath: Quickshell.env("HOME") + "/.local/state/ruixen/launcher-search-config.json"

  function loadLauncherSearchConfig(raw) {
    root.launcherSearchConfig = LauncherSearchConfig.parseSearchConfig(raw)
  }

  function saveLauncherSearchConfig() {
    launcherSearchConfigFile.setText(LauncherSearchConfig.serializeSearchConfig(root.launcherSearchConfig))
  }

  FileView {
    id: launcherSearchConfigFile
    path: root.launcherSearchConfigPath
    watchChanges: true
    atomicWrites: true
    printErrors: false
    onLoaded: root.loadLauncherSearchConfig(text())
    onLoadFailed: root.loadLauncherSearchConfig("")
    onFileChanged: reload()
  }

  function setLauncherIncludeHome(value) {
    root.launcherSearchConfig = Object.assign({}, root.launcherSearchConfig, { includeHome: value })
    root.saveLauncherSearchConfig()
  }

  function setLauncherIncludeMountedRoots(value) {
    root.launcherSearchConfig = Object.assign({}, root.launcherSearchConfig, { includeMountedRoots: value })
    root.saveLauncherSearchConfig()
  }

  // A mount toggled off here stays remembered (present in
  // disabledAutoRoots) even after it's physically unmounted -- the
  // checklist below shows a disabled-but-not-currently-mounted entry
  // too, not just the live findmnt list, so re-plugging the same drive
  // doesn't silently re-enable it.
  function toggleLauncherAutoRootDisabled(path) {
    var list = root.launcherSearchConfig.disabledAutoRoots.slice()
    var idx = list.indexOf(path)
    if (idx === -1) list.push(path)
    else list.splice(idx, 1)
    root.launcherSearchConfig = Object.assign({}, root.launcherSearchConfig, { disabledAutoRoots: list })
    root.saveLauncherSearchConfig()
  }

  // Same real effect as toggleLauncherAutoRootDisabled, but SETS to an
  // explicit state instead of blindly flipping -- needed for the
  // keyboard model below, where Enter always means "commit whichever
  // state the cursor is currently sitting on," not "flip it again".
  // Blindly toggling there would double-flip back to the original
  // state if the cursor happened to land back where it started.
  function setLauncherAutoRootDisabled(path, disabled) {
    var list = root.launcherSearchConfig.disabledAutoRoots.slice()
    var idx = list.indexOf(path)
    if (disabled && idx === -1) list.push(path)
    else if (!disabled && idx !== -1) list.splice(idx, 1)
    else return
    root.launcherSearchConfig = Object.assign({}, root.launcherSearchConfig, { disabledAutoRoots: list })
    root.saveLauncherSearchConfig()
  }

  function addLauncherRoot(path) {
    var p = String(path || "").trim()
    if (!p) return
    var list = root.launcherSearchConfig.roots.slice()
    if (list.indexOf(p) === -1) list.push(p)
    root.launcherSearchConfig = Object.assign({}, root.launcherSearchConfig, { roots: list })
    root.saveLauncherSearchConfig()
  }

  function removeLauncherRoot(path) {
    var list = root.launcherSearchConfig.roots.filter(function(r) { return r !== path })
    root.launcherSearchConfig = Object.assign({}, root.launcherSearchConfig, { roots: list })
    root.saveLauncherSearchConfig()
  }

  function addLauncherExcludePath(path) {
    var p = String(path || "").trim()
    if (!p) return
    var list = root.launcherSearchConfig.excludePaths.slice()
    if (list.indexOf(p) === -1) list.push(p)
    root.launcherSearchConfig = Object.assign({}, root.launcherSearchConfig, { excludePaths: list })
    root.saveLauncherSearchConfig()
  }

  function removeLauncherExcludePath(path) {
    var list = root.launcherSearchConfig.excludePaths.filter(function(p) { return p !== path })
    root.launcherSearchConfig = Object.assign({}, root.launcherSearchConfig, { excludePaths: list })
    root.saveLauncherSearchConfig()
  }

  function addLauncherExcludeName(name) {
    var n = String(name || "").trim()
    if (!n) return
    var list = root.launcherSearchConfig.excludeNames.slice()
    if (list.indexOf(n) === -1) list.push(n)
    root.launcherSearchConfig = Object.assign({}, root.launcherSearchConfig, { excludeNames: list })
    root.saveLauncherSearchConfig()
  }

  function removeLauncherExcludeName(name) {
    var list = root.launcherSearchConfig.excludeNames.filter(function(n) { return n !== name })
    root.launcherSearchConfig = Object.assign({}, root.launcherSearchConfig, { excludeNames: list })
    root.saveLauncherSearchConfig()
  }

  // Live-discovered mounts for the checklist -- same findmnt --json
  // pipeline FileSearchProvider.qml's own refreshRoots() uses, ported
  // as its own small copy per LauncherSearchConfig.js's own header
  // comment (this is a different Item tree than FileSearchProvider's,
  // no way to share the live property directly). Refreshed when the
  // Launcher category is actually opened (onOpenIndexChanged below),
  // not on a timer.
  property var launcherDiscoveredMounts: []

  function refreshLauncherDiscoveredMounts() {
    launcherMountProc.exec(["findmnt", "--json", "-o", "TARGET,FSTYPE"])
  }

  Process {
    id: launcherMountProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.launcherDiscoveredMounts = LauncherSearchConfig.discoverMountedRoots(text)
    }
  }

  // Merges the live findmnt-discovered mounts with any remembered
  // disabled root that ISN'T currently mounted -- ported verbatim from
  // ruixen.settings/LauncherSettingsContent.qml's own mountChecklist.
  readonly property var mountChecklist: {
    var cfg = root.launcherSearchConfig
    var disabledSet = ({})
    for (var i = 0; i < cfg.disabledAutoRoots.length; i++) disabledSet[cfg.disabledAutoRoots[i]] = true
    var seen = ({})
    var out = []
    var live = root.launcherDiscoveredMounts
    for (var j = 0; j < live.length; j++) {
      seen[live[j].path] = true
      out.push({ path: live[j].path, fstype: live[j].fstype, disabled: !!disabledSet[live[j].path], connected: true })
    }
    for (var k = 0; k < cfg.disabledAutoRoots.length; k++) {
      if (seen[cfg.disabledAutoRoots[k]]) continue
      out.push({ path: cfg.disabledAutoRoots[k], fstype: "", disabled: true, connected: false })
    }
    return out
  }

  Component.onCompleted: ensureAvatarStateDirProc.running = true

  // Same 8 sections, same ids/labels/glyphs as ruixen.settings/
  // Settings.qml's own root.sections -- confirmed by reading that file
  // directly, not guessed, so this list reads as the same feature, not
  // a fork of it. Glyph codepoints copied byte-for-byte from there too.
  // `description` is this pass's own addition -- direct request:
  // "instead of coming soon, just add a small one or two line
  // description for each of the settings? bespoke eloquent tone sounds
  // nice" -- one line each, replaced with real content once each
  // section's actual toggles/inputs land.
  // "Bar" is a deliberate deviation from ruixen.settings' own layout --
  // direct request: "instead of doing the bar customization here i
  // might do a left panel for Bar for bar management instead... Window
  // Curvature, Window Spacing and Animation Style can go here in
  // Profile but the Bar Layout ill probably save it for its own page."
  // The real app bundles Bar Layout alongside Window Curvature/Spacing/
  // Animation Style, all on its own single General/Profile page
  // (confirmed by reading ruixen.settings/GeneralContent.qml directly)
  // -- here Bar Layout gets split out into its own category instead,
  // Profile keeps the rest. No real content for Bar yet, same
  // plain-header-and-description placeholder every other not-yet-built
  // category already gets.
  readonly property var sections: [
    { id: "general", label: "Profile", glyph: "",
      description: "Your identity on this machine — display name, avatar, and the small touches that make Ruixen feel like yours." },
    { id: "bar", label: "Bar", glyph: "",
      description: "Layout, docking, and how the bar itself sits on your screen." },
    { id: "launcher", label: "Launcher", glyph: "",
      description: "How this very launcher searches, ranks, and remembers what matters most the moment you reach for it." },
    { id: "audio", label: "Audio", glyph: "",
      description: "Volume, output routing, and the quieter details of how this machine sounds." },
    { id: "wifi", label: "Wi-Fi", glyph: "",
      description: "Known networks and the signal that keeps this machine reliably reachable." },
    { id: "bluetooth", label: "Bluetooth", glyph: "",
      description: "Paired devices and the wireless companions currently orbiting this machine." },
    { id: "display", label: "Display", glyph: "",
      description: "Brightness and display scale, tuned to how you actually look at this screen." },
    { id: "plugins", label: "Plugins", glyph: "",
      description: "Everything Ruixen has installed, kept updated, and quietly running." },
    { id: "about", label: "About", glyph: "",
      description: "Version, update status, and the fine print behind this shell." }
  ]

  // Filtered by label, same as ruixen.settings/Settings.qml's own
  // filteredSections -- ported logic, not reinvented. Keeps each row's
  // real position in root.sections (originalIndex) rather than the
  // filtered array's own position, same reasoning as that file's own
  // comment: openIndex should always point into the full list
  // underneath, so a since-filtered-out opened category stays correct
  // (just not visible in the list right now) instead of pointing at
  // the wrong section entirely.
  readonly property var filteredSections: {
    var q = root.searchText.trim().toLowerCase()
    var out = []
    for (var i = 0; i < root.sections.length; i++) {
      var s = root.sections[i]
      if (q.length === 0 || s.label.toLowerCase().includes(q))
        out.push({ id: s.id, label: s.label, glyph: s.glyph, originalIndex: i })
    }
    return out
  }

  // Each VISIBLE (filtered) section reshaped into the exact same
  // result-row object shape every other ResultsList model in this
  // plugin already uses (id/providerId/icon/label/breadcrumb/kind/
  // providerName/score/sectionLabel) -- ResultRow itself never needs to
  // know these came from Settings rather than a real provider.
  // providerId "settings-category" isn't dispatched anywhere (this
  // list's own onRowActivated below handles activation directly, the
  // same way Launcher.qml's resultsList does for real results), it's
  // just kept for shape-consistency/future-proofing.
  readonly property var sectionRows: {
    var rows = []
    for (var i = 0; i < root.filteredSections.length; i++) {
      var s = root.filteredSections[i]
      rows.push({
        id: "settings:" + s.id,
        providerId: "settings-category",
        icon: s.glyph,
        label: s.label,
        breadcrumb: "",
        kind: "",
        providerName: "",
        score: 0,
        sectionLabel: "Categories"
      })
    }
    return rows
  }

  // Keyboard cursor over the left list -- indexes into filteredSections
  // (the CURRENT visible list), not root.sections, same distinction
  // ruixen.settings' own sidebarFocusIndex draws. Up/Down move this; it
  // does NOT by itself change what the right panel shows (see openIndex
  // below), matching the user's own "then enter to go into the right
  // panel" phrasing rather than a live-preview-on-hover model.
  property int selectedIndex: 0
  // Index into root.sections (the FULL list, unaffected by filtering).
  // -1 means the right panel shows its own neutral empty state (kept
  // as a fallback, e.g. an out-of-range value); in practice this
  // starts on Profile (0) -- direct request: "we can land in the
  // profile page" -- and Enter/a real row click move it from there,
  // matching ResultsList's own rowActivated meaning everywhere else
  // it's used.
  property int openIndex: 0

  // Up/Down do double duty depending on which level has focus. Enter
  // OPENS a category (shows its content on the right) without also
  // focusing it -- direct correction after the previous "Enter opens
  // AND focuses" pass: "can we not do auto focus on the first item,
  // sometime i just wanna glance through the menu item and i have to
  // go down enter esc down enter esc everytime rn." Browsing every
  // category is now just Down, Enter, Down, Enter... with no Escape
  // ever required, since nothing auto-focuses while doing that. Tab
  // is back as its own, single-purpose gesture (see focusRightPanel's
  // own comment) -- not redundant with Enter this time, since Enter no
  // longer does what Tab does.
  function moveSelectionUp() {
    if (root.rightFocused) { root.moveItemFocusUp(); return }
    if (root.selectedIndex > 0) root.selectedIndex--
  }
  function moveSelectionDown() {
    if (root.rightFocused) { root.moveItemFocusDown(); return }
    if (root.selectedIndex < root.filteredSections.length - 1) root.selectedIndex++
  }
  function activateSelection() {
    if (root.rightFocused) { root.activateFocusedOption(); return }
    if (root.selectedIndex < root.filteredSections.length)
      root.openIndex = root.filteredSections[root.selectedIndex].originalIndex
  }

  // --- Right-panel keyboard focus -- see moveSelectionUp's own
  // comment above for the current interaction shape. Only meaningful
  // while the open category actually has real items -- a plain
  // header+description category has nothing to focus into.
  property bool rightFocused: false
  property int focusedItemIndex: 0
  property int focusedOptionIndex: 0

  // One entry per item card in the CURRENTLY OPEN category, top to
  // bottom -- `options` is the plain list of ids Left/Right cycle
  // through, `current` is whichever one is actually applied right now
  // (used to seed the keyboard cursor when focusing a card), `activate`
  // calls that item's own real setter. A plain data table per category
  // here, not a hardcoded switch in every nav function below, so a new
  // item (or a whole new category) is one more table entry, not a
  // change to the navigation logic itself.
  readonly property var profileItems: [
    {
      options: root.avatarCollections.map(function(c) { return c.id }),
      current: root.avatarCollection,
      activate: function(id) { root.selectAvatar(id) }
    },
    {
      options: ["sharp", "rounded"],
      current: root.cornerCurvature,
      activate: function(id) { root.setCornerCurvature(id) }
    },
    {
      options: ["comfy", "tight"],
      current: root.spacingProfile,
      activate: function(id) { root.setSpacingProfile(id) }
    },
    {
      options: ["calm", "bubbly", "snappy"],
      current: root.animationProfile,
      activate: function(id) { root.setAnimationProfile(id) }
    }
  ]
  readonly property var barItems: [
    {
      options: ["floating", "docked"],
      current: root.barMode,
      activate: function(id) { root.setBarMode(id) }
    }
  ]
  // Every on/off switch on the Launcher page, in the same order
  // they're stacked -- direct report: "the tab kbd stuff not working
  // on launcher setting" (currentItems had no branch for Launcher at
  // all). Each switch modeled as a 2-option item (off/on), same shape
  // as every segmented item above -- Left/Right moves the cursor
  // between the two states, Enter commits whichever one it's on. The
  // three add+list boxes (Custom Search Roots/Excluded Paths/Excluded
  // Directory Names) stay mouse-only -- typing into a text field needs
  // real Qt focus forwarded into that TextInput, a genuinely different
  // piece of work from cycling between labeled options, not an
  // extension of this same shape.
  readonly property var launcherItems: {
    var items = [
      {
        options: ["off", "on"],
        current: root.launcherSearchConfig.includeHome ? "on" : "off",
        activate: function(id) { root.setLauncherIncludeHome(id === "on") }
      },
      {
        options: ["off", "on"],
        current: root.launcherSearchConfig.includeMountedRoots ? "on" : "off",
        activate: function(id) { root.setLauncherIncludeMountedRoots(id === "on") }
      }
    ]
    for (var i = 0; i < root.mountChecklist.length; i++) {
      items.push(root.mountToggleItem(root.mountChecklist[i]))
    }
    return items
  }

  // Split out from launcherItems' own loop body so the closure below
  // captures each mount's own `m.path` correctly -- a function
  // declared directly inside a for-loop body closes over the loop
  // variable itself, not its value at that iteration, and every
  // resulting activate() would silently apply to whichever mount
  // happened to be last.
  function mountToggleItem(m) {
    return {
      options: ["off", "on"],
      current: m.disabled ? "off" : "on",
      activate: function(id) { root.setLauncherAutoRootDisabled(m.path, id === "off") }
    }
  }

  // The single thing every nav function below actually reads --
  // whichever category is open picks its own table, everything else
  // (an empty header+description category) has nothing to navigate.
  readonly property var currentItems: {
    if (root.profileOpen) return root.profileItems
    if (root.barOpen) return root.barItems
    if (root.launcherOpen) return root.launcherItems
    return []
  }

  // Seeds the keyboard cursor to wherever the item's own currently
  // applied option already sits, same "start where you already are"
  // convention the dropdown's own seedDropdownSelection (Launcher.qml)
  // established -- landing on option 0 regardless of the real value
  // would put the cursor somewhere that doesn't match what's actually
  // highlighted as current.
  function seedFocusedOption() {
    var item = root.currentItems[root.focusedItemIndex]
    if (!item) { root.focusedOptionIndex = 0; return }
    var idx = item.options.indexOf(item.current)
    root.focusedOptionIndex = idx >= 0 ? idx : 0
  }

  // Tab's own, single job in this extension now -- drills into the
  // currently-open category's item cards (a no-op via the
  // currentItems.length guard for a plain header+description category
  // with nothing to focus). Enter no longer calls this at all; see
  // activateSelection's own comment.
  function focusRightPanel() {
    if (root.currentItems.length === 0) return
    root.rightFocused = true
    root.focusedItemIndex = 0
    root.seedFocusedOption()
    Qt.callLater(root.scrollToFocusedItem)
  }

  function blurToLeftPanel() {
    root.rightFocused = false
  }

  // Up/Down between item cards while the right panel has focus --
  // wraps at either end rather than dead-ending, same as the left
  // category list already effectively does via filteredSections.
  function moveItemFocusUp() {
    if (root.currentItems.length === 0) return
    root.focusedItemIndex = (root.focusedItemIndex - 1 + root.currentItems.length) % root.currentItems.length
    root.seedFocusedOption()
    Qt.callLater(root.scrollToFocusedItem)
  }
  function moveItemFocusDown() {
    if (root.currentItems.length === 0) return
    root.focusedItemIndex = (root.focusedItemIndex + 1) % root.currentItems.length
    root.seedFocusedOption()
    Qt.callLater(root.scrollToFocusedItem)
  }

  // Direct follow-up: "when i tab to the animation style, can the
  // panel know to flick up or down depending on where the options
  // are?" -- Tab can land on a card the Flickable hasn't scrolled to
  // yet (Animation Style, the last one, sits below the fold at the
  // panel's normal scroll position). Same "only scroll the minimum
  // needed" shape a scrolloff implementation uses: nudge up if the
  // card's top is above the visible top, nudge down if its bottom is
  // below the visible bottom, otherwise leave contentY alone (a card
  // already fully in view shouldn't jump for no reason). Qt.callLater
  // in every caller -- a card's own height can depend on content that
  // hasn't finished laying out in the same tick focus moved to it.
  // Profile/Bar's own items are whole cards, direct children of
  // rightContentColumn -- plain `.y` was enough. Launcher's items are
  // individual SettingsToggleRow instances NESTED inside a card
  // (launcherToggleItem) or a Repeater (mountRepeater), so their
  // position relative to rightContentColumn has to go through
  // mapToItem rather than a bare `.y` (which would only ever be
  // relative to their own immediate parent).
  function focusedItemVisual() {
    if (root.profileOpen) {
      return [profilePictureItem, windowCurvatureItem, windowSpacingItem, animationStyleItem][root.focusedItemIndex]
    }
    if (root.barOpen) {
      return [barLayoutItem][root.focusedItemIndex]
    }
    if (root.launcherOpen) {
      if (root.focusedItemIndex === 0) return includeHomeRow
      if (root.focusedItemIndex === 1) return includeMountedRow
      return mountRepeater.itemAt(root.focusedItemIndex - 2)
    }
    return null
  }

  function scrollToFocusedItem() {
    var item = root.focusedItemVisual()
    if (!item) return
    var pos = item.mapToItem(rightContentColumn, 0, 0)
    var itemTop = rightContentColumn.y + pos.y
    var itemBottom = itemTop + item.height
    if (itemTop < rightPaneScroll.contentY) {
      rightPaneScroll.contentY = Math.max(0, itemTop - 8)
    } else if (itemBottom > rightPaneScroll.contentY + rightPaneScroll.height) {
      rightPaneScroll.contentY = Math.min(rightPaneScroll.contentHeight - rightPaneScroll.height, itemBottom + 8 - rightPaneScroll.height)
    }
  }

  function moveOptionLeft() {
    if (!root.rightFocused) return
    var item = root.currentItems[root.focusedItemIndex]
    if (!item || item.options.length === 0) return
    root.focusedOptionIndex = (root.focusedOptionIndex - 1 + item.options.length) % item.options.length
  }

  function moveOptionRight() {
    if (!root.rightFocused) return
    var item = root.currentItems[root.focusedItemIndex]
    if (!item || item.options.length === 0) return
    root.focusedOptionIndex = (root.focusedOptionIndex + 1) % item.options.length
  }

  function activateFocusedOption() {
    var item = root.currentItems[root.focusedItemIndex]
    if (!item) return
    item.activate(item.options[root.focusedOptionIndex])
  }

  // No stale keyboard focus surviving a category switch -- landing on
  // a different category (a click, or Enter on a new left-panel row)
  // always starts back on the left panel's own list, never mid-way
  // into whatever the PREVIOUS category's right-panel cursor happened
  // to be on.
  onOpenIndexChanged: {
    root.rightFocused = false
    root.focusedItemIndex = 0
    rightPaneScroll.contentY = 0
    // Fresh mount list every time Launcher is (re)opened -- a drive
    // plugged in or removed since the last visit should show up
    // without needing a full shell restart, same reasoning
    // FileSearchProvider.qml's own refreshRoots() already applies.
    if (root.launcherOpen) root.refreshLauncherDiscoveredMounts()
  }

  // Fresh cursor on every new query, same as every other search
  // surface in this plugin (onQueryChanged/onFilesModeChanged) -- a
  // stale selectedIndex from before a keystroke could otherwise land
  // past the end of a now-shorter filtered list, or highlight a
  // visually different row than the one that was actually highlighted
  // a moment ago.
  onSearchTextChanged: root.selectedIndex = 0

  // Fresh state every time the extension is (re)entered -- same
  // "no stale cursor from last time" convention onFilesModeChanged/
  // onOpenedChanged already apply elsewhere in this plugin.
  onActiveChanged: {
    if (root.active) {
      root.selectedIndex = 0
      root.openIndex = 0
      // Explicit, not left to onOpenIndexChanged alone -- openIndex
      // may already BE 0 from a previous visit (no change event to
      // react to), which would otherwise leave a stale right-panel
      // focus active the moment this extension reopens.
      root.rightFocused = false
      root.focusedItemIndex = 0
      rightPaneScroll.contentY = 0
      // Same "fetch once" gate ruixen.settings' own onOpenedChanged
      // uses -- fastfetch is not free enough to re-run every time this
      // extension is (re)entered.
      if (root.hardwareName === "") identityProc.running = true
      // Unlike hardwareName above, these two are cheap AND can
      // genuinely change out from under this extension between visits
      // (the real ruixen.settings panel, or a CLI run of
      // ruixen-lookfeel.sh, changing curvature) -- refreshed on every
      // entry, unconditionally, same as ruixen.settings' own
      // onOpenedChanged does for both.
      cornerCurvatureReadProc.running = true
      spacingProfileReadProc.running = true
      animationProfileReadProc.running = true
      barModeReadProc.running = true
    }
  }

  ExtensionTwoPanel {
    id: panel
    anchors.fill: parent
  }

  // Reparented into panel's own left slot (see ExtensionTwoPanel.qml's
  // own header comment for why a slot Item + `parent:` beats a Loader/
  // Component here) -- every binding below is a plain, direct binding
  // off this file's own root, exactly like Launcher.qml's real
  // resultsList instantiation.
  ResultsList {
    parent: panel.leftPane
    anchors.fill: parent
    model: root.sectionRows
    // Icon+label only, no meta/kind/keybind columns -- the exact same
    // reduced row Search Files itself renders through this same flag,
    // which is the whole point: this isn't a look-alike, it's the same
    // component in the same mode.
    filesMode: true
    selectedIndex: root.selectedIndex
    textColor: root.textColor
    mutedColor: root.muted
    accentColor: root.accent
    fontFamily: root.fontFamily
    onRowHovered: (idx) => { root.selectedIndex = idx }
    onRowActivated: (idx) => {
      root.selectedIndex = idx
      if (idx < root.filteredSections.length)
        root.openIndex = root.filteredSections[idx].originalIndex
    }
  }

  // Same "typo'd query, empty sidebar" edge case ruixen.settings' own
  // empty state covers -- 8 rows is rare to filter down to nothing,
  // but not impossible.
  Text {
    parent: panel.leftPane
    anchors.centerIn: parent
    width: parent.width - 16
    visible: root.filteredSections.length === 0
    horizontalAlignment: Text.AlignHCenter
    wrapMode: Text.WordWrap
    text: "No matches"
    font.family: root.fontFamily
    font.pixelSize: 11
    color: root.muted
  }

  // Fallback only -- openIndex starts on Profile (0) now and every
  // activation/click keeps it in range, so this shouldn't normally be
  // reachable, but it's cheap insurance against an out-of-range value
  // rather than rendering nothing at all.
  Column {
    parent: panel.rightPane
    anchors.centerIn: parent
    spacing: 6
    visible: root.openIndex < 0 || root.openIndex >= root.sections.length

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: ""
      font.family: root.fontFamily
      font.pixelSize: 22
      color: root.muted
    }
    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      text: "Select a category and press Enter"
      font.family: root.fontFamily
      font.pixelSize: 12
      color: root.muted
    }
  }

  // True while Profile specifically is open -- checked by id, not the
  // bare index 0, so this stays correct even if sections' own order
  // ever changes.
  readonly property bool profileOpen: root.openIndex >= 0
    && root.openIndex < root.sections.length
    && root.sections[root.openIndex].id === "general"
  readonly property bool barOpen: root.openIndex >= 0
    && root.openIndex < root.sections.length
    && root.sections[root.openIndex].id === "bar"
  readonly property bool launcherOpen: root.openIndex >= 0
    && root.openIndex < root.sections.length
    && root.sections[root.openIndex].id === "launcher"

  // Every category's right-panel content, Profile included, scrolls as
  // ONE unit -- direct request: "we need the right panel to be able to
  // scroll down with mouse wheel" (Profile's own 4 stacked item cards
  // can run past the panel's fixed viewport height). A plain Flickable,
  // same "no overscroll bounce" convention ResultsList.qml/ruixen.
  // settings' own detail Flickable already use -- Column, not manual
  // anchor-chaining between siblings, so contentHeight is just the
  // Column's own height and a short/plain category (header +
  // description only, no item cards) needs no special-casing: Column
  // already skips each `visible: false` item card's own space, exactly
  // like it did as anchor-chained siblings before.
  Flickable {
    id: rightPaneScroll
    parent: panel.rightPane
    anchors.fill: parent
    contentWidth: width
    // rightContentColumn's own y (20, matching its x inset) plus a
    // matching 20 at the bottom -- direct report: "it doesnt scroll
    // down enough, im only seeeing half of the last item". This was
    // rightContentColumn.height alone, which is only the COLUMN's own
    // stacked height -- it doesn't know about the 20px it's offset
    // down by, so the Flickable thought the content ended 20px (plus,
    // with no bottom inset at all, the last item sat flush against
    // that miscalculated edge) before it actually does.
    contentHeight: rightContentColumn.y + rightContentColumn.height + 20
    boundsBehavior: Flickable.StopAtBounds
    clip: true

    Column {
      id: rightContentColumn
      x: 20
      y: 20
      width: parent.width - 40
      // One uniform gap between every stacked element (header down
      // through the last item card) -- simpler than the two slightly
      // different gaps (16 header-to-first-card, 12 card-to-card) the
      // previous anchor-chained version used, and the difference
      // wasn't something anyone asked to preserve.
      spacing: 16

  // Every category's right-panel content, Profile included, starts
  // with this same header (its own label) + short description -- a
  // plain layout convention every future real panel keeps building on
  // top of, not a separate component of its own (there's nothing else
  // here yet to warrant one). Direct correction: Profile's own real
  // content (below) had quietly REPLACED this instead of sitting under
  // it -- "why did you nuke the Profile and description subtitle we
  // had above it? keep it there please".
  Column {
    id: headerColumn
    width: parent.width
    spacing: 6
    visible: root.openIndex >= 0 && root.openIndex < root.sections.length

    Text {
      width: parent.width
      text: root.openIndex >= 0 && root.openIndex < root.sections.length
        ? root.sections[root.openIndex].label : ""
      font.family: root.fontFamily
      font.pixelSize: 16
      font.weight: Font.DemiBold
      color: root.textColor
    }
    Text {
      width: parent.width
      text: root.openIndex >= 0 && root.openIndex < root.sections.length
        ? root.sections[root.openIndex].description : ""
      wrapMode: Text.WordWrap
      lineHeight: 1.3
      font.family: root.fontFamily
      font.pixelSize: 12
      color: root.muted
    }
  }

  // Profile's own real content -- centered avatar + username@machine,
  // then the DiceBear collection picker -- ported from ruixen.settings/
  // GeneralContent.qml's own avatar card (see this file's header
  // comment). Sits BELOW headerColumn (its "Profile" label + subtitle
  // stay in place), not instead of it. No card background/border here
  // (unlike the real app's own black card) -- this pane is already the
  // ghost/ContentPage treatment every extension's right side uses, a
  // second nested card would be a surface-on-a-surface with nothing to
  // visually separate.
  // Frames this one setting as a distinct menu item/option -- direct
  // follow-up: "this would be considered an option or menu item, how
  // do we group it as that... put that darker bg tonal we used for
  // the file picker text or zebra stripe... frame this as a item but
  // dont frame the header Profile and description in it though." Same
  // dark tonal FileDetailsPanel.qml's own zebra-striped metadata rows
  // already use (Qt.rgba(0, 0, 0, 0.18)) -- this is that same"item"
  // treatment scaled up to a whole option's card instead of one thin
  // row, not a new color invented for this. headerColumn (the page's
  // own "Profile" title + description) stays a separate, unframed
  // sibling above -- explicitly not wrapped in this.
  Rectangle {
    id: profilePictureItem
    width: parent.width
    height: profilePictureContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    // Card-level focus ring -- direct request: "tab between cards...
    // then left or right direction and enter for that option". Shown
    // whenever this is the Tab-focused card, regardless of which of
    // its own options the cursor is on.
    border.width: root.rightFocused && root.focusedItemIndex === 0 ? 1 : 0
    border.color: root.accent
    visible: root.profileOpen

    Column {
      id: profilePictureContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      // Each individual setting gets its OWN plain, descriptive label
      // -- no separate subtitle underneath it -- direct correction:
      // "for this first setting option we can put Select Profile
      // Picture. i dont think these options need subtitle if we make
      // the option... kind a descriptive? itll be good for searching
      // for them later too." This is the per-ITEM label (distinct
      // from headerColumn's own per-PAGE "Profile" title above); every
      // future real setting in any category follows this same
      // one-line, self-descriptive convention rather than a
      // title+subtitle pair. Shortened to "Profile Picture" per direct
      // follow-up.
      Text {
        text: "Profile Picture"
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.textColor
      }

      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        width: 64
        height: 64

        // Circular gradient fallback -- explicitly hidden once a real
        // image is loaded (not just painted over by an assumed-opaque
        // one), so nothing is left behind for any load-state edge case
        // to reveal.
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          visible: avatarPreviewImage.status !== Image.Ready
          gradient: Gradient {
            GradientStop { position: 0.0; color: Qt.lighter(root.accent, 1.6) }
            GradientStop { position: 1.0; color: Qt.darker(root.accent, 1.4) }
          }
        }

        // "#" cache-bust fragment, not "?" -- Qt's local file:// loader
        // can try to resolve a "?"-suffixed string as a literal filename
        // instead of stripping it, unlike an HTTP server. A URL fragment
        // is always stripped before path resolution, busting the Image's
        // own source-string cache (needed since a new avatar overwrites
        // the exact same path) without that risk.
        Image {
          id: avatarPreviewImage
          anchors.fill: parent
          source: "file://" + Quickshell.env("HOME") + "/.face.icon#" + root.avatarCacheBust
          fillMode: Image.PreserveAspectCrop
          asynchronous: true
          cache: false
          visible: false
        }

        Rectangle {
          id: avatarPreviewMask
          anchors.fill: parent
          radius: width * 0.2
          color: "#ffffff"
          visible: false
          layer.enabled: true
        }

        MultiEffect {
          anchors.fill: parent
          source: avatarPreviewImage
          maskEnabled: true
          maskSource: avatarPreviewMask
          maskThresholdMin: 0.5
          maskThresholdMax: 1.0
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: Quickshell.env("USER") + "@" + root.hardwareName
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.muted
      }

      // Selecting one both picks it (highlighted border) AND immediately
      // applies it -- no separate "pick then press an action button"
      // step, same as the real picker. Flow, not a Row -- 9 labels don't
      // reliably fit one line at this panel's width.
      Flow {
        width: parent.width
        spacing: 6

        Repeater {
          model: root.avatarCollections

          Rectangle {
            id: collectionBtn
            required property var modelData
            required property int index
            readonly property bool isCurrent: root.avatarCollection === collectionBtn.modelData.id
            // Keyboard cursor position, distinct from isCurrent (the
            // actually-applied value) -- direct request: "tab between
            // cards options and then left or right direction and enter
            // for that option". Direct correction: an all-white border
            // here read as bad design, clobbering the accent ring's own
            // meaning -- shown as an underline on the label instead
            // (below), leaving border.color alone entirely.
            readonly property bool isFocused: root.rightFocused
              && root.focusedItemIndex === 0 && root.focusedOptionIndex === collectionBtn.index

            width: collectionLabel.implicitWidth + 16
            height: 24
            radius: 6
            color: collectionBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
            border.width: 1
            border.color: collectionBtn.isCurrent ? root.accent : Qt.rgba(1, 1, 1, 0.12)
            opacity: root.avatarBusy ? 0.5 : 1

            Text {
              id: collectionLabel
              anchors.centerIn: parent
              text: collectionBtn.modelData.label
              font.family: root.fontFamily
              font.pixelSize: 10
              font.weight: collectionBtn.isCurrent ? Font.DemiBold : Font.Normal
              color: collectionBtn.isCurrent ? root.textColor : root.muted
            }

            // Accent-colored underline, not font.underline -- direct
            // correction: "the underline kinda hard to see, use the
            // accent color for the underline?" font.underline always
            // draws in the text's OWN color (muted when not current),
            // which is exactly why it read as faint; a separate bar
            // can be any color regardless of the label's own.
            Rectangle {
              visible: collectionBtn.isFocused
              anchors.top: collectionLabel.bottom
              anchors.horizontalCenter: collectionLabel.horizontalCenter
              width: collectionLabel.paintedWidth
              height: 1
              color: root.accent
            }

            MouseArea {
              anchors.fill: parent
              enabled: !root.avatarBusy
              cursorShape: Qt.PointingHandCursor
              onClicked: root.selectAvatar(collectionBtn.modelData.id)
            }
          }
        }
      }
    }
  }

  // Second/third/fourth Profile items -- SettingsSegmentedItem.qml,
  // the shared "segmented option" card three near-identical hand-
  // rolled copies got extracted into: "how do we keep this pattern
  // going? easy to reuse". Ported values (options/current/activate)
  // still come from ruixen.settings, unchanged -- only the visual
  // shell moved into the shared component.
  SettingsSegmentedItem {
    id: windowCurvatureItem
    label: "Window Curvature"
    options: [
      { id: "sharp", label: "Sharp" },
      { id: "rounded", label: "Rounded" }
    ]
    current: root.cornerCurvature
    cardFocused: root.rightFocused && root.focusedItemIndex === 1
    focusedOptionIndex: cardFocused ? root.focusedOptionIndex : -1
    visible: root.profileOpen
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onActivated: (id) => root.setCornerCurvature(id)
  }

  SettingsSegmentedItem {
    id: windowSpacingItem
    label: "Window Spacing"
    options: [
      { id: "comfy", label: "Comfy" },
      { id: "tight", label: "Tight" }
    ]
    current: root.spacingProfile
    cardFocused: root.rightFocused && root.focusedItemIndex === 2
    focusedOptionIndex: cardFocused ? root.focusedOptionIndex : -1
    visible: root.profileOpen
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onActivated: (id) => root.setSpacingProfile(id)
  }

  SettingsSegmentedItem {
    id: animationStyleItem
    label: "Animation Style"
    // Calm first (the real app's own default), then Bubbly, then
    // Snappy -- matches ruixen.settings/GeneralContent.qml's own model
    // order exactly, not alphabetical.
    options: [
      { id: "calm", label: "Calm" },
      { id: "bubbly", label: "Bubbly" },
      { id: "snappy", label: "Snappy" }
    ]
    current: root.animationProfile
    cardFocused: root.rightFocused && root.focusedItemIndex === 3
    focusedOptionIndex: cardFocused ? root.focusedOptionIndex : -1
    visible: root.profileOpen
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onActivated: (id) => root.setAnimationProfile(id)
  }

  // Bar's own single item -- direct request: "think we're ready for
  // the bar page next, it should just be one setting option there for
  // bar layout floating or dock." A plain Column child like the three
  // above, not anchored -- Column already skips every invisible
  // sibling's space, so with Profile's own four items all hidden while
  // Bar is open, this naturally lands right after headerColumn with
  // the Column's own 16px spacing between them, same as every other
  // item-after-header gap.
  SettingsSegmentedItem {
    id: barLayoutItem
    label: "Bar Layout"
    options: [
      { id: "floating", label: "Floating" },
      { id: "docked", label: "Docked" }
    ]
    current: root.barMode
    cardFocused: root.rightFocused && root.focusedItemIndex === 0
    focusedOptionIndex: cardFocused ? root.focusedOptionIndex : -1
    visible: root.barOpen
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onActivated: (id) => root.setBarMode(id)
  }

  // Launcher's own first item -- two on/off toggles grouped in one
  // card, matching ruixen.settings/LauncherSettingsContent.qml's own
  // "Launcher" card exactly (both toggles together, not one card
  // each). Mouse-only for this pass, deliberately not wired into the
  // Tab/Up-Down/Left-Right/Enter keyboard model SettingsSegmentedItem
  // items use -- a toggle's own natural interaction (flip it directly)
  // doesn't fit that "cycle between N options" shape, and building a
  // real keyboard model for it is its own separate piece of work, not
  // a same-shape extension of this one. The mounted-drives checklist,
  // custom roots, and path/name exclusions from the real page are
  // real follow-on work too, not part of this pass.
  Rectangle {
    id: launcherToggleItem
    width: parent.width
    height: launcherToggleContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.launcherOpen

    Column {
      id: launcherToggleContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Launcher Search"
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.textColor
      }

      SettingsToggleRow {
        id: includeHomeRow
        label: "Include Home"
        checked: root.launcherSearchConfig.includeHome
        rowFocused: root.launcherOpen && root.rightFocused && root.focusedItemIndex === 0
        textColor: root.textColor
        accent: root.accent
        fontFamily: root.fontFamily
        onToggled: (value) => root.setLauncherIncludeHome(value)
      }

      SettingsToggleRow {
        id: includeMountedRow
        label: "Auto-include Mounted Drives"
        checked: root.launcherSearchConfig.includeMountedRoots
        rowFocused: root.launcherOpen && root.rightFocused && root.focusedItemIndex === 1
        textColor: root.textColor
        accent: root.accent
        fontFamily: root.fontFamily
        onToggled: (value) => root.setLauncherIncludeMountedRoots(value)
      }
    }
  }

  // Launcher's second item -- one toggle per discovered mount, ported
  // from ruixen.settings/LauncherSettingsContent.qml's own "MOUNTED
  // DRIVES" checklist. A disabled-but-unmounted entry (see
  // toggleLauncherAutoRootDisabled's own comment) shows its own "Not
  // currently connected" subtitle via SettingsToggleRow's own
  // `subtitle` -- the exact shape that prop was added for.
  Rectangle {
    id: mountedDrivesItem
    width: parent.width
    height: mountedDrivesContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.launcherOpen

    Column {
      id: mountedDrivesContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 10

      Text {
        text: "Mounted Drives"
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.textColor
      }

      // Centered icon + caption, matching ruixen.launcher's own
      // EmptyState.qml "No Results" treatment -- same fa-hdd_o
      // (U+F0A0) glyph, confirmed present in JetBrainsMono Nerd Font's
      // cmap directly (same convention as every other \u-escaped glyph
      // in this file).
      Column {
        width: parent.width
        visible: root.mountChecklist.length === 0
        spacing: 4

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: ""
          font.family: root.fontFamily
          font.pixelSize: 20
          color: root.muted
        }
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          text: "No drives detected"
          font.family: root.fontFamily
          font.pixelSize: 11
          color: root.muted
        }
      }

      Column {
        width: parent.width
        spacing: 10

        Repeater {
          id: mountRepeater
          model: root.mountChecklist

          SettingsToggleRow {
            required property var modelData
            required property int index
            width: parent.width
            label: modelData.path
            subtitle: modelData.connected ? "" : "Not currently connected"
            elideLabel: true
            checked: !modelData.disabled
            rowFocused: root.launcherOpen && root.rightFocused && root.focusedItemIndex === (2 + index)
            textColor: root.textColor
            muted: root.muted
            accent: root.accent
            fontFamily: root.fontFamily
            onToggled: root.toggleLauncherAutoRootDisabled(modelData.path)
          }
        }
      }
    }
  }

  // Launcher's third/fourth/fifth items -- the three remaining
  // sections from ruixen.settings/LauncherSettingsContent.qml, all on
  // SettingsAddListItem.qml (see its own header comment for why one
  // component covers all three shapes).
  SettingsAddListItem {
    id: customRootsItem
    label: "Custom Search Roots"
    placeholder: "~/Work or /mnt/Documents"
    items: root.launcherSearchConfig.roots
    visible: root.launcherOpen
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onAdded: (value) => root.addLauncherRoot(value)
    onRemoved: (value) => root.removeLauncherRoot(value)
  }

  SettingsAddListItem {
    id: excludedPathsItem
    label: "Excluded Paths"
    placeholder: "~/VMs or ~/Downloads/ISOs"
    items: root.launcherSearchConfig.excludePaths
    visible: root.launcherOpen
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onAdded: (value) => root.addLauncherExcludePath(value)
    onRemoved: (value) => root.removeLauncherExcludePath(value)
  }

  SettingsAddListItem {
    id: excludedNamesItem
    label: "Excluded Directory Names"
    placeholder: "e.g. dist or .venv"
    chipMode: true
    items: root.launcherSearchConfig.excludeNames
    visible: root.launcherOpen
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onAdded: (value) => root.addLauncherExcludeName(value)
    onRemoved: (value) => root.removeLauncherExcludeName(value)
  }
    }
  }
}
