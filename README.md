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

**Switch the bar back to stock Omarchy:**

```bash
omarchy bar defaults
```

`omarchy plugin enable omarchy.bar` looks like the obvious command here, but
it only swaps which bar *engine* renders — it leaves your saved widget
`layout` untouched, so you get Omarchy's bar trying to render Ruixen's widget
IDs, not a clean default. `omarchy bar defaults` is the real reset: it
replaces the whole bar config (id, layout, position, transparency) with
Omarchy's shipped defaults in one shot. We hit this ourselves — the first
version of this doc was wrong, and we caught it because a live toggle test
came back looking broken, not because we imagined the failure mode.

There's no single command to get back to Ruixen's own bar layout afterward
(swapping bar identity doesn't restore a custom layout any more than it did
going the other way) — reinstalling (`./install.sh`) is the straightforward
way back if you want it.

**Fully remove a plugin's files:**

```bash
omarchy plugin remove ruixen.bar
```

Disable/enable only flips a live flag — nothing is deleted, and there's no
reason to reinstall just to try turning something off. `remove` is the one
destructive step, and it only touches the plugin you name.

We ran this full off → on cycle on a live setup (disable the overlays,
`omarchy bar defaults` to reset the bar, then reinstall to bring Ruixen's
layout back) to confirm it's clean: the stock Omarchy bar and panels render
correctly with Ruixen off, the shell process never restarts or drops, and
`hyprctl` confirms every setting the toggle touches actually changes.

## Window look'n'feel (Hyprland)

Ruixen's frame and bar use a 24px corner radius, and `hyprland/looknfeel.ruixen.lua`
matches that in Hyprland itself (window rounding + blur) so windows read as
part of the same shell instead of clashing with it. This is a real Hyprland
`decoration` override, separate from the plugin toggles above — disabling
the shell plugins doesn't touch it.

A small script ships alongside it to swap between Ruixen's look and stock
Omarchy's (square corners, no blur):

```bash
hyprland/ruixen-lookfeel.sh on      # rounded corners + blur, matches the frame
hyprland/ruixen-lookfeel.sh off     # stock Omarchy: square corners, no blur
hyprland/ruixen-lookfeel.sh status  # show which variant is active
```

It works by symlinking `~/.config/hypr/looknfeel.lua` to whichever variant
file you pick and running `hyprctl reload` — no shell restart, and any
existing plain (non-symlinked) `looknfeel.lua` you already have gets backed
up rather than overwritten. Verified directly with `hyprctl getoption
decoration:rounding` / `decoration:blur:enabled` before and after each
toggle, not just by eye.

## Requirements

- Omarchy `4.0.0-1` (or a nearby build of the same shell generation)
- Quickshell, as provided by Omarchy

## License

Released under the [MIT License](LICENSE).
