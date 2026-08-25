# Ruixen Shell

A connected bar, notch, and settings app for Omarchy — an OLED-black, unified
visual layer that runs as plugins inside the Omarchy shell you already use.

## What's included

- **`ruixen.bar`** — the top bar itself: workspaces, app launcher, media,
  weather, clock, and a settings shortcut, all in one connected pill layout.
- **`ruixen.notch`** — a center-notch dashboard with metrics, wallpapers, and
  storage, expanding from the bar.
- **`ruixen.frame-widget`** — the OLED-black screen frame that ties the bar
  and notch together visually.
- **`ruixen.settings`** — a standalone settings app (Audio, Wi-Fi, Bluetooth,
  Display) that can replace the default Omarchy settings panel entirely, or
  run on its own.
- **`ruixen.workspaces`** — workspace indicator widget.
- **Tray widgets** — `ruixen.tray`, `ruixen.stayawake`, `ruixen.dnd`,
  `ruixen.quickactions`, `ruixen.weather`, `ruixen.media`,
  `ruixen.applauncher`, `ruixen.settingsbutton`.

Every plugin shares the same OLED-black background, corner radii, and motion
language, so they read as one shell instead of a pile of separate widgets.

## Install

Ruixen Shell targets Omarchy `4.0.0-1`. Install from source:

```bash
git clone https://github.com/gitcoder89431/ruixen-shell.git
cd ruixen-shell
./install.sh
```

An AUR package is planned but not yet published — cloning from source is the
only install path right now.

The installer copies each plugin into `~/.config/omarchy/plugins/`, backs up
anything it would overwrite, applies a known-good `shell.json` layout (also
backed up if you already have one), and restarts the Omarchy shell.

After installing, add a keybind of your own for opening Ruixen Settings —
the installer deliberately doesn't touch your Hyprland config:

```lua
-- in your ~/.config/hypr/bindings.lua
bind("SUPER", "comma", "exec", "omarchy-shell shell toggle ruixen.settings")
```

## Disabling / going back to Omarchy defaults

Nothing here is a one-way door. Omarchy's own plugin commands handle
enable/disable and bar-switching live, with no file edits or shell restart
needed:

**Turn individual plugins off, keep everything installed:**

```bash
omarchy plugin disable ruixen.notch
omarchy plugin disable ruixen.frame-widget
omarchy plugin disable ruixen.settings
# same for any of the tray widgets: ruixen.tray, ruixen.weather, etc.

omarchy plugin enable ruixen.notch   # turns it back on
```

**Switch the bar back to stock Omarchy** (the bar is exclusive — only one
renders at a time):

```bash
omarchy plugin enable omarchy.bar
# and back again:
omarchy plugin enable ruixen.bar
```

**Fully remove a plugin's files:**

```bash
omarchy plugin remove ruixen.bar
```

Disable/enable and the bar switch only flip a live flag — nothing is
deleted, and there's no reason to reinstall just to try turning something
off. `remove` is the one destructive step, and it only touches the plugin
you name.

We ran this full off → on cycle on a live setup (disable the overlays,
switch the bar back to `omarchy.bar`, then re-enable everything) to confirm
it's clean: the stock Omarchy bar and panels render correctly with Ruixen
off, the shell process never restarts or drops, and the layout comes back
byte-for-byte once everything's re-enabled.

## Requirements

- Omarchy `4.0.0-1` (or a nearby build of the same shell generation)
- Quickshell, as provided by Omarchy

## License

Released under the [MIT License](LICENSE).
