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
keyword doesn't accept for a dynamically swapped-in bar. Patch on top of the
clone: drop `required` from those 3 properties, plain defaults instead —
the actual fix for the crash above.

## Floating pill background

The bar background itself is fully transparent (`BarPanel.color:
"transparent"`) — instead of one solid bar-wide background, each widget
cluster sits in its own small rounded "pill" (`component GroupPill`, solid
`#000000`, matching `ruixen.frame-widget`'s hardcoded black), so groups read
as separate floating islands rather than one continuous bar:

- **menuPill** — just the Omarchy logo/menu icon.
- **workspacesPill** — workspace numbers.
- **rightPill** — the general icon tray (agents, bluetooth, network, audio,
  monitor, power).
- **togglesPill** — stay-awake + do-not-disturb toggles
  (`ruixen.stayawake`/`ruixen.dnd`, see `ruixen-tray-widgets`), always
  visible.
- **trayPill** — the system tray (`ruixen.tray`) on its own, separate from
  togglesPill. `visible: trayContent.implicitWidth > 0`, so it fully
  disappears when no tray apps are running — safe to let it vanish because
  togglesPill next to it is a separate, always-present anchor pill.

Each pill's own width is driven by its content's `implicitWidth` (see
`root.sideRightIds`/`root.togglesPillIds` and the `.filter(...)` calls
splitting `layoutEntries("right")` in `Bar.qml`), so they grow/shrink with
whatever's actually inside them — not pre-reserved space.

## Widget customization needs its own top-level plugin, not a file drop here

Only `Bar.qml`/`BarModel.js` (the bar shell itself) are loaded from this
plugin's own folder. Anything registered as its own `kind: bar-widget`
plugin — tray, audio, network, workspaces, indicators, clock, etc. — is
resolved globally by manifest `id` from a top-level plugin directory under
`~/.config/omarchy/plugins/`, regardless of which bar is active. Dropping a
patched copy of one of those widgets inside `ruixen-bar/widgets/` (as this
repo used to, leftover from `omarchy plugin clone omarchy.bar` copying the
stock bar's bundled widgets subfolder wholesale) silently does nothing —
the shell keeps resolving that widget's id to the real, unmodified,
first-party version, since a manifest nested inside another plugin's folder
is never scanned as its own plugin. Confirmed the hard way: extensive edits
to a dropped-in `Tray.qml` had zero visible effect for an entire session.

Any bar-widget customization needs `omarchy plugin clone <id>` to get a
real top-level plugin first. See
[`ruixen-tray-widgets`](https://github.com/gitcoder89431/ruixen-tray-widgets)
for the tray/stay-awake/do-not-disturb widgets built this way.

## Drag-to-reposition disabled

`startDrag()` is a no-op — the built-in "drag the bar to another screen
edge" feature is disabled. The frame-clearance insets here only account for
`position === "top"`; re-enable once left/right/bottom get their own
insets.

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
2. **[`ruixen-tray-widgets`](https://github.com/gitcoder89431/ruixen-tray-widgets)**
   — the system tray, stay-awake, and do-not-disturb widgets referenced by
   `sideRightIds`/`togglesPillIds` above. Without these enabled under their
   `ruixen.*` ids, those layout entries just won't resolve to anything.
3. **Rounded window corners, matching `cornerRadius` (24)** — set in
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
cp manifest.json Bar.qml BarModel.js ~/.config/omarchy/plugins/ruixen.bar/
omarchy plugin validate ~/.config/omarchy/plugins/ruixen.bar
omarchy bar use ruixen.bar
omarchy restart shell
```

Plugin folders can't contain symlinks (the shell's loader rejects them), so
this has to be a real copy, not `ln -s`.
