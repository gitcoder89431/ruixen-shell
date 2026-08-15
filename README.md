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

## Dashboard: media hover/pin now ports ambxst's actual WidgetsTab.qml

`DashboardContent.qml` (new file, not folded into `Overlay.qml` — that
file was already large) is a pure-frontend port of ambxst's
`modules/widgets/dashboard/widgets/WidgetsTab.qml` — the real content of
their dashboard's default tab, not a from-scratch design. Four columns:
player | quick controls + calendar | notification history |
volume/brightness/mic dials. `expandedContent` (hover/pin) instantiates
it directly now, replacing the old simple album-art/progress/transport
layout it used to have.

Deliberately scoped to just those 5 pieces, not ambxst's *entire*
dashboard tree — that's ~32k lines total (notes app, clipboard manager,
tmux integration, a full keybinds editor, theme editor, wallpaper
picker with its own color-scheme system, system/compositor panels, a
metrics tab, weather widget, emoji picker). Only the calendar is
genuinely functional (plain `Date` math, no backend needed) — prev/next
month navigation works, today's cell highlights correctly. Everything
else (quick-control toggles, notification list, volume/mic/brightness
dials) is static/decorative, a visual reference for deciding what's
worth actually wiring up later, not a promise that it works yet.

Built with plain QML primitives (`Rectangle`/`Text`/`Canvas`/
`RowLayout`/`ColumnLayout`) throughout, not ambxst's own `StyledRect`/
`Styling`/`Colors` design-token system, which doesn't exist in this
project — same "port the shape, not their whole framework" approach as
the notch's own concave-corner masking.

This is what made trying the `900×344` dashboard size worthwhile in the
first place (see the collapsed/media/launcher sizing notes above) — a
`420×190` box has no room for 4 real columns, so hover/pin needed the
bigger, previously-untested size specifically to have somewhere to put
this.

Height later bumped again, `344` → `400`, per direct feedback ("a bit
too short"). Past the previously-tested-safe value, so stress-tested
3x (open/close cycles via toggling `pinnedOpen`, screenshotting the
bottom corners each time) against the flat-bottom-corner masking bug
documented above before keeping it — clean rounded corners all 3
rounds, no recurrence.

**Pane styling**: originally every column used one filled tonal card
look (`Pane`: `Qt.rgba(1,1,1,0.05)` fill, no border) — a flat grey
block sitting on the notch's own black background. Per direct
feedback this read as "backwards" next to ambxst's own OLED-mode
look: the player/quick-controls/calendar/volume-dial columns switched
to `Pane` v2 -- `color: "transparent"` (falls through to the notch's
real black) with a `Qt.rgba(1,1,1,0.14)` / `1.5px` border, so each
column reads as a black card *framed* by a visible grey outline
instead of a grey block. **Notifications is the one deliberate
exception** -- kept on the original filled look, now split out as its
own `PaneFilled` component, per direct "yea i want the notification
grey" feedback after the black+border pass. Two components now,
picked per-column, not a single shared one.

**Notifications header row**: the "Notifications" label is now its own
small black pill (matching the tab bar/settings glyph treatment
elsewhere), and the row also carries two small circular black-pill
buttons on the right -- a DND bell and a "clear all" broom, mirroring
ambxst's own `NotificationHistory.qml` header (`dndHover`/`broomHover`
`StyledRect`s). Both are decorative for now, same as the rest of this
column -- no real notification service wired here.

