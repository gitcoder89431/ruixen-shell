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

## License

MIT — see [LICENSE](LICENSE).
