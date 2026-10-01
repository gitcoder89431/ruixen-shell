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
| `Enter` | Paste the highlighted entry |
| `Alt+C` | Copy only |
| `Alt+O` | Open |
| `Alt+P` | Paste an image's file path |
| `Alt+D` | Delete (press twice to confirm) |
| `Alt+R` | Reveal / hide a masked possible secret |

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
