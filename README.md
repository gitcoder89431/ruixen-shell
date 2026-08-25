# Ruixen Settings

A center-panel settings app for [Omarchy](https://omarchy.org/) — a real, standalone Omarchy shell plugin (`kind: overlay`), not a fork or a dependency of any other ruixen plugin. It shares the dark card look and radii used across [`ruixen-notch`](https://github.com/gitcoder89431/ruixen-notch)'s own stat tiles, but this repo works completely on its own: clone it, drop it in your plugins folder, and it runs — no `ruixen-bar` or `ruixen-notch` required.

This is also the first of what's meant to become a small family of "ruixen apps" (settings today, a launcher/AI chat/notepad later) that all share the same visual language as a lightweight, hand-copied component style rather than a real shared library — Omarchy's plugin loader rejects symlinks inside plugin folders, so there's no clean way to import a shared QML package across separate plugin repos. Each app vendors its own copy of whatever it reuses.

## What it does right now

Toggling it opens a centered 680x440 dark modal card (gear icon + "Settings" header, close button, click-outside-to-dismiss, Escape-to-dismiss) with two panels inside: a left sidebar for switching between setting sections, and a right detail panel showing whichever section is selected. No real settings content yet — sections currently just show a "coming soon" placeholder, the same stub pattern `ruixen-notch`'s own Metrics/Wallpapers tabs started from before being filled in iteratively. The sidebar/detail *navigation* itself is real, not decorative — clicking a section actually switches `selectedSection` and the detail panel's own label.

## How it works

Follows the exact contract Omarchy's own built-in overlay plugins use (confirmed by reading `$OMARCHY_PATH/shell/plugins/emojis/Emojis.qml` directly):

- The root `Item` exposes `shell` and `manifest` properties, injected by the host shell at load time.
- `open()` / `close()` / `toggle()` / `dismiss()` functions — `dismiss()` additionally calls `shell.hide(manifest.id)` so the host's own toggle bookkeeping stays in sync whether the panel was closed via the host's toggle command, a click outside, the close button, or Escape.
- An internal `PanelWindow` (`WlrLayershell.namespace: "ruixen-settings"`, `layer: WlrLayer.Overlay`, `keyboardFocus: WlrKeyboardFocus.Exclusive` so Escape reaches it) whose `visible` follows `root.opened`.

The card's own background is a hardcoded `#000000` — matching `ruixen-notch`/`ruixen-bar`'s own established OLED-black convention (see `Overlay.qml`'s `notchColor` / `Bar.qml`'s `GroupPill` comment), not a theme-driven token, since that's this family's own signature look. Text/accent colors still come from `qs.Commons`' real `Color` singleton (`Color.accent`, `Color.bar.text` with the same luminance-safety-net fallback `ruixen-notch`/`ruixen-bar` already use) so they stay theme-correct, and the backdrop scrim (`Color.menu.scrim`) is real theme data too — only the card's own fill is hardcoded. `qs.Commons` is part of the Omarchy shell runtime itself, not a ruixen-specific dependency, so using it doesn't break this plugin's standalone-ness.

Sections are a plain `readonly property var sections` array of `{ id, label, glyph }`, rendered via a `Repeater` in the sidebar and driving `property int selectedSection`. Same left-nav/right-content shape `ruixen-notch`'s own dashboard already uses (a tab-button column + the active tab's own content) — reused here as this repo's own version of that pattern, not copied code (see the top-level "no shared library across plugin repos" note above).

## Installation

```bash
git clone https://github.com/gitcoder89431/ruixen-settings ~/.config/omarchy/plugins/ruixen.settings
```

Enable it by adding an entry to the `plugins` array in `~/.config/omarchy/shell.json` (hot-reloads on save, no restart needed):

```json
{
  "plugins": [
    { "id": "ruixen.settings" }
  ]
}
```

(`shell.json` itself isn't tracked in any dotfiles repo — Omarchy
rewrites it constantly, theme changes and `omarchy bar` commands both
write through it — so it's live state on the machine, not a static
dotfile. This README is the reproducible record of what to add.)

