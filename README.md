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

## Reverted: the cutout above never actually worked

Follow-up debugging (prompted by direct feedback: "im not seeing a
hole cut at all") found the geometry WAS wrong -- the original
formula forgot the 70px left tab bar + 8px `RowLayout` spacing between
it and the dashboard content, off by exactly 78px, confirmed by
sampling actual rendered pixel color at a temporary red debug border
around `playerCard` vs where the cutout rectangle assumed it started.

Fixing the geometry did NOT fix the actual problem. Extensive
isolation testing (temporarily setting `notchMask.visible: true` to
preview the raw mask texture directly, toggling `layer.enabled`,
testing a deliberately huge/impossible-to-miss cutout, nesting the
Rectangle as a child of `centerMask` instead of a new sibling of
`notchMask`, hardcoding `visible: true` with no bindings, forcing a
genuinely cold process restart) found a real, reproducible
technical wall: **a newly-added child Rectangle simply never appears
in the texture `notchBg`'s masked `layer.effect` actually samples**,
even though the exact same Rectangle renders correctly when previewed
directly (`layer.enabled: false`). Property CHANGES on already-
existing elements (e.g. `centerMask.visible = false`, which DID
correctly reveal real desktop everywhere centerMask used to cover --
proving the general masking-produces-transparency mechanism is sound)
get picked up reliably every time; brand-new child elements added to
an already-`layer.enabled` item's subtree do not, at least not in this
Quickshell/Qt environment, across a dozen+ full process restarts
(confirmed via changing PIDs each time, ruling out stale hot-reload).
Root cause not conclusively identified -- suspect a scenegraph/layer-
texture recapture bug specific to structural additions vs property
mutations, not a QML authoring mistake.

Reverted to the pre-cutout state (matching commit `1515bb8`) rather
than ship broken/misleading code. If this comes back: don't retry the
"add a new Rectangle to the mask tree" approach without first testing
whether it renders in a `layer.enabled: false` preview (cheap,
conclusive) -- and consider a single self-contained `QtQuick.Shapes`
donut-path (outer notch boundary minus an inner rect, one path, even-
odd fill) as a fundamentally different technique that doesn't rely on
adding a new child to existing layered content.

## Actually fixed: the real bug was alpha vs. luminance, not structure

A second opinion (an independent agent review) diagnosed the true
root cause, and it's simpler and completely different from what the
extensive isolation testing above concluded: `MultiEffect.maskSource`
reads the mask texture's **alpha channel**, not RGB luminance. The
reverted cutout painted `color: "#000000"` -- opaque black, `alpha:
1.0`. Visually indistinguishable from "nothing" to a human eye, but
to an alpha-based mask it's identical to opaque white, just a
different RGB -- it was never going to subtract anything, regardless
of geometry, nesting location, or any of the other variables tested.
That single wrong assumption explains every confusing result from the
prior debugging session:  `centerMask.visible = false` worked because
it made that region genuinely unpainted (`alpha: 0`); the black
Rectangle never worked because it was never actually transparent.

Concrete proof this was the real bug, already sitting in this
codebase: `ruixen.frame-widget`'s own `Overlay.qml` punches its
border-hole using `Canvas` + `ctx.globalCompositeOperation =
"destination-out"`, which produces genuine `alpha: 0` pixels -- and
that one has worked reliably the whole time.

**The actual fix**: `centerMask` converted from a plain `Rectangle`
into a `Canvas`. It paints the notch's own rounded-bottom silhouette
opaque white (a hand-rolled `roundedRect()` helper, same shape
`Rectangle`'s `topLeftRadius`/etc. used to produce, now with
independently-controllable per-corner radii since Canvas needs them
explicit), then -- only while `panel.pinnedOpen || panel.hoverOpen`
-- switches to `globalCompositeOperation = "destination-out"` and
fills a second rounded rect over the player column's own region
before switching back to `"source-over"`. Same geometry the reverted
attempt already worked out (`x: 90` relative to `centerMask`'s own
origin, `y: 20`, `210×(height-32)`, matching `playerCard`'s real
position -- `cornerSize(28) + expandedContent.leftMargin(12) +
tabBarWidth(70) + RowLayout.spacing(8) - centerMask's own x offset(28)
= 90`). The animated `bottomLeftRadius`/`bottomRightRadius` (still
via `Behavior`, same as before) and the `cutoutActive` toggle both
call `requestPaint()` on change, same reactive-repaint pattern
`RoundCorner`'s own `Canvas` already used elsewhere in this file.

Confirmed working via screenshot -- clearly readable terminal text
visible straight through the player column -- and stress-tested 3x
(open/close cycles) against the known flat-bottom-corner masking bug,
clean across all rounds.

## Reverted again -- the cutout was never the right target at all

The literal hole *worked*, but showed the raw, unblurred desktop
straight through -- looked sharp/plain, not "frosted glass" at all
(nothing in this pipeline was blurring what's actually behind the
window; that would need real Hyprland compositor blur, `layer_rule`
`blur`/`xray`, a much bigger and riskier change touching global
`decoration.blur.enabled`, currently `false` in Omarchy's stock
config).

Before going down that road, re-checked what ambxst's `FullPlayer.qml`
actually does for its own "glass" background -- and it doesn't show
real desktop AT ALL. It blurs the track's own art when playing, and
falls back to blurring their **own desktop wallpaper file**
(`GlobalStates.wallpaperManager.currentWallpaper`) when idle -- a
static image, not a live compositor blur-through. Confirmed directly
in their source (`FullPlayer.qml:112-129`), not assumed.

Reverted `Overlay.qml` back to the pre-cutout state a second time
(matching `1515bb8` again -- the Canvas/`destination-out` mask code is
gone) and updated `DashboardContent.qml`'s player background instead:
`playerCard.wallpaperPath` now points at Omarchy's own stable current-
wallpaper symlink (`~/.local/state/omarchy/current/background` --
survives theme/wallpaper changes, no need to track the actual
filename), and `playerBgSource` picks `root.artUrl` when there's media
playing or `wallpaperPath` otherwise -- so the blur `MultiEffect`
always has something to blur, never blank. Opacity corrected `0.35`
-> `0.25` to match ambxst's real ratio (was a guess before, now
confirmed from their source alongside the wallpaper fallback fix).

