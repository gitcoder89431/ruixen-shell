# Ruixen Settings

A center-panel settings app for [Omarchy](https://omarchy.org/) — a real, standalone Omarchy shell plugin (`kind: overlay`), not a fork or a dependency of any other ruixen plugin. It shares the dark card look and radii used across [`ruixen-notch`](https://github.com/gitcoder89431/ruixen-notch)'s own stat tiles, but this repo works completely on its own: clone it, drop it in your plugins folder, and it runs — no `ruixen-bar` or `ruixen-notch` required.

This is also the first of what's meant to become a small family of "ruixen apps" (settings today, a launcher/AI chat/notepad later) that all share the same visual language as a lightweight, hand-copied component style rather than a real shared library — Omarchy's plugin loader rejects symlinks inside plugin folders, so there's no clean way to import a shared QML package across separate plugin repos. Each app vendors its own copy of whatever it reuses.

## What it does right now

Toggling it opens a centered, dark modal card (gear icon + "Settings" header, close button, click-outside-to-dismiss, Escape-to-dismiss) with a placeholder body. No real settings sections yet — this is the initial working scaffold, not a finished app. Real sections (appearance, notifications, about, etc.) are follow-up work, the same "coming soon" stub pattern `ruixen-notch`'s own Metrics/Wallpapers tabs started from before being filled in iteratively.

## How it works

Follows the exact contract Omarchy's own built-in overlay plugins use (confirmed by reading `$OMARCHY_PATH/shell/plugins/emojis/Emojis.qml` directly):

- The root `Item` exposes `shell` and `manifest` properties, injected by the host shell at load time.
- `open()` / `close()` / `toggle()` / `dismiss()` functions — `dismiss()` additionally calls `shell.hide(manifest.id)` so the host's own toggle bookkeeping stays in sync whether the panel was closed via the host's toggle command, a click outside, the close button, or Escape.
- An internal `PanelWindow` (`WlrLayershell.namespace: "ruixen-settings"`, `layer: WlrLayer.Overlay`, `keyboardFocus: WlrKeyboardFocus.Exclusive` so Escape reaches it) whose `visible` follows `root.opened`.

Colors come from `qs.Commons`' real `Color` singleton — `Color.menu.background`/`border`/`scrim` for the panel chrome (the same tokens Omarchy's own built-in modal overlays use, so it stays theme-correct instead of a hardcoded black that could clash with a light theme) and `Color.accent`/`Color.bar.text` (with the same luminance-safety-net fallback `ruixen-notch`/`ruixen-bar` already use) for the accent and text colors. `qs.Commons` is part of the Omarchy shell runtime itself, not a ruixen-specific dependency, so using it doesn't break this plugin's standalone-ness.

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

Then bind a key to it in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + COMMA", "Settings", "omarchy-shell shell toggle ruixen.settings")
```

Or toggle it manually to test:

```bash
omarchy-shell shell toggle ruixen.settings
```

## License

MIT — see [LICENSE](LICENSE).
