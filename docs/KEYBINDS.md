# Keybind Recipes

None of these are set up for you — the installer deliberately doesn't touch
your Hyprland config. Add whichever of these you actually want to your own
`~/.config/hypr/bindings.lua`, then reload Hyprland to pick them up.

`omarchy menu keybindings --print` lists what's already bound, so you don't
clobber an existing key.

## Ruixen Settings

```lua
o.bind("SUPER + R", "Ruixen Settings", "omarchy-shell shell toggle ruixen.settings")
```

Want a keybind that jumps straight to one settings page instead of always
opening on whichever page was open last? Use `summon` with a `section`
payload instead of `toggle` — this opens Ruixen Settings on that page (or
switches to it if the panel's already open on a different one) rather than
closing the panel if it happens to already be open:

```lua
o.bind("SUPER + W", "Wi-Fi Settings", [[omarchy-shell shell summon ruixen.settings '{"section":"wifi"}']])
o.bind("SUPER + A", "Audio Settings", [[omarchy-shell shell summon ruixen.settings '{"section":"audio"}']])
o.bind("SUPER + B", "Bluetooth Settings", [[omarchy-shell shell summon ruixen.settings '{"section":"bluetooth"}']])
o.bind("SUPER + D", "Display Settings", [[omarchy-shell shell summon ruixen.settings '{"section":"display"}']])
```

Valid `section` values: `general` (Profile), `audio`, `wifi`, `bluetooth`,
`display`, `plugins`, `about`.

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