Net result: the whole cutout/compositor-blur investigation (multiple
sessions, a second-opinion review, real diagnostic effort) turned out
to be solving a problem ambxst's own design doesn't actually have.
Worth remembering for next time: check what the reference project
*actually does* before chasing a technique it doesn't use.

## Player: circular disc art + separate title/artist lines

Per direct request, matching ambxst's own `discArea`: the album-art
thumbnail is now a real circle, and title/artist are two separate
centered lines instead of one combined "artist - title" string.

**A real gotcha, not obvious from anywhere else in this project**:
plain `Rectangle { radius: width/2; clip: true }` does NOT clip child
content to the rounded shape in QtQuick -- `clip: true` on an ordinary
`Item`/`Rectangle` only clips to the bounding BOX, completely ignoring
`radius`, regardless of how high it's set. Confirmed the hard way:
went from `radius: 10` (looked like a plain square, barely-rounded
corners not actually working either, just too subtle to notice at
that size) all the way up to a hardcoded `radius: 40` on an 80x80 box
-- still a flat square, no visible change at all, even with `color`
swapped to solid `"red"`/`"magenta"` to rule out an image-loading
issue. A bare debug `Rectangle` (no child `Image`) at the same radius
rendered as a correct circle immediately, isolating the bug
specifically to clipping a CHILD item, not the rectangle's own fill.

The fix: `Quickshell.Widgets.ClippingRectangle`, not a plain
`Rectangle` -- confirmed via ambxst's own source, which uses exactly
this component for the exact same purpose (`clippedDisc`, `radius:
width / 2`). It's a real Quickshell-provided component specifically
for rounded-clip content, not equivalent to `Rectangle.clip`. Worth
remembering for any future rounded-image-thumbnail work in this
project -- reach for `ClippingRectangle` first, don't assume plain
`clip: true` respects `radius`.

## Duration text added below transport controls

