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

**Header row redone to match ambxst's own titleRect/dndToggle/
clearButton layout**: the "Notifications" pill now uses
`Layout.fillWidth: true` (fills the row instead of a snug-fit pill
around the text, mirroring their `titleRect`), text/icon sizes bumped
11px → 13px, and the whole row uses a fixed `26px` height per direct
feedback ("these headers text and icon gotta be bigger"). Hit the
**exact same `RowLayout` height bug already documented above** for
width: `Layout.preferredHeight: 26` alone did not cap the row -- its
`Layout.fillHeight: true` children stretched it to nearly the full
column height (rendering as a giant stadium-shaped blob, `radius:
height/2` following the runaway height). Fixed identically to the
width version: pair `Layout.preferredHeight` with an explicit
`Layout.maximumHeight: 26`. Worth internalizing as a general rule for
this file, not just a width-specific gotcha: `Layout.preferredX` alone
never hard-caps in either axis if a `Layout.fillX: true` child wants
more.

## Are we actually the right size vs. ambxst?

Checked directly against `Dashboard.qml`'s own real computed size, not
just `DashboardView.qml`'s declared `900×344` (that value turns out to
be dead/overridden -- `Dashboard.qml` sets its own explicit `width:
animatedWidth` / `height: animatedHeight`, driven by `implicitWidth:
nonAnimWidth = (currentTab===0 ? 600 : 400) + tabWidth(48) + 16` and a
flat `implicitHeight: 430`, which wins over the parent's `anchors.fill`
sizing). Their REAL on-screen Widgets-tab content area is `viewWrapper`
-- `parent.width - tabWidth(48) - 2 - 16`, i.e. **~598×430** for tab 0,
not 900×344.

