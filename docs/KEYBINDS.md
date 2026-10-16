# Keybind Recipes

The installer leaves Hyprland keybindings alone by default. If you want the
recommended keybinds and the keys are free, run:

```bash
./install.sh --with-launcher-keybind
```

Otherwise, add whichever of these you actually want to your own
`~/.config/hypr/bindings.lua`, then reload Hyprland to pick them up.

`omarchy menu keybindings --print` lists what's already bound, so you don't
clobber an existing key.

## Ruixen Launcher

Raycast/Spotlight-style command palette — searches Omarchy menu actions and
installed apps from one overlay:

```lua
o.bind("SUPER + R", "Ruixen Launcher", "omarchy-shell shell toggle ruixen.launcher")
```

## Ruixen Shelf

The drop pocket under the notch — drop files onto it, filter what's there,
clear it. Same overlay lifecycle as the Launcher, so `toggle` opens or
closes it and `summon` just makes sure it's open:

```lua
o.bind("SUPER + D", "Ruixen Shelf", "omarchy-shell shell toggle ruixen.shelf")
```

## Ruixen Settings

Settings lives as its own extension inside Ruixen Launcher, not a
separate overlay — open it with an `extension` payload on
`ruixen.launcher` itself:

```lua
o.bind("SUPER + SHIFT + R", "Ruixen Settings", [[omarchy-shell shell toggle ruixen.launcher '{"extension":"settings"}']])
```

Want a keybind that jumps straight to one settings category instead of
always opening on whichever one was open last? Add a `section` key
alongside `extension`, and use `summon` instead of `toggle` — this opens
on that category (or switches to it if the panel's already open on a
different one) rather than closing the panel if it happens to already be
open:

```lua
o.bind("SUPER + W", "Wi-Fi Settings", [[omarchy-shell shell summon ruixen.launcher '{"extension":"settings","section":"wifi"}']])
o.bind("SUPER + A", "Audio Settings", [[omarchy-shell shell summon ruixen.launcher '{"extension":"settings","section":"audio"}']])
o.bind("SUPER + B", "Bluetooth Settings", [[omarchy-shell shell summon ruixen.launcher '{"extension":"settings","section":"bluetooth"}']])
```

`SUPER + D` below is deliberately not one of these: `install.sh
--with-launcher-keybind` uses it for the Ruixen Shelf drop pocket, so
pick a different free key for Display if you want that shortcut.

```lua
o.bind("SUPER + SHIFT + D", "Display Settings", [[omarchy-shell shell summon ruixen.launcher '{"extension":"settings","section":"display"}']])
```

Valid `section` values: `general` (Profile), `bar`, `launcher` (File
Search), `audio`, `wifi`, `bluetooth`, `display`, `plugins`, `about`.

## Clipboard History

Clipboard History is another extension inside Ruixen Launcher (it reads
Omarchy's own clipboard history). Open it directly with:

```lua
o.bind("SUPER + SHIFT + V", "Clipboard History", [[omarchy-shell shell toggle ruixen.launcher '{"extension":"clipboard"}']])
```

Inside it, `Enter` copies the highlighted entry; `Alt+C` copies it, `Alt+O`
opens it, `Alt+P` copies an image's file path, `Alt+D` deletes it (press
twice to confirm), `Alt+R` reveals a masked possible secret, and `Alt+I`
pins or unpins it -- a pinned entry gets its own "Pinned" section at the
top of the list and keeps showing (and stays pasteable) even once
Omarchy's own 300-entry history cap would otherwise have dropped it.

## Cliamp Radio, Wallpaper Shuffle, Bjarneo Themes, Wallpapers Effects, Kanban Board

Same `extension` payload shape as Clipboard History above — each is its own
extension inside Ruixen Launcher:

```lua
o.bind("SUPER + SHIFT + U", "Cliamp Radio", [[omarchy-shell shell toggle ruixen.launcher '{"extension":"cliamp"}']])
o.bind("SUPER + SHIFT + J", "Wallpaper Shuffle", [[omarchy-shell shell toggle ruixen.launcher '{"extension":"wallpaper-shuffle"}']])
o.bind("SUPER + SHIFT + T", "Bjarneo Themes", [[omarchy-shell shell toggle ruixen.launcher '{"extension":"theme-browser"}']])
o.bind("SUPER + SHIFT + K", "Wallpapers Effects", [[omarchy-shell shell toggle ruixen.launcher '{"extension":"wallpapers"}']])
o.bind("SUPER + SHIFT + H", "Kanban Board", [[omarchy-shell shell toggle ruixen.launcher '{"extension":"kanban"}']])
```

Confirmed free via `omarchy menu keybindings --print` first -- the more
mnemonic SHIFT+C/W/E collide with stock Calendar/Omawrite/Email, which is
exactly the check this doc's own intro says to run before picking a key.
SHIFT+K (the mnemonic letter) was already spent on Wallpapers Effects, so
Kanban Board gets SHIFT+H instead -- just confirmed free, no mnemonic tie
to the name.

The label (the quoted string in the middle) has to be exactly this —
Ruixen Launcher's own landing row for each extension looks up a keybind
hint to show next to it by that same label text, same mechanism the
"Ruixen Settings" binding above already relies on. No binding yet (or a
label that doesn't match) just means no hint shows — it doesn't stop the
extension working.

## Shelf (drop pocket)

`ruixen.shelf` is its own overlay plugin with its own IPC target. Toggle its
window with the host's shell command or the plugin's own target — either
works:

```lua
o.bind("SUPER + SHIFT + S", "Ruixen shelf", "omarchy-shell ruixen.shelf toggle")
-- equivalent: "omarchy-shell shell toggle ruixen.shelf"
```

You don't need the window open to drop onto it: drag local files over the
collapsed notch and drop to add them.

## Notch dashboard and app launcher

Both live on `ruixen.notch`'s own IPC target directly — a different shape
from the `shell summon`/`toggle` convention above (see
[`docs/CONTROL.md`](CONTROL.md) for why these are two distinct mechanisms):

```lua
o.bind("SUPER + N", "Notch dashboard", "omarchy-shell ruixen.notch toggleDashboard")
o.bind("SUPER + L", "App launcher", "omarchy-shell ruixen.notch toggleLauncher")
```

`toggleDashboard`/`openDashboard` open on whichever tab (Widgets/
Wallpapers/Metrics/Kanban) was last selected. Want a keybind that jumps
straight to one tab instead — e.g. to check the Kanban board? Use
`openDashboardTab` with the tab name instead:

```lua
o.bind("SUPER + K", "Kanban board", "omarchy-shell ruixen.notch openDashboardTab kanban")
```

Valid tab names: `widgets`, `wallpapers`, `metrics`, `kanban`. Unlike
Settings' `summon` above, this is its own dedicated function taking a
plain string, not a JSON payload on `openDashboard` itself — Quickshell's
IpcHandler enforces exact argument count against a function's declared
signature, so a payload bolted on as an "optional" second argument would
have broken every existing zero-arg `openDashboard` call instead of
actually being optional.

`openDashboard`/`closeDashboard` and `openLauncher`/`closeLauncher` also
exist, if you'd rather have separate open/close keys instead of one toggle.

The Wallpapers tab has its own toggle, same shape as `toggleDashboard` —
a closed notch opens straight onto the tab, an open one just closes. This
is the keybind the installer's `--with-launcher-keybind` recommends (as
SUPER+CTRL+SPACE — note stock Omarchy binds that key to its background
switcher, so the installer will point at the collision instead of
stealing the key; unbind it first and add the bind yourself):

```lua
hl.unbind("SUPER + CTRL + SPACE") -- previously: Background switcher
o.bind("SUPER + CTRL + SPACE", "Ruixen wallpapers", "omarchy-shell ruixen.notch toggleWallpapers")
```

That tab is also the notch's theme switcher: a WALLPAPER/THEME sliding
tab to the right of its search box, where the theme half lists every
installed Omarchy theme and clicking one runs the real
`omarchy-theme-set`.
