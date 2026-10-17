# Ruixen Launcher

A Raycast/Spotlight-style command palette — one overlay for running Omarchy
menu actions, launching installed apps, and searching your filesystem by
name or content.

Default install leaves Hyprland keybindings alone, but
`./install.sh --with-launcher-keybind` adds `SUPER + R` for Launcher and
`SUPER + SHIFT + R` for Settings when those keys are free. See
[`KEYBINDS.md`](KEYBINDS.md) for the manual recipes.

```bash
omarchy-shell shell toggle ruixen.launcher
```

## Applications and Commands

Typing with nothing else selected searches two things at once, ranked
together in one flat list: installed apps (real desktop entries) and
Omarchy menu actions (theme changes, window management, lock, screenshot,
anything in Omarchy's own menu). An empty query shows a curated
Suggestions list plus the full Commands catalog below it.

Existing Omarchy keybinds show as key-cap chips next to a row when one's
configured, and jump straight to it — no separate trip to Omarchy's own
keybindings menu needed.

## Search Files

Typing a query that doesn't match any app/command always leaves a **Search
Files** row at the bottom (`Use "..." with`) — select it (or just keep
typing and press Enter on it) to switch into Search Files mode. The card
widens and splits into a result list (left) and a metadata/preview panel
(right) for whichever result is selected.

- **Filenames and folders** are searched via `fd`; **file contents** via
  `ripgrep` — both run together, content matches ranked below filename
  matches so a query with real filename hits reads exactly as before, and
  a query with none falls through to content matches instead of a dead
  "No Results".
- **Multi-word queries work across path components**, not just the
  filename — `ruixen readme` finds `~/Projects/ruixen-shell/README.md`
  even though neither word alone is the whole filename.
- The **source picker** (top right, "All Sources" by default) restricts a
  search to one specific drive — every auto-discovered mount (an internal
  drive, a plugged-in USB stick) shows up here automatically.
- Selecting a result shows a real preview (an extracted video frame, an
  image thumbnail, or a text/markdown/JSON snippet) plus metadata — type,
  dimensions/duration, size, location, created/modified, permissions.

Press the back-arrow (left side of the search box) or `Escape` to drop
back out to Applications/Commands; `Escape` again dismisses the whole
launcher.

### Filters

A row of controls appears under the search box once you're in Search
Files:

| Control | What it does |
|---|---|
| **Type** | Click to cycle through file categories: All → Folders → Documents → Images → Video → Audio → Archives → Code/Text → back to All |
| **Both / Names / Contents** | Restrict the search to filenames only, contents only, or both (the default) |
| **Hidden** | Off by default (dotfiles/dotdirs excluded, same as `fd`/`rg`'s own convention) — click to include them. `.git` internals stay excluded either way |

These persist for the rest of the session (they don't reset when you
close and reopen the launcher), independent of whichever query you're
currently typing.

### Query operators

Prefer to stay on the keyboard? Type filters directly into the search
box instead of clicking the row above — same effect, scoped to that one
query:

```text
type:image sunset          # only Images matching "sunset"
kind:folder projects       # kind: is an alias for type:
in:Home invoice            # scope to one specific source by label
in:"Work Drive" report     # quote a label that has spaces in it
name:architecture          # Names-only scope, "architecture" as the query
content:candidateBudget    # Contents-only scope
hidden:true ssh            # include hidden files for this one query
```

An operator overrides the corresponding filter-row control only for as
long as it's present in the query — delete it and the search reverts to
whatever the filter row is currently set to. An operator with no real
match (an unrecognized category, a source that doesn't exist) or a typo'd
key (`fyle:` instead of `file:`) is treated as ordinary literal search
text instead of silently doing nothing, so a mistyped operator never
looks like the launcher just ignored your query.

## Contextual actions

Every Search Files result has a small action menu beyond the default
Enter-to-open:

- **Tab** opens it for whichever row is currently selected.
- **Right-click** a row to open it for that row directly (left-click
  still opens it, same as Enter).

The menu appears right under the row it's for, matching its width.
Up/Down navigate it, Enter runs the highlighted action, Escape closes it
without exiting Search Files.

Available actions (folders get one extra):

- **Open** (or **Open Folder**) — same as pressing Enter on the row
- **Search Inside This Folder** *(folders only)* — scopes the current
  session to that folder, session-only; `Escape` afterward restores
  whichever source was selected before
- **Open Containing Folder** — opens the real parent directory in your
  file manager
- **Copy Path** / **Copy Name** / **Copy Parent Directory Path** — copies
  the exact real value, never the abbreviated `~` form shown in the
  metadata panel

## Clipboard History

An extension (open it from the empty-query list, or with
`'{"extension":"clipboard"}'` — see [`docs/KEYBINDS.md`](KEYBINDS.md))
that lists Omarchy's clipboard history (`~/.local/state/omarchy/clipboard-history.json`)
with a preview and metadata panel. It reuses Omarchy's own paste/open
helpers rather than a second clipboard backend.

| Key | Action |
| --- | --- |
| `Enter` | Copy the highlighted entry |
| `Alt+C` | Copy the highlighted entry |
| `Alt+O` | Open |
| `Alt+P` | Copy an image's file path |
| `Alt+D` | Delete (press twice to confirm) |
| `Alt+R` | Reveal / hide a masked possible secret |
| `Alt+I` | Pin / unpin |

Text entries are sorted into kinds, each with its own icon and metadata:
**Link** (host, scheme, parameter count), **Color** (hex/rgb()/hsl() with a
swatch and converted values), **Email** (domain; Open uses `mailto:`),
**Path** (name, extension, and whether it exists; Open uses `xdg-open`),
**JSON** (object/array summary, pretty-printed preview), and plain text
(characters, words, lines). Anything shaped like a credential (known token
prefixes, JWTs, private keys, or a long high-entropy string) is a
**Secret**: its row and preview are masked until revealed, and its text is
not searchable. This is a heuristic for masking only — it never blocks
copying or pasting.

A chip row above the list filters and sorts it: **Type** cycles through the
kinds actually present (right-click resets to All), and **Recent** / **By
Type** pick the sort — clicking the active one flips its direction. By Type
also groups the list under per-kind headers.

Delete rewrites the history file atomically and matches the entry by
identity, not position; an entry that has changed or vanished since it was
drawn is left alone. Deleting an image also removes its file from
`clipboard-images` if no other entry uses it.

Pinning keeps an entry in its own **Pinned** section at the top of the
list, ahead of the Recent/By Type sort — a separate, Ruixen-owned layer
(`~/.local/state/ruixen/clipboard-pinned.json`), not Omarchy's own
history. Omarchy's own clipboard watcher caps that history at 300
entries and silently drops the oldest once it's full, with no pin
concept of its own; a pinned entry keeps showing (and stays pasteable)
even once Omarchy's own cap has pushed it out of the live file. Deleting
a pinned entry also unpins it.

## Bjarneo Themes

An extension (open it from the empty-query list, or with
`'{"extension":"theme-browser"}'` -- see [`docs/KEYBINDS.md`](KEYBINDS.md))
that browses and installs several of bjarneo's community Omarchy theme
collections, left list + right preview, same two-panel shape Settings
and Clipboard History use. `Enter` installs the highlighted theme (or
switches to it directly if it's already installed); `Tab` opens an
actions menu with the same choice plus **Pin**/**Unpin** and
**Uninstall** (once installed).

Pinning puts a theme in its own **Pinned** section at the top of the
list, still subject to whichever Name/Style sort and Collection/Style/
Installed filter is active -- a plain preference layer
(`~/.local/state/ruixen/theme-browser-pinned.json`), not a "survives
deletion" one the way Clipboard's own pin had to be: the theme catalog
itself never disappears out from under it.

## Cliamp Radio

An extension (open it from the empty-query list, or with
`'{"extension":"cliamp"}'` — see [`docs/KEYBINDS.md`](KEYBINDS.md)) that
browses and plays Omarchy's bundled `cliamp` radio directory from a list
instead of its own TUI. Talks to the real `cliamp` daemon over its own
IPC socket (starting one headlessly on first use if none is running) —
no second radio backend.

- Leave the search box empty for the curated station catalog; any
  favorited station groups into a **Favorites** section at the top
  (only appears once you have at least one), including a station only
  ever reachable via search and never in cliamp's own curated catalog
  at all. Type to search the worldwide station directory by name
  instead.
- **Enter** or click a row to play it — on whichever row is actually
  playing right now, the same Enter/click pauses it instead of
  restarting the stream.
- **Tab** or right-click opens a row's actions: **Play** (relabels to
  **Pause** for the row actually on air), and **Favorite**/
  **Unfavorite** for every row, catalog or search hit alike. Favoriting
  runs through this plugin's own small local store
  (`~/.local/state/ruixen/cliamp-favorites.json`), not cliamp's native
  favorites — cliamp's own `provider.favorite` only ever takes a
  catalog id, which a raw search result never carries, so there's no
  single favorite operation that can reach both; this plugin keeps one
  consistent star everywhere instead of two different ones. Favorites
  set here won't show starred in cliamp's own TUI as a result.
- The right-hand panel shows details for whichever row is selected
  (country/bitrate, parsed out of cliamp's own station name — it has no
  separate fields or station art for these; a "Last Played" field once
  a station's been played at least once from here), plus a featured
  "Now Playing" card for whatever's actually on air.

No transport controls here on purpose: cliamp exposes itself over MPRIS
the moment it's running, so the notch's own media widget already
plays/pauses/skips it like any other player — this extension's job is
picking what plays, not a second set of buttons for controlling it.

Radio is the only cliamp provider this extension drives today — your
own library, playlists, and the other streaming providers cliamp
supports stay in cliamp's own TUI for now.

## Wallpaper Shuffle

An extension (open it from the empty-query list, or with
`'{"extension":"wallpaper-shuffle"}'` — see
[`docs/KEYBINDS.md`](KEYBINDS.md)) that owns rotation's own queue —
both WHICH artwork plays next and WHETHER/how often it advances.
Separate from the **Wallpapers Effects** extension (appearance/
transition/effect controls, plus its own grid layout, which doesn't
fit a reorderable list). Lists every image, GIF, and video in
`~/Pictures/ruixen-wallpapers` (the same folder rotation already reads
from — no folder picker here), each with its own left-edge icon (a
distinct glyph per image/GIF/video, current/ignored taking priority
over that), a live preview on the right, and a checkmark on whichever
one is actually playing right now.

A two-part chip row sits above the list:

- **Shuffle On/Off** — a toggle pill. Click to flip it; turning it
  back on resumes at whichever interval was last set, same as turning
  it off always remembers it.
- **5m / 15m / 30m / 60m** — pick an interval directly; picking one
  also turns Shuffle on with that interval highlighted.

Rotation steps through this list in order (current always moves to the
front, the one that just retired to the back) rather than picking
randomly — the queue you see here is genuinely what plays next, not
just a display of something else's own random pick. The search box's
own Enter-hint chip doubles as a live countdown to the next rotation
while this extension is open ("4:32"), or reads **Paused** whenever
Shuffle is off (or, rarer, something outside rotation is mid-playback —
see [`CONTROL.md`](CONTROL.md#wallpaper-rotation-ruixen-wallpaper-rotation)).

- **Enter** or click a row to set it as the wallpaper right now — this
  also re-anchors the queue (that pick moves to the front) and clears
  any pause, exactly as if rotation itself had picked it.
- **Tab** opens that row's actions, in priority order: **Move up** /
  **Move down** (only the directions actually legal from that position
  are shown) — **Ignore** (excludes it from rotation's own candidate
  pool entirely, both the live queue and the actual pick; still listed
  here, with its own icon, so there's a way back to Un-ignore it) — and
  **Set as wallpaper** last, the same action Enter already does, kept
  reachable here too.

Reordering writes `~/.local/state/ruixen/wallpaper-order.json` directly
(plain filenames, no IPC round-trip) — the same file
`ruixen.wallpaper`'s own rotation reads and reconciles against the live
folder on every pick: your explicit order wins, a file that's been
removed drops out silently, and a new file not yet in the order appends
at the end rather than breaking the sequence. Ignoring writes
`~/.local/state/ruixen/wallpaper-ignored.json` the same way.

## Kanban Board

An extension (open it from the empty-query list, or with
`'{"extension":"kanban"}'` — see [`docs/KEYBINDS.md`](KEYBINDS.md)) over
the same board the notch's own Kanban dashboard tab reads and writes —
`~/.local/state/ruixen/kanban-store.json`. Both surfaces show the same
live data; this one is read-only on disk (watches the store file for
changes but never writes it directly) and makes every change exclusively
through the notch's own `kanbanAddCard`/`kanbanAdvanceCard`/
`kanbanRegressCard`/`kanbanSetPriority`/`kanbanRenameCard`/
`kanbanSetDescription`/`kanbanDeleteCard`/`kanbanReorderColumn` IPC ops
— see [`CONTROL.md`](CONTROL.md) and [`AGENT.md`](AGENT.md) for the
full op list, including the agent-driven reorganize workflow.

Cards are listed left-to-right by column (**Todo**, **In Progress**,
**Done**, in that fixed order — columns themselves aren't renameable
here, only their display labels, from the notch side), sectioned with
the same plain muted header style used elsewhere in the launcher. Each
row's own left-edge icon is a dot tinted by priority (red/yellow/muted
for high/medium/low), swapped for a green checkmark once a card reaches
Done — same visual language the notch's own Kanban panel already uses
for this. The right-hand panel shows the selected card's title, then —
if it has one — a word-wrapped **Description** block right underneath
(expanded here, unlike the notch's own compact single-elided-line
treatment of the same field, since this panel has the room), then
column, priority, label, due date (overdue dates shown in red), and
created time.

A **Column** and **Priority** chip sit above the list, same cycling-pill
shape as Bjarneo Themes' own Collection/Style chips — click to cycle
through All → Todo → In Progress → Done (or All → High → Medium → Low),
right-click either one to jump straight back to All. These narrow which
rows show on the left; there's no separate sort chip, since each
column's own order (manual, once an agent or `kanbanReorderColumn` has
touched it, otherwise priority then age) already is the sort.

- Typing in the search box and pressing **Enter** when nothing matches
  creates a new card in **Todo**, titled with whatever you typed — the
  search box clears once the card exists. This is the only "add"
  screen; there's no separate create form. A trailing `!h`/`!m`/`!l`
  word sets priority (medium if omitted); `--` splits off everything
  after it as the description — e.g. `Fix login bug !h -- breaks SSO
  on Safari`. The hint text under the list previews what Enter will
  actually create.
- **Enter** on an existing row (or a click) advances that card to the
  next column (Todo → In Progress → Done), mirroring the notch panel's
  own click-to-advance behavior.
- **Tab** opens that row's actions, conditionally shown by column:
  **Advance** (any column but Done) / **Regress** (any column but Todo)
  — **Cycle Priority** (high → medium → low → high) — **Rename** (opens
  one inline field in the details panel, same narrow shape as the
  Settings About page's own uninstall-confirm field) — **Add
  Description** / **Edit Description** (same inline-field shape, opens
  right under the title; an empty result really does clear it, same as
  the raw `kanbanSetDescription <id> ""` CLI call) — **Delete**
  (two-step arm/confirm, same shape as Clipboard History's).

Setting a label or due date isn't exposed here yet — use the notch's
own in-panel editor or the raw `kanban*` CLI ops for those.

## Configuring search locations

By default, Search Files walks your home directory plus every
auto-discovered mount. To add a folder outside home, exclude a subtree
entirely, or turn a specific drive off without disabling auto-discovery —
open **Ruixen Settings → File Search** (this plugin's own built-in
Settings extension):

```bash
omarchy-shell shell summon ruixen.launcher '{"extension":"settings","section":"launcher"}'
```

- **Include Home** / **Auto-include mounted drives** — on/off toggles
- **Mounted Drives** — every currently-detected drive, individually
  enabled/disabled. A drive you disable stays listed (marked "not
  currently connected") even after you unplug it, so you can re-enable
  it later without waiting for it to be mounted again
- **Custom Search Roots** — arbitrary extra folders to always search
  (`~/Work`, `/mnt/Documents`, ...)
- **Excluded Paths** — subtrees to never search, regardless of which
  root they're under (`~/VMs`, `~/Downloads/ISOs`, ...)
- **Excluded Directory Names** — patterns applied at any depth across
  every root (seeded with `node_modules`, `vendor`, `target`, `go`,
  `.git` — add your own, e.g. `dist`, `.venv`)

Changes apply immediately — no shell restart needed, and no need to
reopen the launcher.
