# Ruixen Shell

A connected bar, notch, and settings app for Omarchy — an OLED-black, unified
visual layer that runs as plugins inside the Omarchy shell you already use.

![Ruixen Shell preview](preview.png)

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
anything it would overwrite, applies a known-good `shell.json` layout,
applies a matching Hyprland window look (rounded corners + blur, see
below — also backed up if you already have a `looknfeel.lua`), and restarts
the Omarchy shell.

After installing, add a keybind of your own for opening Ruixen Settings —
the installer deliberately doesn't touch your Hyprland config:

```lua
-- in your ~/.config/hypr/bindings.lua
bind("SUPER", "comma", "exec", "omarchy-shell shell toggle ruixen.settings")
```

## Disabling / going back to Omarchy defaults

Nothing here is a one-way door.

**Turn individual plugins off, keep everything installed:**

```bash
omarchy plugin disable ruixen.notch
omarchy plugin disable ruixen.frame-widget
omarchy plugin disable ruixen.settings
# same for any of the tray widgets: ruixen.tray, ruixen.weather, etc.

omarchy plugin enable ruixen.notch   # turns it back on
```

If a plugin stops updating after toggling it a few times, run
`omarchy restart shell` — a full restart always clears it.

**Switch the bar back to stock Omarchy:**

```bash
omarchy bar defaults
```

Use `omarchy bar defaults`, not `omarchy plugin enable omarchy.bar` — that
command only swaps the bar engine and leaves Ruixen's widget layout in
place, which looks broken rather than default. `omarchy bar defaults`
resets everything (id, layout, position, transparency) in one shot.

To bring Ruixen's own bar back afterward, just run `./install.sh` again.

**Fully remove a plugin's files:**

```bash
omarchy plugin remove ruixen.bar
```

This is the only step that deletes anything — disable/enable and the bar
reset just flip settings.

## Window look'n'feel (Hyprland)

Ruixen also rounds window corners (24px) and adds blur, to match the
frame/bar. Toggle it independently of the plugins above:

```bash
hyprland/ruixen-lookfeel.sh on      # rounded corners + blur, matches the frame
hyprland/ruixen-lookfeel.sh off     # stock Omarchy: square corners, no blur
hyprland/ruixen-lookfeel.sh status  # show which one is active
```

## Requirements

- Omarchy `4.0.0-1` (or a nearby build of the same shell generation)
- Quickshell, as provided by Omarchy

## License

Released under the [MIT License](LICENSE).
