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

## Known limitation

Uses `WlrLayer.Overlay` (the topmost Wayland layer-shell layer), so it draws
on top of the bar and all windows rather than sitting behind them. Tried
`WlrLayer.Background` (got hidden behind the opaque wallpaper surface, since
two surfaces on the same layer have no defined stacking order) and
`WlrLayer.Bottom` (still didn't render visibly, cause not yet diagnosed) —
neither panned out, so this is parked at `Overlay` for now since it's the
one confirmed to actually render.

## Install (local dev)

```bash
cp manifest.json Overlay.qml ~/.config/omarchy/plugins/ruixen.frame-widget/
omarchy plugin validate ~/.config/omarchy/plugins/ruixen.frame-widget
omarchy plugin enable ruixen.frame-widget
omarchy restart shell
```

Plugin folders can't contain symlinks (the shell's loader rejects them), so
this has to be a real copy, not `ln -s`.
