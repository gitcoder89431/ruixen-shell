# ruixen.bar

A minimal from-scratch Omarchy bar — workspaces + clock, nothing else.
Designed to pair with `ruixen.frame-widget`: the frame draws one continuous
rounded-rect shell around the whole screen, and this bar sits inset inside
it as plain content (not a shape with its own corners).

## Why from-scratch, not cloned

`omarchy plugin clone omarchy.bar` produces a `Bar.qml` that declares
`required property` for `omarchyPath`, `barWidgetRegistry`, and `barConfig`.
Swapping to that clone via `omarchy bar use` crashed with "Required
property X was not initialized" — the shell injects these via a later
assignment (`target.x = ...`), not at creation time, which QML's `required`
keyword doesn't accept for a dynamically swapped-in bar. This bar uses
plain optional properties with defaults instead, which sidesteps it.

## Pairing with the frame

- `ruixen.frame-widget`: `thickness = 6`, `cornerRadius = 24`, draws the
  full rounded-rect border.
- This bar: inset by `frameThickness` (6px, matching the frame's border)
  on top/left/right via `PanelWindow.margins`, `barColor` deliberately
  *not* the frame's black (so it contrasts rather than blends in).

A larger inset (`frameThickness + frameCornerRadius`, clearing the
rounded-corner zone entirely) was tried first and looked like a floating
disconnected box — too much empty gap on either side. Settled on the
smaller thickness-only inset, which spans nearly the full width and only
slightly overlaps the very tip of the frame's rounded corners.

## Companion setup (required for the full look)

1. **[`ruixen.frame-widget`](https://github.com/gitcoder89431/ruixen-frame-widget)**
   — this bar is designed to sit inside its hole, not stand alone.
2. **Rounded window corners, matching `cornerRadius` (24)** — set in
   Hyprland, not a plugin concern:
   ```lua
   -- ~/.config/hypr/looknfeel.lua
   hl.config({
     decoration = {
       rounding = 24,
     },
   })
   ```

## Install (local dev)

```bash
cp manifest.json Bar.qml ~/.config/omarchy/plugins/ruixen.bar/
omarchy plugin validate ~/.config/omarchy/plugins/ruixen.bar
omarchy bar use ruixen.bar
omarchy restart shell
```

Plugin folders can't contain symlinks (the shell's loader rejects them), so
this has to be a real copy, not `ln -s`.
