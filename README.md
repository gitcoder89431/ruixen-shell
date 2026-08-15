# ruixen.notch

A hover-expanding "dynamic island" notch at the bar's true center — a
standalone `kind: overlay` plugin, not part of `ruixen-bar`'s own window.
Shows an avatar / media status / notification indicator collapsed; on
hover or click (pins it open) it expands into a bigger card with track
info, an animated progress wave, and transport controls.

## Why a separate overlay plugin, not another `ruixen-bar` pill

The design goal (a literal iPhone/MacBook-style notch: square top corners
that visually weld into the frame, concave curves at the two top corners
where it meets the bezel, expanding downward on hover) needs a surface
that can grow well past the bar's own thin strip without touching the
bar's reserved screen zone or repositioning every other pill's vertical
anchor. A separate `PanelWindow` with `exclusionMode: ExclusionMode.Ignore`
(same as `ruixen.frame-widget`) sidesteps all of that — it floats over
windows independent of `ruixen-bar`'s window entirely.

**`mask` is required**, scoped to the notch's own current rect
(`notchOuter.x/y/width/height`, kept in sync as it resizes). Mocha's
original prototype (see below) has no mask on a full-width,
`ExclusionMode.Ignore` surface — exactly the shape of bug that broke
terminal scrolling system-wide earlier in `ruixen.frame-widget` before
its own mask fix. Without this the whole top strip would swallow
clicks/scroll even outside the visible notch shape.

## Where the design actually came from

Two source projects, ported in stages:

1. **Shape mechanics** — `~/REPOS/PLUGINS/quickshell-ambxst/modules/notch/
   Notch.qml` + `modules/corners/RoundCorner.qml`. The concave "bezel
   flows into the notch" look isn't a plain rounded rect: a background
   layer is masked (`QtQuick.Effects` `MultiEffect`, `maskEnabled`) by an
   assembled silhouette — a full-height center block (square top corners,
   animated round bottom corners) flanked by two small corner tiles at the
   very top-left/top-right, each painted with `RoundCorner`'s
   quarter-circle `Canvas` facing *toward* the center block. That carves a
   concave bite exactly where the flanks meet the block.
2. **The wave** — `modules/components/WavyLine.qml`, ported verbatim. A
   plain `Canvas` drawing a sine wave whose phase increments off
   `Date.now()`, redrawn every frame via `FrameAnimation` while `running`.
   Genuinely self-contained, no shader/effect dependency. Used for both
   the collapsed mini-progress and the expanded full progress bar — only
   the *played* portion renders as wave (`width: fullWidth *
   progressRatio`), a dim static `Rectangle` covers the rest, matching
   ambxst's actual `StyledSlider` behavior instead of a purely decorative
   full-width animation.
3. **Row layout** (avatar → divider → player → divider → bell) — ported
   from `modules/widgets/defaultview/DefaultView.qml`'s `mainRow`,
   `UserInfo.qml`, and `NotificationIndicator.qml`.
4. **Interaction shell** (hover-preview / click-to-pin, animated
   width/height/radius) — from `~/REPOS/PLUGINS/quickshell-mocha-v2/
   modules/bar/Bar.qml`, an earlier, much simpler prototype that got
   built first as a base before the ambxst shape replaced its plain
   rounded-pill silhouette. Its catppuccin color palette was dropped in
   favor of neutral OLED black + white/gray, deliberately not matching
   ambxst's own colors either — design/interaction first, real color
   tokens (probably theme-linked, like `ruixen-bar`) come later.

**What was deliberately *not* ported**: ambxst's notch hosts a
`StackView` navigating into launcher/dashboard/powermenu/tools/
notification screens — collectively tens of thousands of lines, built
against their own `Config`/service/theming framework (`qs.config`,
`qs.modules.services`, `qs.modules.widgets.dashboard`, etc.) that doesn't
exist here. Only the notch's own shape/animation/row-layout code is
ported; content is ours, wired to real Omarchy/`ruixen.*` services
instead of ambxst's.

## Content wiring status

- **Media** (`ruixen.media`, see `ruixen-tray-widgets`) — fully wired:
  play/pause click, prev/next in the expanded view, real position/length
  driving the wave. Not wired: drag-to-seek (click/drag the wave to jump
  to a position) — display-only for now.
- **Notification bell** — reflects real `omarchy.notifications`
  `doNotDisturb` state (red when active) via the same first-party service
  `ruixen.dnd` reads. Not clickable — the actual toggle stays in
  `ruixen.dnd`, in `ruixen-bar`'s toggles pill. Not wired: real
  notification count/shake-on-new-notification (ambxst's version does
  this via their own `Notifications` service).