So: we're not undersized -- our own `DashboardContent` area (900 total
minus tab bar/margins) comes out to **~830px wide**, meaningfully
*wider* than their real 598px, though a bit shorter (368px inner height
vs their 430px). What actually didn't match was rhythm, not size:
their `mainLayout` `Row` and `WidgetsTab`'s own `RowLayout` both use
`spacing: 8`; we were at `10`/`12`. Tightened both to `8` (plus the
volume-dial column's own `ColumnLayout`, `10` → `8`) to match, per
direct feedback after confirming the real numbers first rather than
guessing.

**Quick controls: game mode swapped for Omarchy's Agents widget**, per
direct request -- game mode wasn't needed, and the 5th slot now shows
the same `robot_excited` glyph (`U+F16A3`) `omarchy.agents`' own bar
icon uses (found directly in `/usr/share/omarchy/shell/plugins/agents/
Panel.qml`, not guessed). That widget's manifest only declares `kinds:
["bar-widget"]`, no `"service"` kind, so its `alarming` property
(`>=90%` of a rate limit -- the "face goes red" behavior) isn't
reachable via `shell.firstPartyServiceFor()` the way `ruixen.media`/
`omarchy.notifications` are. Stays static like its 4 siblings rather
than faking the live red-alert state.

**Notifications header, round 2**: still looked too small after the
above per direct feedback ("doesn't fill in the header enough").
Re-checked ambxst's real header proportions in
`NotificationHistory.qml`: `Layout.maximumHeight: 32` on the row
(we were at `26`), `Layout.preferredWidth: 32` on the bell/broom
buttons (we were at `26`), icon `font.pixelSize: 18` (we were at
`13`), title `font.pixelSize: Config.theme.fontSize` (their default
`14`, we were at `13`). Bumped row height `26`→`32`, button width
`26`→`32`, title text `13`→`14`, icon size `13`→`16` (kept a touch
below their `18` since our row is a hair shorter and icons at 18
started crowding the 32px circle).

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

## Quick controls: 4 of 5 are real toggles now

Wired per direct request -- click-to-toggle with live on/off coloring
(`root.accent` fill + black glyph when on, the original grey tonal
when off, matching how the calendar's today-cell and the active tab
already use accent for "on" state):

- **WiFi** -- `Quickshell.Networking`'s `Networking.wifiEnabled`. A
  real global Quickshell singleton, not gated behind Omarchy's plugin
  registry at all -- readable/writable directly, same as
  `omarchy.network`'s own `toggleNetwork()`.
- **Bluetooth** -- `Quickshell.Bluetooth`'s `Bluetooth.defaultAdapter
  .enabled` for reading state. Toggling does NOT write `adapter.enabled`
  directly (that hits BlueZ's `Powered`, which nothing persists, so it
  comes back on at next boot) -- calls `Quickshell.execDetached([
  "omarchy-bluetooth-power", ...])` instead, the exact same helper
  `omarchy.bluetooth`'s own panel uses, which moves the rfkill soft
  block (survives reboots via systemd-rfkill).
- **Night light** -- `shell.firstPartyServiceFor("omarchy.nightlight")`,
  a real `kind: "service"` plugin (confirmed via its manifest) with a
  directly-callable `.toggle()` method on the service object itself --
  no IPC needed, same pattern `mediaService` already used here.
- **Caffeine/stay-awake** -- `shell.firstPartyServiceFor("omarchy.idle")`
  `.stayAwake` / `.setIdleEnabled(...)`. Ported the exact toggle
  expression `ruixen.stayawake`'s own `StayAwake.qml` uses --
  `setIdleEnabled(currentStayAwakeValue)` looks backwards at a glance
  but is correct: `stayAwake` and `idleEnabled` are semantic opposites,
  so passing the about-to-be-old `stayAwake` value in as the new
  `idleEnabled` value IS the toggle.
- **Agent glyph** -- deliberately left non-interactive, per direct
  instruction ("dont worry about the agent one"). See the note above
  on why (`omarchy.agents` has no `service` kind to read from).

All 4 read-sides verified against real system state before committing
(`nmcli radio wifi`, `rfkill list bluetooth`, `qs ipc call nightlight
status` all matched what rendered) -- couldn't script a real mouse
click in this environment (a standing limitation all session, see the
launcher-testing notes elsewhere in this repo's history), so the
write-side confidence comes from reusing the *exact* commands/methods
the already-shipped, real Omarchy panels and our own `ruixen.stayawake`
widget use, not from an end-to-end click test.

`QuickToggle` (new shared component, next to `Pane`/`PaneFilled`) is
the button itself -- accent/grey fill + `signal activated()`, same
shape as `TabButton` in `Overlay.qml`. Its size is now a property
(`size: 32` default, `radius`/`font.pixelSize` derived from it) rather
than hardcoded, so instances can override -- see the width/icon-count
change below.

## Column 2 widened, agent icon dropped, remaining 4 toggles grown

Per direct feedback ("calendar too narrow... make icon row bigger,
push it down a bit... if we need to get rid of the AI button we
can"): the quick-controls+calendar column widened `220px` -> `250px`,
the (never-interactive) Agents glyph was dropped from the quick
controls row entirely, and the remaining 4 real toggles grew
`32px` -> `40px` (via `QuickToggle`'s new `size` property) to use the
freed-up space instead of leaving it empty. The quick-controls `Pane`
itself grew `44px` -> `52px` tall to fit the bigger buttons, which
naturally pushes the calendar down slightly, exactly as asked.

**Follow-up: week rows still looked "too hamburger" (too much gap
between rows)**, even though width was now fine. Root cause: the
day-grid `Rectangle` used `Layout.fillHeight: true`, stretching it to
match whatever leftover height `calendarPane` (also `fillHeight:
true`) had -- and `ColumnLayout` spread that leftover space out as
visible gaps between every week row instead of leaving it as one
trailing gap. Fixed by sizing the day-grid to its actual content
instead: `Layout.preferredHeight: 172` (paired with
`Layout.maximumHeight: 172`, same lesson as the 3 prior instances of
this pattern in this file) plus `Layout.alignment: Qt.AlignTop`. Any
leftover column height now shows as plain grey space below the grid
instead of stretching the rows apart -- confirmed via a zoomed
screenshot crop, not just eyeballing the full dashboard.

**Follow-up: that trailing grey space was too big** ("a ton of space
below the calendar... i guess our notch was too tall?"). Not a notch
height problem -- `calendarPane` (the grey outer card) still had
`Layout.fillHeight: true` to stay aligned with its sibling columns,
while the day-grid inside was capped to a small fixed content size, so
the difference showed up as empty grey padding. Grew the actual rows/
cells to use more of that space instead of shrinking the notch: week
row height `20px` -> `30px`, "today" circle `20px` -> `26px`, weekday
label font `9px` -> `10px`, day-number font `9px` -> `11px`, day-grid
`Layout.preferredHeight`/`maximumHeight` `172` -> `224`. Some grey
space still remains below (deliberately not maxed out to fill 100% --
would have made the calendar cells look oversized next to the
narrower dial column) but it's much less noticeable now.

**Follow-up: header row (title + chevrons) still looked small** next
to the now-bigger day-grid. Bumped to match: row height `22px` ->
`28px`, chevron pill width `22px` -> `28px`, title text `11px` ->
`13px`, chevron glyph `11px` -> `14px`, pill radius `6` -> `8`.

**Follow-up: quick-controls frame/border too thin** next to the now
bigger toggles. `Pane`'s shared default (`border.width: 1.5`) is
overridden per-instance here to `2.5`, height `52px` -> `60px`, radius
`10` -> `14` -- a visibly thicker, chunkier card than the other 3
`Pane`s in this file, deliberately (only this instance is overridden,
not the shared component).

**Follow-up: weekday labels / divider / day-grid too cramped**
vertically -- the inner `ColumnLayout` spacing was still `2`, left
over from before the row/cell size bumps above. Bumped to `6`, and
grew the day-grid `Rectangle`'s own height `224px` -> `250px` to fit
the extra spacing without clipping (7 gaps at `6px` vs `2px` = `+28px`
of new spacing needed).

**Follow-up: weekday labels (M T W T F S S) too light/small.** Bumped
`10px` -> `13px` and added `font.bold: true`.

**Follow-up: still a sliver of unfilled grey below the day-grid.**
Day-grid `Rectangle` height `250px` -> `268px`, closing the last bit
of the gap between the black grid and calendarPane's own grey card
edge.

## Player column: frosted-glass background, no border

Per direct request, checked ambxst's real `FullPlayer.qml` for the
actual technique instead of guessing: their player uses `variant:
"transparent"` (their `StyledRect` variant that forces border AND fill
opacity to 0 -- genuinely no visible border, confirmed in `Styling.qml`
earlier) plus a blurred-album-art backdrop
(`backgroundArtBlurred` + `MultiEffect { blurEnabled: true; blurMax:
32; blur: 1.0; opacity: 0.25 }`).

Ported the same idea with our own tools rather than their `StyledRect`
system: swapped the player column from the shared `Pane` (black+border)
to a bespoke `Rectangle` (`playerCard`) with no border at all, `color:
Qt.rgba(0,0,0,0.35)` as a flat fallback tint for when there's no art,
and a blurred `root.artUrl` backdrop underneath the existing content --
literally the same `Image` (small `sourceSize: 64x64` for a cheap
blur) + `MultiEffect` pattern the collapsed notch view's own `bgArt`
already uses one file over in `Overlay.qml`, just at `opacity: 0.35`
matching ambxst's ratio more closely than a copy-paste of our own
`0.35` used elsewhere. New `import QtQuick.Effects` needed for
`MultiEffect` (wasn't previously imported in this file).

**Verified the blur actually renders**, not just that it doesn't
error: no MPRIS player was active to test with for real, so
temporarily hardcoded `root.artUrl` (in `Overlay.qml`, reverted after)
to a real local wallpaper file
(`~/.local/state/omarchy/current/theme/backgrounds/1-tree-tops.jpg`)
and confirmed via screenshot -- soft blurred mountain tones visible
behind the sharp thumbnail, exactly the frosted-glass look asked for.

**Follow-up, real misread worth recording**: first pass still gave
`playerCard` its own `color: Qt.rgba(0,0,0,0.35)` fallback fill --
read as "the border isn't see-through, there's a black layer under
it," and initially misread as a request for real compositor-level
desktop blur-through (Hyprland `layer_rule` `blur`/`xray`). It wasn't
-- the actual ask was simpler: ambxst's real player has **no fill at
all** (`variant: "transparent"` forces `opacity: 0` AND `border`
width `0`, confirmed back in `Styling.qml`), so there's no separate
card layer competing with the blur; the notch's own shared black base
shows straight through when idle. Removed the `0.35` fallback tint
entirely (`color: "transparent"`) -- the player column now reads as
part of the notch's shared black instead of its own darker floating
box, matching the other columns' relationship to the shared base
without needing an actual desktop-blur-through effect at all.

**Follow-up, the actual real ask**: still wasn't it -- "no its not the
blur im talking about, its like a hole or cut out of the border of
the music card only... does this mean the notch is transparent and
each of our section have oled bg or something?" Correct diagnosis:
they wanted a literal geometric hole in the notch's own rendered
surface for that column, not alpha-blended tinting against the shared
black. Implemented in `notchMask` (`Overlay.qml`) -- a plain black
`Rectangle` painted on top of `centerMask`'s white fill, at the exact
position/size `playerCard` occupies in `DashboardContent.qml`'s
layout (`x: notchOuter.cornerSize + 12, y: 20, width: 210, height:
parent.height - 20 - 12`, mirroring `cornerSize` + `expandedContent`'s
margins + `playerCard`'s own width). Since the mask uses
luminance-based thresholding (`maskThresholdMin: 0.5`), pure black
there means `notchBg`'s `layer.effect` genuinely doesn't paint
anything in that region -- combined with `playerCard`'s already-fully-
transparent fill (previous fix) and `PanelWindow.color: "transparent"`,
that area is a real gap in the rendered surface, not a color trick.
Confirmed via screenshot: actual terminal text visible straight
through the player column, while every other column stays solid
black. A nice side effect: since the blurred-art `MultiEffect` still
sits on top at `opacity: 0.35` when there IS media, playing music
naturally blends 35% blurred album art over 65% real desktop behind
it -- an actual tinted-glass look, not something separately built.

`visible: panel.pinnedOpen || panel.hoverOpen` scopes the cutout to
exactly when the dashboard's real player column exists (matches
`panel.expanded` minus `launcherOpen`, since launcher/collapsed have
no player column to align the hole to).

**Stress-tested 3x** (open/close cycles, screenshot each round) given
this touches the same `notchMask`/`notchBg` masking system that
caused the flat-bottom-corner bug earlier in this project -- clean
rounded corners and a consistent cutout across all 3 rounds, no
recurrence.

## Agent icon added back to quick controls

Per direct request -- with the column now `250px` wide and toggles at
`size: 40`, there was enough spare width to fit a 5th icon (4 icons
left ~30px of empty side padding, confirmed by direct measurement, not
a guess). Re-added the same static `robot_excited` glyph
(`U+F16A3`), row `spacing` trimmed `10` -> `8` to keep the whole row
comfortably clear of the frame's own thicker `2.5px` border instead of
crowding it.

**A real glyph-insertion gotcha, not just a PUA-matching one**: adding
this back via the `Edit` tool wrote the LITERAL text
`"\U000f16a3"` (backslash and all) into the file instead of the
actual character -- `Edit` doesn't interpret Python-style `\U` escapes,
it just inserts the string verbatim. Every glyph inserted successfully
elsewhere in this file was written with a Python `heredoc` script
(`content.replace(old, new)` where `new` contains a real
`'\U000f16a3'` Python string, which Python itself decodes into the
literal character before writing bytes to disk) -- reusing the `Edit`
tool directly for a **new** glyph insertion (as opposed to
find-and-replace on a glyph that's already correctly in the file) will
hit this every time. Caught immediately via screenshot (rendered as
literal `U000f16a...` text), fixed with the usual Python one-liner.

## Calendar: ported literally from ambxst's real Calendar.qml

First pass (grey header bar, black body) was a misread -- the actual
ask, confirmed by rereading ambxst's real `Calendar.qml` directly, was
their literal structure, colors included: the outer frame is grey
(`Qt.rgba(1,1,1,0.08)`, mirroring their `variant: "pane"`), and BOTH
the title text AND each chevron get their OWN separate black pill
(mirroring `titleRect`/`leftButton`/`rightButton`, all `variant:
"internalbg"`) -- the grey never fills behind text itself, it only
ever shows as the gutter *around* those black pills. The day-grid
(weekday labels + all 6 week rows) is a second black sub-panel, with
the row containing today (`currentWeekRow`, ported as a new
`calendarPane.calendarData.currentWeekRow` computed alongside `weeks`)
getting a grey highlight strip -- exactly ambxst's own
`(rowIndex === root.currentWeekRow) ? "pane" : "transparent"`.
Individual day cells keep their existing accent-circle "today"
treatment unchanged, that part was never in question.

Hit the exact same `RowLayout`-doesn't-cap-on-`Layout.preferredHeight`
bug a third time, in the new header `RowLayout` (its black title/
chevron pill children have `Layout.fillHeight: true`, and without a
matching `Layout.maximumHeight` they stretched to swallow nearly the
whole card again). Fixed identically to the previous two times: paired
`Layout.preferredHeight: 22` with `Layout.maximumHeight: 22`. Three
occurrences of this same bug in one file now -- worth treating as a
reflex any time a `RowLayout`/`ColumnLayout` gets a `Layout.preferredX`
in this codebase: always pair it with `Layout.maximumX` up front,
don't wait to hit the bug again.

**Follow-up: the day-grid itself looked "skinny"** inside its own
black panel -- the weekday-label row and each week row were a plain
`Row` of fixed-`20px` cells, centered (`Layout.alignment:
Qt.AlignHCenter`) rather than stretched, so once the day-grid panel
was as wide as the rest of the card, the actual 7-day grid sat as a
narrow ~152px block with big empty gutters on both sides. Switched
both to `RowLayout` with `Layout.fillWidth: true` on all 7 columns, so
they spread edge-to-edge like the header row already did. The "today"
highlight needed an extra wrapper to survive this: a bare `Rectangle`
with `Layout.fillWidth: true` would have stretched the accent circle
into an ellipse, so each day is now an `Item { Layout.fillWidth:
Layout.fillHeight: true }` column holding a fixed `20x20` circle
`anchors.centerIn` inside it -- the column shares width evenly, the
circle itself stays round.

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
