import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
import "services"
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
  // Relayed up to Launcher.qml (searchHeader.focusInput()) whenever a
  // text-entry item's own real Qt focus needs to hand back to the
  // fake-focus keyboard nav -- see SettingsAddListItem.qml's own
  // cancelled() comment for the full chain.
  signal returnFocusRequested()

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

  // --- Audio: real Pipewire volume + output/input device pickers,
  // ported from ruixen.settings/AudioContent.qml + its Settings.qml
  // backend (outputSink/outputVolume/outputMuted/outputDevices/
  // setOutputVolume/toggleOutputMute/setDefaultOutput, and the input
  // mirror of each). Quickshell.Services.Pipewire is a standard
  // Quickshell module (not Omarchy-private, confirmed by reading
  // Omarchy's own audio bar-widget directly for these exact property
  // paths, same as the real page's own comment already documents) --
  // no repo-checkout dependency, no shell restart, standalone-safe by
  // construction the same way Window Spacing/Animation Style already
  // are.
  readonly property var outputSink: Pipewire.defaultAudioSink
  readonly property real outputVolume: outputSink && outputSink.audio ? outputSink.audio.volume : 0
  readonly property bool outputMuted: outputSink && outputSink.audio ? outputSink.audio.muted : false

  readonly property var outputDevices: {
    var list = []
    var all = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < all.length; i++) {
      var n = all[i]
      if (n && n.isSink && !n.isStream) list.push(n)
    }
    return list
  }

  function setOutputVolume(v) {
    if (root.outputSink && root.outputSink.audio)
      root.outputSink.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleOutputMute() {
    if (root.outputSink && root.outputSink.audio)
      root.outputSink.audio.muted = !root.outputSink.audio.muted
  }

  function setDefaultOutput(node) {
    Pipewire.preferredDefaultAudioSink = node
  }

  // Input (microphone) -- same real API shape as output, mirrored from
  // Omarchy's own Panel.qml. isSource's filter is broader than isSink/
  // isStream alone -- a source node can be a true audio source without
  // node.isSink ever being set.
  readonly property var inputSource: Pipewire.defaultAudioSource
  readonly property real inputVolume: inputSource && inputSource.audio ? inputSource.audio.volume : 0
  readonly property bool inputMuted: inputSource && inputSource.audio ? inputSource.audio.muted : false

  readonly property var inputDevices: {
    var list = []
    var all = Pipewire.nodes ? Pipewire.nodes.values : []
    for (var i = 0; i < all.length; i++) {
      var n = all[i]
      if (!n || n.isSink || n.isStream) continue
      var mediaClass = String(n.type || "")
      var isSource = !!n.audio || mediaClass.indexOf("Audio/Source") !== -1
        || mediaClass.indexOf("AudioSource") !== -1 || mediaClass.indexOf("Source") !== -1
      if (!isSource) continue
      if ((n.name || "") === "quickshell") continue
      list.push(n)
    }
    return list
  }

  function setInputVolume(v) {
    if (root.inputSource && root.inputSource.audio)
      root.inputSource.audio.volume = Math.max(0, Math.min(1, v))
  }

  function toggleInputMute() {
    if (root.inputSource && root.inputSource.audio)
      root.inputSource.audio.muted = !root.inputSource.audio.muted
  }

  function setDefaultInput(node) {
    Pipewire.preferredDefaultAudioSource = node
  }

  // Audio's own top-level on/off, same hero-switch semantics as
  // Omarchy's own audio panel (confirmed by reading
  // $OMARCHY_PATH/shell/plugins/panels/audio/Panel.qml directly, not
  // guessed) -- PipeWire itself has no real "off" state for a sink/
  // source the way a Wi-Fi/Bluetooth radio does, so this is a mute-both
  // toggle standing in for one: reads as on while anything is still
  // audible (either channel), and a single press mutes BOTH output and
  // input together, or unmutes both together, whichever the current
  // state calls for. Muting just one channel from its own row below
  // does NOT flip this master switch off by itself -- only when both
  // end up muted does anyAudible go false.
  readonly property bool anyAudible: (!!root.outputSink && !root.outputMuted) || (!!root.inputSource && !root.inputMuted)

  function toggleAllMuted() {
    var mute = root.anyAudible
    if (root.outputSink && root.outputSink.audio) root.outputSink.audio.muted = mute
    if (root.inputSource && root.inputSource.audio) root.inputSource.audio.muted = mute
  }

  // Same real property-preference order as Omarchy's own nodeLabel()/
  // friendlyDeviceLabel(), ported directly: nickname/nick fields
  // first, falling back to description/name, then trimmed of the same
  // noisy driver-name prefixes/suffixes and the Microphones->Microphone
  // normalization real hardware strings carry. Shared by both output
  // and input rows.
  function deviceLabel(node) {
    if (!node) return "Unknown"
    var props = (node.ready && node.properties) ? node.properties : {}
    var nickname = node.nickname || node.nick || props["node.nick"] || props["device.profile.description"] || ""
    var label = String(nickname || node.description || props["node.description"] || node.name || "Unknown").trim()
    label = label.replace(/^sof-soundwire\s+/i, "")
    label = label.replace(/^built-?in audio\s+/i, "")
    label = label.replace(/\s+Output$/i, "")
    label = label.replace(/\s+Input$/i, "")
    label = label.replace(/\bMicrophones\b/g, "Microphone")
    return label
  }

  // Binds/tracks the candidate output/input nodes so their volume/
  // muted/name properties actually receive live updates.
  PwObjectTracker { objects: root.outputDevices }
  PwObjectTracker { objects: root.inputDevices }

  // --- Display: real brightness + scale, ported from ruixen.settings/
  // DisplayContent.qml + its Settings.qml backend (brightnessPercent/
  // focusedMonitor/brightnessAvailable/setBrightness, scalePresets/
  // displayScale/setDisplayScale). Same real omarchy-monitor-state
  // read / omarchy-brightness-display + omarchy-hyprland-monitor-
  // scaling write mechanism ruixen-notch's own proven brightness
  // control already uses -- no repo-checkout dependency, no shell
  // restart, standalone-safe the same way Audio already is.
  property real brightnessPercent: 50
  property string focusedMonitor: ""
  property bool brightnessAvailable: false

  Process {
    id: brightnessStateProc
    command: ["omarchy-monitor-state"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var lines = String(text || "").split("\n")
        var b = String(lines[0] || "").trim()
        // An empty first line isn't the same as a genuine
        // "unavailable" response (a real race with ruixen-notch's own
        // independent poll of the same command, confirmed live in the
        // real app) -- ignored rather than treated as authoritative,
        // keeping the last known good state.
        if (b === "") return
        root.brightnessAvailable = b !== "unavailable"
        if (root.brightnessAvailable) root.brightnessPercent = Math.max(0, Math.min(100, parseInt(b, 10)))
        root.focusedMonitor = String(lines[5] || "").trim()
        var scaleLine = parseFloat(String(lines[6] || "").trim())
        if (isFinite(scaleLine)) root.displayScale = String(Math.round(scaleLine * 100) / 100)
      }
    }
  }

  Timer {
    interval: 5000
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!brightnessStateProc.running) brightnessStateProc.running = true
  }

  Process {
    id: setBrightnessProc
    stdout: StdioCollector { waitForEnd: true }
    // Deliberately does NOT trigger a re-read on completion -- same
    // reasoning ported from ruixen-notch's own comment: re-reading via
    // omarchy-monitor-state right after a write races the hardware/
    // driver and can return an empty string, briefly bouncing the
    // slider back to 0. The locally-set value is authoritative until
    // the next periodic poll.
  }

  function setBrightness(percent) {
    var p = Math.max(0, Math.min(100, Math.round(percent)))
    root.brightnessPercent = p
    setBrightnessProc.command = ["omarchy-brightness-display", "--no-osd", "--monitor", root.focusedMonitor, p + "%"]
    setBrightnessProc.running = true
  }

  // Display scale (Hyprland's own per-monitor fractional scaling) --
  // real presets ported from Omarchy's own scalePresets in Panel.qml.
  readonly property var scalePresets: ["1", "1.25", "1.6", "2", "3", "4"]
  property string displayScale: ""

  Process {
    id: setScaleProc
    stdout: StdioCollector { waitForEnd: true }
  }

  function setDisplayScale(scale) {
    root.displayScale = scale
    setScaleProc.command = ["bash", "-c", "omarchy-hyprland-monitor-scaling " + scale]
    setScaleProc.running = true
  }

  // Real Quickshell.Networking-backed Wi-Fi state -- another standard
  // Quickshell module, confirmed the same way Audio's own Pipewire
  // backend was (reading Omarchy's own network bar-widget directly).
  // Scoped the same as ruixen.settings' own real page: status + known-
  // network switcher + connect to open/known/new-secured networks, no
  // WPA-Enterprise flow (rare outside campus/corporate Wi-Fi, a real
  // separate nmcli-scripted flow their own file documents as its own
  // out-of-scope case too).
  readonly property var networkDevices: Networking.devices ? Networking.devices.values : []

  function findWifiDevice() {
    var devices = root.networkDevices
    var fallback = null
    for (var i = 0; i < devices.length; i++) {
      var d = devices[i]
      if (!d || d.type !== DeviceType.Wifi) continue
      if (d.connected) return d
      if (!fallback) fallback = d
    }
    return fallback
  }

  readonly property var wifiDevice: findWifiDevice()
  readonly property var wifiNetworkObjects: wifiDevice && wifiDevice.networks ? wifiDevice.networks.values : []
  property var wifiRows: []

  // Primitives only, not the live WifiNetwork objects -- ported
  // directly from ruixen.settings/Settings.qml's own syncWifiNetworks()
  // comment: NetworkManager scan churn can destroy a network object
  // while a delegate built from it is still incubating, which segfaults
  // quickshell if a live QObject wrapper sits in list-model data.
  // Connecting resolves back to the live object via networkForSsid() at
  // activate time instead.
  function syncWifiNetworks() {
    // Skip while a password prompt is open -- a scan tick mid-typing
    // would replace wifiRows with a brand-new array, tearing down and
    // recreating every row (including the one whose password field is
    // focused). Caught up again in closeWifiPasswordPrompt() below.
    if (root.wifiPasswordSsid !== "") return
    var nets = []
    var networks = root.wifiNetworkObjects
    for (var i = 0; i < networks.length; i++) {
      var n = networks[i]
      if (!n) continue
      nets.push({
        connected: !!n.connected,
        known: !!n.known,
        ssid: n.name || "",
        signal: Math.round((n.signalStrength || 0) * 100),
        security: n.security
      })
    }
    nets.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      if (a.known !== b.known) return a.known ? -1 : 1
      return b.signal - a.signal
    })
    root.wifiRows = nets
  }

  onWifiNetworkObjectsChanged: root.syncWifiNetworks()

  readonly property var connectedWifiNetwork: {
    for (var i = 0; i < root.wifiRows.length; i++)
      if (root.wifiRows[i].connected) return root.wifiRows[i]
    return null
  }

  readonly property var knownWifiRows: root.wifiRows.filter(function(r) { return r.known })
  readonly property var otherWifiRows: root.wifiRows.filter(function(r) { return !r.known })

  function isOpenNetwork(security) {
    return security === WifiSecurityType.Open
  }

  function networkForSsid(ssid) {
    var networks = root.wifiNetworkObjects
    for (var i = 0; i < networks.length; i++)
      if (networks[i] && networks[i].name === ssid) return networks[i]
    return null
  }

  // Passphrase prompt state for connecting to a new (unknown) protected
  // network. Unlike the real page's own wifiPasswordAttempt, the typed
  // password never lives here -- SettingsWifiRow.qml keeps it locally
  // and hands it over once, via passwordSubmitted(password), since
  // nothing else in this simpler keyboard-nav model needs to read it
  // mid-type.
  property string wifiPasswordSsid: ""
  property bool wifiConnecting: false
  property string wifiConnectError: ""

  function openWifiPasswordPrompt(ssid) {
    root.wifiPasswordSsid = ssid
    root.wifiConnectError = ""
    root.wifiConnecting = false
  }

  function closeWifiPasswordPrompt() {
    root.wifiPasswordSsid = ""
    root.wifiConnectError = ""
    root.wifiConnecting = false
    root.syncWifiNetworks()
  }

  function submitWifiPassword(password) {
    if (root.wifiConnecting || !password || password.length === 0) return
    var network = root.networkForSsid(root.wifiPasswordSsid)
    if (!network) { root.wifiConnectError = "Network no longer in range"; return }
    // Real error hit live on ruixen.settings' own page: "WifiNetwork is
    // already connected" -- the network can transition to connected on
    // its own between click and submit (802.11k/v roaming between two
    // SSIDs off the same router), and connectWithPsk() on an already-
    // connected network throws that instead of no-op'ing.
    if (network.connected) { root.closeWifiPasswordPrompt(); return }
    root.wifiConnectError = ""
    root.wifiConnecting = true
    network.connectWithPsk(password)
  }

  // Scoped to whichever network the open passphrase prompt targets --
  // connectionFailed(reason)/connectedChanged are the same two signals
  // ruixen.settings' own page listens to for this exact purpose.
  Connections {
    target: root.wifiPasswordSsid !== "" ? root.networkForSsid(root.wifiPasswordSsid) : null
    function onConnectionFailed(reason) {
      root.wifiConnecting = false
      root.wifiConnectError = (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout)
        ? "Wrong password" : "Couldn't connect"
      // connectWithPsk() creates a full, autoconnect-enabled
      // NetworkManager profile immediately as part of attempting the
      // connection -- BEFORE the password is validated. On failure that
      // broken profile just sits there looking "known" despite never
      // authenticating, and NM keeps quietly retrying it whenever in
      // range. This flow only opens for rows that were NOT known when
      // clicked, so failure here always means the attempt itself
      // failed -- safe to forget unconditionally.
      if (target) target.forget()
    }
    function onConnectedChanged() {
      if (target && target.connected) root.closeWifiPasswordPrompt()
    }
  }

  // Real click/Enter-to-connect. Known networks and open networks
  // connect immediately; a new protected network opens the passphrase
  // prompt instead.
  function connectToWifi(row) {
    if (!row || row.connected) return
    if (!row.known && !root.isOpenNetwork(row.security)) {
      // Activating the row that's already expanded closes it back up.
      if (root.wifiPasswordSsid === row.ssid) root.closeWifiPasswordPrompt()
      else root.openWifiPasswordPrompt(row.ssid)
      return
    }
    var network = root.networkForSsid(row.ssid)
    if (network && !network.connected) network.connect()
  }

  // Excludes the connected network (mirrors canForgetNetwork: known &&
  // !connected on the real page) -- forgetting the network you're
  // actively using would disconnect you as a side effect of what's
  // meant to be a plain cleanup click.
  function forgetWifi(row) {
    if (!row || row.connected) return
    var network = root.networkForSsid(row.ssid)
    if (network) network.forget()
  }

  function toggleWifiRadio() {
    Networking.wifiEnabled = !Networking.wifiEnabled
  }

  // scannerEnabled lives on the shared WifiDevice, not per-instance
  // state, so it has to be explicitly released -- tracks which device
  // THIS instance turned scanning on for, same as ruixen.settings' own
  // setScannerEnabled()/scannerDevice.
  property var scannerDevice: null

  function setScannerEnabled(enabled) {
    var nextDevice = root.active ? root.wifiDevice : null
    if (root.scannerDevice && root.scannerDevice !== nextDevice)
      root.scannerDevice.scannerEnabled = false
    root.scannerDevice = nextDevice
    if (root.scannerDevice)
      root.scannerDevice.scannerEnabled = enabled
  }

  // Actual onActiveChanged wiring lives on the existing handler further
  // down (search for "Fresh state every time the extension is
  // (re)entered") -- QML only allows one onXChanged per signal per
  // object, so this call is folded into that one rather than declared
  // again here.
  onWifiDeviceChanged: root.setScannerEnabled(true)
  // Component.onDestruction is folded into the one below (Bluetooth's
  // own scanner release) -- same one-handler-per-signal reason.

  // Real connection stats (IP, gateway, ping) via `omarchy-network-
  // status --verbose` -- a real standalone Omarchy CLI binary, same
  // class of dependency as omarchy-monitor-state above. Tab-separated
  // key\tvalue lines, confirmed by running it directly, not guessed.
  // Display-only, no keyboard target -- same reasoning Profile
  // Picture's own preview or the mount checklist's "Not currently
  // connected" subtitle already apply (plain informational text next
  // to something that IS interactive).
  property var netInfo: ({})

  function parseNetStatus(raw) {
    var next = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var line = lines[i]
      if (!line) continue
      var idx = line.indexOf("\t")
      if (idx === -1) continue
      next[line.substring(0, idx)] = line.substring(idx + 1).trim()
    }
    return next
  }

  Process {
    id: netStatusProc
    command: ["omarchy-network-status", "--verbose"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.netInfo = root.parseNetStatus(text)
    }
  }

  Timer {
    interval: 2000
    running: root.active
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!netStatusProc.running) netStatusProc.running = true
  }

  // Real Quickshell.Bluetooth-backed state -- another standard
  // Quickshell module, confirmed the same way Wi-Fi's own
  // Quickshell.Networking backend was. Real mechanism difference from
  // Wi-Fi/Audio, confirmed directly: the adapter's own `enabled`
  // property doesn't persist by itself (that only writes BlueZ's
  // Powered, which nothing persists), so toggling and per-device
  // actions both go through real external CLIs (omarchy-bluetooth-
  // power, omarchy-bluetooth-device) via Quickshell.execDetached(), not
  // direct property writes the way Wi-Fi's own network.connect() was.
  readonly property var btAdapter: Bluetooth.defaultAdapter
  readonly property bool btEnabled: !!(btAdapter && btAdapter.enabled)
  readonly property var btDeviceObjects: Bluetooth.devices ? Bluetooth.devices.values : []
  property var btRows: []

  function btDeviceLabel(d) {
    return String((d && (d.deviceName || d.name)) || "").trim()
  }

  function btIsUuidLike(value) {
    var text = String(value || "").trim()
    if (text === "") return false
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(text)
      || /^[0-9a-f]{32}$/i.test(text)
  }

  function btIsAddressLike(value) {
    return /^([0-9a-f]{2}[:-]){5}[0-9a-f]{2}$/i.test(String(value || "").trim())
  }

  function btHasHumanName(d) {
    var label = root.btDeviceLabel(d)
    return label !== "" && !root.btIsUuidLike(label) && !root.btIsAddressLike(label)
  }

  // Primitives only, not the live Bluetooth device objects -- same
  // real crash-avoidance reasoning as Wi-Fi's own syncWifiNetworks():
  // BlueZ churn (discovery timeouts, unpair) can destroy a device
  // object while a delegate built from it is still incubating. Actions
  // resolve back to the live object via btDeviceForAddress() at
  // activate time instead.
  function syncBtDevices() {
    var rows = []
    var devs = root.btDeviceObjects
    for (var i = 0; i < devs.length; i++) {
      var d = devs[i]
      if (!d || !root.btHasHumanName(d)) continue
      rows.push({
        address: d.address || "",
        name: root.btDeviceLabel(d),
        connected: !!d.connected,
        known: !!(d.paired || d.bonded || d.trusted),
        pairedFormally: !!(d.paired || d.bonded)
      })
    }
    rows.sort(function(a, b) {
      if (a.connected !== b.connected) return a.connected ? -1 : 1
      if (a.known !== b.known) return a.known ? -1 : 1
      return a.name.localeCompare(b.name)
    })
    root.btRows = rows
    // Clear a busy marker once the device's real state actually moved
    // -- without this, "Connecting.../Pairing..." would hang forever if
    // the CLI's own best-effort connect/pair silently no-ops.
    if (root.btBusyAddress !== "") {
      var busy = root.btDeviceForAddress(root.btBusyAddress)
      if (!busy || busy.connected) root.btBusyAddress = ""
    }
  }

  onBtDeviceObjectsChanged: root.syncBtDevices()

  // Busy feedback for an in-flight connect/pair -- a fire-and-forget
  // CLI call with real ~1-minute BLE connect latency reads as "did
  // nothing" without this. Cleared above once the device's connected
  // state moves, or by this timeout as a backstop if it never does.
  property string btBusyAddress: ""

  Timer {
    id: btBusyTimeout
    interval: 20000
    onTriggered: root.btBusyAddress = ""
  }

  readonly property var knownBtRows: root.btRows.filter(function(r) { return r.known })
  readonly property var otherBtRows: root.btRows.filter(function(r) { return !r.known })

  // Confirm-before-pair for unknown devices -- unlike Wi-Fi (picking a
  // network you already recognize as yours), a nearby Bluetooth device
  // can easily be someone else's phone/earbuds in a shared space. First
  // click on an other-device row arms it (Confirm Pair button); the
  // actual pair command only fires on that second, deliberate action.
  property string btPairArmedAddress: ""

  function toggleBluetoothRadio() {
    Quickshell.execDetached(["omarchy-bluetooth-power", root.btEnabled ? "off" : "on"])
  }

  function btDeviceForAddress(address) {
    var devs = root.btDeviceObjects
    for (var i = 0; i < devs.length; i++)
      if (devs[i] && devs[i].address === address) return devs[i]
    return null
  }

  function toggleBtConnection(row) {
    if (!row || !row.address) return
    if (row.connected) { Quickshell.execDetached(["omarchy-bluetooth-device", "disconnect", row.address]); return }
    if (row.known) {
      root.btBusyAddress = row.address
      btBusyTimeout.restart()
      Quickshell.execDetached(["omarchy-bluetooth-device", "connect", row.address])
      return
    }
    // Unknown device -- arms the row instead of pairing immediately.
    // Clicking the row that's already armed disarms it, same toggle-
    // closed-on-second-click Wi-Fi's own password prompt uses.
    root.btPairArmedAddress = (root.btPairArmedAddress === row.address) ? "" : row.address
  }

  function confirmPairBtDevice(row) {
    if (!row || !row.address) return
    root.btPairArmedAddress = ""
    root.btBusyAddress = row.address
    btBusyTimeout.restart()
    Quickshell.execDetached(["omarchy-bluetooth-device", "pair", row.address])
  }

  // Excludes the connected device -- disconnect first, then forget,
  // rather than a one-step forget that disconnects as a side effect.
  function forgetBtDevice(row) {
    if (!row || !row.address || row.connected) return
    Quickshell.execDetached(["omarchy-bluetooth-device", "forget", row.address])
  }

  // scannerEnabled equivalent for BlueZ's discovery session -- same
  // ownership-release reasoning as Wi-Fi's own scannerDevice, applied
  // to adapter.discovering instead ("keep nudging it back on so an
  // enabled adapter is always scanning" while this category is open).
  property var btScannerAdapter: null

  function setBtScannerEnabled(enabled) {
    var nextAdapter = root.active ? root.btAdapter : null
    if (root.btScannerAdapter && root.btScannerAdapter !== nextAdapter)
      root.btScannerAdapter.discovering = false
    root.btScannerAdapter = nextAdapter
    if (root.btScannerAdapter)
      root.btScannerAdapter.discovering = enabled
  }

  // Actual onActiveChanged wiring lives on the existing handler (search
  // for "Fresh state every time the extension is (re)entered") -- QML
  // only allows one onXChanged per signal per object.
  onBtAdapterChanged: root.setBtScannerEnabled(true)
  // Releases both the Wi-Fi scan radio and the Bluetooth discovery
  // session together -- folded into one handler since QML only allows
  // a single Component.onDestruction per object.
  Component.onDestruction: {
    if (root.scannerDevice) root.scannerDevice.scannerEnabled = false
    if (root.btScannerAdapter) root.btScannerAdapter.discovering = false
  }

  // Plugins category's own real backend -- list/toggle/update/check,
  // same PluginService.qml shape as ruixen.settings' own Plugins page
  // (see services/PluginService.qml's own header comment for the one
  // deliberate difference: self-lockout here is for ruixen.launcher,
  // not ruixen.settings). Thin pass-through aliases/wrappers on root,
  // same convention ruixen.settings' own Settings.qml uses so the rest
  // of this file's own xxxItems/currentItems plumbing doesn't need to
  // know a separate service object exists underneath.
  PluginService { id: pluginService }

  property alias pluginRows: pluginService.pluginRows
  property alias pluginBusyId: pluginService.pluginBusyId
  property alias pluginUpdateStatus: pluginService.pluginUpdateStatus
  property alias pluginUpdateError: pluginService.pluginUpdateError
  property alias pluginCheckStatus: pluginService.pluginCheckStatus
  property alias pluginCheckError: pluginService.pluginCheckError
  property alias pluginChangedIds: pluginService.pluginChangedIds
  property alias ruixenRepoPath: pluginService.ruixenRepoPath
  property alias uninstallConfirmPhrase: pluginService.uninstallConfirmPhrase
  property alias uninstallConfirmInput: pluginService.uninstallConfirmInput

  function refreshPlugins() { pluginService.refreshPlugins() }
  function pluginIsProtected(row) { return pluginService.pluginIsProtected(row) }
  function togglePluginEnabled(row) { pluginService.togglePluginEnabled(row) }
  function updateRuixenShell() { pluginService.updateRuixenShell() }
  function checkForUpdates() { pluginService.checkForUpdates() }
  function confirmFullUninstall() { pluginService.confirmFullUninstall() }

  // Keyboard-navigable subset of pluginRows -- protected rows (locked,
  // no toggle to reach) are drawn but deliberately not part of
  // currentItems, same "nothing there to interact with" reasoning empty
  // states elsewhere in this file already use. Matched back to its full
  // pluginRows position by id (not index) wherever a row visual is
  // needed, since this list and the Repeater's own full model don't
  // share indices once protected rows are filtered out.
  readonly property var togglablePluginRows: root.pluginRows.filter(function(r) { return !root.pluginIsProtected(r) })

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
  // Every real control on the Launcher page, in the same order
  // they're stacked -- direct report: "the tab kbd stuff not working
  // on launcher setting" (currentItems had no branch for Launcher at
  // all), then "well the togle doesnt work, i think i need to enter to
  // toggle" (correct -- a first pass modeled each switch as a 2-option
  // segmented item, which needed Left/Right to move a cursor onto the
  // OTHER state before Enter would do anything, since Enter there
  // means "commit whichever option the cursor already sits on," not
  // "flip"). Two real item `kind`s here now, alongside the segmented
  // kind profileItems/barItems use (implicit -- anything with an
  // `options` array):
  //   "toggle" -- Enter flips it directly, no cursor to pre-position.
  //   "textEntry" -- Enter hands real Qt focus to the actual TextInput
  //     (SettingsAddListItem.focusTextInput()) so typing just works
  //     natively -- direct follow-up: "why wouldnt the text entry
  //     work... i just tab and go to it with d pad then type and enter
  //     to add." Left/Right/Up/Down do nothing special for either kind
  //     while it's merely the highlighted item (see moveOptionLeft/
  //     Right's own guards) -- a toggle has no options to cycle, and a
  //     text field's Left/Right only mean anything once it actually
  //     has real focus, at which point they're plain text-cursor
  //     movement Qt already handles for free.
  readonly property var launcherItems: {
    var items = [
      {
        kind: "toggle",
        checked: root.launcherSearchConfig.includeHome,
        activate: function() { root.setLauncherIncludeHome(!root.launcherSearchConfig.includeHome) }
      },
      {
        kind: "toggle",
        checked: root.launcherSearchConfig.includeMountedRoots,
        activate: function() { root.setLauncherIncludeMountedRoots(!root.launcherSearchConfig.includeMountedRoots) }
      }
    ]
    for (var i = 0; i < root.mountChecklist.length; i++) {
      items.push(root.mountToggleItem(root.mountChecklist[i]))
    }
    items.push({ kind: "textEntry", focus: function() { customRootsItem.focusTextInput() } })
    items.push({ kind: "textEntry", focus: function() { excludedPathsItem.focusTextInput() } })
    items.push({ kind: "textEntry", focus: function() { excludedNamesItem.focusTextInput() } })
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
      kind: "toggle",
      checked: !m.disabled,
      activate: function() { root.toggleLauncherAutoRootDisabled(m.path) }
    }
  }

  // Output's own item count (the combined volume/mute control, plus
  // one per device) -- Input's items start right after these in
  // audioItems below, so both this file and the two
  // SettingsAudioChannelItem instances' own focus bindings need the
  // exact same offset.
  readonly property int outputItemCount: 1 + root.outputDevices.length

  // Mute+slider is ONE combined item per channel (Left/Right adjusts
  // volume, Enter toggles mute -- like a real volume knob: turn to
  // adjust, press to mute), not two separate stops -- direct follow-
  // up: "wanna do the tab kbd now?" Each device is its own "select"
  // item (Enter sets it as the default, no options to cycle -- same
  // direct-activate() shape "toggle" items already use, just a
  // different real name so the intent reads clearly).
  //
  // The radio toggle sits first (index 0), same top-of-page slot Wi-Fi/
  // Bluetooth's own radio occupies -- direct request: "on omarchy
  // theres a toggle for on and off, we have this for bluetooth and
  // wifi as the top option, can we have an audio on and off toggle
  // too". Everything below it shifts down by exactly 1 from before.
  readonly property var audioItems: {
    var items = [{
      kind: "toggle",
      checked: root.anyAudible,
      activate: function() { root.toggleAllMuted() }
    }, root.volumeControlItem("output")]
    for (var i = 0; i < root.outputDevices.length; i++) {
      items.push(root.deviceSelectItem(root.outputDevices[i], "output"))
    }
    items.push(root.volumeControlItem("input"))
    for (var j = 0; j < root.inputDevices.length; j++) {
      items.push(root.deviceSelectItem(root.inputDevices[j], "input"))
    }
    return items
  }

  function volumeControlItem(channel) {
    if (channel === "output") {
      return {
        kind: "volumeControl",
        adjust: function(delta) { root.setOutputVolume(root.outputVolume + delta) },
        activate: function() { root.toggleOutputMute() }
      }
    }
    return {
      kind: "volumeControl",
      adjust: function(delta) { root.setInputVolume(root.inputVolume + delta) },
      activate: function() { root.toggleInputMute() }
    }
  }

  // Split out from audioItems' own loop bodies for the same closure
  // reason mountToggleItem's own comment explains -- a function
  // declared directly inside a for-loop body closes over the loop
  // variable itself, not each iteration's value.
  function deviceSelectItem(node, channel) {
    return {
      kind: "select",
      activate: channel === "output"
        ? function() { root.setDefaultOutput(node) }
        : function() { root.setDefaultInput(node) }
    }
  }

  // Brightness (kind: "slider" -- Left/Right adjusts, nothing for
  // Enter to commit since it already applies live) then Display Scale
  // (a plain segmented item, same shape as Bar Layout/Window
  // Curvature -- fits the existing model with no new kind needed).
  // Empty entirely when brightnessAvailable is false, matching both
  // cards' own visibility gate below -- nothing to navigate to.
  readonly property var displayItems: {
    if (!root.brightnessAvailable) return []
    return [
      {
        kind: "slider",
        adjust: function(delta) { root.setBrightness(root.brightnessPercent + delta * 100) }
      },
      {
        options: root.scalePresets,
        current: root.displayScale,
        activate: function(id) { root.setDisplayScale(id) }
      }
    ]
  }

  // Wi-Fi's own items -- the radio toggle, then (only while enabled)
  // one "select" item per known network followed by one per available
  // (unknown) network. Both row kinds use "select" -- activate() takes
  // no args either way, same shape "select"/"toggle" already share; the
  // only difference is what activate() itself does (connect/switch vs.
  // connect-or-open-the-password-prompt), which is real backend logic,
  // not a new keyboard-nav shape.
  readonly property var wifiItems: {
    var items = [{
      kind: "toggle",
      checked: Networking.wifiEnabled,
      activate: function() { root.toggleWifiRadio() }
    }]
    if (!Networking.wifiEnabled) return items
    for (var i = 0; i < root.knownWifiRows.length; i++) {
      items.push(root.wifiKnownRowItem(root.knownWifiRows[i]))
    }
    for (var j = 0; j < root.otherWifiRows.length; j++) {
      items.push(root.wifiOtherRowItem(root.otherWifiRows[j], j))
    }
    return items
  }

  // Split out from wifiItems' own loop bodies for the same closure
  // reason mountToggleItem's own comment explains.
  function wifiKnownRowItem(row) {
    return {
      kind: "select",
      activate: function() { root.connectToWifi(row) }
    }
  }

  // Unknown+secured rows: connectToWifi() itself decides whether this
  // opens the password prompt or connects immediately (open network) --
  // this item only needs to hand real Qt focus to the password field
  // right after, and only when the prompt actually just opened for THIS
  // row (connectToWifi() also closes an already-open prompt on a second
  // press of the same row, which must NOT re-focus a field that no
  // longer exists).
  function wifiOtherRowItem(row, index) {
    return {
      kind: "select",
      activate: function() {
        root.connectToWifi(row)
        if (root.wifiPasswordSsid === row.ssid) {
          Qt.callLater(function() { otherRepeater.itemAt(index).focusPasswordInput() })
        }
      }
    }
  }

  // Bluetooth's own items -- the radio toggle, then (only while
  // enabled) one "select" item per paired device followed by one per
  // available (unknown) device. Same "select" shape as Wi-Fi's own
  // rows -- activate() takes no args, connectToWifi()'s Bluetooth
  // equivalent (toggleBtConnection) decides what actually happens.
  readonly property var btItems: {
    var items = [{
      kind: "toggle",
      checked: root.btEnabled,
      activate: function() { root.toggleBluetoothRadio() }
    }]
    if (!root.btEnabled) return items
    for (var i = 0; i < root.knownBtRows.length; i++) {
      items.push(root.btKnownRowItem(root.knownBtRows[i]))
    }
    for (var j = 0; j < root.otherBtRows.length; j++) {
      items.push(root.btOtherRowItem(root.otherBtRows[j]))
    }
    return items
  }

  function btKnownRowItem(row) {
    return {
      kind: "select",
      activate: function() { root.toggleBtConnection(row) }
    }
  }

  // Enter twice pairs: the first arms the row (same as a mouse click),
  // the second -- while still armed -- confirms the pair directly
  // rather than mouse-click's own disarm-on-second-click, since Enter
  // committing something real (not toggling back off) matches every
  // other item's own keyboard convention in this file.
  function btOtherRowItem(row) {
    return {
      kind: "select",
      activate: function() {
        if (root.btPairArmedAddress === row.address) root.confirmPairBtDevice(row)
        else root.toggleBtConnection(row)
      }
    }
  }

  // Plugins' own items -- Check for Updates and Update (both "select",
  // no-op via their own activate() guard whenever ruixenRepoPath is
  // empty or an action is already in flight, same disabled-button
  // reasoning the real page's own MouseArea.enabled gates use), then
  // one "toggle" per non-protected plugin row.
  readonly property var pluginItems: {
    var items = [
      {
        kind: "select",
        activate: function() {
          if (root.ruixenRepoPath !== "" && root.pluginCheckStatus !== "checking") root.checkForUpdates()
        }
      },
      {
        kind: "select",
        activate: function() {
          if (root.ruixenRepoPath !== "" && root.pluginUpdateStatus !== "updating") root.updateRuixenShell()
        }
      }
    ]
    for (var i = 0; i < root.togglablePluginRows.length; i++) {
      items.push(root.pluginToggleItem(root.togglablePluginRows[i]))
    }
    return items
  }

  function pluginToggleItem(row) {
    return {
      kind: "toggle",
      checked: row.enabled,
      activate: function() {
        if (root.pluginBusyId === row.id) return
        root.togglePluginEnabled(row)
      }
    }
  }

  // About's own two items -- the uninstall confirm field (kind
  // "textEntry", same real Qt focus handoff Launcher's own add-list
  // boxes use) and the Uninstall button itself ("select", no-op via its
  // own activate() guard until ready, same disabled-button reasoning
  // Plugins' own Check/Update items use).
  readonly property var aboutItems: {
    return [
      {
        kind: "textEntry",
        focus: function() { uninstallConfirmField.forceActiveFocus() }
      },
      {
        kind: "select",
        activate: function() {
          if (root.ruixenRepoPath !== "" && root.uninstallConfirmInput === root.uninstallConfirmPhrase)
            root.confirmFullUninstall()
        }
      }
    ]
  }

  // The single thing every nav function below actually reads --
  // whichever category is open picks its own table, everything else
  // (an empty header+description category) has nothing to navigate.
  readonly property var currentItems: {
    if (root.profileOpen) return root.profileItems
    if (root.barOpen) return root.barItems
    if (root.launcherOpen) return root.launcherItems
    if (root.audioOpen) return root.audioItems
    if (root.displayOpen) return root.displayItems
    if (root.wifiOpen) return root.wifiItems
    if (root.btOpen) return root.btItems
    if (root.pluginsOpen) return root.pluginItems
    if (root.aboutOpen) return root.aboutItems
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
    // Toggle/textEntry items have no `options` array at all -- nothing
    // to seed a cursor position into, so this just stays at its
    // harmless default.
    if (!item || !item.options) { root.focusedOptionIndex = 0; return }
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
      var mountIdx = root.focusedItemIndex - 2
      if (mountIdx < root.mountChecklist.length) return mountRepeater.itemAt(mountIdx)
      var textEntryIdx = mountIdx - root.mountChecklist.length
      return [customRootsItem, excludedPathsItem, excludedNamesItem][textEntryIdx]
    }
    if (root.audioOpen) {
      if (root.focusedItemIndex === 0) return audioRadioRow
      var audioIdx = root.focusedItemIndex - 1
      if (audioIdx === 0) return outputChannelItem.volumeRowItem
      if (audioIdx < root.outputItemCount) return outputChannelItem.deviceRowAt(audioIdx - 1)
      var inputIdx = audioIdx - root.outputItemCount
      if (inputIdx === 0) return inputChannelItem.volumeRowItem
      return inputChannelItem.deviceRowAt(inputIdx - 1)
    }
    if (root.displayOpen) {
      return [brightnessItem, displayScaleItem][root.focusedItemIndex]
    }
    if (root.wifiOpen) {
      if (root.focusedItemIndex === 0) return wifiRadioRow
      var knownIdx = root.focusedItemIndex - 1
      if (knownIdx < root.knownWifiRows.length) return knownRepeater.itemAt(knownIdx)
      var otherIdx = knownIdx - root.knownWifiRows.length
      return otherRepeater.itemAt(otherIdx)
    }
    if (root.btOpen) {
      if (root.focusedItemIndex === 0) return btRadioRow
      var knownBtIdx = root.focusedItemIndex - 1
      if (knownBtIdx < root.knownBtRows.length) return knownBtRepeater.itemAt(knownBtIdx)
      var otherBtIdx = knownBtIdx - root.knownBtRows.length
      return otherBtRepeater.itemAt(otherBtIdx)
    }
    if (root.pluginsOpen) {
      if (root.focusedItemIndex === 0) return pluginCheckButton
      if (root.focusedItemIndex === 1) return pluginUpdateButton
      var togIdx = root.focusedItemIndex - 2
      var target = root.togglablePluginRows[togIdx]
      if (!target) return null
      for (var i = 0; i < root.pluginRows.length; i++) {
        if (root.pluginRows[i].id === target.id) return pluginRepeater.itemAt(i)
      }
      return null
    }
    if (root.aboutOpen) {
      return [uninstallConfirmRow, uninstallButtonRow][root.focusedItemIndex]
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

  // 5% per press -- same step the real slider's own scroll-wheel
  // handler already uses (AudioContent.qml's own wheel step, ported
  // verbatim), so keyboard and scroll always move volume by the same
  // amount.
  readonly property real volumeStep: 0.05

  function moveOptionLeft() {
    if (!root.rightFocused) return
    var item = root.currentItems[root.focusedItemIndex]
    if (!item) return
    if (item.kind === "volumeControl" || item.kind === "slider") { item.adjust(-root.volumeStep); return }
    // Toggle/select/textEntry items have nothing to cycle -- a plain
    // no-op, not an error, while one of those is the focused item.
    if (!item.options || item.options.length === 0) return
    root.focusedOptionIndex = (root.focusedOptionIndex - 1 + item.options.length) % item.options.length
  }

  function moveOptionRight() {
    if (!root.rightFocused) return
    var item = root.currentItems[root.focusedItemIndex]
    if (!item) return
    if (item.kind === "volumeControl" || item.kind === "slider") { item.adjust(root.volumeStep); return }
    if (!item.options || item.options.length === 0) return
    root.focusedOptionIndex = (root.focusedOptionIndex + 1) % item.options.length
  }

  // Enter's meaning depends on the focused item's own kind -- a
  // toggle/volume-control/select item all act directly with no args
  // (flip a switch, toggle mute, or pick this device -- none of them
  // have a cursor pre-positioned first), a text entry hands off real
  // Qt focus so typing works, and everything else (every segmented
  // item) commits whichever option the cursor currently sits on.
  function activateFocusedOption() {
    var item = root.currentItems[root.focusedItemIndex]
    if (!item) return
    if (item.kind === "toggle" || item.kind === "volumeControl" || item.kind === "select") { item.activate(); return }
    if (item.kind === "textEntry") { item.focus(); return }
    // A plain slider (Brightness) has nothing for Enter to commit --
    // Left/Right already applies the value directly, live.
    if (item.kind === "slider") return
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
      root.refreshPlugins()
      pluginService.refreshRepoPath()
    }
    // Releases the Wi-Fi scan radio and Bluetooth discovery the moment
    // this extension closes -- both read root.active itself to decide
    // the real device/adapter vs. null.
    root.setScannerEnabled(true)
    root.setBtScannerEnabled(true)
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
  readonly property bool audioOpen: root.openIndex >= 0
    && root.openIndex < root.sections.length
    && root.sections[root.openIndex].id === "audio"
  readonly property bool displayOpen: root.openIndex >= 0
    && root.openIndex < root.sections.length
    && root.sections[root.openIndex].id === "display"
  readonly property bool wifiOpen: root.openIndex >= 0
    && root.openIndex < root.sections.length
    && root.sections[root.openIndex].id === "wifi"
  readonly property bool btOpen: root.openIndex >= 0
    && root.openIndex < root.sections.length
    && root.sections[root.openIndex].id === "bluetooth"
  readonly property bool pluginsOpen: root.openIndex >= 0
    && root.openIndex < root.sections.length
    && root.sections[root.openIndex].id === "plugins"
  readonly property bool aboutOpen: root.openIndex >= 0
    && root.openIndex < root.sections.length
    && root.sections[root.openIndex].id === "about"

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

  // No more per-category header (label + description) above the item
  // cards here -- direct follow-up: "its kinda cluttering, i think we
  // dont need that and can just start with options without the header
  // and subtitle". The left panel's own row already names which
  // category is open; repeating that plus a description right above
  // the first option was redundant with it. sections[].description
  // itself stays on the data (not dead: kept for a stated future
  // search use -- "itll be good for searching for them later too"),
  // just no longer rendered anywhere.
  //
  // Profile's own real content -- centered avatar + username@machine,
  // then the DiceBear collection picker -- ported from ruixen.settings/
  // GeneralContent.qml's own avatar card (see this file's header
  // comment). No card background/border here (unlike the real app's
  // own black card) -- this pane is already the ghost/ContentPage
  // treatment every extension's right side uses, a second nested card
  // would be a surface-on-a-surface with nothing to visually separate.
  // Frames this one setting as a distinct menu item/option -- direct
  // follow-up: "this would be considered an option or menu item, how
  // do we group it as that... put that darker bg tonal we used for
  // the file picker text or zebra stripe." Same dark tonal
  // FileDetailsPanel.qml's own zebra-striped metadata rows already use
  // (Qt.rgba(0, 0, 0, 0.18)) -- this is that same "item" treatment
  // scaled up to a whole option's card instead of one thin row, not a
  // new color invented for this.
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
      // for them later too." Every future real setting in any category
      // follows this same one-line, self-descriptive convention rather
      // than a title+subtitle pair. Shortened to "Profile Picture" per
      // direct follow-up.
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
  // Bar is open, this naturally lands at the top of the column, same
  // as every other category's own first item.
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
    // launcherItems' own order: 2 fixed toggles, then one per mount,
    // then these three text-entry cards last.
    cardFocused: root.launcherOpen && root.rightFocused
      && root.focusedItemIndex === 2 + root.mountChecklist.length
    visible: root.launcherOpen
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onAdded: (value) => root.addLauncherRoot(value)
    onRemoved: (value) => root.removeLauncherRoot(value)
    onCancelled: root.returnFocusRequested()
  }

  SettingsAddListItem {
    id: excludedPathsItem
    label: "Excluded Paths"
    placeholder: "~/VMs or ~/Downloads/ISOs"
    items: root.launcherSearchConfig.excludePaths
    cardFocused: root.launcherOpen && root.rightFocused
      && root.focusedItemIndex === 3 + root.mountChecklist.length
    visible: root.launcherOpen
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onAdded: (value) => root.addLauncherExcludePath(value)
    onRemoved: (value) => root.removeLauncherExcludePath(value)
    onCancelled: root.returnFocusRequested()
  }

  SettingsAddListItem {
    id: excludedNamesItem
    label: "Excluded Directory Names"
    placeholder: "e.g. dist or .venv"
    chipMode: true
    items: root.launcherSearchConfig.excludeNames
    cardFocused: root.launcherOpen && root.rightFocused
      && root.focusedItemIndex === 4 + root.mountChecklist.length
    visible: root.launcherOpen
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onAdded: (value) => root.addLauncherExcludeName(value)
    onRemoved: (value) => root.removeLauncherExcludeName(value)
    onCancelled: root.returnFocusRequested()
  }

  // Audio's own radio toggle -- direct request: "on omarchy theres a
  // toggle for on and off, we have this for bluetooth and wifi as the
  // top option, can we have an audio on and off toggle too." Same
  // mute-both semantics as Omarchy's own hero switch (see
  // root.toggleAllMuted()'s own comment) -- reused SettingsToggleRow
  // directly, same card-wrapped shape Wi-Fi/Bluetooth's own radio uses.
  Rectangle {
    id: audioRadioItem
    width: parent.width
    height: audioRadioContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.audioOpen

    Column {
      id: audioRadioContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Audio"
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.textColor
      }

      SettingsToggleRow {
        id: audioRadioRow
        label: "Enabled"
        checked: root.anyAudible
        rowFocused: root.audioOpen && root.rightFocused && root.focusedItemIndex === 0
        textColor: root.textColor
        accent: root.accent
        fontFamily: root.fontFamily
        onToggled: root.toggleAllMuted()
      }
    }
  }

  // Audio's own two channel items -- Output and Input, both on
  // SettingsAudioChannelItem.qml (see its own header comment). Mouse/
  // scroll-wheel only for this pass, same as Profile Picture's own
  // avatar picker started out -- a continuous slider is a genuinely
  // different keyboard shape (adjust a value, not cycle/flip/type)
  // from every item already wired into currentItems, real follow-on
  // work rather than a same-shape extension of any of them.
  SettingsAudioChannelItem {
    id: outputChannelItem
    label: "Output"
    volume: root.outputVolume
    channelMuted: root.outputMuted
    devices: root.outputDevices
    defaultDevice: root.outputSink
    // Output's own items are index 1 (volume/mute, right after the
    // radio toggle at index 0) through 1 + outputDevices.length (the
    // last device) in audioItems above.
    volumeFocused: root.audioOpen && root.rightFocused && root.focusedItemIndex === 1
    focusedDeviceIndex: (root.audioOpen && root.rightFocused
      && root.focusedItemIndex >= 2 && root.focusedItemIndex <= 1 + root.outputDevices.length)
      ? root.focusedItemIndex - 2 : -1
    iconMuted: ""
    iconUnmuted: ""
    labelFor: root.deviceLabel
    visible: root.audioOpen
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onMuteToggled: root.toggleOutputMute()
    onVolumeAdjusted: (value) => root.setOutputVolume(value)
    onDeviceSelected: (node) => root.setDefaultOutput(node)
  }

  SettingsAudioChannelItem {
    id: inputChannelItem
    label: "Input"
    volume: root.inputVolume
    channelMuted: root.inputMuted
    devices: root.inputDevices
    defaultDevice: root.inputSource
    // Input's items pick up right where Output's own leave off -- 1 +
    // root.outputItemCount is exactly the offset both this file and
    // focusedItemVisual()/audioItems above already agree on (the extra
    // +1 is the radio toggle at index 0).
    volumeFocused: root.audioOpen && root.rightFocused && root.focusedItemIndex === 1 + root.outputItemCount
    focusedDeviceIndex: (root.audioOpen && root.rightFocused
      && root.focusedItemIndex > 1 + root.outputItemCount
      && root.focusedItemIndex <= 1 + root.outputItemCount + root.inputDevices.length)
      ? root.focusedItemIndex - root.outputItemCount - 2 : -1
    iconMuted: ""
    iconUnmuted: ""
    labelFor: root.deviceLabel
    visible: root.audioOpen
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onMuteToggled: root.toggleInputMute()
    onVolumeAdjusted: (value) => root.setInputVolume(value)
    onDeviceSelected: (node) => root.setDefaultInput(node)
  }

  // Display's own two items -- Brightness (a plain slider, no mute
  // concept, hence SettingsSliderRow.qml rather than
  // SettingsAudioChannelItem's own) and Display Scale (a plain
  // segmented item, same shape as Bar Layout/Window Curvature). Both
  // gated on brightnessAvailable, same as ruixen.settings' own
  // DisplayContent.qml -- a laptop-less/headless session has no
  // backlight to control.
  Rectangle {
    id: brightnessItem
    width: parent.width
    height: brightnessContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    border.width: (root.displayOpen && root.rightFocused && root.focusedItemIndex === 0) ? 1 : 0
    border.color: root.accent
    visible: root.displayOpen && root.brightnessAvailable

    Column {
      id: brightnessContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Brightness"
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.textColor
      }

      SettingsSliderRow {
        icon: ""
        value: root.brightnessPercent / 100
        textColor: root.textColor
        muted: root.muted
        accent: root.accent
        fontFamily: root.fontFamily
        onAdjusted: (value) => root.setBrightness(value * 100)
      }
    }
  }

  SettingsSegmentedItem {
    id: displayScaleItem
    label: "Display Scale"
    options: root.scalePresets.map(function(s) { return { id: s, label: s + "x" } })
    current: root.displayScale
    cardFocused: root.displayOpen && root.rightFocused && root.focusedItemIndex === 1
    focusedOptionIndex: displayScaleItem.cardFocused ? root.focusedOptionIndex : -1
    visible: root.displayOpen && root.brightnessAvailable
    textColor: root.textColor
    muted: root.muted
    accent: root.accent
    fontFamily: root.fontFamily
    onActivated: (id) => root.setDisplayScale(id)
  }

  // Wi-Fi's own three items -- the radio toggle (reuses
  // SettingsToggleRow.qml directly, same as Launcher's own toggles),
  // then Known Networks and Available Networks, both on
  // SettingsWifiRow.qml (see its own header comment). Real backend on
  // root above, ported from ruixen.settings/WifiContent.qml +
  // Settings.qml -- no QR-share/speed-test buttons (those summon two
  // separate Omarchy panel plugins, out of scope for this pass).
  Rectangle {
    id: wifiRadioItem
    width: parent.width
    height: wifiRadioContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.wifiOpen

    Column {
      id: wifiRadioContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Wi-Fi"
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.textColor
      }

      SettingsToggleRow {
        id: wifiRadioRow
        label: "Enabled"
        checked: Networking.wifiEnabled
        rowFocused: root.wifiOpen && root.rightFocused && root.focusedItemIndex === 0
        textColor: root.textColor
        accent: root.accent
        fontFamily: root.fontFamily
        onToggled: root.toggleWifiRadio()
      }
    }
  }

  Rectangle {
    id: knownNetworksItem
    width: parent.width
    height: knownNetworksContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.wifiOpen && Networking.wifiEnabled

    Column {
      id: knownNetworksContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Known Networks"
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.textColor
      }

      // Connection stats -- describes whichever known network is
      // currently active, same placement as the real page.
      Column {
        width: parent.width
        visible: root.connectedWifiNetwork !== null
        spacing: 2

        Item {
          width: parent.width
          height: 16
          Text { anchors.left: parent.left; text: "IP Address"; font.family: root.fontFamily; font.pixelSize: 11; color: root.muted }
          Text { anchors.right: parent.right; text: root.netInfo.ip || "--"; font.family: root.fontFamily; font.pixelSize: 11; color: root.textColor; elide: Text.ElideLeft }
        }
        Item {
          width: parent.width
          height: 16
          Text { anchors.left: parent.left; text: "Gateway"; font.family: root.fontFamily; font.pixelSize: 11; color: root.muted }
          Text { anchors.right: parent.right; text: root.netInfo.gateway || "--"; font.family: root.fontFamily; font.pixelSize: 11; color: root.textColor; elide: Text.ElideLeft }
        }
        Item {
          width: parent.width
          height: 16
          Text { anchors.left: parent.left; text: "Ping"; font.family: root.fontFamily; font.pixelSize: 11; color: root.muted }
          Text { anchors.right: parent.right; text: root.netInfo.internet_ping_ms ? Math.round(parseFloat(root.netInfo.internet_ping_ms)) + " ms" : "--"; font.family: root.fontFamily; font.pixelSize: 11; color: root.textColor }
        }
      }

      Column {
        width: parent.width
        spacing: 4

        Repeater {
          id: knownRepeater
          model: root.knownWifiRows

          SettingsWifiRow {
            required property var modelData
            required property int index
            width: parent.width
            ssid: modelData.ssid
            connected: modelData.connected
            signalPercent: modelData.signal
            secured: !root.isOpenNetwork(modelData.security)
            showForget: !modelData.connected
            rowFocused: root.wifiOpen && root.rightFocused && root.focusedItemIndex === (1 + index)
            textColor: root.textColor
            muted: root.muted
            accent: root.accent
            fontFamily: root.fontFamily
            onActivated: root.connectToWifi(modelData)
            onForgetRequested: root.forgetWifi(modelData)
          }
        }

        Text {
          visible: root.knownWifiRows.length === 0
          text: "No known networks"
          font.family: root.fontFamily
          font.pixelSize: 11
          color: root.muted
        }
      }
    }
  }

  Rectangle {
    id: otherNetworksItem
    width: parent.width
    height: otherNetworksContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.wifiOpen && Networking.wifiEnabled && root.otherWifiRows.length > 0

    Column {
      id: otherNetworksContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 10

      Text {
        text: "Available Networks"
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.textColor
      }

      Column {
        width: parent.width
        spacing: 4

        Repeater {
          id: otherRepeater
          model: root.otherWifiRows

          SettingsWifiRow {
            required property var modelData
            required property int index
            width: parent.width
            ssid: modelData.ssid
            connected: modelData.connected
            signalPercent: modelData.signal
            secured: !root.isOpenNetwork(modelData.security)
            expanded: root.wifiPasswordSsid === modelData.ssid
            connecting: root.wifiConnecting
            errorText: root.wifiPasswordSsid === modelData.ssid ? root.wifiConnectError : ""
            rowFocused: root.wifiOpen && root.rightFocused
              && root.focusedItemIndex === (1 + root.knownWifiRows.length + index)
            textColor: root.textColor
            muted: root.muted
            accent: root.accent
            fontFamily: root.fontFamily
            onActivated: root.connectToWifi(modelData)
            onPasswordSubmitted: (password) => root.submitWifiPassword(password)
            onCancelled: { root.closeWifiPasswordPrompt(); root.returnFocusRequested() }
          }
        }
      }
    }
  }

  Text {
    visible: root.wifiOpen && !Networking.wifiEnabled
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    topPadding: 24
    text: "Turn on Wi-Fi to see nearby networks"
    font.family: root.fontFamily
    font.pixelSize: 12
    color: root.muted
  }

  // Bluetooth's own three items -- radio toggle, then Paired Devices
  // and Available Devices, both on SettingsBtRow.qml (see its own
  // header comment). Real backend on root above, ported from
  // ruixen.settings/BluetoothContent.qml + Settings.qml.
  Rectangle {
    id: btRadioItem
    width: parent.width
    height: btRadioContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.btOpen

    Column {
      id: btRadioContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Bluetooth"
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.textColor
      }

      SettingsToggleRow {
        id: btRadioRow
        label: "Enabled"
        checked: root.btEnabled
        rowFocused: root.btOpen && root.rightFocused && root.focusedItemIndex === 0
        textColor: root.textColor
        accent: root.accent
        fontFamily: root.fontFamily
        onToggled: root.toggleBluetoothRadio()
      }
    }
  }

  Rectangle {
    id: pairedDevicesItem
    width: parent.width
    height: pairedDevicesContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.btOpen && root.btEnabled

    Column {
      id: pairedDevicesContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Paired Devices"
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.textColor
      }

      Column {
        width: parent.width
        spacing: 4

        Repeater {
          id: knownBtRepeater
          model: root.knownBtRows

          SettingsBtRow {
            required property var modelData
            required property int index
            width: parent.width
            name: modelData.name
            connected: modelData.connected
            known: true
            pairedFormally: modelData.pairedFormally
            busy: root.btBusyAddress === modelData.address
            showForget: !modelData.connected
            rowFocused: root.btOpen && root.rightFocused && root.focusedItemIndex === (1 + index)
            textColor: root.textColor
            muted: root.muted
            accent: root.accent
            fontFamily: root.fontFamily
            onActivated: root.toggleBtConnection(modelData)
            onForgetRequested: root.forgetBtDevice(modelData)
          }
        }

        Text {
          visible: root.knownBtRows.length === 0
          text: "No paired devices"
          font.family: root.fontFamily
          font.pixelSize: 11
          color: root.muted
        }
      }
    }
  }

  Rectangle {
    id: availableDevicesItem
    width: parent.width
    height: availableDevicesContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.btOpen && root.btEnabled && root.otherBtRows.length > 0

    Column {
      id: availableDevicesContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 12

      Text {
        text: "Available Devices"
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.textColor
      }

      Column {
        width: parent.width
        spacing: 4

        Repeater {
          id: otherBtRepeater
          model: root.otherBtRows

          SettingsBtRow {
            required property var modelData
            required property int index
            width: parent.width
            name: modelData.name
            connected: false
            known: false
            busy: root.btBusyAddress === modelData.address
            armed: root.btPairArmedAddress === modelData.address
            rowFocused: root.btOpen && root.rightFocused
              && root.focusedItemIndex === (1 + root.knownBtRows.length + index)
            textColor: root.textColor
            muted: root.muted
            accent: root.accent
            fontFamily: root.fontFamily
            onActivated: root.toggleBtConnection(modelData)
            onConfirmPair: root.confirmPairBtDevice(modelData)
          }
        }
      }
    }
  }

  Text {
    visible: root.btOpen && !root.btEnabled
    width: parent.width
    horizontalAlignment: Text.AlignHCenter
    topPadding: 24
    text: "Turn on Bluetooth to see nearby devices"
    font.family: root.fontFamily
    font.pixelSize: 12
    color: root.muted
  }

  // Plugins' own two items -- Check for Updates and Update actions,
  // then the checklist. Ported from ruixen.settings/PluginsContent.qml
  // + Settings.qml's own header-row Check/Update icons -- this plugin
  // has no shared header-icon chrome to put those in, so they're their
  // own action rows in a small card instead, same "adapt the chrome,
  // not the backend" approach Wi-Fi's own dropped QR/speed-test buttons
  // took the other way (dropped entirely there; kept here since these
  // two are core to the page, not optional extras).
  Rectangle {
    id: pluginActionsItem
    width: parent.width
    height: pluginActionsContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.pluginsOpen

    Column {
      id: pluginActionsContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 10

      Text {
        visible: root.ruixenRepoPath === ""
        width: parent.width
        text: "Update needs a repo checkout path -- run install.sh or update.sh once from your ruixen-shell clone to enable it here."
        wrapMode: Text.WordWrap
        font.family: root.fontFamily
        font.pixelSize: 10
        color: root.muted
      }

      Text {
        visible: root.pluginUpdateStatus === "error" && root.pluginUpdateError !== ""
        width: parent.width
        text: root.pluginUpdateError
        wrapMode: Text.WordWrap
        font.family: root.fontFamily
        font.pixelSize: 10
        color: "#e05252"
      }

      Text {
        visible: root.pluginCheckStatus === "error" && root.pluginCheckError !== ""
        width: parent.width
        text: root.pluginCheckError
        wrapMode: Text.WordWrap
        font.family: root.fontFamily
        font.pixelSize: 10
        color: "#e05252"
      }

      Item {
        id: pluginCheckButton
        width: parent.width
        height: 24
        readonly property bool actionEnabled: root.ruixenRepoPath !== "" && root.pluginCheckStatus !== "checking"

        Rectangle {
          visible: root.pluginsOpen && root.rightFocused && root.focusedItemIndex === 0
          anchors.fill: parent
          anchors.margins: -4
          radius: 6
          color: "transparent"
          border.width: 1
          border.color: root.accent
        }

        Text {
          id: checkGlyph
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: ""
          font.family: root.fontFamily
          font.pixelSize: 14
          color: pluginCheckButton.actionEnabled ? root.textColor : Qt.rgba(1, 1, 1, 0.25)
          rotation: root.pluginCheckStatus === "checking" ? checkSpinAngle : 0
          property real checkSpinAngle: 0

          NumberAnimation on checkSpinAngle {
            running: root.pluginCheckStatus === "checking"
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 900
          }
        }

        Text {
          anchors.left: checkGlyph.right
          anchors.leftMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          text: "Check for Updates"
          font.family: root.fontFamily
          font.pixelSize: 12
          color: pluginCheckButton.actionEnabled ? root.textColor : root.muted
        }

        MouseArea {
          anchors.fill: parent
          enabled: pluginCheckButton.actionEnabled
          cursorShape: Qt.PointingHandCursor
          onClicked: root.checkForUpdates()
        }
      }

      Item {
        id: pluginUpdateButton
        width: parent.width
        height: 24
        readonly property bool actionEnabled: root.ruixenRepoPath !== "" && root.pluginUpdateStatus !== "updating"

        Rectangle {
          visible: root.pluginsOpen && root.rightFocused && root.focusedItemIndex === 1
          anchors.fill: parent
          anchors.margins: -4
          radius: 6
          color: "transparent"
          border.width: 1
          border.color: root.accent
        }

        Text {
          id: updateGlyph
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: root.pluginUpdateStatus === "updating" ? "" : ""
          font.family: root.fontFamily
          font.pixelSize: 14
          color: pluginUpdateButton.actionEnabled ? root.textColor : Qt.rgba(1, 1, 1, 0.25)
          rotation: root.pluginUpdateStatus === "updating" ? updateSpinAngle : 0
          property real updateSpinAngle: 0

          NumberAnimation on updateSpinAngle {
            running: root.pluginUpdateStatus === "updating"
            loops: Animation.Infinite
            from: 0
            to: 360
            duration: 900
          }
        }

        Text {
          anchors.left: updateGlyph.right
          anchors.leftMargin: 10
          anchors.verticalCenter: parent.verticalCenter
          text: "Update"
          font.family: root.fontFamily
          font.pixelSize: 12
          color: pluginUpdateButton.actionEnabled ? root.textColor : root.muted
        }

        MouseArea {
          anchors.fill: parent
          enabled: pluginUpdateButton.actionEnabled
          cursorShape: Qt.PointingHandCursor
          onClicked: root.updateRuixenShell()
        }
      }
    }
  }

  Rectangle {
    id: pluginListItem
    width: parent.width
    height: pluginListContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.pluginsOpen

    Column {
      id: pluginListContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 4

      Text {
        visible: root.pluginRows.length === 0
        text: "No plugins found"
        font.family: root.fontFamily
        font.pixelSize: 11
        color: root.muted
      }

      Repeater {
        id: pluginRepeater
        model: root.pluginRows

        Item {
          id: pluginRow
          required property var modelData
          required property int index
          readonly property bool isProtected: root.pluginIsProtected(modelData)
          readonly property bool busy: root.pluginBusyId === modelData.id
          readonly property int focusIndex: {
            for (var i = 0; i < root.togglablePluginRows.length; i++)
              if (root.togglablePluginRows[i].id === modelData.id) return i
            return -1
          }

          width: parent.width
          height: 28

          Rectangle {
            visible: !pluginRow.isProtected && root.pluginsOpen && root.rightFocused
              && root.focusedItemIndex === (2 + pluginRow.focusIndex)
            anchors.fill: parent
            anchors.margins: -4
            radius: 6
            color: "transparent"
            border.width: 1
            border.color: root.accent
          }

          Text {
            id: pluginNameText
            anchors.left: parent.left
            anchors.right: pluginStatusDot.visible ? pluginStatusDot.left : (pluginLock.visible ? pluginLock.left : pluginToggle.left)
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            text: pluginRow.modelData.name
            font.family: root.fontFamily
            font.pixelSize: 12
            color: pluginRow.isProtected ? root.muted : root.textColor
            elide: Text.ElideRight
          }

          // Update-status dot -- pending (yellow) if this plugin has
          // files in the checked batch, up to date (accent) otherwise.
          // Only shown once a real check has actually run.
          Rectangle {
            id: pluginStatusDot
            visible: root.pluginCheckStatus === "checked"
            readonly property bool pending: root.pluginChangedIds.indexOf(pluginRow.modelData.id) >= 0
            anchors.right: pluginLock.visible ? pluginLock.left : pluginToggle.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            width: 6
            height: 6
            radius: 3
            color: pending ? "#e8c34a" : "#3ecf5b"
          }

          Text {
            id: pluginLock
            visible: pluginRow.isProtected
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: ""
            font.family: root.fontFamily
            font.pixelSize: 11
            color: root.muted
          }

          Rectangle {
            id: pluginToggle
            visible: !pluginRow.isProtected
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 32
            height: 16
            radius: 8
            color: pluginRow.modelData.enabled ? root.accent : Qt.rgba(1, 1, 1, 0.15)
            opacity: pluginRow.busy ? 0.5 : 1
            Behavior on color { ColorAnimation { duration: 120 } }

            Rectangle {
              width: 12
              height: 12
              radius: 6
              color: "#ffffff"
              anchors.verticalCenter: parent.verticalCenter
              x: pluginRow.modelData.enabled ? parent.width - width - 2 : 2
              Behavior on x { NumberAnimation { duration: 120 } }
            }

            MouseArea {
              anchors.fill: parent
              enabled: !pluginRow.busy
              cursorShape: Qt.PointingHandCursor
              onClicked: root.togglePluginEnabled(pluginRow.modelData)
            }
          }
        }
      }
    }
  }

  // About's own two items -- the version card (small and static, same
  // reasoning as ruixen.settings' own: no real version tracking exists
  // in this repo yet, so this mirrors the one number that does --
  // ruixen.launcher's own manifest.json "version" field, "Ruixen
  // Launcher" not "Ruixen Shell" since that's this plugin's own name)
  // and the danger-zone full uninstall, ported from
  // ruixen.settings/AboutContent.qml. Gated behind typing an exact
  // phrase, not just a click-through confirm.
  Rectangle {
    id: aboutVersionItem
    width: parent.width
    height: aboutVersionContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0, 0, 0, 0.18)
    visible: root.aboutOpen

    Column {
      id: aboutVersionContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 4

      Text {
        text: "Ruixen Launcher"
        font.family: root.fontFamily
        font.pixelSize: 12
        font.weight: Font.DemiBold
        color: root.textColor
      }

      Text {
        text: "v0.1.0 -- github.com/gitcoder89431/ruixen-shell"
        font.family: root.fontFamily
        font.pixelSize: 10
        color: root.muted
      }
    }
  }

  Rectangle {
    id: dangerZoneItem
    width: parent.width
    height: dangerZoneContent.implicitHeight + 24
    radius: 10
    color: Qt.rgba(0.878, 0.322, 0.322, 0.08)
    border.width: 1
    border.color: Qt.rgba(0.878, 0.322, 0.322, 0.35)
    visible: root.aboutOpen

    Column {
      id: dangerZoneContent
      anchors.fill: parent
      anchors.margins: 12
      spacing: 8

      Text {
        visible: root.ruixenRepoPath === ""
        width: parent.width
        text: "Uninstall needs a repo checkout path -- run install.sh or update.sh once from your ruixen-shell clone to enable it here."
        wrapMode: Text.WordWrap
        font.family: root.fontFamily
        font.pixelSize: 10
        color: root.muted
      }

      Item {
        id: uninstallConfirmRow
        width: parent.width
        height: 32

        Rectangle {
          visible: root.aboutOpen && root.rightFocused && root.focusedItemIndex === 0
          anchors.fill: parent
          anchors.margins: -4
          radius: 10
          color: "transparent"
          border.width: 1
          border.color: root.accent
        }

        Rectangle {
          anchors.left: parent.left
          anchors.right: uninstallButtonRow.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          height: 32
          radius: 10
          color: Qt.rgba(1, 1, 1, 0.06)

          TextInput {
            id: uninstallConfirmField
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            verticalAlignment: TextInput.AlignVCenter
            color: root.textColor
            font.family: root.fontFamily
            font.pixelSize: 12
            clip: true
            text: root.uninstallConfirmInput
            onTextChanged: root.uninstallConfirmInput = text

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: root.uninstallConfirmPhrase
              color: root.muted
              font.family: root.fontFamily
              font.pixelSize: 12
              visible: uninstallConfirmField.text.length === 0
            }

            Keys.onEscapePressed: root.returnFocusRequested()
          }
        }

        Rectangle {
          id: uninstallButtonRow
          readonly property bool ready: root.ruixenRepoPath !== "" && root.uninstallConfirmInput === root.uninstallConfirmPhrase

          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: 96
          height: 32
          radius: 10
          color: !uninstallButtonRow.ready ? Qt.rgba(1, 1, 1, 0.06)
            : (uninstallMouse.containsMouse ? Qt.rgba(0.878, 0.322, 0.322, 0.55) : Qt.rgba(0.878, 0.322, 0.322, 0.4))
          opacity: uninstallButtonRow.ready ? 1 : 0.5

          Rectangle {
            visible: root.aboutOpen && root.rightFocused && root.focusedItemIndex === 1
            anchors.fill: parent
            anchors.margins: -4
            radius: 12
            color: "transparent"
            border.width: 1
            border.color: root.accent
          }

          Text {
            anchors.centerIn: parent
            text: "Uninstall"
            font.family: root.fontFamily
            font.pixelSize: 12
            font.weight: Font.DemiBold
            color: root.textColor
          }

          MouseArea {
            id: uninstallMouse
            anchors.fill: parent
            hoverEnabled: true
            enabled: uninstallButtonRow.ready
            cursorShape: Qt.PointingHandCursor
            onClicked: root.confirmFullUninstall()
          }
        }
      }
    }
  }
    }
  }
}