Also add a `ruixen.settingsbutton` bar-widget entry (from the
[`ruixen-tray-widgets`](https://github.com/gitcoder89431/ruixen-tray-widgets)
repo) to `bar.layout.left` if you want a one-click toggle on the bar
instead of only a keybind — see that repo's own README.

Then bind a key to it in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + COMMA", "Settings", "omarchy-shell shell toggle ruixen.settings")
```

Or toggle it manually to test:

```bash
omarchy-shell shell toggle ruixen.settings
```

## Sidebar + detail panel, OLED black background

Direct follow-up right after the initial scaffold: "can we make it match our other plug in with the oled black bg as well and then 2 panels, so theres a left side for switching between setting options and then to the right is where the settings and toggles are. so like a sidebar for the settings and then details to the right of it. i feel like thats a highly reusable design."

Two changes: `panelBackground` switched from `Color.menu.background` (real theme data, but the wrong real data — that token is meant for Omarchy's own built-in menus) to a hardcoded `#000000`, matching `ruixen-notch`/`ruixen-bar`'s own established convention. The card also grew from 480x360 to 680x440 to fit a sidebar beside real content instead of just a header and one centered message, and gained the sidebar/detail split described above.

**Verified**: brace-balance check clean, glyph codepoints (`fa-sliders` U+F1DE, `fa-palette` U+EFCC, `fa-info` U+F129) confirmed against the font's own cmap, not guessed. Hit a real hot-reload gap during testing — `omarchy-shell shell rescanPlugins` and even a `touch`-forced reload event didn't actually re-render the already-open `PanelWindow` instance (old 480x360 layout kept showing after both), only a full `omarchy restart shell` picked up the new file. Section-switching itself verified as real (not just laid out) by temporarily hardcoding `selectedSection: 1`, restarting, and screenshotting — sidebar highlight and detail label both tracked the hardcoded value correctly before being reverted.

## Detail panel collapsed to zero width -- real fillWidth bug

Direct report right after the sidebar/detail redesign: "the panel on the right that says general settings comming soon etc is off to the right of the menu. is it cause its empty now?" -- the "coming soon" text was rendering past the card's own right edge instead of centered in the detail panel.

Root cause: the exact same `ColumnLayout`/`RowLayout` default-`fillWidth` quirk `ruixen-notch` hit before (see that repo's own README) -- Qt's `Layout`-type items default their own `Layout.fillWidth` attached property to `true` even when unset, unlike a plain `Item`/`Rectangle` which defaults to `false`. The sidebar `ColumnLayout` had `Layout.preferredWidth: 150` set but no explicit `Layout.fillWidth: false`, so it was still competing for extra distributable width by default, right alongside the detail `Rectangle`'s own `Layout.fillWidth: true` -- and lost that contest, collapsing the detail panel down to a sliver at the card's far-right edge instead of the ~480px it should have gotten.

Confirmed with real evidence, not guesswork: added a temporary `border.width: 3; border.color: "#ff0000"` to the detail `Rectangle` (same debug-border technique `ruixen-notch` used for its own version of this bug), then pixel-scanned the screenshot for red pixels via `magick`+Python instead of eyeballing it -- found a ~2px-wide red sliver at the card's right edge, confirming the Rectangle had collapsed to near-zero width rather than just being mispositioned. Isolated it further with a hardcoded `Layout.preferredWidth: 100` + bright green fill, which rendered correctly-sized but still pinned to the far right with a large empty gap before it -- proving the sidebar itself was the one eating the space, not a detail-panel-side bug. Fix: `Layout.fillWidth: false` added to the sidebar `ColumnLayout`.

**Verified**: brace-balance check clean, `omarchy plugin validate` clean, full shell restarts between each debug iteration (this specific overlay plugin doesn't reliably pick up changes from `rescanPlugins`/file-touch alone -- see the note above), screenshotted after removing the debug border -- detail panel now correctly fills the remaining space right after the sidebar, "General settings coming soon" properly centered within it.

## Real sections + deep-linkable via payload

Direct plan, shared right after the layout fix above: "for these settings, i think im gonna use it to control the audio, wifi, and bluetooth display, so then we dont need to use the omarchy one. on our top bar we can use the icon to open the settings we are making onto like the bluetooth page there."

`sections` renamed from the placeholder General/Appearance/About to Audio/Wi-Fi/Bluetooth (`fa-volume_up`, `fa-wifi`, `fa-bluetooth` -- confirmed against the font's own cmap). `open(payloadJson)` and `toggle(payloadJson)` now accept an optional JSON payload, matching the real host convention (`omarchy-shell --help` documents `omarchy-shell shell toggle omarchy.menu '{"menu":"root"}'` as an example) -- a bar icon can jump straight to a section:

```bash
omarchy-shell shell toggle ruixen.settings '{"section":"bluetooth"}'
```

`sectionIndexFor(id)` resolves the payload's `section` id to an array index; malformed/missing payloads are caught and just leave `selectedSection` at whatever it already was. The actual audio/Wi-Fi/Bluetooth *controls* (real PipeWire/NetworkManager/bluez wiring, not just navigation) are separate follow-up work -- this pass only makes the sections real and jump-to-able.

**Verified**: brace-balance check clean, glyph codepoints confirmed against the font's own cmap, `omarchy plugin validate` clean, live-restarted the shell, ran the exact real command above (`omarchy-shell shell toggle ruixen.settings '{"section":"bluetooth"}'`) and screenshotted -- panel opened directly on the Bluetooth section, sidebar highlight and detail label both correct, no errors in the Quickshell log.

## Header removed, page name leads the detail panel instead

Direct follow-up: "right now the header has like a settings text and a seperator, we dont need to mention its a setting. remove the header and then just lead with the settings options page name like Bluetooth Wifi Audio inside the top of the right panel instead, is that a better way to do it?" -- agreed and implemented. The header row (gear icon + "Settings" text + close X) and the separator line below it are gone entirely.

The detail panel's own top now shows the selected section's real name ("Audio"/"Wi-Fi"/"Bluetooth") as its title, replacing the old generic "X settings coming soon" single centered line -- title up top, placeholder body below it, no longer repeating the section name twice. Close button became a small `fa-xmark` in the card's own top-right corner instead of living in a full header row; Escape and click-outside-to-dismiss still work too, so losing the header didn't remove any actual functionality.

Immediate direct follow-up once this was live: "the x to close doesnt line up anymore lol, should go on the row as[...]" -- the corner X was anchored to the card's own top-right at a fixed 16px margin, while the new page title sits one level deeper (card's own 16px margin + the detail panel's own 16px inner margin = 32px), so they didn't sit on the same visual row. Fixed by giving the title `Text` an `id` (`sectionTitle`) and binding the close button's `anchors.verticalCenter` directly to `sectionTitle.verticalCenter`, instead of guessing a matching margin -- stays correct regardless of future spacing changes to either element.

**Verified**: brace-balance check clean, glyph codepoints confirmed, `omarchy plugin validate` clean, live-restarted the shell, tested with the real deep-link payload (`omarchy-shell shell toggle ruixen.settings '{"section":"bluetooth"}'`) and screenshotted a tight crop around the title row -- close button now sits precisely level with "Bluetooth"/"Audio"/"Wi-Fi" instead of floating above it.

## Corner close button removed entirely

The `verticalCenter`-bound fix above still wasn't enough: "the x to close doesnt line up anymore lol its still too high, i guess maybe easier to remove cause we have click away from panel to close already right." Correct -- the backdrop's own `MouseArea { onClicked: root.dismiss() }` and the card's `Keys.onEscapePressed: root.dismiss()` were never touched by any of the header/close-button changes, so removing the corner X loses zero functionality. Simpler than continuing to chase pixel alignment on a redundant affordance.

Removed the whole corner-X `Text`+`MouseArea` block, the now-stale `id: sectionTitle` (only existed for the removed button's `verticalCenter` binding) and its matching comment, and a stray double-blank-line left over from an earlier splice.

**Verified**: brace-balance check clean, `omarchy plugin validate` clean, live-restarted the shell, screenshotted -- panel now leads cleanly with just the section title ("Audio"/"Wi-Fi"/"Bluetooth"), no misaligned close button. Confirmed the backdrop's own dismiss handler is untouched (`grep` still finds it wired at the same line), so click-outside-to-dismiss and Escape both still work.

## Real Audio section: volume slider + output device picker

Direct request: "cool ok so should we start with the audio then. do we use the audio from omarchy as reference it seems to have what we need." Read Omarchy's own audio bar-widget directly (`$OMARCHY_PATH/shell/plugins/panels/audio/Panel.qml` + `Model.js`, 1,237 + 262 lines) to find the real API rather than guessing -- `Quickshell.Services.Pipewire` is a standard Quickshell module (not Omarchy-private), so it's fair game for this standalone plugin too. Scope for this first pass (confirmed): volume + output device picker, not a full per-app mixer.

Ported the exact real property paths and calls, not the file itself (theirs also covers per-app streams + MPRIS stream-name matching, well beyond this pass's scope, and pulls in `qs.Ui` widgets this plugin deliberately avoids):

- `Pipewire.defaultAudioSink.audio.volume` (0-1) / `.audio.muted` -- master output volume/mute
- `Pipewire.nodes.values` filtered to `n.isSink && !n.isStream` -- the real output device list
- `Pipewire.preferredDefaultAudioSink = node` -- switches the default output device
- `PwObjectTracker { objects: root.outputDevices }` -- required so tracked nodes' properties actually receive live updates (same real requirement their own widget has)
- `outputLabel(node)` ports Omarchy's own `nodeLabel()`/`friendlyDeviceLabel()` property-preference order verbatim (nickname/nick fields first, falling back to description/name, trimmed of the same noisy driver-name prefixes their real hardware strings carry) -- not reimplemented from scratch, copied from a working reference.
- Default-device comparison uses `root.outputSink.id === node.id`, the same real comparison their own `isActive` property uses.

UI: a custom drag-to-set volume bar (icon toggles mute, `Rectangle` track + fill, `MouseArea` computing volume from `mouse.x / width` on press and drag) since this plugin doesn't use `qs.Ui.Slider`, plus a device list styled like the sidebar's own selected-row treatment (accent-colored icon/text + faint background pill for whichever device is currently default).

**Verified**: brace-balance check clean (caught and fixed a real double-closed-brace from the line-splice edit before testing), glyph codepoints confirmed, `omarchy plugin validate` clean, live-restarted the shell, opened via the real deep-link payload, and screenshotted -- volume slider showed the actual live system volume (27%) and both real connected output devices ("USB Audio and HID", "CB242Y E" -- an actual connected monitor), not placeholder data. Drag-to-set/mute-click/device-switch-click themselves couldn't be directly simulated (same standing mouse-interaction limitation as the rest of this project), but every property path and function call is copied byte-for-byte from Omarchy's own shipped, working implementation rather than guessed.

## Input (microphone) section added

Direct follow-up right after Output shipped: "cool does it also shows the input? the omarchy has it showing." Mirrored the exact same real API shape from `Panel.qml`'s own `source`/`inputVolume`/`inputMuted`/`candidateSources`/`setDefaultSource`:

- `Pipewire.defaultAudioSource.audio.volume`/`.muted` -- input volume/mute
- `Pipewire.preferredDefaultAudioSource = node` -- switches the default input device
- A new `inputDevices` filter ported from Omarchy's real `isAudioSource()` (Model.js) rather than reusing the sink filter -- a source node can be a true audio source without `isSink` ever being set, so this checks `node.audio` presence and the node's own media-class string, same broader real check their widget uses. Also excludes the `"quickshell"` self-node, same as their own `candidateSources`.
- A second `PwObjectTracker { objects: root.inputDevices }`, same live-update requirement as the output list.

`outputLabel` renamed to `deviceLabel` and reused for both output and input rows -- Omarchy's own `nodeLabel()` is generic in the real source too, not sink-specific. Also picked up the two label fixes their `friendlyDeviceLabel()` has that the first pass missed: trimming a trailing `" Input"` suffix (only `" Output"` was ported before) and normalizing `"Microphones"` -> `"Microphone"`. Added small muted "Output"/"Input" sub-labels above each block now that there are two.

**Verified**: brace-balance check clean, glyph codepoints confirmed (`fa-microphone` U+F130, `fa-microphone_slash` U+F131), `omarchy plugin validate` clean, live-restarted the shell, screenshotted -- Input section shows the real live mic volume (100%) and the real connected input device ("USB Audio and HID"), not placeholder data, right below the unchanged Output section.

## Real Wi-Fi section: status + network list + connect

Direct request: "cool ok wifi next." Read Omarchy's own network bar-widget directly (`$OMARCHY_PATH/shell/plugins/panels/network/Panel.qml` + `Model.js`, 1,958 + 369 lines) before writing anything -- `Quickshell.Networking` is another standard Quickshell module, not Omarchy-private. Confirmed scope up front: status + network list + connect to open/known networks only, no passphrase-entry UI for brand-new protected networks yet (their own file has a real separate flow for that -- passphrase prompt, WPA-Enterprise `nmcli` scripting, retry-on-failure state -- genuinely out of scope for this pass, not skipped by accident).

Ported the real API shape, not the file:

- `Networking.wifiEnabled` (bool, settable) -- radio on/off, driving a real toggle switch
- `Networking.devices.values` filtered to `d.type === DeviceType.Wifi`, preferring an already-connected device -- same `findDevice()` logic as their own `wifiDevice`/`wiredDevice`
- `wifiDevice.networks.values` -- the real scanned network list
- **Real crash-avoidance pattern, ported verbatim, not simplified away**: Omarchy's own `wifiRow()` in `Model.js` explicitly extracts primitives only (`connected`, `known`, `ssid` from `network.name`, `signal` from `signalStrength`, `security`) into list-model rows, never the live `WifiNetwork` object -- their own comment explains why: NetworkManager scan churn can destroy a network object while a delegate built from it is still incubating, segfaulting Quickshell if a live QObject wrapper sits in list-model data. Connecting resolves back to the live object via `networkForSsid()` (matching on `.name`) at click time instead, same as their real `connectKnown()`.
- `network.connect()` -- called only for known networks or networks whose `security === WifiSecurityType.Open`; a protected+unknown network is a deliberate no-op this pass (no passphrase UI to collect one)
- **`wifiDevice.scannerEnabled`, ported directly** -- scanning isn't automatic; Omarchy's own `setScannerEnabled()`/`scannerDevice` tracks which device *this* panel instance turned scanning on for, releasing it when the panel closes or the device changes, since `scannerEnabled` lives on the shared device with no reference counting. Without this, the network list would just stay empty.

UI: real toggle switch (animated knob, bound to `Networking.wifiEnabled`), current connection status line (SSID + signal when connected, "Wi-Fi off" when disabled), and a network list styled like the audio device rows (lock icon for protected networks, signal %, click-to-connect).

**Verified**: brace-balance check clean, glyph codepoints confirmed (`fa-wifi` U+F1EB, `fa-lock` U+F023), `omarchy plugin validate` clean, live-restarted the shell, opened via the real deep-link payload, and screenshotted -- toggle correctly reflected the real Wi-Fi radio state, status line correctly showed "Not connected" (this machine wasn't actively joined to a network), and one real scanned network appeared ("STZ-P2", lock icon for its real protected security, real signal reading) -- not placeholder data.

## Wi-Fi list scoped to known networks, wrapped in a scoped Flickable

Direct report right after Wi-Fi shipped: "hmm but it showing all wifi spot available to join and its overflowing down the center panel. were we gonna show just the one[s] we already connected to so they can switch, and then the wifi stats section above it?" Correct on both counts -- the status row (SSID/signal/toggle) already served as the "stats section," but the list below was every scanned nearby AP, which is what actually overflowed the panel.

Added `readonly property var knownWifiRows: root.wifiRows.filter(function(r) { return r.known })` and pointed the list `Repeater`'s `model` at it instead of the full `wifiRows` -- the list is now a switcher between networks this device already knows, not a site-survey of everything in range. Also wrapped the list in a scoped `Flickable` (`clip: true`, `boundsBehavior: Flickable.StopAtBounds`, `contentHeight` bound to the inner `ColumnLayout`'s `implicitHeight`) as a defensive safety net -- same bounded-height + internal-scroll pattern `ruixen-notch`'s own storage section uses, since a plain `ColumnLayout`+`Repeater` grows unbounded past the panel's visible height with no clipping otherwise (same root cause as that earlier bug, ported the same fix).

**Verified**: brace-balance check clean, glyph codepoints confirmed intact after the restructure, `omarchy plugin validate` clean, live-restarted the shell, opened via the real deep-link payload, and screenshotted -- this machine had actually joined "STZ-P2" (90% signal) by this point, and the list now shows exactly that one known network instead of every scanned AP, matching the status row above it.

## Real connection stats: IP, Gateway, Ping -- dropped the raw signal %

Direct report: "damn what about the other stats, the omarchy one has way better. it shows ping ip all that stuff i dont think it shows the % wifi strenght too. idk bro i think they have a way better one." Confirmed both halves directly rather than guessing: Omarchy's own network panel builds an 8-field grid (Ping, Packet Loss, Receiving, Sending, Downloaded, Uploaded, IP Address, Gateway) from a real standalone CLI, `omarchy-network-status --verbose`; and their own header signal treatment is a 5-tier bar icon (`wifiIconFor()` in their `Model.js`), never a raw percentage -- so the number this plugin was showing wasn't just less impressive, it was showing something their real UI deliberately doesn't.

Before implementing, checked whether this duplicated something already built: `ruixen-notch`'s own Network stat tile already has real download/upload rate + lifetime totals, but sourced from `/proc/net/dev` + `ip route show default`, not `omarchy-network-status`. Scoped this pass to the three fields actually named (IP, Gateway, Ping) via the new real source, and dropped the raw `%` -- rate/totals reusing `ruixen-notch`'s own already-proven `/proc/net/dev` mechanism is a natural follow-up but wasn't re-confirmed as in-scope for this specific pass, so it's not included here.

`omarchy-network-status --verbose` is a real standalone Omarchy CLI binary, same class of dependency as `fastfetch`/`sensors`/`df` (which `ruixen-notch` already uses freely) -- not a dependency on `ruixen-bar`/`ruixen-notch`'s own internal services, so it doesn't break this plugin's standalone-ness. Confirmed the real output format by running it directly on this machine rather than guessing: tab-separated `key\tvalue` lines (`iface`, `ip`, `prefix`, `gateway`, `rx_bytes`, `tx_bytes`, `type`, `ssid`, `signal_dbm`, `freq`, `bitrate`, `router_ping_ms`, `internet_ping_ms`). Polled on a 2-second `Timer` gated to `root.opened` (no point polling ping/IP while the panel is closed), parsed with the same tab-split logic as their own `parseKeyValue()`.

New `GridLayout` under the status row shows IP Address, Gateway, and Ping (from `internet_ping_ms`, rounded), visible only when actually connected. The old raw `signal + "%"` `Text` is gone.

**Verified**: brace-balance check clean, glyph codepoints confirmed intact, `omarchy plugin validate` clean, live-restarted the shell, opened via the real deep-link payload, waited for a real poll cycle, and screenshotted -- IP Address (`192.168.1.153`), Gateway (`192.168.1.1`), and Ping (`7 ms`) all matched this machine's real live connection state, not placeholder data, and the raw `%` no longer appears in the status row.

## License

MIT — see [LICENSE](LICENSE).