**A real glyph-guessing miss worth remembering**: first attempt at the
broom glyph used `U+F0389`, guessed by pattern-matching other Nerd
Font MDI codepoints already working in this file -- rendered as a
music-note glyph instead (`md-music_note_half`, confirmed via
screenshot). Installed `python-fonttools` (`pkexec pacman -S
python-fonttools` -- `sudo` needed a TTY this session didn't have) and
read `JetBrainsMonoNerdFont-Regular.ttf`'s actual cmap/glyph names
instead of guessing further:
```python
from fontTools.ttLib import TTFont
f = TTFont("/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf")
cmap = f.getBestCmap()
rev = {v: k for k, v in cmap.items()}
rev["md-broom"]  # -> 0xf00e2, the actual correct codepoint
```
Worth reaching for this instead of trial-and-error screenshot cycles
for any future icon glyph in this project -- it's exact, not a guess.

**A real layout bug worth knowing about**: `Layout.preferredWidth`
alone does not hard-cap a `RowLayout` column's width if a child further
down wants more — the calendar's own natural content width was
overriding the `220` I set on its column and starving the notifications
column down to near-zero width, which looked like a completely
different, invisible-panel bug at first. Fixed by pairing every
fixed-width column with an explicit `Layout.maximumWidth` matching its
`Layout.preferredWidth`, plus `clip: true` on the shared `Pane`
component as a backstop. Worth remembering for any future `RowLayout`/
`ColumnLayout` work in this file.

## Left-side tab bar (shell only)

`Overlay.qml`'s `expandedContent` (media hover/pin state) now wraps
`DashboardContent` in a `RowLayout` alongside a 70px-wide vertical tab
bar on the left, matching ambxst's own `Dashboard.qml` `tabsContainer`:
three stacked icon buttons (Widgets/Wallpapers/Metrics) with a settings
gear pinned at the bottom via a `Layout.fillHeight` spacer above it.
Column width and button size (48×48, up from an initial 30×30) match
the volume/brightness/mic dial column on the right per direct
feedback — the first pass was too thin and clipped the settings glyph.

**Clicking a tab near the box's own edge could collapse the notch
before the click landed.** Staying expanded here relied entirely on
unbroken hover (`panel.hoverOpen`) -- a tab click doesn't bubble up to
the notch's own click-to-pin `MouseArea` (its own `MouseArea` consumes
the click first), so nothing set `pinnedOpen`. If the cursor's approach
toward the tab bar (which sits close to the expanded box's own left
edge) so much as grazed outside `notchOuter`'s hit rect -- e.g. while
the 230ms grow animation was still catching up -- `onExited` fired
immediately and the whole thing shrank back down, "chasing" the mouse
away from the target it was reaching for. Fixed two ways: (1)
`hoverExitTimer`, a 220ms debounce between `onExited` and actually
setting `hoverOpen = false`, giving brief boundary hiccups room to
self-correct; (2) every tab button's `onActivated` also sets
`panel.pinnedOpen = true`, so once a tab's actually been clicked the
notch no longer depends on hover at all.

**That second fix immediately exposed a new one: pinning via a tab
click had no way to un-pin.** The click-away-to-dismiss mask/MouseArea
(see "Third mode: quick app launcher" above) only ever widened for
`launcherOpen` -- clicking `pinnedOpen` open (now reachable via a tab,
not just the notch's own click-to-pin) left the mask tight to
`notchOuter`, so a click anywhere outside the notch shape just passed
straight through to the window behind instead of reaching this
surface at all. Generalized: `panel.clickedOpen` (`pinnedOpen ||
launcherOpen`) now drives both the mask widening and the click-away
`MouseArea`'s `enabled`, and the click-away handler clears both flags.
Deliberately excludes plain `hoverOpen` -- that already self-dismisses
on mouse-exit (via `hoverExitTimer` above), and widening the mask for
a passing hover would swallow clicks meant for other windows, not just
this notch.
State lives on `panel.dashboardTab` (`0`/`1`/`2`), one `Item` per tab
toggling `visible` — same "one window, swap content" mechanism ambxst
uses (no `StackView`, no second window/animation to coordinate).

Scoped to just the switcher, per direct request: **Widgets** (tab 0) is
the real `DashboardContent` port; **Wallpapers** and **Metrics** (tabs
1/2) are static "coming soon" stub panes, no actual page behind them
yet. The **settings** gear is the one fully real action in this bar —
it runs `omarchy-menu summon settings` via a fire-once `Process`
(`settingsProc`, `running: false` until clicked), opening Omarchy's own
real settings menu instead of reimplementing one here. `"setup"` is the
actual root `omarchy-menu.jsonc` entry (aliased `"settings"`) —
confirmed working directly (`omarchy-menu summon settings` opens the
`omarchy-menu` layer) before wiring it up.

Icon glyphs (Nerd Font Material Design Icons / Font Awesome codepoints,
verified by screenshot, not guessed): Widgets reuses the grid glyph
(`U+F0570`) from an earlier `ruixen.applauncher` icon iteration;
Wallpapers is FA `image` (`U+F03E`); Metrics is FA `heartbeat`
(`U+F21E`); Settings is FA `gear` (`U+F013`, the same glyph
`ruixen.quickactions` used before its own swap to sliders-vertical).

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
