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
    { id: "audio", label: "Audio", glyph: "" },
    { id: "wifi", label: "Wi-Fi", glyph: "" },
    { id: "bluetooth", label: "Bluetooth", glyph: "" },
    { id: "display", label: "Display", glyph: "" }
  ]
  property int selectedSection: 0

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
    root.opened = true
    if (payloadJson) {
      try {
        var payload = JSON.parse(payloadJson)
        if (payload && payload.section)
          root.selectedSection = root.sectionIndexFor(payload.section)
      } catch (e) {}
    }
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
        root.brightnessAvailable = b !== "unavailable" && b !== ""
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

            Repeater {
              model: root.sections

              Rectangle {
                id: sectionRow
                required property var modelData
                required property int index
                readonly property bool selected: root.selectedSection === index

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
                  onClicked: root.selectedSection = sectionRow.index
                }
              }
            }

            Item { Layout.fillHeight: true }
          }

          Rectangle {
            // Detail panel -- own faint card background, matching
            // ruixen.notch's own stat-tile fill (Qt.rgba(1, 1, 1, 0.05))
            // so it reads as a distinct surface from the sidebar instead
            // of bleeding into the same flat black.
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: 10
            color: Qt.rgba(1, 1, 1, 0.05)

            ColumnLayout {
              anchors.fill: parent
              anchors.margins: 16
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
                    text: root.selectedSection === 1
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
                    visible: root.selectedSection === 0
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
                    visible: root.selectedSection === 1
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
                    visible: root.selectedSection === 1
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
                    visible: root.selectedSection === 1
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
                    visible: root.selectedSection === 2
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
                }
              }


              // Audio -- real Pipewire volume + output/input device
              // pickers, per direct request ("should we start with the
              // audio then... volume + output device picker", then
              // "does it also shows the input? the omarchy has it
              // showing"). Wi-Fi/Bluetooth stay on the generic
              // placeholder below until their own real backends land.
              ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.selectedSection === 0
                spacing: 16

                Rectangle {
                  // Groups the whole Output/Input section (label +
                  // slider + device list) into one card, same real
                  // shape as the header pill (radius: 10, color:
                  // "#000000") -- direct follow-up ("still feels a bit
                  // off, can we try nesting few things like the black
                  // card too Output and Input group"). Height tracks
                  // the inner content's own implicitHeight (12px margin
                  // top/bottom) instead of a fixed number, so it still
                  // fits correctly as the device list grows/shrinks.
                  Layout.fillWidth: true
                  Layout.preferredHeight: outputCardContent.implicitHeight + 24
                  radius: 10
                  color: "#000000"

                  ColumnLayout {
                    id: outputCardContent
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Text {
                      text: "Output"
                      font.family: root.fontFamily
                      font.pixelSize: 11
                      font.weight: Font.DemiBold
                      color: root.muted
                    }

                    RowLayout {
                      Layout.fillWidth: true
                      spacing: 10

                      Text {
                        text: root.outputMuted ? "" : ""
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        color: root.textColor

                        MouseArea {
                          anchors.fill: parent
                          anchors.margins: -6
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.toggleOutputMute()
                        }
                      }

                      Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.1)

                        Rectangle {
                          width: parent.width * Math.max(0, Math.min(1, root.outputVolume))
                          height: parent.height
                          radius: 3
                          color: root.outputMuted ? root.muted : root.accent
                          Behavior on width { NumberAnimation { duration: 120 } }
                        }

                        MouseArea {
                          anchors.fill: parent
                          anchors.topMargin: -8
                          anchors.bottomMargin: -8
                          onPressed: mouse => root.setOutputVolume(mouse.x / width)
                          onPositionChanged: mouse => { if (pressed) root.setOutputVolume(mouse.x / width) }
                          // Scroll to adjust -- direct request ("allow
                          // the middle button to add or lower the
                          // volume... when hovering it too"). 5% per
                          // notch, same clamp the click/drag handlers
                          // above already apply.
                          onWheel: wheel => root.setOutputVolume(Math.max(0, Math.min(1, root.outputVolume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
                        }
                      }

                      Text {
                        text: Math.round(root.outputVolume * 100) + "%"
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        color: root.muted
                        Layout.preferredWidth: 32
                        horizontalAlignment: Text.AlignRight
                      }
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 4

                      Repeater {
                        model: root.outputDevices

                        Rectangle {
                          id: deviceRow
                          required property var modelData
                          readonly property bool isDefault: root.outputSink && deviceRow.modelData && root.outputSink.id === deviceRow.modelData.id

                          Layout.fillWidth: true
                          Layout.preferredHeight: 32
                          radius: 8
                          color: deviceRow.isDefault ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                          RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                              text: ""
                              font.family: root.fontFamily
                              font.pixelSize: 13
                              color: deviceRow.isDefault ? root.accent : root.muted
                            }

                            Text {
                              text: root.deviceLabel(deviceRow.modelData)
                              font.family: root.fontFamily
                              font.pixelSize: 12
                              font.weight: deviceRow.isDefault ? Font.DemiBold : Font.Normal
                              color: deviceRow.isDefault ? root.textColor : root.muted
                              elide: Text.ElideRight
                              Layout.fillWidth: true
                            }
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setDefaultOutput(deviceRow.modelData)
                          }
                        }
                      }
                    }
                  }
                }


                Rectangle {
                  // Groups the whole Output/Input section (label +
                  // slider + device list) into one card, same real
                  // shape as the header pill (radius: 10, color:
                  // "#000000") -- direct follow-up ("still feels a bit
                  // off, can we try nesting few things like the black
                  // card too Output and Input group"). Height tracks
                  // the inner content's own implicitHeight (12px margin
                  // top/bottom) instead of a fixed number, so it still
                  // fits correctly as the device list grows/shrinks.
                  Layout.fillWidth: true
                  Layout.preferredHeight: inputCardContent.implicitHeight + 24
                  radius: 10
                  color: "#000000"

                  ColumnLayout {
                    id: inputCardContent
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Text {
                      text: "Input"
                      font.family: root.fontFamily
                      font.pixelSize: 11
                      font.weight: Font.DemiBold
                      color: root.muted
                    }

                    RowLayout {
                      Layout.fillWidth: true
                      spacing: 10

                      Text {
                        text: root.inputMuted ? "" : ""
                        font.family: root.fontFamily
                        font.pixelSize: 15
                        color: root.textColor

                        MouseArea {
                          anchors.fill: parent
                          anchors.margins: -6
                          cursorShape: Qt.PointingHandCursor
                          onClicked: root.toggleInputMute()
                        }
                      }

                      Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 6
                        radius: 3
                        color: Qt.rgba(1, 1, 1, 0.1)

                        Rectangle {
                          width: parent.width * Math.max(0, Math.min(1, root.inputVolume))
                          height: parent.height
                          radius: 3
                          color: root.inputMuted ? root.muted : root.accent
                          Behavior on width { NumberAnimation { duration: 120 } }
                        }

                        MouseArea {
                          anchors.fill: parent
                          anchors.topMargin: -8
                          anchors.bottomMargin: -8
                          onPressed: mouse => root.setInputVolume(mouse.x / width)
                          onPositionChanged: mouse => { if (pressed) root.setInputVolume(mouse.x / width) }
                          // Scroll to adjust -- same real reasoning and
                          // step as Output's own slider above.
                          onWheel: wheel => root.setInputVolume(Math.max(0, Math.min(1, root.inputVolume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
                        }
                      }

                      Text {
                        text: Math.round(root.inputVolume * 100) + "%"
                        font.family: root.fontFamily
                        font.pixelSize: 12
                        color: root.muted
                        Layout.preferredWidth: 32
                        horizontalAlignment: Text.AlignRight
                      }
                    }

                    ColumnLayout {
                      Layout.fillWidth: true
                      spacing: 4

                      Repeater {
                        model: root.inputDevices

                        Rectangle {
                          id: inputRow
                          required property var modelData
                          readonly property bool isDefault: root.inputSource && inputRow.modelData && root.inputSource.id === inputRow.modelData.id

                          Layout.fillWidth: true
                          Layout.preferredHeight: 32
                          radius: 8
                          color: inputRow.isDefault ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                          RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 8

                            Text {
                              text: ""
                              font.family: root.fontFamily
                              font.pixelSize: 13
                              color: inputRow.isDefault ? root.accent : root.muted
                            }

                            Text {
                              text: root.deviceLabel(inputRow.modelData)
                              font.family: root.fontFamily
                              font.pixelSize: 12
                              font.weight: inputRow.isDefault ? Font.DemiBold : Font.Normal
                              color: inputRow.isDefault ? root.textColor : root.muted
                              elide: Text.ElideRight
                              Layout.fillWidth: true
                            }
                          }

                          MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.setDefaultInput(inputRow.modelData)
                          }
                        }
                      }
                    }
                  }
                }


                Item { Layout.fillHeight: true }
              }

              // Wi-Fi -- real Quickshell.Networking status + network
              // list + connect to open/known networks, per direct
              // request ("wifi next") and scope confirmation (status +
              // list + connect to open/known only, no new-password
              // flow yet).
              ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.selectedSection === 1
                spacing: 12

                // Status row removed -- its own job (icon + SSID/"Not
                // connected"/"Wi-Fi off") is now the collapsed header
                // title above (see the shared title Text's own
                // comment), saving a row per direct follow-up.


                // Real connection stats -- IP/Gateway/Ping -- per direct
                // follow-up ("what about the other stats, the omarchy
                // one has way better. it shows ping ip all that stuff i
                // dont think it shows the % wifi strenght too"). The
                // raw signal % above is gone -- confirmed directly that
                // Omarchy's own header treats signal as a 5-tier bar
                // icon (wifiIconFor() in their Model.js), never a
                // number, so dropping it here actually matches their
                // real behavior, not a guess.
                Flickable {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  visible: Networking.wifiEnabled
                  contentWidth: width
                  contentHeight: wifiCards.implicitHeight
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds

                  ColumnLayout {
                    id: wifiCards
                    width: parent.width
                    spacing: 12

                    // Known Networks -- direct follow-up ("do we need
                    // to group Known Network in its own black card and
                    // then Other Networks, we dont have a Known network
                    // group"): same card treatment (radius: 10, color:
                    // "#000000") as Output/Input and the header pill.
                    // No label text here (tried one, direct follow-up
                    // said drop it -- "Other Networks" below still has
                    // its own since that one's an interactive accordion
                    // toggle, not just a group boundary). Connection
                    // stats (IP/Gateway/Ping) live inside this card too,
                    // above the switcher list, since they describe
                    // whichever known network is currently active.
                    Rectangle {
                      Layout.fillWidth: true
                      Layout.preferredHeight: knownCardContent.implicitHeight + 24
                      radius: 10
                      color: "#000000"

                      ColumnLayout {
                        id: knownCardContent
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        GridLayout {
                          Layout.fillWidth: true
                          visible: root.connectedWifiNetwork !== null
                          columns: 2
                          columnSpacing: 12
                          rowSpacing: 2

                          Text {
                            text: "IP Address"
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            color: root.muted
                          }
                          Text {
                            Layout.fillWidth: true
                            text: root.netInfo.ip || "--"
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            color: root.textColor
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideLeft
                          }

                          Text {
                            text: "Gateway"
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            color: root.muted
                          }
                          Text {
                            Layout.fillWidth: true
                            text: root.netInfo.gateway || "--"
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            color: root.textColor
                            horizontalAlignment: Text.AlignRight
                            elide: Text.ElideLeft
                          }

                          Text {
                            text: "Ping"
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            color: root.muted
                          }
                          Text {
                            Layout.fillWidth: true
                            text: root.netInfo.internet_ping_ms ? Math.round(parseFloat(root.netInfo.internet_ping_ms)) + " ms" : "--"
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            color: root.textColor
                            horizontalAlignment: Text.AlignRight
                          }
                        }
                        ColumnLayout {
                          Layout.fillWidth: true
                          spacing: 4

                          Repeater {
                            // Known networks only -- per direct follow-up
                            // ("it showing all wifi spot available to join and
                            // its overflowing... were we gonna show just the
                            // one[s] we already connected to so they can
                            // switch"). Every scanned nearby AP was the actual
                            // overflow cause; this list is meant to be a
                            // switcher between networks this device already
                            // knows, not a full site-survey. Discovering/
                            // joining brand-new networks stays out of scope
                            // for this pass either way (no passphrase UI yet).
                            model: root.knownWifiRows

                            Rectangle {
                              id: wifiRow
                              required property var modelData

                              Layout.fillWidth: true
                              Layout.preferredHeight: 32
                              radius: 8
                              color: wifiRow.modelData.connected ? Qt.rgba(1, 1, 1, 0.08) : "transparent"

                              RowLayout {
                                // z above wifiRowMouse below -- a z set on an
                                // element nested INSIDE this RowLayout (like the
                                // forget icon further down) only ranks it against
                                // OTHER CHILDREN OF THIS ROWLAYOUT -- it has no
                                // effect on wifiRowMouse, which is a sibling of
                                // this RowLayout itself, not of anything inside
                                // it. z comparisons only happen between items
                                // that share the same immediate parent. Real
                                // report this caused: forget's own z:1 (still
                                // present below) looked like a fix but the click
                                // still landed on wifiRowMouse regardless -- this
                                // is the level that actually needed it.
                                z: 1
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                Text {
                                  text: ""
                                  font.family: root.fontFamily
                                  font.pixelSize: 13
                                  color: wifiRow.modelData.connected ? root.accent : root.muted
                                }

                                Text {
                                  text: wifiRow.modelData.ssid
                                  font.family: root.fontFamily
                                  font.pixelSize: 12
                                  font.weight: wifiRow.modelData.connected ? Font.DemiBold : Font.Normal
                                  color: wifiRow.modelData.connected ? root.textColor : root.muted
                                  elide: Text.ElideRight
                                  Layout.fillWidth: true
                                }

                                Text {
                                  visible: !root.isOpenNetwork(wifiRow.modelData.security)
                                  text: ""
                                  font.family: root.fontFamily
                                  font.pixelSize: 10
                                  color: root.muted
                                }

                                // Swaps to a "forget" icon on hover -- direct
                                // follow-up after a couple of test-password
                                // attempts left stray known networks with no way
                                // to remove them short of asking nmcli directly.
                                // Excludes the connected network, same rule
                                // Omarchy's own real panel uses (canForgetNetwork:
                                // known && !connected) -- forgetting the network
                                // you're actively on would disconnect you as a
                                // side effect of what reads like a cleanup click.
                                Text {
                                  visible: !(wifiRowMouse.containsMouse && !wifiRow.modelData.connected)
                                  text: wifiRow.modelData.signal + "%"
                                  font.family: root.fontFamily
                                  font.pixelSize: 11
                                  color: root.muted
                                  Layout.preferredWidth: 28
                                  horizontalAlignment: Text.AlignRight
                                }

                                Text {
                                  // The real fix for forget-clicks getting
                                  // swallowed by the row-wide click-to-connect
                                  // handler lives on the RowLayout itself above
                                  // (z: 1, see its comment) -- z only compares
                                  // siblings sharing the same immediate parent,
                                  // so a z set here would only rank this against
                                  // its OWN RowLayout siblings, never against
                                  // wifiRowMouse below (a sibling of the whole
                                  // RowLayout, not of this Text).
                                  visible: wifiRowMouse.containsMouse && !wifiRow.modelData.connected
                                  text: ""
                                  font.family: root.fontFamily
                                  font.pixelSize: 13
                                  color: forgetMouse.containsMouse ? "#e05252" : root.muted
                                  Layout.preferredWidth: 28
                                  horizontalAlignment: Text.AlignRight

                                  MouseArea {
                                    id: forgetMouse
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.forgetWifi(wifiRow.modelData)
                                  }
                                }
                              }

                              MouseArea {
                                id: wifiRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.connectToWifi(wifiRow.modelData)
                              }
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

                    // Other Networks -- same card treatment, own
                    // accordion header unchanged (see its own comment).
                    Rectangle {
                      Layout.fillWidth: true
                      visible: root.otherWifiRows.length > 0
                      Layout.preferredHeight: otherCardContent.implicitHeight + 24
                      radius: 10
                      color: "#000000"

                      ColumnLayout {
                        id: otherCardContent
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        // "Other Networks" -- accordion, open by default (see
                        // showOtherNetworks above). Clicking the header toggles
                        // it; chevron rotates to show state. Each row still
                        // expands in place for its own password field (see
                        // otherRow below) rather than a single shared prompt --
                        // that part is unrelated to this collapse/expand and
                        // stays exactly as it was.
                        Rectangle {
                          id: otherNetworksHeader
                          Layout.fillWidth: true
                          Layout.preferredHeight: 24
                          Layout.topMargin: 4
                          radius: 6
                          color: otherHeaderMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                          visible: root.otherWifiRows.length > 0

                          RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                              // "Available", not "Other" -- direct
                              // follow-up ("does it show this section
                              // when im not connected, should we call it
                              // available networks instead"): "Other"
                              // only reads sensibly relative to a
                              // network you're already on, which breaks
                              // down exactly when disconnected -- the
                              // one state this section matters most.
                              // Internal names (otherWifiRows,
                              // showOtherNetworks, etc.) stay as-is,
                              // this is just the visible label.
                              text: "Available Networks"
                              font.family: root.fontFamily
                              font.pixelSize: 11
                              color: root.muted
                              Layout.fillWidth: true
                            }

                            Text {
                              text: root.showOtherNetworks ? "" : ""
                              font.family: root.fontFamily
                              font.pixelSize: 9
                              color: root.muted
                            }
                          }

                          MouseArea {
                            id: otherHeaderMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showOtherNetworks = !root.showOtherNetworks
                          }
                        }
                        ColumnLayout {
                          // visible, not a conditionally-emptied
                          // Repeater model -- same fix as Bluetooth's
                          // Paired/Available Devices list wrappers (see
                          // their comment): a Rectangle's height bound
                          // to another Layout's implicitHeight didn't
                          // reliably shrink when the model driving it
                          // went from populated to [] via a Repeater.
                          Layout.fillWidth: true
                          visible: root.showOtherNetworks
                          spacing: 4

                          Repeater {
                            model: root.otherWifiRows

                            Rectangle {
                              id: otherRow
                              required property var modelData
                              readonly property bool expanded: root.wifiPasswordSsid === otherRow.modelData.ssid

                              Layout.fillWidth: true
                              Layout.preferredHeight: otherContent.implicitHeight + 16
                              radius: 8
                              color: otherRow.expanded ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                              clip: true
                              Behavior on Layout.preferredHeight { NumberAnimation { duration: 120 } }

                              ColumnLayout {
                                id: otherContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                  id: otherHeaderRow
                                  Layout.fillWidth: true
                                  Layout.preferredHeight: 16
                                  spacing: 8

                                  Text {
                                    text: ""
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                    color: root.muted
                                  }

                                  Text {
                                    text: otherRow.modelData.ssid
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    color: root.muted
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                  }

                                  Text {
                                    visible: !root.isOpenNetwork(otherRow.modelData.security)
                                    text: ""
                                    font.family: root.fontFamily
                                    font.pixelSize: 10
                                    color: root.muted
                                  }

                                  Text {
                                    text: otherRow.modelData.signal + "%"
                                    font.family: root.fontFamily
                                    font.pixelSize: 11
                                    color: root.muted
                                    Layout.preferredWidth: 28
                                    horizontalAlignment: Text.AlignRight
                                  }
                                }

                                // Inline passphrase field -- same plain-primitive
                                // search-box style ruixen.notch's own launcher/
                                // wallpaper search boxes use (Rectangle radius
                                // 12, Qt.rgba(1,1,1,0.06) background, TextInput +
                                // placeholder Text overlay), not a new visual
                                // language. Submit button is icon-only (arrow) on
                                // the right per direct request ("with enter on
                                // the right"), Enter key on the field does the
                                // same thing.
                                RowLayout {
                                  visible: otherRow.expanded
                                  Layout.fillWidth: true
                                  spacing: 6

                                  Rectangle {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 32
                                    radius: 10
                                    color: Qt.rgba(1, 1, 1, 0.06)

                                    TextInput {
                                      id: wifiPasswordInput
                                      anchors.fill: parent
                                      anchors.leftMargin: 10
                                      anchors.rightMargin: 10
                                      verticalAlignment: TextInput.AlignVCenter
                                      echoMode: TextInput.Password
                                      enabled: !root.wifiConnecting
                                      color: root.textColor
                                      font.family: root.fontFamily
                                      font.pixelSize: 12
                                      clip: true
                                      focus: otherRow.expanded
                                      text: root.wifiPasswordAttempt
                                      onTextChanged: root.wifiPasswordAttempt = text
                                      Keys.onPressed: function(event) {
                                        if (event.key === Qt.Key_Escape) {
                                          root.closeWifiPasswordPrompt()
                                          event.accepted = true
                                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                                          root.submitWifiPassword()
                                          event.accepted = true
                                        }
                                      }

                                      Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.wifiConnecting ? "Connecting…" : "Enter password..."
                                        color: root.muted
                                        font.family: root.fontFamily
                                        font.pixelSize: 12
                                        visible: wifiPasswordInput.text.length === 0
                                      }
                                    }
                                  }

                                  Rectangle {
                                    Layout.preferredWidth: 32
                                    Layout.preferredHeight: 32
                                    radius: 10
                                    color: connectMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)
                                    opacity: root.wifiConnecting ? 0.5 : 1

                                    Text {
                                      anchors.centerIn: parent
                                      text: ""
                                      font.family: root.fontFamily
                                      font.pixelSize: 13
                                      color: root.textColor
                                    }

                                    MouseArea {
                                      id: connectMouse
                                      anchors.fill: parent
                                      hoverEnabled: true
                                      enabled: !root.wifiConnecting
                                      cursorShape: Qt.PointingHandCursor
                                      onClicked: root.submitWifiPassword()
                                    }
                                  }
                                }

                                Text {
                                  visible: otherRow.expanded && root.wifiConnectError !== ""
                                  text: root.wifiConnectError
                                  font.family: root.fontFamily
                                  font.pixelSize: 10
                                  color: "#e05252"
                                  Layout.leftMargin: 4
                                }
                              }

                              // Stops at the header row's real bottom edge, not
                              // the password field below it once expanded -- an
                              // anchors.fill MouseArea here would sit on top of
                              // (and swallow clicks meant for) the TextInput/
                              // submit button once the row grows. Direct follow-
                              // up fix: this used to be anchors.top: parent.top +
                              // a fixed height approximating otherHeaderRow's
                              // size, but otherContent (the header's real parent)
                              // has its own 8px top margin the approximation
                              // didn't account for -- the hit region sat 8px
                              // above where the header actually rendered, so only
                              // the text's own top edge was clickable. Tried
                              // anchoring directly to otherHeaderRow.bottom next
                              // (cross-hierarchy anchor into a ColumnLayout
                              // child), but that made clicks stop registering
                              // entirely -- reverted to plain height arithmetic
                              // instead: otherContent's own top margin (8, see
                              // its anchors.margins above) plus the header's live
                              // height covers exactly the same region without
                              // relying on anchoring into a Layout's internals.
                              MouseArea {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: 8 + otherHeaderRow.height
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.connectToWifi(otherRow.modelData)
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }

                Text {
                  visible: !Networking.wifiEnabled
                  Layout.alignment: Qt.AlignHCenter
                  Layout.fillHeight: true
                  verticalAlignment: Text.AlignVCenter
                  text: "Turn on Wi-Fi to see nearby networks"
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  color: root.muted
                }
              }

              // Bluetooth -- known/paired devices with connect/disconnect/
              // forget, plus an "Other Devices" accordion for pairing a
              // brand-new one, same known/other split as Wi-Fi. Simpler
              // than Wi-Fi's own version turned out to be: no inline
              // password field needed at all -- see the pairing-
              // mechanism comment above (btAdapter block) for why.
              ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.selectedSection === 2
                spacing: 12

                Text {
                  visible: root.knownBtRows.length === 0 && root.otherBtRows.length === 0
                  Layout.alignment: Qt.AlignHCenter
                  Layout.fillHeight: true
                  verticalAlignment: Text.AlignVCenter
                  text: !root.btEnabled ? "Turn on Bluetooth to see nearby devices" : "No devices found"
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  color: root.muted
                }

                // Same scoped-Flickable safety net as Wi-Fi's own known-
                // networks list -- bounded height, internal scroll,
                // matching ruixen-notch's own storage-section pattern.
                Flickable {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  visible: root.knownBtRows.length > 0 || root.otherBtRows.length > 0
                  contentWidth: width
                  contentHeight: btCards.implicitHeight
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds

                  ColumnLayout {
                    id: btCards
                    width: parent.width
                    spacing: 12

                    // Paired Devices -- same card treatment as Wi-Fi's
                    // Known Networks (radius: 10, color: "#000000"),
                    // but keeping the label this time per direct
                    // follow-up ("i think we needed a Paired Device
                    // group") -- unlike Wi-Fi's card, there's no stats
                    // block above the list here to make the card's
                    // purpose obvious without one.
                    Rectangle {
                      Layout.fillWidth: true
                      Layout.preferredHeight: pairedCardContent.implicitHeight + 24
                      radius: 10
                      color: "#000000"

                      ColumnLayout {
                        id: pairedCardContent
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        // Accordion, same shape as Available Devices'
                        // own header below -- direct follow-up ("put
                        // paired device into an accordian too, so it
                        // lines up the text nicely with avalable
                        // device"): was a plain DemiBold Text before,
                        // which didn't line up with the other card's
                        // RowLayout-based header (fillWidth text +
                        // chevron, own hover tint). Open by default.
                        Rectangle {
                          id: pairedBtHeader
                          Layout.fillWidth: true
                          Layout.preferredHeight: 24
                          radius: 6
                          color: pairedBtHeaderMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"

                          RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                              text: "Paired Devices"
                              font.family: root.fontFamily
                              font.pixelSize: 11
                              color: root.muted
                              Layout.fillWidth: true
                            }

                            Text {
                              text: root.showPairedBtDevices ? "" : ""
                              font.family: root.fontFamily
                              font.pixelSize: 9
                              color: root.muted
                            }
                          }

                          MouseArea {
                            id: pairedBtHeaderMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showPairedBtDevices = !root.showPairedBtDevices
                          }
                        }

                        ColumnLayout {
                          // visible, not a conditionally-emptied Repeater
                          // model -- direct follow-up ("its not
                          // collapsing, its just hides the bluetooth
                          // stuff i have paired, the collapse and
                          // expand doesnt effect the card"): swapping
                          // the Repeater's own model to [] didn't shrink
                          // the card's own Layout.preferredHeight
                          // binding (pairedCardContent.implicitHeight)
                          // reliably. Items with visible: false are
                          // fully excluded from a Layout's own size
                          // calculation (documented Qt Quick Layouts
                          // behavior), so toggling visibility on this
                          // whole wrapper is the more deterministic way
                          // to actually collapse it.
                          Layout.fillWidth: true
                          visible: root.showPairedBtDevices
                          spacing: 4

                          Repeater {
                            model: root.knownBtRows

                            Rectangle {
                              id: btRow
                              required property var modelData
                              readonly property bool busy: root.btBusyAddress === btRow.modelData.address

                              Layout.fillWidth: true
                              Layout.preferredHeight: 32
                              radius: 8
                              color: btRow.modelData.connected ? Qt.rgba(1, 1, 1, 0.08)
                                : (btRowMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.04) : "transparent")

                              RowLayout {
                              // z above btRowMouse below -- same mistake as
                              // Wi-Fi's own row above: a z set on an element
                              // nested INSIDE this RowLayout (the forget icon
                              // further down) only ranks it against OTHER
                              // CHILDREN OF THIS ROWLAYOUT -- it has no effect
                              // on btRowMouse, which is a sibling of this
                              // RowLayout itself, not of anything inside it.
                              // Real report: "the trash button to forget
                              // doesnt do anything, its trying to connect" --
                              // the inner z:1 (still present below) never
                              // reached the comparison that mattered.
                              z: 1
                                anchors.fill: parent
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                spacing: 8

                                Text {
                                  text: ""
                                  font.family: root.fontFamily
                                  font.pixelSize: 13
                                  color: btRow.modelData.connected ? root.accent : root.muted
                                }

                                // Row-wide click still does connect/disconnect
                                // (see btRowMouse below) -- but the "no label
                                // at all, just click the row" version of this
                                // left users with nothing to actually notice:
                                // direct report was "i can only forget it?
                                // theres no reconnect" once the hover-only
                                // forget icon became the only visible thing on
                                // the row. Brought back a real status/hint
                                // label, just not sharing the forget icon's
                                // slot this time (see below) so nothing swaps
                                // away right as you aim a click.
                                Text {
                                  text: btRow.modelData.name
                                    + (!btRow.modelData.connected && !btRow.modelData.pairedFormally ? "  (unpaired)" : "")
                                  font.family: root.fontFamily
                                  font.pixelSize: 12
                                  font.weight: btRow.modelData.connected ? Font.DemiBold : Font.Normal
                                  color: btRow.modelData.connected ? root.textColor : root.muted
                                  elide: Text.ElideRight
                                  Layout.fillWidth: true
                                }

                                // Icon instead of text -- direct follow-up,
                                // matching the trash icon's own treatment
                                // rather than a text label. Busy state swaps
                                // to a spinner glyph with a running rotation
                                // instead of "Connecting..." text.
                                Text {
                                  visible: !btRow.modelData.connected
                                  text: btRow.busy ? "" : ""
                                  font.family: root.fontFamily
                                  font.pixelSize: 13
                                  color: root.muted
                                  // rotation is forced to 0 whenever not busy
                                  // (see spinAngle below) rather than bound
                                  // straight to a RotationAnimation -- that
                                  // animation never resets rotation when it
                                  // stops, so the plug glyph could land at
                                  // whatever crooked angle the spin was mid-
                                  // cycle at instead of upright. Real report:
                                  // "the plug spin is too much".
                                  rotation: btRow.busy ? spinAngle : 0
                                  property real spinAngle: 0

                                  NumberAnimation on spinAngle {
                                    running: btRow.busy
                                    loops: Animation.Infinite
                                    from: 0
                                    to: 360
                                    duration: 900
                                  }
                                }

                                // Red X -- passive "you can click the row to
                                // disconnect" indicator, not its own click
                                // target (the row itself handles that, same
                                // as Omarchy's own rowMouse.onClicked
                                // branching on isConnected).
                                Text {
                                  visible: btRow.modelData.connected
                                  text: ""
                                  font.family: root.fontFamily
                                  font.pixelSize: 12
                                  color: "#e05252"
                                }

                                // Forget -- its own dedicated slot, excluding
                                // the connected device per direct follow-up
                                // (disconnect first, then forget, rather than
                                // a one-step forget that disconnects as a
                                // side effect -- Omarchy's own panel allows
                                // the one-step version, this one deliberately
                                // doesn't). No longer hover-gated: it used to
                                // swap in over the "Connect" label on hover,
                                // meaning the exact thing you were aiming at
                                // disappeared right as the cursor arrived.
                                // Always shown now (dim by default, same as
                                // Wi-Fi's known-network trash icon), just
                                // brightens on its own hover.
                                Text {
                                  // The real fix for forget-clicks getting
                                  // swallowed by the row-wide click-to-connect
                                  // handler lives on the RowLayout itself above
                                  // (z: 1, see its comment) -- z only compares
                                  // siblings sharing the same immediate parent,
                                  // so a z set here would only rank this
                                  // against its OWN RowLayout siblings, never
                                  // against btRowMouse below (a sibling of the
                                  // whole RowLayout, not of this Text). Real
                                  // report this cost: "the trash button to
                                  // forget doesnt do anything, its trying to
                                  // connect" -- confirmed the CLI itself
                                  // (omarchy-bluetooth-device forget) works
                                  // fine when run directly, so this was purely
                                  // a UI hit-testing bug both times.
                                  visible: !btRow.modelData.connected
                                  text: ""
                                  font.family: root.fontFamily
                                  font.pixelSize: 13
                                  color: btForgetMouse.containsMouse ? "#e05252" : root.muted

                                  MouseArea {
                                    id: btForgetMouse
                                    anchors.fill: parent
                                    anchors.margins: -4
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.forgetBtDevice(btRow.modelData)
                                  }
                                }
                              }

                              MouseArea {
                                id: btRowMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleBtConnection(btRow.modelData)
                              }
                            }
                          }
                          Text {
                            visible: root.showPairedBtDevices && root.knownBtRows.length === 0
                            text: "No paired devices"
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            color: root.muted
                          }
                        }
                      }
                    }

                    // Available Devices -- same rename reasoning as
                    // Wi-Fi's own "Other Networks" -> "Available
                    // Networks": "Other" only reads sensibly relative
                    // to a device you're already paired with.
                    Rectangle {
                      Layout.fillWidth: true
                      visible: root.otherBtRows.length > 0
                      Layout.preferredHeight: availableCardContent.implicitHeight + 24
                      radius: 10
                      color: "#000000"

                      ColumnLayout {
                        id: availableCardContent
                        anchors.fill: parent
                        anchors.margins: 12
                        spacing: 12

                        // "Other Devices" -- accordion, open by default,
                        // same shape as Wi-Fi's own "Other Networks". No
                        // inline password field on click here (see the
                        // pairing-mechanism comment above) -- a tap just
                        // fires pair+trust+connect via
                        // omarchy-bluetooth-device directly.
                        Rectangle {
                          id: otherBtHeader
                          Layout.fillWidth: true
                          Layout.preferredHeight: 24
                          Layout.topMargin: 4
                          radius: 6
                          color: otherBtHeaderMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                          visible: root.otherBtRows.length > 0

                          RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 6

                            Text {
                              // "Available", not "Other" -- same rename
                              // reasoning as Wi-Fi's own "Available
                              // Networks" (see the card comment above).
                              text: "Available Devices"
                              font.family: root.fontFamily
                              font.pixelSize: 11
                              color: root.muted
                              Layout.fillWidth: true
                            }

                            Text {
                              text: root.showOtherBtDevices ? "" : ""
                              font.family: root.fontFamily
                              font.pixelSize: 9
                              color: root.muted
                            }
                          }

                          MouseArea {
                            id: otherBtHeaderMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.showOtherBtDevices = !root.showOtherBtDevices
                          }
                        }
                        ColumnLayout {
                          // visible, not a conditionally-emptied
                          // Repeater model -- same fix as Paired
                          // Devices' own list wrapper above, applied
                          // here too for consistency (see its comment).
                          Layout.fillWidth: true
                          visible: root.showOtherBtDevices
                          spacing: 4

                          Repeater {
                            model: root.otherBtRows

                            Rectangle {
                              id: otherBtRow
                              required property var modelData
                              readonly property bool armed: root.btPairArmedAddress === otherBtRow.modelData.address

                              Layout.fillWidth: true
                              Layout.preferredHeight: otherBtContent.implicitHeight + 16
                              radius: 8
                              color: otherBtRow.armed ? Qt.rgba(1, 1, 1, 0.06) : "transparent"
                              clip: true
                              Behavior on Layout.preferredHeight { NumberAnimation { duration: 120 } }

                              ColumnLayout {
                                id: otherBtContent
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                anchors.margins: 8
                                spacing: 6

                                RowLayout {
                                  id: otherBtHeaderRow
                                  Layout.fillWidth: true
                                  Layout.preferredHeight: 16
                                  spacing: 8

                                  Text {
                                    text: ""
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                    color: root.muted
                                  }

                                  Text {
                                    text: otherBtRow.modelData.name
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    color: root.muted
                                    elide: Text.ElideRight
                                    Layout.fillWidth: true
                                  }

                                  // Icon instead of text, same treatment as
                                  // the known-row connect icon above.
                                  Text {
                                    readonly property bool busy: root.btBusyAddress === otherBtRow.modelData.address
                                    // Link icon, not the same plug used for
                                    // Connect above -- direct follow-up:
                                    // "the reconnect and pair with the plug
                                    // looks weird, maybe another one for
                                    // pair so its not too many plugs".
                                    text: busy ? "" : ""
                                    font.family: root.fontFamily
                                    font.pixelSize: 13
                                    color: root.muted
                                    // Same rotation-reset fix as the known-row
                                    // connect icon above -- see its comment.
                                    rotation: busy ? spinAngle : 0
                                    property real spinAngle: 0

                                    NumberAnimation on spinAngle {
                                      running: parent.busy
                                      loops: Animation.Infinite
                                      from: 0
                                      to: 360
                                      duration: 900
                                    }
                                  }
                                }

                                // Real confirmation step -- direct report: a
                                // bare single click here used to pair
                                // immediately, no confirmation, and unlike
                                // Wi-Fi (picking a network you already
                                // recognize as yours) a nearby Bluetooth
                                // device can easily belong to someone else in
                                // a shared space. First click arms the row
                                // (see toggleBtConnection); only this explicit
                                // second click actually pairs.
                                Rectangle {
                                  visible: otherBtRow.armed
                                  Layout.fillWidth: true
                                  Layout.preferredHeight: 32
                                  radius: 10
                                  color: confirmPairMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.12) : Qt.rgba(1, 1, 1, 0.06)

                                  Text {
                                    anchors.centerIn: parent
                                    text: "Confirm Pair"
                                    font.family: root.fontFamily
                                    font.pixelSize: 12
                                    font.weight: Font.DemiBold
                                    color: root.textColor
                                  }

                                  MouseArea {
                                    id: confirmPairMouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.confirmPairBtDevice(otherBtRow.modelData)
                                  }
                                }
                              }

                              // Height arithmetic instead of anchoring into
                              // otherBtHeaderRow directly -- same fix (and the
                              // same reason) as Wi-Fi's own otherRow header
                              // MouseArea: a cross-hierarchy anchors.bottom
                              // binding into a ColumnLayout child stopped
                              // clicks from registering entirely when tried
                              // there.
                              MouseArea {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.top: parent.top
                                height: 8 + otherBtHeaderRow.height
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.toggleBtConnection(otherBtRow.modelData)
                              }
                            }
                          }
                        }
                      }
                    }
                  }
                }
              }

              // Display -- real brightness slider, ported directly
              // from ruixen-notch's own proven mechanism (see the
              // brightnessPercent/setBrightness block above) rather
              // than reading Omarchy's own Panel.qml, per direct
              // request ("can we do a display one too, the omarchy one
              // has it, looks pretty simple?").
              ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: root.selectedSection === 3
                spacing: 16

                Text {
                  visible: !root.brightnessAvailable
                  Layout.alignment: Qt.AlignHCenter
                  Layout.fillHeight: true
                  verticalAlignment: Text.AlignVCenter
                  text: "No controllable display found"
                  font.family: root.fontFamily
                  font.pixelSize: 12
                  color: root.muted
                }

                // Brightness -- own card, same treatment (radius:
                // 10, color: "#000000") as every other section's
                // groups (Output/Input, Known/Available Networks,
                // Paired/Available Devices).
                Rectangle {
                  visible: root.brightnessAvailable
                  Layout.fillWidth: true
                  Layout.preferredHeight: brightnessCardContent.implicitHeight + 24
                  radius: 10
                  color: "#000000"

                  ColumnLayout {
                    id: brightnessCardContent
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                      Text {
                        visible: root.brightnessAvailable
                        text: "Brightness"
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: root.muted
                      }
                      RowLayout {
                        visible: root.brightnessAvailable
                        Layout.fillWidth: true
                        spacing: 10

                        Text {
                          text: ""
                          font.family: root.fontFamily
                          font.pixelSize: 15
                          color: root.textColor
                        }

                        Rectangle {
                          Layout.fillWidth: true
                          Layout.preferredHeight: 6
                          radius: 3
                          color: Qt.rgba(1, 1, 1, 0.1)

                          Rectangle {
                            width: parent.width * Math.max(0, Math.min(1, root.brightnessPercent / 100))
                            height: parent.height
                            radius: 3
                            color: root.accent
                            Behavior on width { NumberAnimation { duration: 120 } }
                          }

                          MouseArea {
                            anchors.fill: parent
                            anchors.topMargin: -8
                            anchors.bottomMargin: -8
                            onPressed: mouse => root.setBrightness(100 * mouse.x / width)
                            onPositionChanged: mouse => { if (pressed) root.setBrightness(100 * mouse.x / width) }
                          }
                        }

                        Text {
                          text: Math.round(root.brightnessPercent) + "%"
                          font.family: root.fontFamily
                          font.pixelSize: 12
                          color: root.muted
                          Layout.preferredWidth: 32
                          horizontalAlignment: Text.AlignRight
                        }
                      }
                  }
                }

                // Display Scale -- own card, same treatment.
                Rectangle {
                  visible: root.brightnessAvailable
                  Layout.fillWidth: true
                  Layout.preferredHeight: scaleCardContent.implicitHeight + 24
                  radius: 10
                  color: "#000000"

                  ColumnLayout {
                    id: scaleCardContent
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                      Text {
                        visible: root.brightnessAvailable
                        text: "Display Scale"
                        font.family: root.fontFamily
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        color: root.muted
                      }
                      RowLayout {
                        visible: root.brightnessAvailable
                        Layout.fillWidth: true
                        spacing: 6

                        Repeater {
                          model: root.scalePresets

                          Rectangle {
                            id: scaleBtn
                            required property string modelData
                            readonly property bool isCurrent: root.displayScale === scaleBtn.modelData

                            Layout.fillWidth: true
                            Layout.preferredHeight: 28
                            radius: 6
                            color: scaleBtn.isCurrent ? Qt.rgba(1, 1, 1, 0.08) : "transparent"
                            border.width: 1
                            border.color: scaleBtn.isCurrent ? root.accent : Qt.rgba(1, 1, 1, 0.12)

                            Text {
                              anchors.centerIn: parent
                              text: scaleBtn.modelData + "x"
                              font.family: root.fontFamily
                              font.pixelSize: 11
                              font.weight: scaleBtn.isCurrent ? Font.DemiBold : Font.Normal
                              color: scaleBtn.isCurrent ? root.textColor : root.muted
                            }

                            MouseArea {
                              anchors.fill: parent
                              cursorShape: Qt.PointingHandCursor
                              onClicked: root.setDisplayScale(scaleBtn.modelData)
                            }
                          }
                        }
                      }
                  }
                }


                Item { Layout.fillHeight: true }
              }


            }
          }
        }
      }
    }
  }
}
