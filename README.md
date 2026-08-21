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

## License

MIT — see [LICENSE](LICENSE).
