# ruixen.frame-widget

A basic Omarchy shell plugin — a colored, rounded-corner border frame around
the whole screen edge.

## What it is

A `kind: overlay` plugin. The Canvas fills the screen with `frameColor`,
then punches a rounded-rect hole out of the middle (`destination-out`
compositing), leaving a colored border with rounded inner corners. Ported
from `REPOS/PLUGINS/quickshell-mocha-v2`'s `Frame.qml` (`FrameMaskCanvas`),
stripped of its notch/dock/theme-JSON machinery.

`"keepLoaded": true` in the manifest means it mounts once at shell startup
and stays up — no `summon`/`hide` calls needed, unlike a toggleable overlay
(emoji picker, clipboard, etc).

`mask: Region {}` (empty region) on the `PanelWindow` is required, not
optional — without it, this full-screen topmost-layer surface swallows
scroll/click input for everything underneath (broke terminal scrollback
system-wide once, before this was added). Same pattern the built-in bar/osd
plugins use for their own non-interactive areas.

## Color is intentionally hardcoded, not theme-linked

`frameColor` is a fixed `#000000` (OLED black) — a deliberate choice, not
an oversight. Unlike `ruixen.bar` (which uses `Color.bar.*` theme bindings
and re-colors automatically on `omarchy theme set`), this frame stays pure
black no matter what theme is active. That's fine on dark themes, but will
look wrong on light ones (`catppuccin-latte`, `flexoki-light`, `white`,
etc.) — known and accepted, not planned to change. If that tradeoff ever
flips, the fix is reading `accent`/`background` from the active theme's
`colors.toml` the same way the bar reads `Color.bar.*`.

## Known limitation

Uses `WlrLayer.Overlay` (the topmost Wayland layer-shell layer), so it draws
on top of the bar and all windows rather than sitting behind them. Tried
`WlrLayer.Background` (got hidden behind the opaque wallpaper surface, since
two surfaces on the same layer have no defined stacking order) and
`WlrLayer.Bottom` (still didn't render visibly, cause not yet diagnosed) —
neither panned out, so this is parked at `Overlay` for now since it's the
one confirmed to actually render.

## Companion setup (required for the full look)

This plugin only draws the border — for the intended cohesive look you also
need:

1. **[`ruixen.bar`](https://github.com/gitcoder89431/ruixen-bar)** — a bar
   that sits inset inside this frame's hole instead of flush against the
   screen edge. The stock built-in Omarchy bar doesn't support this (no
   margin/inset config), so this frame alone will visually clip across
   whatever bar you're using unless it's `ruixen.bar` or something insetting
   the same way.
2. **Rounded window corners matching this plugin's `cornerRadius` (24)** —
   set in Hyprland, not here (a Quickshell plugin can't reach into the
   compositor's own settings):
   ```lua
   -- ~/.config/hypr/looknfeel.lua
   hl.config({
     decoration = {
       rounding = 24,
     },
   })
   ```
   Without this, windows keep sharp 90° corners while the frame and bar are
   rounded — inconsistent, not broken, but not the intended look.

## Install (local dev)

```bash
cp manifest.json Overlay.qml ~/.config/omarchy/plugins/ruixen.frame-widget/
omarchy plugin validate ~/.config/omarchy/plugins/ruixen.frame-widget
omarchy plugin enable ruixen.frame-widget
omarchy restart shell
```

Plugin folders can't contain symlinks (the shell's loader rejects them), so
this has to be a real copy, not `ln -s`.