Matches ambxst's own "Duration Area" text exactly -- `formatTime
(position) + " / " + formatTime(length)`, muted, centered. Uses
`root.trackPosition`/`root.trackLength`/`root.formatTime` -- all
already threaded through from `Overlay.qml`, no new wiring needed.

## Play/pause: square, not round + tighter gap above it

Two follow-ups per direct feedback: the gap between the artist line
and transport controls (`12px` fixed spacer) was trimmed to `4px` --
too much air. And play/pause's shape changed from a full circle
(`radius: 17`, ambxst's own look) to a rounded square (`radius: 8`,
roughly the same `size/4` proportion `QuickToggle` already uses for
the wifi/bluetooth quick-controls buttons) -- explicitly requested to
match that shape instead.

## Play/pause: bigger, tonal accent chip

Per direct feedback, matching ambxst's real `playPauseBtn` (a
`StyledRect variant: "primary"` 44x44 tile, distinct from the plain
glyph-only `MediaIconButton` prev/next use): play/pause is now its
own `34x34` accent-filled circle (`root.accent` bg, black glyph,
`16px`), while prev/next stay plain `14px` glyphs with no background.
Also added `anchors.verticalCenter: parent.verticalCenter` to all
three row children -- the differently-sized elements weren't aligned
to a common baseline before. Confirmed the click handlers are wired
to a real, correct API before touching styling: `runAction("previous"
/"playPause"/"next", ...)` is the exact same function
`ruixen-tray-widgets`' own `media/Service.qml` IPC handler already
calls successfully elsewhere in this project.

## Album line restored + transport row actually centered

Two real bugs, per direct feedback. First: the transport controls
row had BOTH `Layout.fillWidth: true` and `Layout.alignment:
Qt.AlignHCenter` -- a plain `Row` doesn't center its own children, it
left-packs them from its own x=0, so `fillWidth` stretched the row to
the card's full width while the icons stayed pinned to the left edge
inside it. `Layout.alignment` only centers the Row ITSELF within
leftover space, which only does anything when the Row isn't already
stretched to fill everything. Removed `fillWidth`, kept `alignment`.

Second: ambxst's real metadata block is three lines (title bold,
album, artist -- both secondary dimmer), confirmed directly in
`FullPlayer.qml`. We had two (title, artist) -- album was missing
entirely, not just out of order. `activePlayer.trackAlbum` was
already exposed as a real MPRIS property elsewhere in this project
(`ruixen-tray-widgets`' own `media/Service.qml` already computes an
`album` property from it) -- just never threaded through this notch.
Added `root.album` in `Overlay.qml` (same pattern as `title`/
`artist`), passed through to `DashboardContent`, added a third `Text`
line matching the same visibility-gated-on-non-empty pattern the
other two already use.

## Half-circle progress ring arcing over the album art disc

Per direct request ("the wave from the compact notch... just the same
thing but on bended half-ish circle"): checked ambxst's real
`CircularSeekBar.qml` first. Their version is genuinely heavy --
`QtQuick.Shapes` (`PathAngleArc`/`PathPolyline`), draggable seeking, a
dashed/marquee mode, a handle indicator. Ported just the visual result
with a `Canvas` instead (`CircularSeek`, new shared component next to
`QuickToggle`) -- same sine-perturbation-redrawn-every-frame technique
`WavyLine` already uses in `Overlay.qml`, just applied to an arc's
radius instead of a straight line's y-offset, only animating
(`FrameAnimation`) while `root.isPlaying`.

`startAngle: Math.PI, spanAngle: Math.PI` isn't arbitrary -- in Canvas
angle convention (0 = 3 o'clock, clockwise), that sweeps left ->
top -> right, i.e. literally the top half of a circle, matching
ambxst's own values and "arcs over the top" geometrically. The disc +
ring now share one `100x100` container, both centered -- the ring's
radius is bigger than the disc's `80x80`, so it physically arcs over
the disc's own top edge instead of sitting as a separate element. The
old flat linear progress `Rectangle` row is gone, replaced entirely by
this ring.

## Player content block: actually centered vertically

Per direct feedback: the disc/title block sat pinned to the very top
(no top padding) while the transport controls landed right at the
card's bottom edge. First attempt paired the existing bottom
`Layout.fillHeight` spacer with a matching one above the disc,
assuming `ColumnLayout` would split leftover space evenly between
them -- it didn't (still visibly bottom-heavy after), and a follow-up
`anchors.bottomMargin` bump barely moved anything against a ~250px
gap. Replaced both fillHeight spacers entirely: the whole content
block (disc, title/artist, a small fixed `12px` gap, transport row)
now lives in one inner `ColumnLayout` with `anchors.centerIn: parent`
on an outer plain `Item`, instead of fighting `ColumnLayout`'s own
flex-space distribution. Centers the whole group as one unit,
predictably, real padding on both sides.

## Sharp-edge accent ring added

The "border" the user kept describing across this whole saga turned
out to be a real detail in ambxst's own `FullPlayer.qml` -- noted on
the very first read of that file, early in this session, but never
actually ported until now. Their player layers a SECOND, full-
resolution (unblurred) copy of the same art/wallpaper on top of the
blurred backdrop, masked with `maskInverted: true` against a
`Rectangle` inset 4px on every side. Inverted means the mask hides the
interior and only lets the sharp image through in the thin ring
OUTSIDE that inset -- a crisp, detailed edge framing a soft blurred
interior, not a flat color border at all.

Ported directly: `playerBgArtFull` (a second `Image`, full `256x256`
`sourceSize` instead of the blurred layer's cheap `64x64`), an
`innerAreaMask` `Item` (`layer.enabled: true`, `visible: false`, same
hidden-mask-source pattern `notchMask` itself already uses) holding
the 4px-inset white `Rectangle`, and a `MultiEffect` with
`maskInverted: true` sourcing the sharp image through that mask.
Rendered correctly on the very first try -- worth noting given the
earlier (now-understood-to-be-misdiagnosed) "new child in a
`layer.enabled` item doesn't render" scare from the cutout saga above;
this is the same shape of code (`layer.enabled` item with a freshly-
added child) and it worked immediately, further confirming that
earlier theory was likely a red herring from comparing the wrong test
states, not a real structural bug.

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

## Disc + progress ring: made bigger

Per direct request ("make the album art circle and progress part, that
top section bigger please, it should be more features") — the centerpiece
of the player card was scaled up: ring container `100x100` -> `140x140`,
disc `80x80` -> `110x110` (`ClippingRectangle`, same component as before),
art `sourceSize` `160x160` -> `220x220` to stay crisp at the new disc size
(kept at 2x disc dimensions, same ratio as before), `CircularSeek.ringWidth`
`4` -> `5` so the arc stays proportionally readable at the bigger radius.
Fits fine inside `playerCard`'s `210px` width (centered content area is
`parent.width - 20` = `190px`, well clear of `140px`). Confirmed via
screenshot, no other layout changes needed — the surrounding `ColumnLayout`
already centers the whole content block as one unit.

## Progress ring: thick tip added at the playhead

Per direct request ("add a thick player tip to the progress bar"): checked
ambxst's real `CircularSeekBar.qml` handle first rather than guessing a
shape. Theirs is a fat radial line straddling the track radius at the
current angle (`ShapePath` from `radius - offset` to `radius + offset`,
`Colors.overBackground`, round cap) — not a dot sitting on top of the
ring. Ported the same idea into `CircularSeek`'s existing `Canvas`
`onPaint` instead of a new `Shapes` element: after the progress arc, if
`value > 0`, strokes one line segment from `r - 6` to `r + 6` at
`endAngle`, `lineWidth: ringWidth * 1.5` (thicker than the ring itself,
matching "thick"), round cap, new `tipColor` property (`#ffffff`, for
contrast against the accent-green progress arc).

