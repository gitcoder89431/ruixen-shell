import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Networking
import Quickshell.Bluetooth
import Quickshell.Io
import qs.Commons

// Ruixen Settings -- standalone center-panel settings app. First plugin
// in the "ruixen apps" family (settings/launcher/AI chat/notepad, per
// direct request): meant to carry the same dark card look and radii as
// ruixen.notch's own stat tiles, but as its own independent plugin --
// no dependency on ruixen.bar or ruixen.notch, works if someone installs
// only this one. `qs.Commons` (the Color singleton used here) is part of
// the Omarchy shell runtime itself, not a ruixen-specific dependency, so
// pulling real theme tokens from it doesn't break that independence.
//
// Contract matches Omarchy's own built-in overlay plugins (confirmed by
// reading $OMARCHY_PATH/shell/plugins/emojis/Emojis.qml directly, not
// guessed): root exposes `shell`/`manifest` (injected by the host),
// open()/close()/toggle()/dismiss(), and an internal PanelWindow whose
// `visible` follows `root.opened`. `dismiss()` calls `shell.hide(id)` so
// the host's own toggle bookkeeping (`omarchy-shell shell toggle
// ruixen.settings`) stays in sync with an in-panel close/Escape too.
Item {
  id: root
  property var shell: null
  property var manifest: null

  property bool opened: false

  // Same theme-aware-with-safety-net treatment as ruixen.notch/ruixen.bar
  // (see Overlay.qml's own themeForeground comment for the full
  // reasoning) -- this panel is meant to read as OLED-dark on every
  // theme, so fall back to a fixed light color only when a theme's own
  // foreground would be unreadably dark against that.
  readonly property color themeForeground: Color.bar.text
  readonly property real themeForegroundLuminance: 0.299 * themeForeground.r + 0.587 * themeForeground.g + 0.114 * themeForeground.b
  readonly property color safeForeground: "#e8e8e8"
  readonly property color textColor: themeForegroundLuminance > 0.45 ? themeForeground : safeForeground
  readonly property color muted: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.5)
  readonly property color accent: Color.accent

  // Hardcoded OLED black, not a theme-driven token -- per direct request
  // ("can we make it match our other plugin with the oled black bg as
  // well") to match ruixen.notch/ruixen.bar's own established
  // convention (see Overlay.qml's notchColor / Bar.qml's GroupPill
  // comment: "Every pill is hardcoded OLED black... has to do with
  // what's actually readable against our pills"). The theme-driven
  // Color.menu.background used in the first pass was real data too, but
  // the wrong real data -- that token is meant for Omarchy's own
  // built-in menus, not this family's own signature look. Scrim (the
  // backdrop dimming) stays theme-driven -- that's a different surface,
  // not part of the "match our other plugins" ask.
  readonly property color panelBackground: "#000000"
  readonly property color scrim: Color.menu.scrim

  readonly property string fontFamily: "JetBrainsMono Nerd Font"

  // Sidebar-driven sections -- per direct request ("2 panels, so theres
  // a left side for switching between setting options and then to the
  // right is where the settings and toggles are... a highly reusable
  // design"). Same left-nav/right-content shape ruixen.notch's own
  // dashboard already uses (TabButton column + active tab's content),
  // just applied to this panel's own sections instead of Widgets/
  // Wallpapers/Metrics. Renamed from the placeholder General/
  // Appearance/About to the real plan ("im gonna use it to control the
  // audio, wifi, and bluetooth display, so then we dont need to use
  // the omarchy one") -- glyph codepoints confirmed against
  // JetBrainsMonoNerdFont's own cmap (fa-volume_up, fa-wifi,
  // fa-bluetooth), not guessed.
  readonly property var sections: [
    // Sidebar label "System", not "General"/"Settings" -- direct
    // follow-up chain: first "is it better to just put settings here
    // then general cause like its the main page?" (Settings > General
    // -> just Settings), then, since the app itself is already called
    // Ruixen Settings, "Settings" as a section label read as a
    // confusing "Settings > Settings" -- renamed to System instead.
    // id stays "general" internally (still matches the {"section":
    // "general"} IPC payload convention).
    { id: "general", label: "System", glyph: "" },
    { id: "audio", label: "Audio", glyph: "" },
    { id: "wifi", label: "Wi-Fi", glyph: "" },
    { id: "bluetooth", label: "Bluetooth", glyph: "" },
    { id: "display", label: "Display", glyph: "" },
    { id: "plugins", label: "Plugins", glyph: "" },
    { id: "about", label: "About", glyph: "" }
  ]
  property int selectedSection: 0

  // Sidebar search -- direct request ("a lot of design has that...
  // can we put a search input there and hook it up"). Filters the
  // sidebar list by label only (7 entries total, so matching id/glyph
  // too would just be extra work with nothing real to filter by).
  // Keeps each row's real position in root.sections (originalIndex)
  // rather than the filtered array's own position -- selectedSection
  // is always an index into the full, unfiltered list, so a filtered-
  // out selection stays correct underneath (just not visible in the
  // sidebar) instead of pointing at the wrong section.
  property string sidebarQuery: ""

  readonly property var filteredSections: {
    // Built by hand, not object-spread ({ ...s, ... }) -- QML's JS
    // engine rejected that syntax outright ("Unexpected token '...'"),
    // confirmed live via the journal, not assumed.
    const withIndex = root.sections.map((s, i) => ({ id: s.id, label: s.label, glyph: s.glyph, originalIndex: i }))
    const q = root.sidebarQuery.trim().toLowerCase()
    if (q.length === 0) return withIndex
    return withIndex.filter(s => s.label.toLowerCase().includes(q))
  }

  function sectionIndexFor(id) {
    for (var i = 0; i < root.sections.length; i++)
      if (root.sections[i].id === id) return i
    return 0
  }

  // Accepts an optional JSON payload, matching the real host convention
  // (confirmed directly: `omarchy-shell shell toggle omarchy.menu
  // '{"menu":"root"}'` in `omarchy-shell --help`'s own example) -- per
  // direct plan ("on our top bar we can use the icon to open the
  // settings we are making onto like the bluetooth page there"), a bar
  // icon can jump straight to a section via `omarchy-shell shell
  // toggle ruixen.settings '{"section":"bluetooth"}'` instead of
  // always landing on whatever was last selected.
  function open(payloadJson) {
    // Section applied BEFORE opened flips true -- direct bug hit live
    // ("the display page now has a big gap between display header and
    // the brightness card"): this used to set opened=true first, THEN
    // update selectedSection a moment later as a second, separate
    // reactive update. That let the panel briefly become visible still
    // showing whichever section was selected before (e.g. Audio),
    // before switching to the target section right after -- and that
    // flash was enough for the previous section's own Layout.fillHeight
    // ColumnLayout to compute and lock in a height that persisted even
    // once switched away and invisible again (confirmed live: the gap
    // matched a previously-visible section's own content height,
    // showed up specifically after switching sections, and was traced
    // to this exact ordering by reading open()'s own code, not
    // guessed). Setting selectedSection first means the correct
    // section is already active before the panel is ever shown, so
    // there's no wrong section to flash.
    if (payloadJson) {
      try {
        var payload = JSON.parse(payloadJson)
        if (payload && payload.section)
          root.selectedSection = root.sectionIndexFor(payload.section)
      } catch (e) {}
    }
    root.opened = true
  }

  function close() {
    root.opened = false
  }

  function dismiss() {
    root.opened = false
    if (root.shell && typeof root.shell.hide === "function")
      root.shell.hide((root.manifest && root.manifest.id) || "ruixen.settings")
  }

  function toggle(payloadJson) {
    if (root.opened) root.dismiss()
    else root.open(payloadJson)
  }

  // General -- bar layout mode (docked/floating) + avatar, per direct
  // request ("i think we can just do General for now"). Reads/writes
  // ~/.config/omarchy/shell.json directly rather than shelling out to
  // this repo's own ruixen-bar-mode.sh -- same mutation that script
  // does (bar.docked flag + a live reloadConfig, confirmed by reading
  // it directly), just inlined so this doesn't depend on
  // root.ruixenRepoPath the way the Plugins page's update/uninstall
  // genuinely have to (those need a real git checkout; this doesn't).
  property string barMode: "floating"

  // Machine name + username -- direct follow-up ("instead of the
  // header being General, can you put the machine name... we can also
  // use the username where the Avatar text is"), reusing the exact
  // same sources ruixen.notch's own Metrics tab already shows (its own
  // "identity rows"), not reinvented: fastfetch's Host module for the
  // real hardware/PC name (not the network $HOSTNAME), $USER for the
  // username. Plugins can't import each other's QML, so this is the
  // same command/property shape ported here, not a shared import.
  property string hardwareName: ""
  readonly property string username: {
    var u = Quickshell.env("USER") || "user"
    return u.charAt(0).toUpperCase() + u.slice(1)
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
      "python3 -c \"import json; p='" + path + "'; d=json.load(open(p)); d.setdefault('bar', {})['docked'] = " + value + "; json.dump(d, open(p, 'w'), indent=2)\" && omarchy-shell shell reloadConfig"]
    barModeWriteProc.running = true
  }

  // Avatar -- ~/.face.icon, same convention/gradient-fallback mechanism
  // ruixen.notch's own UserAvatar component already uses. "gradient" is
  // just another entry in avatarCollections, not a separate Reset
  // button/concept -- direct follow-up ("we dont need the shuffle and
  // reset button, just put the collection there and then instead of
  // reset just call it the gradient collection"). Picking it deletes
  // ~/.face.icon so the existing gradient fallback in ruixen.notch's
  // UserAvatar takes back over on its own; picking any real DiceBear
  // style fetches a random avatar from it (api.dicebear.com, free, no
  // auth needed).
  property int avatarCacheBust: 0
  property bool avatarBusy: false

  // Curated to visually distinct DiceBear styles (confirmed real
  // slugs by hitting each one directly, not guessed) plus the gradient
  // pseudo-collection, rather than all ~30 DiceBear ships -- a picker
  // that wide wouldn't fit this card. version/format default to
  // DiceBear's 9.x PNG endpoint (see selectAvatar below) when a
  // collection doesn't specify its own -- Sprouts, Pixelbot, and
  // Bottts-neutral are the 10.x SVG entries so far. Sprouts: direct
  // follow-up ("can we try the animated collections like this one...
  // https://api.dicebear.com/10.x/sprouts/svg"). "Animated" turned out
  // to mean DiceBear ships an opt-in CSS/SMIL animation feature for
  // this style on their own site, not that the raw SVG fetch animates
  // on its own -- confirmed by reading the actual returned markup (an
  // inert <g id="animation-none-..."> placeholder, no <animate>/
  // @keyframes present) -- and Qt's SVG renderer doesn't run CSS/SMIL
  // regardless, so this renders as a nice static sprout-pot character,
  // not a moving one. Confirmed live that Qt can load an SVG through
  // this pipeline at all (~/.face.icon has no extension, was a real
  // unknown -- Qt does content sniffing, works fine) before adding
  // this rather than assuming. This slot has had two other occupants,
  // both swapped out on sight after actually being tried: Adventurer
  // (its character sits small in the middle of the canvas, too much
  // empty space around it -- "the adventuer one looks too small"), then
  // Rings ("crap nvm it looks ugly static" -- a concentric pattern that
  // reads fine as a still image but apparently doesn't work as an
  // avatar). Pixelbot is a simple LED-face style, easy to tell apart at
  // a glance. Bottts-neutral replaces the original 9.x Bottts entry
  // (same label kept, still a robot family) per direct follow-up
  // ("swapp the botts to neutral https://api.dicebear.com/10.x/
  // bottts-neutral/svg") -- a monochrome/single-tone variant of the
  // original multi-colored bottts style. Critters and Moods added per
  // direct follow-up ("that should probably be it so the second toggle
  // row dont look so empty") -- 7 entries wrapped Sprouts alone onto a
  // sparse-looking second Flow row; these two fill it out to three.
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
  // Starts on "gradient" -- matches the real state a fresh install
  // actually starts in (no ~/.face.icon yet). Persisted separately
  // from the file itself, direct follow-up ("the avatar set survives
  // restart? we write it to json or somewhere?") -- ~/.face.icon is
  // real state on disk, so the image itself already survived a
  // restart, but this property is plain in-memory QML state that reset
  // to "gradient" every restart regardless of what the file actually
  // held, leaving the picker's own selected-highlight wrong (showing
  // Gradient selected while a real avatar was visibly showing).
  // Same FileView.setText() persistence pattern already used for
  // ruixen.notch's own launcher-favorites.json (confirmed by reading
  // that one directly) -- a real state file, not guessed at.
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

  Component.onCompleted: ensureAvatarStateDirProc.running = true

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
      avatarNotifyProc.command = ["qs", "-p", "/usr/share/omarchy/shell", "ipc", "call", "ruixen.notch", "refreshAvatar"]
      avatarNotifyProc.running = true
    }
  }

  Process {
    id: avatarNotifyProc
  }

  // Single entry point for every avatar-picker button -- "gradient"
  // deletes ~/.face.icon, any real DiceBear slug fetches a random
  // avatar from that collection. Replaces the old separate shuffleAvatar()/
  // resetAvatar() pair now that Gradient is just another button in the
  // same row instead of a distinct Reset action.
  function selectAvatar(collection) {
    if (root.avatarBusy) return
    root.avatarBusy = true
    root.avatarCollection = collection
    var target = Quickshell.env("HOME") + "/.face.icon"
    if (collection === "gradient") {
      avatarProc.command = ["bash", "-c", "rm -f '" + target + "'"]
    } else {
      var seed = Math.random().toString(36).slice(2) + Date.now()
      // Per-collection version/format, defaulting to DiceBear's 9.x
      // PNG endpoint -- see avatarCollections above for why Sprouts is
      // the one exception (10.x SVG) so far.
      var entry = null
      for (var i = 0; i < root.avatarCollections.length; i++) {
        if (root.avatarCollections[i].id === collection) { entry = root.avatarCollections[i]; break }
      }
      var version = (entry && entry.version) || "9.x"
      var format = (entry && entry.format) || "png"
      // No backgroundType/backgroundColor override anymore, no radius
      // param either -- direct correction: "why are you removing the
      // background it comes with, stop messing with it and just show
      // the dicebear as is". backgroundColor=000000 was originally
      // added to stop the fallback gradient from bleeding through a
      // circular mask's transparent gaps, but that mask (and later
      // radius=50, DiceBear's own circular crop) is gone entirely now
      // -- the gradient and a real avatar are never visible at the
      // same time (gradient's own visible is gated on the image NOT
      // being ready), so there was nothing left for this override to
      // actually protect against. Whatever background each DiceBear
      // style ships by default (transparent for most styles, an
      // automatic soft color for some like Thumbs -- confirmed by
      // fetching a few styles with no params at all) is what renders
      // now, unmodified.
      var url = "https://api.dicebear.com/" + version + "/" + collection + "/" + format + "?seed=" + seed
      avatarProc.command = ["bash", "-c", "curl -fsL '" + url + "' -o '" + target + "'"]
    }
    avatarProc.running = true
  }

  // Real Pipewire-backed audio state -- Quickshell.Services.Pipewire is
  // a standard Quickshell module (not Omarchy-private), confirmed by
  // reading Omarchy's own audio bar-widget directly
  // ($OMARCHY_PATH/shell/plugins/panels/audio/Panel.qml) for the real
  // property paths (node.audio.volume/muted, Pipewire.
  // preferredDefaultAudioSink/Source) rather than guessing -- ported
  // the exact API calls, not the file itself (theirs is a 1200-line
  // full mixer with per-app streams + MPRIS matching; this pass is
  // scoped to volume + output/input device pickers only, per direct
  // request: "should we start with the audio then... volume + output
  // device picker", then "does it also shows the input? the omarchy
  // has it showing").
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
  // Panel.qml's own source/inputVolume/inputMuted/candidateSources/
  // setDefaultSource. isAudioSource's real filter (ported from
  // Model.js) is broader than isSink/isStream alone -- a source node
  // can be true audio-source without node.isSink ever being set, so
  // this checks node.audio presence and the node's own media-class
  // string, same as their real isAudioSource().
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

  // Master mute switch -- ported directly from Omarchy's own audio
  // panel's "hero switch" (hasOutput/hasInput/anyAudible/
  // toggleAllMuted): reads as on while EITHER channel is still
  // audible, and toggling it mutes or unmutes both at once, so muting
  // just one channel from its own row below never silently flips this
  // master switch on its own.
  readonly property bool hasOutput: !!(outputSink && outputSink.audio)
  readonly property bool hasInput: !!(inputSource && inputSource.audio)
  readonly property bool anyAudible: (hasOutput && !outputMuted) || (hasInput && !inputMuted)

  function toggleAllMuted() {
    var mute = root.anyAudible
    if (root.hasOutput) root.outputSink.audio.muted = mute
    if (root.hasInput) root.inputSource.audio.muted = mute
  }

  // Same real property-preference order as Omarchy's own nodeLabel()/
  // friendlyDeviceLabel() in Model.js, ported directly (not guessed):
  // nickname/nick fields first, falling back to description/name, then
  // trimmed of the same noisy driver-name prefixes/suffixes and the
  // Microphones->Microphone normalization their real hardware strings
  // carry on this exact machine class. Shared by both output and input
  // rows -- nodeLabel() itself is generic, not sink-specific, in the
  // real source either.
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
  // muted/name properties actually receive live updates -- same real
  // requirement Omarchy's own audio widget has (its own Panel.qml uses
  // the identical PwObjectTracker pattern for its candidateSinks/
  // candidateSources lists).
  PwObjectTracker { objects: root.outputDevices }
  PwObjectTracker { objects: root.inputDevices }

  // Real Quickshell.Networking-backed Wi-Fi state -- another standard
  // Quickshell module, confirmed by reading Omarchy's own network
  // bar-widget directly ($OMARCHY_PATH/shell/plugins/panels/network/
  // Panel.qml + Model.js, 1958 + 369 lines). Scoped per direct
  // confirmation: status + network list + connect to open/known
  // networks only -- no password-entry UI for new protected networks
  // yet (their own file has one, it's a real separate flow: passphrase
  // prompt, WPA-Enterprise nmcli scripting, retry-on-failure state --
  // out of scope for this pass).
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
  // directly from Omarchy's own wifiRow() comment/reasoning in
  // Model.js: NetworkManager scan churn can destroy a network object
  // while a delegate built from it is still incubating, which segfaults
  // quickshell if a live QObject wrapper is sitting in list-model data.
  // Connecting resolves back to the live object via networkForSsid() at
  // click time instead (same real pattern, see connectToWifi below).
  function syncWifiNetworks() {
    // Skip while a password prompt is open. Real bug this caught: NM
    // scan ticks fire every few seconds regardless, each one replacing
    // wifiRows with a brand-new array (this function always does that,
    // never mutates in place) -- Repeater treats a new array as a new
    // model and tears down/recreates every delegate, INCLUDING the row
    // whose TextInput the user is actively typing into, and rows also
    // re-sort by live signal strength each time, so the list visibly
    // jumped mid-interaction. Freezing here and catching up in
    // closeWifiPasswordPrompt() (below) means the list only reflows
    // when nothing's actively being typed into it.
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

  // Known networks stay their own switcher list -- per the original
  // direct follow-up ("it showing all wifi spot available to join and
  // its overflowing... were we gonna show just the one[s] we already
  // connected to so they can switch") -- with new networks reachable via
  // the "Other Networks" accordion below (see otherWifiRows and
  // showOtherNetworks) instead of mixed into this one.
  readonly property var knownWifiRows: root.wifiRows.filter(function(r) { return r.known })
  readonly property var otherWifiRows: root.wifiRows.filter(function(r) { return !r.known })
  // Accordion, open by default -- per direct follow-up. Was a plain
  // always-visible section (no collapse at all); this brings the
  // toggle back but flips the default from the original collapsed-by-
  // default version (see git history) to open, so new networks are
  // immediately visible without an extra click, while still being
  // collapsible for anyone who wants the shorter view back.
  property bool showOtherNetworks: true

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
  // network -- WPA-PSK only via Quickshell.Networking's own
  // network.connectWithPsk(), the exact call Omarchy's own real network
  // panel uses (confirmed by reading $OMARCHY_PATH/shell/plugins/panels/
  // network/Panel.qml directly). WPA-Enterprise is real but needs a
  // separate nmcli-scripted flow (their own Model.enterpriseConnectScript)
  // -- out of scope here, deliberately: enterprise networks are rare
  // outside campus/corporate Wi-Fi, and the whole point of this pass was
  // making the common "type a password, join home Wi-Fi" case actually
  // work instead of silently no-op'ing.
  property string wifiPasswordSsid: ""
  property string wifiPasswordAttempt: ""
  property bool wifiConnecting: false
  property string wifiConnectError: ""

  function openWifiPasswordPrompt(ssid) {
    root.wifiPasswordSsid = ssid
    root.wifiPasswordAttempt = ""
    root.wifiConnectError = ""
    root.wifiConnecting = false
  }

  function closeWifiPasswordPrompt() {
    root.wifiPasswordSsid = ""
    root.wifiPasswordAttempt = ""
    root.wifiConnectError = ""
    root.wifiConnecting = false
    // Catches up on whatever scan ticks syncWifiNetworks() skipped
    // while the prompt was open (see its own comment) -- otherwise
    // wifiRows stays frozen at a stale snapshot until the next real
    // change event happens to fire on its own.
    root.syncWifiNetworks()
  }

  function submitWifiPassword() {
    if (root.wifiConnecting || root.wifiPasswordAttempt.length === 0) return
    var network = root.networkForSsid(root.wifiPasswordSsid)
    if (!network) { root.wifiConnectError = "Network no longer in range"; return }
    // Real error hit live: "WifiNetwork is already connected" -- the
    // network can transition to connected on its own between the row
    // being clicked and the password actually being submitted (seen
    // with two SSIDs off the same router, likely 802.11k/v roaming),
    // and connectWithPsk() on an already-connected network throws that
    // error instead of being a harmless no-op. Guard it directly.
    if (network.connected) { root.closeWifiPasswordPrompt(); return }
    root.wifiConnectError = ""
    root.wifiConnecting = true
    network.connectWithPsk(root.wifiPasswordAttempt)
  }

  // Scoped to whichever network the open passphrase prompt targets (null
  // target when the prompt is closed, so this is a no-op the rest of the
  // time). connectionFailed(reason) and connectedChanged are the same
  // two signals Omarchy's own network panel listens to for this exact
  // purpose (confirmed by reading their Panel.qml).
  Connections {
    target: root.wifiPasswordSsid !== "" ? root.networkForSsid(root.wifiPasswordSsid) : null
    function onConnectionFailed(reason) {
      root.wifiConnecting = false
      root.wifiConnectError = (reason === ConnectionFailReason.NoSecrets || reason === ConnectionFailReason.WifiAuthTimeout)
        ? "Wrong password" : "Couldn't connect"
      // Real bug hit live: connectWithPsk() creates a full, autoconnect-
      // enabled NetworkManager profile immediately as part of attempting
      // the connection -- BEFORE the password is validated. On failure
      // that broken profile just sits there, showing as "known" despite
      // never actually authenticating, and NM will keep quietly
      // retrying it (autoconnect: yes) in the background whenever it's
      // in range. This flow only ever opens for networks that were NOT
      // known when clicked (see connectToWifi's own guard), so failure
      // here always means "the attempt failed, not that a real saved
      // network's password changed" -- safe to forget unconditionally,
      // and it must happen so a wrong guess doesn't leave a dead
      // autoconnect profile behind. Omarchy's own real panel has this
      // same gap (confirmed by reading their Panel.qml directly, no
      // forget-on-failure there either) -- not something this port did
      // differently, but worth fixing regardless.
      if (target) target.forget()
    }
    function onConnectedChanged() {
      if (target && target.connected) root.closeWifiPasswordPrompt()
    }
  }

  // Real click-to-connect. Known networks (already have saved
  // credentials) and open networks connect immediately via
  // network.connect(); a new protected network opens the passphrase
  // prompt instead of the old deliberate no-op.
  function connectToWifi(row) {
    if (!row || row.connected) return
    if (!row.known && !root.isOpenNetwork(row.security)) {
      // Clicking the row that's already expanded closes it back up
      // instead of just clearing whatever was typed -- matches normal
      // disclosure-row expectations.
      if (root.wifiPasswordSsid === row.ssid) root.closeWifiPasswordPrompt()
      else root.openWifiPasswordPrompt(row.ssid)
      return
    }
    var network = root.networkForSsid(row.ssid)
    // row.connected is a stale snapshot (see the syncWifiNetworks
    // comment above) -- re-check the live object too, same reasoning
    // as submitWifiPassword's own guard.
    if (network && !network.connected) network.connect()
  }

  // Excludes the connected network (mirrors Omarchy's own real panel's
  // canForgetNetwork: known && !connected) -- forgetting the network
  // you're actively using would disconnect you as a side effect of
  // what's meant to be a plain cleanup click.
  function forgetWifi(row) {
    if (!row || row.connected) return
    var network = root.networkForSsid(row.ssid)
    if (network) network.forget()
  }

  function toggleWifiRadio() {
    Networking.wifiEnabled = !Networking.wifiEnabled
  }

  // Both real Omarchy panel plugins (kind: panel), already enabled in
  // this shell -- confirmed via omarchy-shell shell listPlugins, not
  // guessed. root.shell.summon(id, payloadJson) is the same generic
  // host API our own dismiss() already calls as shell.hide(id)
  // (confirmed real at $OMARCHY_PATH/shell/shell.qml's own summon()/
  // hide() functions), just the "open a panel" verb instead of "close
  // this one". Payload shapes ported directly from Omarchy's own
  // summonWifiQr()/summonSpeedTest() in Panel.qml.
  function summonWifiQr() {
    if (!root.shell || typeof root.shell.summon !== "function") return
    var payload = {}
    if (root.connectedWifiNetwork) {
      if (root.netInfo.iface) payload.iface = root.netInfo.iface
      payload.ssid = root.connectedWifiNetwork.ssid
    }
    root.shell.summon("omarchy.wifiqr", JSON.stringify(payload))
  }

  function summonSpeedTest() {
    if (!root.shell || typeof root.shell.summon !== "function") return
    var connection = root.connectedWifiNetwork ? root.connectedWifiNetwork.ssid : ""
    root.shell.summon("omarchy.speedtest", connection ? JSON.stringify({ connection: connection }) : "{}")
  }

  // scannerEnabled lives on the shared WifiDevice (not per-panel-
  // instance state), so it has to be explicitly released -- ported
  // directly from Omarchy's own setScannerEnabled()/scannerDevice
  // comment: tracks which device THIS instance turned scanning on for,
  // so closing the panel (or the device changing) never leaves the
  // radio scanning in the background for nothing.
  property var scannerDevice: null

  function setScannerEnabled(enabled) {
    var nextDevice = root.opened ? root.wifiDevice : null
    if (root.scannerDevice && root.scannerDevice !== nextDevice)
      root.scannerDevice.scannerEnabled = false
    root.scannerDevice = nextDevice
    if (root.scannerDevice)
      root.scannerDevice.scannerEnabled = enabled
  }

  // Same ownership-release reasoning as Wi-Fi's own scannerDevice
  // above, applied to BlueZ's discovery session instead of the Wi-Fi
  // radio's scan -- adapter.discovering is the real property (confirmed
  // in Omarchy's own bluetooth Panel.qml: "keep nudging it back on so
  // an enabled adapter is always scanning" while their panel is open).
  property var btScannerAdapter: null

  function setBtScannerEnabled(enabled) {
    var nextAdapter = root.opened ? root.btAdapter : null
    if (root.btScannerAdapter && root.btScannerAdapter !== nextAdapter)
      root.btScannerAdapter.discovering = false
    root.btScannerAdapter = nextAdapter
    if (root.btScannerAdapter)
      root.btScannerAdapter.discovering = enabled
  }

  onOpenedChanged: {
    root.setScannerEnabled(true)
    root.setBtScannerEnabled(true)
    if (root.opened) {
      root.refreshPlugins()
      repoPathProc.running = true
      barModeReadProc.running = true
      if (root.hardwareName === "") identityProc.running = true
    }
  }
  onWifiDeviceChanged: root.setScannerEnabled(true)
  onBtAdapterChanged: root.setBtScannerEnabled(true)
  Component.onDestruction: {
    if (root.scannerDevice) root.scannerDevice.scannerEnabled = false
    if (root.btScannerAdapter) root.btScannerAdapter.discovering = false
  }

  // Real connection stats (IP, gateway, ping) via `omarchy-network-
  // status --verbose` -- a real standalone Omarchy CLI binary (same
  // class of dependency as fastfetch/sensors/df, which ruixen-notch
  // already uses freely -- this is a real system tool this plugin runs
  // on top of by definition, not a dependency on ruixen-bar/ruixen-
  // notch's own internal services, so it doesn't break this plugin's
  // standalone-ness). Confirmed the real output format by running it
  // directly on this machine, not guessed: tab-separated key\tvalue
  // lines (iface, ip, prefix, gateway, rx_bytes, tx_bytes, type, ssid,
  // signal_dbm, freq, bitrate, router_ping_ms, internet_ping_ms).
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
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: if (!netStatusProc.running) netStatusProc.running = true
  }

  // Real Quickshell.Bluetooth-backed state -- another standard
  // Quickshell module, confirmed by reading Omarchy's own bluetooth
  // bar-widget directly ($OMARCHY_PATH/shell/plugins/panels/bluetooth/
  // Panel.qml + Model.js, 1039 + 177 lines). Originally scoped to
  // known/paired devices only, matching Wi-Fi's own original scope --
  // extended once Wi-Fi got its own discovery+connect flow, per direct
  // follow-up asking whether the same made sense here. Turned out
  // simpler than Wi-Fi's version: pairing a brand-new device needs no
  // password UI at all in the common case -- omarchy-bluetooth-device
  // (below) just shells out to `bluetoothctl pair`, which uses BlueZ's
  // default "Just Works" agent for most real devices (headphones,
  // speakers, keyboards), confirmed by reading that script directly,
  // not the PIN/passkey sequence assumed here previously.
  //
  // Real mechanism difference from Wi-Fi/Audio, confirmed directly:
  // the adapter's own `enabled` property doesn't persist by itself
  // (Omarchy's own comment: "that writes BlueZ's Powered, which
  // nothing persists"), so toggling and per-device actions both go
  // through real external CLIs (omarchy-bluetooth-power, omarchy-
  // bluetooth-device) via Quickshell.execDetached(), not direct
  // property writes the way Wi-Fi's own network.connect() was.
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
  // real crash-avoidance reasoning as Wi-Fi's own wifiRow()/syncWifi-
  // Networks() (see that comment above): BlueZ churn (discovery
  // timeouts, unpair) can destroy a device object while a delegate
  // built from it is still incubating. Actions resolve back to the
  // live object via btDeviceForAddress() at click time instead, same
  // pattern as Wi-Fi's own networkForSsid().
  function syncBtDevices() {
    var rows = []
    var devs = root.btDeviceObjects
    for (var i = 0; i < devs.length; i++) {
      var d = devs[i]
      if (!d || !root.btHasHumanName(d)) continue
      // known no longer gates inclusion (used to drop anything not
      // already paired/bonded/trusted) -- unpaired-but-discovered
      // devices now flow into otherBtRows below instead of being
      // filtered out entirely, same known/other split Wi-Fi's own
      // wifiRows already uses.
      rows.push({
        address: d.address || "",
        name: root.btDeviceLabel(d),
        connected: !!d.connected,
        known: !!(d.paired || d.bonded || d.trusted),
        // Real gap this flags: omarchy-bluetooth-device's pair action
        // calls trust_device() unconditionally, win or lose, so a
        // device can land in "known" purely off a `Trusted: yes` side
        // effect with no actual bond -- e.g. a BLE-only device where
        // classic pairing no-ops but the follow-up raw connect still
        // succeeds. Kept in the same known list (that's still the
        // right place -- it's the only way back to reconnect it) but
        // this distinguishes "genuinely paired" from "merely trusted"
        // so the row can say so instead of looking identical.
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
    // (connected flipped, or an armed/pending device disappeared) --
    // see btBusyAddress below. Without this, "Connecting..."/"Pairing..."
    // would hang forever if the CLI's own best-effort connect/pair
    // silently no-ops.
    if (root.btBusyAddress !== "") {
      var busy = root.btDeviceForAddress(root.btBusyAddress)
      if (!busy || busy.connected) root.btBusyAddress = ""
    }
  }

  onBtDeviceObjectsChanged: root.syncBtDevices()

  // Busy feedback for an in-flight connect/pair -- real report hit
  // live: "i clicked mibox again... nothing happens then after a
  // minute it shows up". Nothing was actually broken; there was just
  // zero feedback that a fire-and-forget CLI call was even in flight,
  // so a real ~1-minute BLE connect latency read as "did nothing".
  // Cleared above once the device's connected state moves, or by this
  // timeout as a backstop if it never does.
  property string btBusyAddress: ""

  Timer {
    id: btBusyTimeout
    interval: 20000
    onTriggered: root.btBusyAddress = ""
  }

  readonly property var knownBtRows: root.btRows.filter(function(r) { return r.known })
  readonly property var otherBtRows: root.btRows.filter(function(r) { return !r.known })
  property bool showOtherBtDevices: true
  property bool showPairedBtDevices: true

  // Confirm-before-pair for unknown devices -- real report hit live: a
  // single click on a nearby "Other Devices" row fired a real
  // bluetoothctl pair immediately, no confirmation at all. Wi-Fi's own
  // flow always needed a real click AND typing a password before
  // anything happened; Bluetooth discovery has no equivalent natural
  // pause, and unlike Wi-Fi (you're picking a network you already
  // recognize as yours), nearby Bluetooth devices can easily be
  // someone else's phone/earbuds in a shared space -- a stray click
  // shouldn't be able to attempt pairing with those. First click on an
  // other-device row now just arms it (expands to show a real "Confirm
  // Pair" button); the actual pair command only fires on that second,
  // deliberate click.
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
    // Unknown device -- arms the row instead of pairing immediately
    // (see btPairArmedAddress above); confirmPairBtDevice below does
    // the actual pairing once armed. Clicking the row that's already
    // armed disarms it, same toggle-closed-on-second-click Wi-Fi's own
    // password prompt uses.
    root.btPairArmedAddress = (root.btPairArmedAddress === row.address) ? "" : row.address
  }

  function confirmPairBtDevice(row) {
    if (!row || !row.address) return
    root.btPairArmedAddress = ""
    root.btBusyAddress = row.address
    btBusyTimeout.restart()
    Quickshell.execDetached(["omarchy-bluetooth-device", "pair", row.address])
  }

  // Excludes the connected device -- per direct follow-up: disconnect
  // first, then forget, rather than offering a one-step forget that
  // disconnects as a side effect. Omarchy's own real panel does allow
  // forgetting a connected device directly (confirmed in their
  // Panel.qml), but that's not the flow wanted here.
  function forgetBtDevice(row) {
    if (!row || !row.address || row.connected) return
    Quickshell.execDetached(["omarchy-bluetooth-device", "forget", row.address])
  }

  // Display brightness -- per direct request ("can we do a display
  // one too, the omarchy one has it, looks pretty simple?"). Didn't
  // need to read Omarchy's own Panel.qml for this one -- ruixen-notch
  // already has this exact real mechanism proven and running in
  // production (Overlay.qml's own brightnessPercent/setBrightness),
  // ported directly rather than reinvented: `omarchy-monitor-state`
  // for reading (line 0 = brightness %, line 5 = focused monitor
  // name, confirmed by running it directly on this machine --
  // "56\n\nHDMI-A-1\n\n\nHDMI-A-1\n1\n[...]"), `omarchy-brightness-
  // display --no-osd --monitor <name> <percent>%` for writing.
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
        // An empty first line is NOT the same as a genuine "unavailable"
        // response -- real bug hit live ("the display page now has a
        // big gap between display header and the brightness card"),
        // root-caused with direct measurements: ruixen-notch runs this
        // exact same omarchy-monitor-state poll independently and
        // continuously (it has its own real brightnessPercent/
        // setBrightness mechanism this was ported from), so this
        // settings page's own poll can land at the same moment and
        // occasionally read back empty output from whatever race that
        // causes. Treating an empty read as "brightness genuinely
        // unavailable" flipped brightnessAvailable false for a frame,
        // collapsing the Brightness/Display Scale cards and showing
        // the fillHeight "No controllable display found" message in
        // their place -- which is exactly the gap that was reported.
        // A blank read now just gets ignored (keep the last known good
        // state) instead of being treated as authoritative.
        if (b === "") return
        root.brightnessAvailable = b !== "unavailable"
        if (root.brightnessAvailable) root.brightnessPercent = Math.max(0, Math.min(100, parseInt(b, 10)))
        root.focusedMonitor = String(lines[5] || "").trim()
        // Same real omarchy-monitor-state output already being parsed
        // above -- line 6 is the current Hyprland monitor scale
        // (confirmed directly: "...HDMI-A-1\n1\n[...]" on this
        // machine), read from the same process instead of polling a
        // second one just for this.
        var scaleLine = parseFloat(String(lines[6] || "").trim())
        if (isFinite(scaleLine)) root.displayScale = String(Math.round(scaleLine * 100) / 100)
      }
    }
  }

  Timer {
    interval: 5000
    running: root.opened
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
  // per direct follow-up ("can we no do text size and scale as well?
  // without them this setting kinda useless"). Real presets ported
  // from Omarchy's own scalePresets in Panel.qml -- skips their
  // resolution-aware availableScales() dedup (filters out presets that
  // render identically at the current resolution), a real refinement
  // left for later rather than guessed at.
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

  // Plugins -- checklist of this repo's own ruixen.* plugins (enable/
  // disable/remove) plus a repo-wide update button, per direct request
  // ("a plugins setting or like shell setting... checklist of plugsin
  // that user can turn on and off and refresh the shell... possibly
  // add a uninstall button too"). Deliberately curated to ids starting
  // "ruixen." rather than every installed plugin -- confirmed direct
  // agreement ("dont think we should show all user plugsin... keep it
  // to manage the shell stuff and our own curated made plugsin"). This
  // settings app has no business managing plugins it doesn't own.
  //
  // Real mechanism, confirmed by running each command directly rather
  // than guessed: `omarchy plugin list --json` returns id/name/kinds/
  // enabled/active/canDisable/firstParty/clonedFrom for every
  // discovered plugin; `omarchy plugin enable/disable <id>` and
  // `omarchy plugin remove <id> --yes` need no TTY (enable/disable
  // call omarchy-shell's setPluginEnabled directly, live, no restart
  // needed; remove's own script refuses to run without --yes when
  // there's no interactive terminal to confirm in, which is always the
  // case launched from here). `omarchy plugin update` also exists but
  // only handles plugins that are THEMSELVES individual git checkouts
  // (confirmed directly: it refused with "not a git checkout" against
  // a real installed ruixen.* plugin) -- these are cp -r'd from one
  // shared monorepo checkout instead, so this repo's own update.sh
  // (git pull + reinstall) is the real update path, not that command.
  property var pluginRows: []
  property string pluginBusyId: ""
  property string pluginUpdateStatus: ""
  property string pluginUpdateError: ""
  property string ruixenRepoPath: ""

  function parsePluginList(raw) {
    var rows = []
    try {
      var data = JSON.parse(raw || "[]")
      for (var i = 0; i < data.length; i++) {
        var p = data[i]
        if (String(p.id || "").indexOf("ruixen.") !== 0) continue
        rows.push(p)
      }
      rows.sort(function(a, b) { return a.name.localeCompare(b.name) })
    } catch (e) {}
    return rows
  }

  Process {
    id: pluginListProc
    command: ["omarchy", "plugin", "list", "--json"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.pluginRows = root.parsePluginList(text)
    }
  }

  function refreshPlugins() {
    if (!pluginListProc.running) pluginListProc.running = true
  }

  // Self-lockout guard the CLI itself doesn't provide -- ruixen.bar
  // reports canDisable: false (Omarchy's own protection, presumably
  // since losing the bar with no keybind back is a real dead end), but
  // ruixen.settings reports canDisable: true even though disabling or
  // removing the very plugin rendering this settings app would unload
  // it immediately, mid-session (confirmed: enable/disable apply live
  // via setPluginEnabled, no restart needed), with no way back in
  // short of a terminal. Blocked here on top of what the CLI allows.
  function pluginIsProtected(row) {
    return !row || row.id === "ruixen.settings" || !row.canDisable
  }

  Process {
    id: pluginActionProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      root.pluginBusyId = ""
      root.refreshPlugins()
    }
  }

  function togglePluginEnabled(row) {
    if (!row || !row.id || root.pluginIsProtected(row)) return
    root.pluginBusyId = row.id
    pluginActionProc.command = ["omarchy", "plugin", row.enabled ? "disable" : "enable", row.id]
    pluginActionProc.running = true
  }

  // Per-plugin remove was dropped entirely per direct follow-up ("why
  // not allow disable only and uninstall gets rid of everything as the
  // only option") -- disable already covers "don't want this running"
  // (instant, reversible), and actual file removal now lives
  // exclusively behind the danger-zone full uninstall's own typed
  // confirmation. A second, lighter-weight per-row way to delete files
  // was redundant with that, not a real safety improvement. See
  // uninstall.sh for the equivalent backup-cleanup reasoning that used
  // to live in a confirmRemovePlugin() here.

  // Repo path -- install.sh now writes its own checkout location to
  // this state file on every install/update run (added alongside this
  // feature, since nothing previously recorded it anywhere machine-
  // readable). Read fresh via bash so a missing file just yields an
  // empty string instead of a QML file-read error.
  Process {
    id: repoPathProc
    command: ["bash", "-c", "cat \"$HOME/.local/state/ruixen/repo-path\" 2>/dev/null"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.ruixenRepoPath = text.trim()
    }
  }

  Process {
    id: updateProc
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        // A successful run never gets here to report success -- update.sh
        // ends with `omarchy restart shell`, which tears down and
        // reloads this very plugin instance before this handler would
        // ever fire. Only a failure that happens BEFORE that point
        // (network down, git pull conflict, etc.) leaves this instance
        // alive long enough to actually show the error.
        if (updateProc.exitCode !== 0) {
          root.pluginUpdateStatus = "error"
          var errLines = text.trim().split("\n")
          root.pluginUpdateError = errLines.slice(Math.max(0, errLines.length - 3)).join("\n")
        }
      }
    }
  }

  function updateRuixenShell() {
    if (root.ruixenRepoPath === "" || root.pluginUpdateStatus === "updating") return
    root.pluginUpdateStatus = "updating"
    root.pluginUpdateError = ""
    // Single-quoted, with any literal single-quote in the path escaped
    // as '\'' -- the standard safe way to embed an arbitrary string as
    // one bash argument, rather than the nested-double-quote version
    // this first went out with (cd \"$(cat \\\"...\\\")\" -- readable
    // on paper but actually wrong: escaping the inner quotes with \\\"
    // stops them from acting as bash quoting at all inside $(...),
    // which already gets a fresh quoting context of its own).
    var safePath = root.ruixenRepoPath.replace(/'/g, "'\\''")
    updateProc.command = ["bash", "-c", "cd '" + safePath + "' && ./update.sh"]
    updateProc.running = true
  }

  // Full uninstall -- direct request, following a real Discord report
  // ("its currently hard to uninstall cleanly even with cli"). Runs
  // this repo's own new uninstall.sh, which reverses everything
  // install.sh did: switches back to the built-in Omarchy bar, removes
  // every ruixen.* plugin's files for real (omarchy-plugin-remove
  // itself only backs a cp -r'd plugin up to a hidden .{id}.bak.
  // <timestamp> folder rather than deleting it -- confirmed by reading
  // it directly -- so uninstall.sh explicitly deletes those backups
  // too afterward, per direct follow-up: "people want like a full
  // uninstall"), restores the real pre-install looknfeel.lua (or
  // Omarchy's own default if there was none), and restarts the shell.
  // See uninstall.sh's own comments for the full research behind each
  // step.
  //
  // Deliberately fired via Quickshell.execDetached, not a lifecycle-
  // bound Process like updateProc above -- the script's own last real
  // step disables/removes ruixen.settings itself, which would tear
  // down this very QML instance (and, plausibly, any Process objects
  // it owns) mid-script if that happened before the script finished.
  // execDetached exists specifically to survive exactly that, the same
  // reason Wi-Fi/Bluetooth's own actions already use it.
  readonly property string uninstallConfirmPhrase: "CONFIRM UNINSTALL"
  property string uninstallConfirmInput: ""

  function confirmFullUninstall() {
    if (root.ruixenRepoPath === "" || root.uninstallConfirmInput !== root.uninstallConfirmPhrase) return
    var safePath = root.ruixenRepoPath.replace(/'/g, "'\\''")
    Quickshell.execDetached(["bash", "-c", "cd '" + safePath + "' && ./uninstall.sh"])
  }

  PanelWindow {
    id: panel
    visible: root.opened
    anchors { top: true; left: true; right: true; bottom: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore

    WlrLayershell.namespace: "ruixen-settings"
    WlrLayershell.layer: WlrLayer.Overlay
    // Exclusive -- Escape needs to reach this surface to close it, same
    // as Emojis' own search-box overlay.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // Backdrop -- click anywhere outside the card to dismiss, same
    // pattern as any modal.
    Rectangle {
      anchors.fill: parent
      color: root.scrim

      MouseArea {
        anchors.fill: parent
        onClicked: root.dismiss()
      }
    }

    Rectangle {
      id: card
      // 480x360 -> 680x440 -- the square card had room for a header and
      // one placeholder message, not a sidebar beside real content.
      anchors.centerIn: parent
      width: 680
      height: 440
      radius: 16
      color: root.panelBackground
      focus: root.opened

      Keys.onEscapePressed: root.dismiss()

      // Swallow clicks so they don't fall through to the backdrop's own
      // dismiss handler.
      MouseArea {
        anchors.fill: parent
        onClicked: {}
      }

      ColumnLayout {
        anchors.fill: parent
        anchors.margins: 16
        spacing: 12

        // Sidebar (section switcher) + detail (selected section's own
        // content) -- per direct request ("2 panels, so theres a left
        // side for switching between setting options and then to the
        // right is where the settings and toggles are"). No divider
        // rectangle between them, matching ruixen.notch's own left-tab/
        // right-content split, which relies on spacing alone.
        RowLayout {
          Layout.fillWidth: true
          Layout.fillHeight: true
          spacing: 16

          ColumnLayout {
            Layout.preferredWidth: 150
            Layout.fillWidth: false
            Layout.fillHeight: true
            Layout.alignment: Qt.AlignTop
            spacing: 4

            // Search -- same plain Rectangle + TextInput + placeholder
            // Text primitive already used for WallpapersContent's own
            // search box and About's uninstall-confirm field, just
            // sized to fit this 150px column (28px tall / radius 8,
            // matching sectionRow's own row height and radius below,
            // instead of Wallpapers' bigger 40px/radius 12 box).
            Rectangle {
              // Layout.bottomMargin (on top of the ColumnLayout's own
              // 4px spacing) -- direct follow-up ("add a bit more gap
              // between search input and the first item"). Only this
              // one Rectangle needs it, not the ColumnLayout's own
              // uniform spacing, since every sectionRow below should
              // stay at the original tighter 4px from each other.
              Layout.fillWidth: true
              Layout.preferredHeight: 28
              Layout.bottomMargin: 8
              radius: 8
              color: Qt.rgba(1, 1, 1, 0.06)

              // Icon is its own fixed Text now, not glued onto the
              // placeholder string -- direct follow-up ("can i not
              // type over the maganify glass, so like the maga is
              // there and then you type where Search Settings is").
              // Previously the whole "  Search Settings" placeholder
              // (icon included) lived inside the TextInput and vanished
              // together the moment any text was typed, and typed text
              // itself started at the same left inset the icon sat at
              // -- so real input would render right under/over the
              // icon's own position. Splitting them means the icon
              // stays put regardless of typing state, and both the
              // TextInput and its own (icon-free) placeholder start
              // after the icon's own width instead of underneath it.
              // Doubles as a clear button once there's a query --
              // direct follow-up ("when a user starts typing in the
              // search, switch the magnify glass into a X so we can
              // click it to clear the input"). fa-xmark (U+F00D), same
              // fa-* glyph family as the search icon itself and every
              // sidebar row icon -- confirmed present in
              // JetBrainsMonoNerdFont's own cmap directly. MouseArea
              // only enabled once there's something to clear, so it
              // doesn't hint clickability (pointer cursor) when it's
              // just the plain search icon with nothing to do.
              Text {
                id: sidebarSearchIcon
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                text: sidebarSearchInput.text.length === 0 ? "" : ""
                // Red once it's a clear button, not muted like
                // the plain search glyph -- direct follow-up
                // ("maybe the X in red then so its more clear").
                // Same danger red as the uninstall button
                // (AboutContent.qml), the only other red accent
                // already established in this file.
                color: sidebarSearchInput.text.length === 0 ? root.muted : Qt.rgba(0.878, 0.322, 0.322, 1)
                font.family: root.fontFamily
                font.pixelSize: 11

                MouseArea {
                  anchors.fill: parent
                  anchors.margins: -4
                  enabled: sidebarSearchInput.text.length > 0
                  cursorShape: Qt.PointingHandCursor
                  onClicked: sidebarSearchInput.text = ""
                }
              }

              TextInput {
                id: sidebarSearchInput
                anchors.left: sidebarSearchIcon.right
                anchors.leftMargin: 6
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                verticalAlignment: TextInput.AlignVCenter
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: 11
                clip: true
                text: root.sidebarQuery
                onTextChanged: root.sidebarQuery = text

                Text {
                  anchors.verticalCenter: parent.verticalCenter
                  text: "Search Settings"
                  color: root.muted
                  font.family: root.fontFamily
                  font.pixelSize: 11
                  visible: sidebarSearchInput.text.length === 0
                }
              }
            }

            Repeater {
              model: root.filteredSections

              Rectangle {
                id: sectionRow
                required property var modelData
                readonly property bool selected: root.selectedSection === sectionRow.modelData.originalIndex

                Layout.fillWidth: true
                Layout.preferredHeight: 32
                radius: 8
                color: selected ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: 8
                  anchors.rightMargin: 8
                  spacing: 8

                  Text {
                    text: sectionRow.modelData.glyph
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    color: sectionRow.selected ? root.accent : root.muted
                  }

                  Text {
                    text: sectionRow.modelData.label
                    font.family: root.fontFamily
                    font.pixelSize: 12
                    font.weight: sectionRow.selected ? Font.DemiBold : Font.Normal
                    color: sectionRow.selected ? root.textColor : root.muted
                    Layout.fillWidth: true
                  }
                }

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.selectedSection = sectionRow.modelData.originalIndex
                }
              }
            }

            // Empty state -- rare with only 7 sections, but a typo'd
            // query would otherwise leave a blank sidebar with no clue
            // why nothing is showing. Centered in the leftover space
            // below the (now-empty) list, not just left-aligned right
            // under the search box -- direct follow-up ("can we make
            // it show up more center and middle"). Doubles as the
            // same leftover-space sink every other list here needs
            // (Layout.fillHeight, see the layout invariant), so there
            // isn't a separate fillHeight Item below it any more --
            // this Item's own remaining height IS what "No matches"
            // centers inside of.
            Item {
              Layout.fillWidth: true
              Layout.fillHeight: true

              Text {
                anchors.centerIn: parent
                visible: root.filteredSections.length === 0
                width: parent.width - 16
                horizontalAlignment: Text.AlignHCenter
                text: "No matches"
                wrapMode: Text.WordWrap
                font.family: root.fontFamily
                font.pixelSize: 11
                color: root.muted
              }
            }
          }

          Rectangle {
            id: detailPanel
            // Detail panel -- own faint card background, matching
            // ruixen.notch's own stat-tile fill (Qt.rgba(1, 1, 1, 0.05))
            // so it reads as a distinct surface from the sidebar instead
            // of bleeding into the same flat black.
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.05)

            // Whole detail panel scrolls as one unit now -- header
            // included, nothing sticky -- direct follow-up ("the top
            // fade sandwhcih between the header and body doesnt work,
            // should we just scroll with the header too, so put the
            // fade on top and everything in the page scroll, nothing
            // is sticky, cause technically the header is already shown
            // on the sidebar menu"). Previously headerPill was a fixed
            // sibling of a plain ColumnLayout, with each page owning
            // its own separate inner Flickable for whatever content of
            // its own didn't fit below that fixed header -- real
            // problem with that shape: the top fade had to be
            // positioned in the narrow, awkward gap between two
            // different scroll regions (the fixed header and whichever
            // page's own inner Flickable), which is exactly what
            // looked broken. One Flickable now wraps headerPill AND
            // the active page's content together, so both fades can
            // just anchor to this detailPanel Rectangle's own fixed
            // top/bottom edges -- see below.
            Flickable {
              id: detailFlickable
              anchors.fill: parent
              anchors.margins: 16
              contentWidth: width
              contentHeight: pageScrollContent.implicitHeight
              clip: true
              boundsBehavior: Flickable.StopAtBounds

            ColumnLayout {
              id: pageScrollContent
              width: parent.width
              spacing: 8

              // Page title -- per direct follow-up ("we dont need to
              // mention its a setting. remove the header and then just
              // lead with the settings options page name like Bluetooth
              // Wifi Audio inside the top of the right panel instead").
              // The removed header used to say "Settings"; this now
              // says which section you're actually looking at instead.
              // A RowLayout now, not a lone Text -- per direct follow-
              // up ("theres a toggle to enable or disable wifi, we need
              // the same toggle for the audio on the previous page
              // right alignned to the top on the Audio header"), the
              // Audio section's own master mute switch lives on this
              // same title row, right-aligned, mirroring where Wi-Fi's
              // radio toggle sits relative to its own header.
              Rectangle {
                id: headerPill
                // Whole header row, rounded bar rather than a true
                // stadium pill -- a full radius: height/2 pill and
                // flush alignment with the plain body rows below it
                // (Output, device rows) were fighting each other no
                // matter what inset got picked: a small inset that
                // lined up with the body crowded the pill's own sharp
                // corner curve, a bigger inset that cleared the curve
                // broke the alignment again (three direct follow-ups on
                // this exact tension: "starts too close to the pill
                // edge", then "the header is so much misalligned with
                // the body"). Same radius as this settings panel's own
                // detail-panel card (10, see the Rectangle at the top
                // of this file's ColumnLayout) instead of a full pill --
                // gentle enough that an 8px inset (matching every other
                // row in this file) both clears the corner AND stays
                // flush with the body.
                Layout.fillWidth: true
                Layout.preferredHeight: 32
                Layout.maximumHeight: 32
                radius: 10
                color: "#000000"

                RowLayout {
                  anchors.fill: parent
                  anchors.leftMargin: 8
                  anchors.rightMargin: 8
                  spacing: 8

                  Text {
                    id: titleText
                    // Wi-Fi's own title collapses with its connection
                    // name -- per direct follow-up ("can we collapse the
                    // Wifi header text with the Wifi connected name, so
                    // it says Wifi when nothing is connected, and then
                    // the Wifi network name when connected... seems like
                    // we can save a row this way"). Bluetooth does NOT
                    // get the same treatment -- per direct correction
                    // ("bluetooth setting doesnnt make sense, we should
                    // keep bluetooth text. its more like audio imo"):
                    // Wi-Fi has exactly one active connection, so
                    // collapsing the title to its name is unambiguous,
                    // but Bluetooth (like Audio's own output+input) can
                    // have several devices connected at once, so a
                    // single collapsed name would misrepresent the real
                    // state. Bluetooth keeps its plain label, same as
                    // Audio.
                    text: root.selectedSection === 2
                      ? (root.connectedWifiNetwork ? root.connectedWifiNetwork.ssid : "Wi-Fi")
                      : root.sections[root.selectedSection].label
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                    color: root.textColor
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                  }

                  // Master mute switch -- ported directly from Omarchy's
                  // own audio panel ("the hero switch is the whole
                  // panel's on/off, so it carries both channels at
                  // once... reads as on while anything is still
                  // audible"): anyAudible/toggleAllMuted below are the
                  // exact same real property/function shape as their own
                  // hasOutput/hasInput/anyAudible/toggleAllMuted.
                  Rectangle {
                    visible: root.selectedSection === 1
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 18
                    radius: 9
                    color: root.anyAudible ? root.accent : Qt.rgba(1, 1, 1, 0.15)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Rectangle {
                      width: 14
                      height: 14
                      radius: 7
                      color: "#ffffff"
                      anchors.verticalCenter: parent.verticalCenter
                      x: root.anyAudible ? parent.width - width - 2 : 2
                      Behavior on x { NumberAnimation { duration: 120 } }
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleAllMuted()
                    }
                  }


                  // QR code button -- summons Omarchy's own real
                  // omarchy.wifiqr panel plugin via the shared host
                  // summon() API (root.shell.summon(id, payloadJson),
                  // same generic function as our own dismiss()'s
                  // shell.hide(id), confirmed real at
                  // $OMARCHY_PATH/shell/shell.qml). Same real payload
                  // shape their own network panel uses -- iface+ssid
                  // when a wifi connection is known, empty object
                  // otherwise (the QR panel self-detects then).
                  Text {
                    visible: root.selectedSection === 2
                    Layout.alignment: Qt.AlignVCenter
                    text: ""
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    color: root.muted

                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -6
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.summonWifiQr()
                    }
                  }

                  // Speed test button -- summons Omarchy's own real
                  // omarchy.speedtest panel plugin, same summon() API
                  // and payload shape (connection name) as their own.
                  Text {
                    visible: root.selectedSection === 2
                    Layout.alignment: Qt.AlignVCenter
                    text: ""
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    color: root.muted

                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -6
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.summonSpeedTest()
                    }
                  }

                  // Wi-Fi radio toggle -- moved up here from the status
                  // row below, per direct follow-up ("the header Wifi
                  // doesnt have a toggle"), matching exactly where
                  // Audio's own master toggle sits on its header.
                  Rectangle {
                    visible: root.selectedSection === 2
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 18
                    radius: 9
                    color: Networking.wifiEnabled ? root.accent : Qt.rgba(1, 1, 1, 0.15)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Rectangle {
                      width: 14
                      height: 14
                      radius: 7
                      color: "#ffffff"
                      anchors.verticalCenter: parent.verticalCenter
                      x: Networking.wifiEnabled ? parent.width - width - 2 : 2
                      Behavior on x { NumberAnimation { duration: 120 } }
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleWifiRadio()
                    }
                  }

                  // Bluetooth radio toggle -- same header placement as
                  // Wi-Fi's own, established from the start this time.
                  // Real adapter power state (Bluetooth.defaultAdapter.
                  // enabled) doesn't persist on its own, per Omarchy's
                  // own comment ("that writes BlueZ's Powered, which
                  // nothing persists"), so toggling goes through the
                  // same real omarchy-bluetooth-power CLI their own
                  // toggleBluetooth() uses, not a direct property write.
                  Rectangle {
                    visible: root.selectedSection === 3
                    Layout.alignment: Qt.AlignVCenter
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 18
                    radius: 9
                    color: root.btEnabled ? root.accent : Qt.rgba(1, 1, 1, 0.15)

                    Behavior on color { ColorAnimation { duration: 120 } }

                    Rectangle {
                      width: 14
                      height: 14
                      radius: 7
                      color: "#ffffff"
                      anchors.verticalCenter: parent.verticalCenter
                      x: root.btEnabled ? parent.width - width - 2 : 2
                      Behavior on x { NumberAnimation { duration: 120 } }
                    }

                    MouseArea {
                      anchors.fill: parent
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.toggleBluetoothRadio()
                    }
                  }

                  // Update -- header-row action for the Plugins
                  // section, same slot Wi-Fi's own QR/speed-test icons
                  // and every section's radio toggle live in. Runs this
                  // repo's own update.sh (git pull + reinstall) -- see
                  // its own comment below for why that's the durable
                  // mechanism, not a stopgap ("its a good fallback to
                  // update anyways").
                  Text {
                    visible: root.selectedSection === 5
                    Layout.alignment: Qt.AlignVCenter
                    // Refresh glyph at rest, same one Omarchy's own
                    // SystemUpdate.qml bar widget uses (confirmed by
                    // reading it directly) -- tried swapping to a download
                    // glyph first per direct follow-up, but reverted:
                    // "the previous update icon was atleast better, i
                    // think thats what omarchy uses too". Also more
                    // accurate than a download icon would be: this button
                    // has no real "is a new version actually available"
                    // check, it unconditionally runs update.sh (git pull +
                    // reinstall) on click -- "re-sync now" is what refresh
                    // signals, "you have N updates" is what download would
                    // wrongly imply.
                    text: root.pluginUpdateStatus === "updating" ? "" : ""
                    font.family: root.fontFamily
                    font.pixelSize: 14
                    color: root.ruixenRepoPath === "" ? Qt.rgba(1, 1, 1, 0.25) : root.muted
                    // Same rotation-reset approach as Bluetooth's own
                    // connect/pair icons (see their comment) -- rotation
                    // is forced to 0 whenever not updating rather than
                    // bound straight to a running animation.
                    rotation: root.pluginUpdateStatus === "updating" ? spinAngle : 0
                    property real spinAngle: 0

                    NumberAnimation on spinAngle {
                      running: root.pluginUpdateStatus === "updating"
                      loops: Animation.Infinite
                      from: 0
                      to: 360
                      duration: 900
                    }

                    MouseArea {
                      anchors.fill: parent
                      anchors.margins: -6
                      enabled: root.ruixenRepoPath !== "" && root.pluginUpdateStatus !== "updating"
                      cursorShape: Qt.PointingHandCursor
                      onClicked: root.updateRuixenShell()
                    }
                  }
                }
              }


              GeneralContent {
                Layout.fillWidth: true
                visible: root.selectedSection === 0
                Layout.preferredHeight: visible ? -1 : 0
                Layout.maximumHeight: visible ? Infinity : 0
                settingsRoot: root
              }

              AudioContent {
                Layout.fillWidth: true
                visible: root.selectedSection === 1
                Layout.preferredHeight: visible ? -1 : 0
                Layout.maximumHeight: visible ? Infinity : 0
                settingsRoot: root
              }

              WifiContent {
                Layout.fillWidth: true
                visible: root.selectedSection === 2
                Layout.preferredHeight: visible ? -1 : 0
                Layout.maximumHeight: visible ? Infinity : 0
                settingsRoot: root
              }

              BluetoothContent {
                Layout.fillWidth: true
                visible: root.selectedSection === 3
                Layout.preferredHeight: visible ? -1 : 0
                Layout.maximumHeight: visible ? Infinity : 0
                settingsRoot: root
              }

              DisplayContent {
                Layout.fillWidth: true
                visible: root.selectedSection === 4
                Layout.preferredHeight: visible ? -1 : 0
                Layout.maximumHeight: visible ? Infinity : 0
                settingsRoot: root
              }

              PluginsContent {
                Layout.fillWidth: true
                visible: root.selectedSection === 5
                Layout.preferredHeight: visible ? -1 : 0
                Layout.maximumHeight: visible ? Infinity : 0
                settingsRoot: root
              }

              AboutContent {
                Layout.fillWidth: true
                visible: root.selectedSection === 6
                Layout.preferredHeight: visible ? -1 : 0
                Layout.maximumHeight: visible ? Infinity : 0
                settingsRoot: root
              }

            }
            }

            // Top/bottom fade -- direct follow-up chain: "theres an
            // effect i want on things that can scroll, its a top and
            // bottom fade... especially the top one", then, after a
            // real geometric problem trying this per-card on the
            // Plugins page ("on scroll i get a square edge then back
            // to round"), moved to this detail-panel Rectangle's own
            // fixed edges instead of any specific card's scrolling
            // content, then, after the header stayed a separate fixed
            // sibling above a per-page inner Flickable, "the top fade
            // sandwhcih between the header and body doesnt work" --
            // squeezed into the narrow gap between two different
            // scroll regions, which looked broken. headerPill is now
            // just the first item inside the one Flickable above
            // (nothing sticky, matching "everything in the page
            // scroll... the header is already shown on the sidebar
            // menu" -- the sidebar's own highlighted entry already
            // carries that context, so a scrolled-away header loses
            // nothing real), so both fades can now anchor to the exact
            // same simple thing: this Rectangle's own fixed top/bottom
            // edges, which never scroll or resize on their own --
            // radius: 10 on both always matches its real rounded
            // corners exactly, at any scroll position, on any page.
            //
            // Opacity now tracks real overflow instead of being always
            // on -- direct follow-up ("it still over the cards on
            // load... the audio that has no scroll also shows the
            // buttom fade so its wierd"): a static always-visible fade
            // was never actually representing "there's more content
            // this direction" -- it sat over the header at rest (no
            // scroll has happened yet, nothing above to hide) and sat
            // at the bottom of pages like Audio that fit the panel with
            // no overflow at all (nothing below to hide either). Sizing
            // tricks (reserve spacers, shrinking the gradient) could
            // never fix that because the actual bug was the fade not
            // knowing the scroll state, not its geometry. overflowAbove/
            // Below below mirror the standard "more content this way"
            // scroll-shadow pattern: hidden at each natural rest edge,
            // visible only once there's real content past it.
            // Opacity now ramps continuously over a short scroll
            // distance instead of snapping between 0/1 at a threshold
            // -- direct follow-up ("the fade looks jumpy when it comes
            // in maybe lessen the fade distance"): a Behavior-animated
            // binary switch has a fixed duration regardless of how
            // fast the actual scroll is, so a quick flick could easily
            // outrun (or look disconnected from) the 120ms opacity
            // animation chasing it -- that mismatch was the real
            // "jump". Binding opacity directly to how far past the
            // edge the content has scrolled removes the animation
            // entirely; it just tracks the drag 1:1, so it can never
            // be ahead of or behind the real scroll position. fadeRun
            // (16px) is the short distance that ramp happens over --
            // shorter than before per the same follow-up, so it eases
            // in fast without a visible pop.
            Rectangle {
              readonly property real fadeRun: 16
              readonly property real overflowAbove: detailFlickable.contentY
              anchors.top: parent.top
              anchors.left: parent.left
              anchors.right: parent.right
              height: 24
              radius: 10
              opacity: Math.max(0, Math.min(1, overflowAbove / fadeRun))
              gradient: Gradient {
                GradientStop { position: 0.0; color: "#000000" }
                GradientStop { position: 1.0; color: Qt.rgba(0, 0, 0, 0) }
              }
            }

            Rectangle {
              readonly property real fadeRun: 16
              readonly property real overflowBelow: detailFlickable.contentHeight - detailFlickable.height - detailFlickable.contentY
              anchors.bottom: parent.bottom
              anchors.left: parent.left
              anchors.right: parent.right
              height: 24
              radius: 10
              opacity: Math.max(0, Math.min(1, overflowBelow / fadeRun))
              gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.rgba(0, 0, 0, 0) }
                GradientStop { position: 1.0; color: "#000000" }
              }
            }
          }
        }
      }
    }
  }
}