- **Avatar** — reads `~/.face.icon` if present, falls back to a gradient
  placeholder circle (not a shipped PNG asset — a `Gradient`-filled
  `Rectangle` scales cleanly at any size with no fixed resolution/ratio to
  pick, and needs no image-generation step). Not clickable.
- **Idle title fallback** — ambxst falls back to the *focused window's
  title*, then `user@host`, rather than ever showing blank. We don't have
  a compositor-window-title service wired up here (that's `ruixen-bar`'s
  own `ActiveWindow` territory, unrelated to this plugin), so this
  currently falls straight to `user@host`.

## Third mode: quick app launcher

A third `panel` state alongside collapsed/media, triggered by
`ruixen.applauncher`'s bar icon over Quickshell's native IPC (`qs ipc call
ruixen.notch openLauncher/closeLauncher/toggleLauncher` — a real
`IpcHandler`, not the `omarchy-menu` CLI route). `panel.launcherOpen` folds
into the same `panel.expanded` every other "open" state uses, so it fully
expands to the exact same `420×190` size and `44px` corner radius the
media view already uses — no dimensions of its own. Shows favorite-app
icons at full size (56px) in a 3-column `Grid`
(`launcherContent.favoriteAppIds`, a plain hardcoded array — edit directly
to change which apps show, currently kitty/Nautilus/chromium/code/spotify/
Discord); click one to launch and close. Reads `shell.appLibrary` directly
for icon/name lookup and launching — the same service the stock
`omarchy.menu`'s Apps submenu uses — no cloning needed, unlike the
`omarchy.menu` icon itself (see the gotcha below).

Deliberately has **no search box**: an earlier version had a `TextInput` +
scrollable `ListView` of search results, its own size (340×260, then
taller), and grabbed `WlrKeyboardFocus.Exclusive` while open. That larger,
never-before-used size hit a real, non-deterministic bug in `notchBg`'s
masking (the `MultiEffect`/`layer.effect` setup two sections up) — the
bottom corner radius randomly stopped rendering (flat/square instead of
rounded) on some opens but not others, *same height, same process, no
restart in between*. Not a clean fixed threshold to binary-search around
— a real timing/race issue in the mask regenerating at sizes the notch
had never actually rendered at before. Simplified instead: drop the
search box entirely and reuse the exact `420×190` the media view already
proved safe, rather than gamble on any new size. If a search box comes
back later, budget time to actually root-cause the masking bug first (or
find a non-`MultiEffect` masking approach) rather than re-hitting it.

## A real gotcha: `ruixen.media` got auto-disabled

When `ruixen.media`'s entry was removed from `ruixen-bar`'s
`bar.layout.center` (replaced by this notch reading its *service*
directly, not through a bar-widget slot), the plugin registry silently
flipped it to **disabled** — apparently "no longer referenced by any bar
layout slot" triggers an auto-disable for plugins declaring both
`service` and `bar-widget` kinds in one manifest. Since `firstPartyServiceFor`
is a pure lookup (not a lazy-creator — services only exist in `_services`
if the plugin is enabled and its `keepLoaded: true` service was eagerly
started), a disabled `ruixen.media` meant `shell.firstPartyServiceFor
("ruixen.media")` returned `null` here, and the whole notch silently had
no data — looked like a bug in this plugin, was actually the OTHER
plugin's state. Fix: `omarchy plugin enable ruixen.media`. Worth checking
`omarchy plugin list | grep media` first if the notch ever goes data-less
again after touching `ruixen-bar`'s layout.

## Install (local dev)

```bash
cp manifest.json Overlay.qml ~/.config/omarchy/plugins/ruixen.notch/
omarchy plugin validate ~/.config/omarchy/plugins/ruixen.notch
omarchy plugin enable ruixen.notch
omarchy restart shell
```

Plugin folders can't contain symlinks (the shell's loader rejects them),
so this has to be a real copy, not `ln -s`.

**`omarchy plugin validate` did not catch a real syntax error once**
during development (a missing closing brace) — it returned exit 0 with no
output while the actual QML component failed to compile at runtime. The
authoritative check is the live `log.qslog`
(`ls -t /run/user/1000/quickshell/by-id/*/log.qslog | head -1`) for
`Expected token`/`ReferenceError`/`TypeError`, plus confirming
`openlayer>>ruixen-notch` actually appears after a restart — not just a
clean `validate` exit code.

## Companion setup

- **[`ruixen-tray-widgets`](https://github.com/gitcoder89431/ruixen-tray-widgets)**
  — `ruixen.media` (must stay *enabled*, see gotcha above) and
  `ruixen.dnd` for the notification-state data this notch displays.
- **[`ruixen.frame-widget`](https://github.com/gitcoder89431/ruixen-frame-widget)**
  — the notch is positioned/colored to visually weld into this frame's
  top border.