Verified with the established art-hardcode test method (no MPRIS art
available at test time) — temporarily pointed `Overlay.qml`'s `artUrl` at
a real local wallpaper file, confirmed via screenshot the tip renders as a
short thick white tick at the true playhead angle, reverted after.

## Ring/tip gap from the disc

Per direct follow-up ("the progress bar and tip is touching the album
art... need more gap"): the tip's outer edge was already computing past
the 140px container's own bounds (`r=65`, tip outer `~74.75` vs a `70`
half-size canvas -- getting cut off at the top) while its inner edge sat
almost flush against the `110px` disc's own edge (`~55` radius vs tip
inner `~55.25` -- effectively zero clearance). Rather than shrink the
disc back down to make room, grew the ring container `140` -> `180` and
added a fixed `-6` extra inset to `CircularSeek`'s radius formula
(`r = min(width,height)/2 - ringWidth - 6`) -- the disc itself is
untouched at `110px`, the ring/tip just got more room to sit further out
from it. Verified via the established art-hardcode test method, real
visible gap between disc edge and the ring's inner edge now, no more
clipping at the canvas's own top edge either.

## Disc bigger, ring untouched, top padding trimmed, real clipping bug found

Per direct follow-up ("you pushed it out too far... gap too far now...
side mask thats clipping over the player headtip and the start and end
of the curve... make the album art circle bigger to get closer to the
current progress bar and remove the top padding"):

**The clipping was real, not a misread.** The previous `-6` inset in
`CircularSeek`'s radius formula left only `~1.25px` between the tip's
sideways extent (its widest point, at the arc's own 9/3 o'clock start/
end) and the canvas edge — visibly close enough to get antialiased away.
Bumped the inset `-6` -> `-9`, giving a real `~4px` margin.

**Fixed the gap by growing the disc, not the ring** — "the progress bar
is almost fine" meant leave `CircularSeek` alone. Container `180` -> `190`
(barely changed, just enough for the bigger inset above), disc `110` ->
`130` (`sourceSize` `220` -> `260`, kept at 2x). Closes the radial gap
from the inner side instead of pushing the ring further out again.

**Top padding**: the semicircle's own topmost point naturally sits
`~14px` below the square container's own top edge (empty space above the
arc that was never anything). Rather than touch the ring's geometry to
remove it, wrapped it in a shorter outer `Item` (`190x160`, `clip: true`)
with the actual `190x190` ring/disc `Item` shifted up inside it
(`y: -18`) — crops the blank strip off while the ring math underneath
stays completely untouched.

**A second real bug found in the process**: the inner `ColumnLayout`'s
own `width: parent.width - 20` (`190px`, playerCard is `210px`) left the
container comfortably inside on paper, but combined with the tight
canvas-edge margin above, was close enough to be part of what read as
"clipping." Widened to `parent.width - 8` (`202px`) as a second layer of
margin, on top of the canvas-level fix.

Verified via the established art-hardcode test method + a zoomed crop
specifically on the arc's start/end points — clean rounded ends, no
clipping, visible-but-modest gap to the now-bigger disc.

## Reverted the top-padding crop -- it clipped the ring itself

