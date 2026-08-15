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

- **menuPill** — leftmost pill, but no longer the Omarchy logo. Removed
  `omarchy.menu` from the bar layout entirely per direct request and put
  `ruixen.applauncher` (home icon) in the same slot instead. `Super+Space`
  still opens the stock menu regardless — that's `omarchy.menu`'s own
  "menu" kind via the `omarchy-menu` CLI, unrelated to whether it has a
  bar button (the shell's own `PluginRegistry.qml` has a comment
  confirming this exact case is handled: a plugin that's both a menu and
  a bar-widget can't be locked out of the shell by removing its button).
  `ruixen.applauncher` opens `ruixen.notch`'s quick-launcher mode instead
  (see `ruixen-notch`'s README) — previously had its own separate pill
  after workspacesPill, moved here since the leftmost slot freed up.
- **workspacesPill** — workspace numbers.
- **rightPill** — the general icon tray (agents, bluetooth, network, audio,
  monitor, power).
- **togglesPill** — keyboard layout, system update, stay-awake,
  do-not-disturb, quick actions, in that order (`omarchy.keyboard-layout`,
  `omarchy.system-update`, `ruixen.stayawake`, `ruixen.dnd`,
  `ruixen.quickactions` — see `ruixen-tray-widgets` for the three
  `ruixen.*` ones), always present. `keyboard-layout` and `system-update`
  only actually show an icon when there's something to show (a second
  layout configured / an update available) — both moved here from the
  center layout, no patching needed (plain layout move, still the stock
  first-party widget) — same widens-when-there's-something-to-show
  pattern as trayPill.
- **trayPill** — the system tray (`ruixen.tray`) on its own, separate from
  togglesPill, faded via `opacity: trayContent.width > 0 ? 1 : 0` instead
  of toggling `visible` when no tray apps are running — safe to let it
  empty out because togglesPill next to it is a separate, always-present
  anchor pill. Simpler than juggling anchors/width around a pill that
  comes and goes, and avoids the `implicitWidth`-vs-`width` pitfall below.
- **clockPill** — weather icon, a thin divider `Rectangle`, then the clock
  — rightmost pill on the bar (took over rightPill's old
  `anchors.right: parent.right` spot; rightPill now anchors off
  `clockPill.left` instead). Direct `ModuleSlot`s in a `Row`, not a
  `ModuleList`, since `ModuleList` has no separator support. Uses
  `ruixen.weather` (see `ruixen-tray-widgets`) for the icon-size match;
  clock is still the stock `omarchy.clock`, untouched.
  **Known limitation**: clicking weather or clock opens its popup centered
  on the whole bar, not anchored near this pill — both stock panels
  hardcode `centerOnBar: true`, not exposed as a setting, only fixable by
  cloning. Left as-is (not worth it).
There used to be a `mediaPill` here too (`ruixen.media`, a clone of stock
`omarchy.media` with a compact progress bar swapped in for the scrolling
title). It's gone now — media moved to
**[`ruixen-notch`](https://github.com/gitcoder89431/ruixen-notch)**, a
standalone hover-expanding notch overlay at the bar's *true* center
(`ruixen.media`'s clone still exists and is still what it reads from, see
`ruixen-tray-widgets` — just no longer rendered as a bar pill here). That
plugin also explored Shibumi-Shell's fancier `cava`-powered audio spectrum
wave and went a different direction (a self-contained animated sine wave
instead) — see its own README for the reasoning.

Each pill's own width is driven by its content's `width` (see
`root.sideRightIds`/`root.togglesPillIds` and the `.filter(...)` calls
splitting `layoutEntries("right")` in `Bar.qml`), so they grow/shrink with
whatever's actually inside them — not pre-reserved space. Read `.width`,
not `.implicitWidth`, off a `ModuleList` — it's a custom `Loader` that only
computes its own `width` property explicitly, never overrides
`implicitWidth`, so reading the latter gets a stale/unset value (cost a
long debugging session to track down — see `ruixen-tray-widgets`'s README
for the other half of that bug, a stale `moduleName`).

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

`omarchy.menu` (the leftmost distro-logo icon) went through a few rounds:
removed and re-added early on (no dedicated `omarchy bar remove` command
exists, so it's a direct JSON edit), then removed for good and replaced
with `ruixen.applauncher` in that same leftmost slot. `Super+Space` still
opens the stock menu regardless of whether it has a bar button — see
menuPill's own comment above for why that's safe.

`ruixen.applauncher` (see `ruixen-tray-widgets`) took a similarly winding
path: enabled and defaulted into `bar.layout.center`, moved to
`bar.layout.right` (alongside `togglesPillIds`) when the right side got
crowded, moved again to its own pill in `bar.layout.left` after
workspaces, and finally into `omarchy.menu`'s old leftmost slot once that
was removed entirely. Current end state:

```bash
python3 -c "
import json
path = '$HOME/.config/omarchy/shell.json'
with open(path) as f: data = json.load(f)
left = [w for w in data['bar']['layout']['left'] if w.get('id') not in ('omarchy.menu', 'ruixen.applauncher')]
left.insert(0, {'id': 'ruixen.applauncher'})
data['bar']['layout']['left'] = left
for section in ('center', 'right'):
    data['bar']['layout'][section] = [w for w in data['bar']['layout'][section] if w.get('id') != 'ruixen.applauncher']
with open(path, 'w') as f: json.dump(data, f, indent=2)
"
```

`shell.json` itself isn't symlinked from this repo — Omarchy rewrites it
constantly (theme changes, `omarchy bar` commands), so it's live state, not
a static dotfile. These commands are the reproducible record of the layout
changes made here.

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
