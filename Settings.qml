import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import Quickshell.Networking
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
    { id: "bluetooth", label: "Bluetooth", glyph: "" }
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

  // Known networks only -- per direct follow-up ("it showing all wifi
  // spot available to join and its overflowing... were we gonna show
  // just the one[s] we already connected to so they can switch"). Every
  // scanned nearby AP was the real overflow cause; this list is a
  // switcher between networks this device already knows, not a
  // site-survey of everything in range.
  readonly property var knownWifiRows: root.wifiRows.filter(function(r) { return r.known })

  function isOpenNetwork(security) {
    return security === WifiSecurityType.Open
  }

  function networkForSsid(ssid) {
    var networks = root.wifiNetworkObjects
    for (var i = 0; i < networks.length; i++)
      if (networks[i] && networks[i].name === ssid) return networks[i]
    return null
  }

  // Real click-to-connect, scoped to known or open networks per direct
  // confirmation -- a protected network this device has never joined
  // before needs a passphrase this pass doesn't collect yet, so it's a
  // deliberate no-op rather than silently failing against
  // NetworkManager with no credentials.
  function connectToWifi(row) {
    if (!row || row.connected) return
    if (!row.known && !root.isOpenNetwork(row.security)) return
    var network = root.networkForSsid(row.ssid)
    if (network) network.connect()
  }

  function toggleWifiRadio() {
    Networking.wifiEnabled = !Networking.wifiEnabled
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

  onOpenedChanged: root.setScannerEnabled(true)
  onWifiDeviceChanged: root.setScannerEnabled(true)
  Component.onDestruction: {
    if (root.scannerDevice) root.scannerDevice.scannerEnabled = false
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
              Text {
                text: root.sections[root.selectedSection].label
                font.family: root.fontFamily
                font.pixelSize: 15
                font.weight: Font.DemiBold
                color: root.textColor
                Layout.fillWidth: true
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

                RowLayout {
                  Layout.fillWidth: true
                  spacing: 10

                  Text {
                    text: ""
                    font.family: root.fontFamily
                    font.pixelSize: 15
                    color: root.textColor
                  }

                  Text {
                    Layout.fillWidth: true
                    text: !Networking.wifiEnabled ? "Wi-Fi off"
                      : (root.connectedWifiNetwork ? root.connectedWifiNetwork.ssid : "Not connected")
                    font.family: root.fontFamily
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    color: root.textColor
                    elide: Text.ElideRight
                  }

                  // Toggle switch -- radio on/off, same real property
                  // (Networking.wifiEnabled) Omarchy's own toggleHint/
                  // click handler uses.
                  Rectangle {
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
                }

                // Real connection stats -- IP/Gateway/Ping -- per direct
                // follow-up ("what about the other stats, the omarchy
                // one has way better. it shows ping ip all that stuff i
                // dont think it shows the % wifi strenght too"). The
                // raw signal % above is gone -- confirmed directly that
                // Omarchy's own header treats signal as a 5-tier bar
                // icon (wifiIconFor() in their Model.js), never a
                // number, so dropping it here actually matches their
                // real behavior, not a guess.
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

                Rectangle { Layout.preferredHeight: 1; Layout.fillWidth: true; color: root.muted }

                // Scoped Flickable, same bounded-height + internal
                // scroll pattern ruixen-notch's own storage section
                // uses -- a plain ColumnLayout + Repeater grows
                // unbounded past the panel's own visible height with
                // no clipping, same root cause as that earlier bug.
                Flickable {
                  Layout.fillWidth: true
                  Layout.fillHeight: true
                  visible: Networking.wifiEnabled
                  contentWidth: width
                  contentHeight: wifiList.implicitHeight
                  clip: true
                  boundsBehavior: Flickable.StopAtBounds

                  ColumnLayout {
                    id: wifiList
                    width: parent.width
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

                        Text {
                          text: wifiRow.modelData.signal + "%"
                          font.family: root.fontFamily
                          font.pixelSize: 11
                          color: root.muted
                          Layout.preferredWidth: 28
                          horizontalAlignment: Text.AlignRight
                        }
                      }

                      MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.connectToWifi(wifiRow.modelData)
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


              // Placeholder -- Bluetooth's real backend lands in a
              // follow-up pass, same "coming soon" stub pattern
              // ruixen.notch's own Metrics/Wallpapers tabs started
              // from. Doesn't repeat the section name again (the title
              // above already says it) -- per the same duplicate-text
              // lesson from CPU/GPU's own "Usage X%" line earlier in
              // this project.
              Text {
                visible: root.selectedSection !== 0 && root.selectedSection !== 1
                Layout.alignment: Qt.AlignHCenter
                Layout.fillHeight: true
                verticalAlignment: Text.AlignVCenter
                text: "Settings coming soon"
                font.family: root.fontFamily
                font.pixelSize: 12
                color: root.muted
              }
            }
          }
        }
      }
    }
  }
}
