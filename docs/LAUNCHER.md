# Ruixen Launcher

A Raycast/Spotlight-style command palette — one overlay for running Omarchy
menu actions, launching installed apps, and searching your filesystem by
name or content.

No keybind opens it out of the box (the installer deliberately doesn't
touch your Hyprland config) — see [`KEYBINDS.md`](KEYBINDS.md) for a
ready-to-use recipe (`SUPER + R` by convention throughout this repo's own
docs).

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

## Configuring search locations

By default, Search Files walks your home directory plus every
auto-discovered mount. To add a folder outside home, exclude a subtree
entirely, or turn a specific drive off without disabling auto-discovery —
open **Ruixen Settings → Launcher**:

```bash
omarchy-shell shell toggle ruixen.settings
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