Per direct follow-up ("the top part has like a mask thats clipping over
the top of the progress bar"): the crop wrapper added in the previous
pass was wrong. It assumed the topmost pixel ever drawn was the plain
arc's own top point (~14px below the square's top edge, "just empty
space"), and cropped an 18px strip off on that assumption. Actually
wrong -- the thick TIP (the playhead marker) swings further out than
the plain track at progress values near the top of the sweep, reaching
within ~4px of the square's own top edge around 50% progress. An 18px
crop sliced the tip clean off exactly at the progress values where it
swings up that far -- confirmed by forcing `progressRatio: 0.5` (the
worst case) via the same hardcode-and-screenshot method used elsewhere,
which is what should have been tested before the previous commit rather
than only the ~53% case that happened to be showing at the time (close,
but the crop math itself was still wrong for the true worst case).

Reverted to a plain, uncropped `190x190` square -- no `clip`, no `y`
offset, no split wrapper. Re-verified at `progressRatio: 0.5` specifically
(zoomed crop on the tip) -- fully visible, no clipping, this time actually
tested at the worst-case angle instead of whatever the live player
happened to be at.

Lesson for this component specifically: any future padding/crop change
around `CircularSeek` needs to be checked at multiple forced
`progressRatio` values (0, ~0.5, ~1), not just whatever's playing live --
the tip's extent depends on the progress angle, so "looks fine" at one
value doesn't mean it's fine at all of them.

## QA pass: title/transport spacing fixed, transport icons scaled up to the disc

Per direct feedback ("weird spacing... player icons can be bigger too...
match it based on the album art circle size"):

**The spacing bug**: the outer `ColumnLayout` already has `spacing: 8`
applied between every child automatically. A separate `Item {
Layout.preferredHeight: 4 }` spacer sat between the title/album/artist
group and the transport row as its OWN child -- meaning the real gap
there was `8 (before spacer) + 4 (spacer) + 8 (after spacer) = 20px`,
double the `8px` gap used everywhere else in this column (disc-to-title
is a plain `8px`, no extra spacer). That mismatch is what read as
"weird" -- not that any one gap was wrong in isolation, but that this
one gap didn't match its neighbors. Deleted the spacer entirely; the
title-to-transport gap is now the same `8px` the rest of the column
already uses.

**Icons scaled to the disc**: the disc grew `80px -> 130px` across
several earlier passes but the transport row was never revisited, so it
stayed sized for the original small card. Play/pause grown `34x34 ->
44x44` (`radius: 8 -> 11`, keeping the same `size/4` proportion) --
`44x44` isn't arbitrary, it's ambxst's own real `playPauseBtn` dimension,
noted early in this project's history but never actually matched since
our version stayed smaller. Prev/next glyphs and row spacing scaled by
the same ~1.3x factor the play/pause button grew by: `14px -> 18px`
glyphs, `18px -> 22px` row spacing (a bit more breathing room needed
between the now-physically-bigger elements).

## Real remaining gap found: the container's own dead space below the disc

Per direct follow-up ("still think the song title group is far from the
circle"): the `8px` `ColumnLayout` spacing fixed in the previous pass was
correct, but it wasn't the actual source of most of the gap. The disc/
ring `Item` is a `190x190` square with the `130px` disc centered inside
it -- disc bottom sits at a fixed `y=160` (95 center + 65 radius), which
leaves `30px` of genuinely empty container space below the disc before
the `8px` layout spacing even starts. That dead space, not the spacing,
was most of what read as "far."

Cropped it this time using the bottom, not the top -- the earlier top-
crop attempt (see above) was reverted because the thick tip swings up
into that zone depending on progress angle. The bottom is provably safe
instead: `CircularSeek`'s sweep is `startAngle: PI, spanAngle: PI`, i.e.
angle always in `[PI, 2*PI]`, where `sin(angle) <= 0` for the entire
range -- the ring and its tip mathematically never draw below the
container's own vertical center, at any progress value. Only the disc's
own (fixed-position) lower half lives in that zone. Wrapped the
`190x190` content in a shorter `165px`-tall `Item` with `clip: true` --
trims `25` of the `30` dead pixels, leaves a small `5px` buffer under the
disc, and is safe unconditionally rather than needing a "looks fine at
this progress value" check.

Verified at `progressRatio: 0.99` (the opposite-side worst case from the
one that broke the top-crop) via the same hardcode-and-screenshot method
-- tip fully intact, real visible reduction in the gap to the title
group.

## Sharp-edge accent ring: corners weren't actually rounded

Per direct feedback ("the inner border... missing the rounded corner...
looks like a straight corner card"): `playerCard` was a plain `Rectangle`
with `clip: true`, `radius: 10` -- the exact same gotcha already
documented in this file for the album art disc (`Rectangle.clip` only
clips children to the bounding BOX, ignoring `radius`, no matter how
it's set). The accent ring's inner edge (from `innerAreaMask`'s inset
rectangle) WAS correctly rounded, but its outer edge was whatever
`playerCard`'s own unclipped rectangular bounds happened to be --
literally square, since nothing was actually enforcing the rounded
shape on the layered `MultiEffect` output. Two different roundnesses on
the same ring is exactly what reads as "straight corners."

Fixed the same way as the disc: swapped `playerCard` from `Rectangle` to
`Quickshell.Widgets.ClippingRectangle` (dropping the now-redundant
`clip: true`), so every child layer -- blur backdrop, sharp accent ring,
content -- is genuinely clipped to the rounded shape instead of just the
bounding box. Verified via a zoomed crop on the card's own top-right
corner -- visibly rounded now, matching `radius: 10`.

## Horizontal padding for long title/album/artist text

Per direct feedback ("text looks ugly when it gets so close to the
edge... even truncated"): the metadata `ColumnLayout` (title/album/
artist) was `Layout.fillWidth: true` with no margin, so its `Text`
children's `elide: Text.ElideRight` ellipsis could land with only
`~4px` of natural clearance from `playerCard`'s own edge (`210px` card,
`202px` inner column). Added `Layout.leftMargin: 10` /
`Layout.rightMargin: 10` to the metadata `ColumnLayout` itself -- one
change insets all three lines at once, rather than repeating margins on
each `Text`.

Verified with a deliberately long fake title (temporarily hardcoded
`Overlay.qml`'s `title` property via the usual test method) -- the
ellipsis now sits with real breathing room from the rounded corner
instead of crowding it.

## A bit more gap between transport row and duration text

Per direct feedback: added `Layout.topMargin: 4` to the duration `Text`,
on top of the `ColumnLayout`'s own `8px` spacing (`12px` total) --
targeted at just this one gap rather than bumping the shared `spacing`
value, which would've widened every gap in the column equally.

**Follow-up: still wanted more.** Bumped `Layout.topMargin` `4` -> `10`
(`18px` total gap now) per a second round of the same feedback.

## Grey track no longer bleeds through the wavy progress arc

Per direct feedback ("like the compact notch, the grey bar line after
the waves goes over it needs to like hide itself, no tail"): `CircularSeek`
was drawing the grey track for the FULL span first, then the wavy green
progress stroke on top. Since the wave's radius wobbles around the
track's own radius `r` (the sine perturbation), the green stroke doesn't
sit exactly on top of the grey arc at every angle -- wherever the wave's
radius differs from `r`, a sliver of the grey track underneath was still
visible, reading as a "tail" trailing the wave.

The compact notch's own linear `WavyLine` (in `Overlay.qml`) never has
this problem because it's structural, not a draw-order trick: its
`Canvas` width IS `parent.width * progressRatio`, so the dim track
`Rectangle` drawn alongside it only ever covers what's actually
unplayed -- there's no full-length grey layer for the wave to imperfectly
cover in the first place. Matched the same idea in `CircularSeek`:
the grey track now draws from `endAngle` (the progress boundary) to the
sweep's end, not from `startAngle`, so it never occupies the played
region where the wave lives.

Verified at a forced `progressRatio: 0.55` (deliberately mid-sweep,
where the wave's wobble is most visible) via a zoomed screenshot crop --
clean boundary right at the tip, no grey visible along the wave's
length.

## Compact notch progress line thickened

Per direct feedback ("isnt really thick enough... more comfy"): the
collapsed notch's mini progress indicator (`collapsedContent` in
`Overlay.qml`) had the dim track, `WavyLine`, and playhead all at a thin
`2px`. Bumped all three to `4px` together (track `height: 2 -> 4`,
`radius: 1 -> 2`; `WavyLine.lineWidth: 2 -> 4`; playhead `width: 2 -> 4`)
so they stay visually consistent with each other rather than drifting
out of proportion. Confirmed via screenshot on the live collapsed notch
(no pin/hover toggle needed, this is the default at-rest state).

**Follow-up: top/bottom of the wave were getting clipped.** Real bug,
not cosmetic -- `WavyLine` is a `Canvas`, and content drawn outside its
own item bounds is simply never rendered (an implicit clip, reads the
same as a mask even though it isn't literally one). The wrapping `Item`
was still `height: 12` from before the thickness bump. At the new
`lineWidth: 4` / `amplitudeMultiplier: 1.4`, the wave's peak extent is
`+-(amp + lineWidth/2) = +-7.6px` from center -- needs `>=15.2px` of
height, and `12px` was already too short even before accounting for
that. Grew the container `12px -> 20px`. Verified via screenshot -- full
crests and troughs render now, nothing cut off top or bottom.

**Follow-up: the track was fine, wave/playhead read a bit too thick.**
Per direct feedback, toned `WavyLine.lineWidth` and the playhead
`Rectangle`'s `width` back down `4 -> 3`, left the track `Rectangle` at
`4`. The `20px` container has plenty of headroom for the smaller wave
extent now (`+-(amp+lineWidth/2)` drops to `+-5.7px`), no clipping risk.

## Empty-state (no media) no longer collapses the whole card

Per direct feedback ("keep all the stuff shown so it doesnt get jumpy"):
the disc/ring `Item` had `visible: root.artUrl !== ""`, and the album/
artist `Text` lines had `visible: root.hasMedia && ...` -- with nothing
playing, the whole card shrank down to just a title line, then popped
back to full size the instant something started playing. Made every
piece of the card always-visible and always-sized the same regardless
of `hasMedia`:

- **Disc art**: now sources `playerCard.playerBgSource` instead of
  `root.artUrl` directly -- that property already resolves to the
  desktop wallpaper when there's no track art (added earlier for the
  blurred backdrop), so the disc just shows a crop of the wallpaper when
  idle instead of being hidden.
- **Title**: `"Nothing Playing"` instead of `root.displayedTitle`
  (`user@host` -- that fallback exists for the COLLAPSED notch's own
  title, not this dashboard, and reads wrong here).
- **Album / artist**: made-up placeholder text per direct request --
  `"Enjoy the Silence"` / `"White Noise"` -- shown unconditionally when
  idle instead of being hidden.
- **Duration**: already handled correctly (`"--:-- / --:--"` when
  `!hasMedia`), no change needed there.
- **Ring/transport/play-icon**: no changes needed -- `progressRatio`
  naturally computes to `0` and `isPlaying` to `false` when there's
  really no active player, which already renders as an empty grey ring
  and a plain play glyph with no extra logic required.

Verified two ways: first with only `hasMedia` hardcoded to `false` (a
real player was still active in the background, so `progressRatio`/
`isPlaying` leaked through from it -- a testing artifact, not a bug,
caught immediately from the ring showing a stale full progress arc);
then with `isPlaying`/`progressRatio` also forced to `false`/`0` to
simulate a genuinely idle state -- empty ring, play (not pause) icon,
wallpaper crop in the disc, all three placeholder lines, `--:-- / --:--`.
Matches the actual "nothing playing at all" case correctly.

## Playhead tip always visible, artist placeholder becomes a braille spinner

Two follow-ups on the empty-state work above, per direct feedback:

**Tip at value 0**: `CircularSeek`'s tip was gated on `clamped > 0`, so
it fully disappeared in the idle state (`progressRatio` is `0` with no
active player). Per direct request ("keep the playtip head at the head
of the progress bar when theres nothing playing"), removed the gate --
the tip now always draws, sitting right at the arc's own start point
(`endAngle === startAngle`) when `clamped` is exactly `0`. No behavior
change for real playback, which already had `clamped > 0` almost all the
time anyway.

**Artist placeholder**: first tried wiring up the real Omarchy version
(matching fastfetch's own "OS: Omarchy 4.0.0-1" line, via
`omarchy-version` -- the same CLI fastfetch itself shells out to) as a
more "real" placeholder than the made-up "White Noise". Scrapped before
finishing, per direct follow-up ("fuck nvm maybe thats too much") in
favor of an animated braille spinner instead ("some braille stuff we can
do that animates in one row that might be cooler"). First implementation
used ONE braille character bumped to `16px` + bold (braille glyphs are
near-invisible at the shared `10px` size otherwise, each dot only a
fraction of the cell) -- wrong shape of animation per the immediate
follow-up ("taking too much space... multiple braille patterns looping
in one row, not really a big braille... like ascii art pattern").

Rebuilt as an actual row: `brailleCells: 6` fixed-width string rebuilt
every tick, one "lit" cell (`"⣿"`, a full block) at the scanning
position and dim resting dots (`"⠂"`) everywhere else -- a small
Cylon/KITT-style scanner instead of a single spinning glyph, back at the
same plain `10px` the album/artist lines already use (the `16px`/bold
override was removed along with the single-glyph approach). Position
ping-pongs `0..5..0` (`brailleStep % braillePeriod`, reflected back
instead of wrapping) so the lit dot visibly scans back and forth. `Timer`
interval bumped `90ms -> 110ms` to match the calmer sweep.

**Follow-up: slowed further, three times more.** Per direct feedback,
`110ms -> 220ms`, then `220ms -> 450ms` (still too fast), then
`450ms -> 1200ms` ("much slower, more like ambient"), then landed on
`1200ms -> 1000ms` ("like a second each movement") -- an exact, literal
number this time rather than another "slower" guess.

**A real process gap, caught mid-investigation**: the next "still too
fast" report turned out to be partly caused by me forgetting to actually
run `omarchy restart shell` after two of the interval edits above -- the
plugin was re-validated and synced but the LIVE shell process kept
running the old QML, so the user was legitimately seeing a stale, faster
interval than what was actually committed. Investigated properly this
time: set `interval: 3000` (a deliberately distinguishable value) plus a
timestamped `console.log` in `onTriggered`, restarted, and let it run --
screenshot sampling at 1s cadence was too noisy to fully confirm exact
timing (`grim` + shell overhead adds real jitter to sub-second
measurements), but confirmed the Timer does hold each position for
multiple consecutive seconds rather than advancing every tick, i.e. no
double-speed/duplicate-Timer bug. Reverted the diagnostic `3000ms` +
`console.log` back to the last real value (`1000ms`) once satisfied
there wasn't a structural bug -- likely just discrete single-cell jumps
reading as "fast" regardless of the literal interval, a perception
issue rather than a timing one.

**Resting-dot glyph fixed for symmetry**: per direct feedback ("the
middle line instead of just 1 dot is there 2 middle dot we can use, it
looks lopsided cause the scanner has 4 dots") -- resting cells used
`"⠂"` (a single dot sitting in just the left half of the cell), which
read as lopsided next to the active cell's full `"⣿"` block. Swapped to
`"⠒"` (dots 2+5, a horizontally-centered pair spanning the full cell
width, the same glyph the "flatline" reference pattern discussed earlier
in this session uses) -- resting cells now read as an even dotted line
instead of an off-center smear.

Verified twice: first that the ROW actually renders as 6 small dots at
the right size (zoomed crop), then that it's genuinely animating -- two
screenshots ~400ms apart show the lit cell at different positions in the
row, confirming the scan is actually moving rather than static.

## Accent color switched to follow the active theme

Per direct question-then-request: `textColor`/`muted` were already
theme-linked (`Color.bar.text`, itself sourced from `theme/colors.toml`
+ `theme/shell.toml`), but `accent` -- the green driving the wave,
playhead, play/pause chip, quick-control toggle "on" state, and the
calendar's today-highlight -- was a fixed `#3ecf5b`, deliberately kept
separate from theming as a semantic "media active" color matching
`ruixen.media`'s own badge.

Per direct follow-up ("can we try the accent color to follow the
themes... so they match too"), switched to `Color.accent` -- confirmed
in Omarchy's own `Commons/Color.qml` (`loadColors()`) that this is real
theme data, not a static default: it's read directly from
`theme/colors.toml`'s own `accent` key, falling back to `color4` if a
theme doesn't define one. One property change cascades everywhere
already, since every consumer already reads through the existing
`accent: root.accent` passthrough to `DashboardContent` -- no other
files needed touching.

Verified against the live active theme (Everforest-ish, real
`colors.toml` accent `#7fbbb3`, a teal -- visibly different from the old
hardcoded green) via screenshot: play/pause chip, quick-control toggles,
and the calendar's today-circle all picked up the new color consistently.

## Calendar chevrons switched to the accent token too

Per direct follow-up: the `<`/`>` month-navigation chevrons were
`color: root.textColor` (plain theme foreground, same as the title
text next to them). Switched both to `root.accent`, matching the
now-theme-linked accent used everywhere else on the dashboard.
Verified via screenshot -- both chevrons render in the theme's teal.

## Calendar header grown, day-grid shrunk to rebalance emphasis

Per direct feedback ("the calender month year and chevlon [row], can we
increase the size... make the calender like below abit smaller, right
now the M T W T F takes too much of the attention"):

- **Header row**: `28px -> 36px` height, title text `13px -> 16px`,
  chevron pills `28px -> 36px` wide, chevron glyphs `14px -> 16px`.
- **Day-grid panel**: `268px -> 230px` overall height, weekday labels
  (`M T W T F S S`) `13px -> 10px` (this was the specific thing reading
  as too loud), week-row height `30px -> 26px`, today-circle
  `26px -> 22px`, day-number text `11px -> 10px`.

Net effect: the title/navigation row now reads as the visually dominant
piece, with the grid below sized more like supporting detail instead of
competing for the same attention. Verified via screenshot.

**Follow-up: weekday labels bumped back up a touch.** Per direct
feedback ("the calender ends abit too early, make the M T W T a bit
bigger to compensate") -- the day-grid was now ending early within
calendarPane's available height. `10px -> 12px` on just the weekday
label row (row height/today-circle/day-number left alone).

**Follow-up: font nudge wasn't nearly enough, gap still very visible.**
A 2px font bump on one row can't close a real ~30px layout gap -- traced
it properly this time by sampling actual rendered pixel colors down the
column (`magick ... txt:`) instead of guessing another font size. Found
the real cause: the day-grid shrink (`268px -> 230px`, a `-38px` change)
didn't account for the header growing `+8px` (`28px -> 36px`) in the
same pass -- together that's a `-30px` net loss in `calendarColumn`'s
total content height, which shows up as exactly that much extra grey
gutter below the day-grid. Fixed by solving for the height that restores
the ORIGINAL total: `margins(8) + header(36) + spacing(4) + daygrid(X) =
308` (the original working total, `8+28+4+268`) gives `X = 260`. Set
`230px -> 260px`. Verified the same way -- resampled pixel colors down
the column, black day-grid panel now runs most of the way down
`calendarPane` with just a small, consistent margin left, not a visibly
separate grey band.

## Today's weekday letter reads brighter

Per direct request: added `calendarPane.currentDayOfWeek` (Monday-first
index, `0..6`, matching the `M T W T F S S` label order -- JS `getDay()`
is Sunday-first so `(today.getDay() + 6) % 7` shifts it; `-1` when
viewing a different month, same guard the day-cell `isToday` check
already uses). The matching weekday `Text` now uses `root.textColor`
(full brightness) instead of `root.muted` when its `index` matches,
everything else stays dim. Verified via screenshot -- today is Saturday
in the current test, and the "S" label reads bright while the rest stay
muted, lining up with the accent-highlighted day cell below it.

## Companion setup

- **[`ruixen-tray-widgets`](https://github.com/gitcoder89431/ruixen-tray-widgets)**
  — `ruixen.media` (must stay *enabled*, see gotcha above) and
  `ruixen.dnd` for the notification-state data this notch displays.
- **[`ruixen.frame-widget`](https://github.com/gitcoder89431/ruixen-frame-widget)**
  — the notch is positioned/colored to visually weld into this frame's
  top border.
