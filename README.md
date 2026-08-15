# ruixen.bar

A patched clone of the built-in Omarchy bar — full stock functionality
(audio, bluetooth, network, tray, weather, system updates, workspaces,
indicators, etc.), styled to sit inside `ruixen.frame-widget`'s rounded-rect
shell instead of flush against the screen edge.

Started as a from-scratch minimal bar (workspaces + clock only) to prove
out the fix below; once that was confirmed, replaced with a real patched
clone so nothing has to be hand-reimplemented widget by widget.

## Theming

Colors are **not** hardcoded — `Bar.qml` still uses the same `Color.bar.*`
bindings (`qs.Commons`) as the stock bar, which resolve from the active
Omarchy theme's `colors.toml` → generated `shell.toml` `[bar]` section.
Switching Omarchy themes re-colors this bar automatically, same as stock.

## Why patched, not used as-is

`omarchy plugin clone omarchy.bar` produces a `Bar.qml` that declares
`required property` for `omarchyPath`, `barWidgetRegistry`, and `barConfig`.
Swapping to that clone via `omarchy bar use` crashes with "Required
property X was not initialized" — the shell injects these via a later
assignment (`target.x = ...`), not at creation time, which QML's `required`
keyword doesn't accept for a dynamically swapped-in bar. Two patches on top
of the clone:

1. **Drop `required`** from those 3 properties, plain defaults instead —
   the actual fix for the crash above.
2. **Inset margins** — `frameInset = 6` (matching `ruixen.frame-widget`'s
   `thickness`) added to the bar's top/left/right `margins`, only for
   `position === "top"`.
3. **Extra left/right content padding** (`Style.space(8) + 20`) on top of
   the existing per-widget spacing, so the leftmost/rightmost bar content
   clears the frame's rounded corner (`cornerRadius: 24`) instead of
   starting right at it.

## Pairing with the frame

A larger panel inset (`frameThickness + frameCornerRadius`, clearing the
rounded-corner zone entirely) was tried first and looked like a floating
disconnected box — too much empty gap on either side. Settled on the
smaller thickness-only panel inset instead, plus the separate content
padding above to keep the actual widgets clear of the corner curve.

## Bar layout used with this setup

`omarchy.menu` (the leftmost distro-logo icon) was removed and re-added via
`~/.config/omarchy/shell.json`'s `bar.layout.left` — no dedicated `omarchy
bar remove` command exists, so it's a direct JSON edit:

```bash
python3 -c "
import json
path = '$HOME/.config/omarchy/shell.json'
with open(path) as f: data = json.load(f)
data['bar']['layout']['left'] = [w for w in data['bar']['layout']['left'] if w.get('id') != 'omarchy.menu']
with open(path, 'w') as f: json.dump(data, f, indent=2)
"
```

`shell.json` itself isn't symlinked from this repo — Omarchy rewrites it
constantly (theme changes, `omarchy bar` commands), so it's live state, not
a static dotfile. This command is the reproducible record of the one
layout change made here.

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
cp -r manifest.json Bar.qml BarModel.js indicators widgets ~/.config/omarchy/plugins/ruixen.bar/
omarchy plugin validate ~/.config/omarchy/plugins/ruixen.bar
omarchy bar use ruixen.bar
omarchy restart shell
```

Plugin folders can't contain symlinks (the shell's loader rejects them), so
this has to be a real copy, not `ln -s`.
