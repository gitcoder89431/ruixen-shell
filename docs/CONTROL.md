# Controlling Ruixen Programmatically

Every Ruixen plugin talks over the same mechanism Omarchy's own shell
already uses for its own panels: a local IPC call via `omarchy-shell
<target> <method> [args...]`. This isn't a Ruixen-specific API bolted on
top — it's the same Quickshell `IpcHandler` primitive the whole Omarchy
shell is built on, which means anything on this machine that can run a
shell command can drive these plugins: a keybind, a script, your own tool,
or an AI agent working in the same terminal you already use.

That last one is the actual point. Because control happens over a plain CLI
call instead of a bespoke API, letting an agent manage part of your
workflow (a Kanban board, say) isn't a special integration someone had to
build — it's the exact same command you'd type yourself, put in a keybind,
or call from a script. There's no separate "agent mode."

## The two shapes

**A plugin's own direct target** — some plugins expose their own named
functions on their own IPC target:

```bash
omarchy-shell ruixen.notch toggleLauncher
omarchy-shell ruixen.notch kanbanAddCard "Fix bug" todo high
```

**The generic overlay convention** — "overlay"-kind plugins (like
`ruixen.settings`) also answer to the host's own generic `shell
summon`/`toggle` calls, which accept an optional JSON payload:

```bash
omarchy-shell shell summon ruixen.settings '{"section":"wifi"}'
omarchy-shell shell toggle ruixen.settings
```

A plugin can support either, both, or neither shape — there's no rule that
every plugin must expose the same surface. Discovering what's actually
there: `omarchy-shell shell listPlugins` lists every enabled plugin id;
each plugin's own QML source (`Overlay.qml`/`Settings.qml`, in this repo)
is the real source of truth for which functions its `IpcHandler` exposes —
there's no separate schema doc to fall out of sync with the actual code.

See [`docs/KEYBINDS.md`](KEYBINDS.md) for ready-to-use examples of both
shapes as Hyprland keybinds.

## Worked example: the Kanban board

`ruixen.notch`'s Kanban tab (Todo / In Progress / Done, a 4th dashboard tab
— Tab cycles through all 4, or click the column-icon in the left rail) is a
concrete case of this: every mutation — adding a card, moving it, setting
its priority, renaming a column — is a real IPC call, not a special
AI-only feature. The panel's own UI calls the exact same functions a script
would:

```bash
omarchy-shell ruixen.notch kanbanAddCard "Fix bug" todo high   # priority: high/medium/low, defaults to medium if omitted/blank
omarchy-shell ruixen.notch kanbanMoveCard <cardId> in-progress
omarchy-shell ruixen.notch kanbanSetPriority <cardId> high
omarchy-shell ruixen.notch kanbanRenameCard <cardId> "Fix the other bug"   # no-op on a blank title
omarchy-shell ruixen.notch kanbanSetDueDate <cardId> 2026-09-12   # any Date.parse()-recognized string; "" clears it, an unparseable value is a no-op
omarchy-shell ruixen.notch kanbanSetLabel <cardId> "Github"       # one free-text label per card, not multiple tags; "" clears it
omarchy-shell ruixen.notch kanbanSetDescription <cardId> "Needs review"   # a short second line, always shown elided to one line; "" clears it
omarchy-shell ruixen.notch kanbanRenameColumn todo "Backlog"
omarchy-shell ruixen.notch kanbanRemoveCard <cardId>
omarchy-shell ruixen.notch kanbanListCards                     # whole board as JSON -- read it back from a script just as easily
```

A card overdue (past its due date, and not in the Done column) shows its due
date in red in the panel — Done cards never do, a shipped card is not late.

Titles and descriptions are deliberately short (48 / 60 characters, silently
trimmed rather than rejected) — this board is a glance surface, not a notes
app. Anything more detailed belongs in the terminal or an agent's own
context, not a longer field here.

Board state is a plain JSON file at `~/.local/state/ruixen/kanban-store.json`
— nothing about it is locked to this plugin. Any other tool with filesystem
access can read it directly; writing to it directly also works, but won't
show up live in the panel until it reloads (`FileView.watchChanges` is off
here), so going through the CLI calls above is the reliable way to keep the
panel and an external writer in sync live.

Moving cards around by hand still works too: left-click a card to advance
it (dismisses it once it's in Done, since there's nothing further to
advance to), right-click to send it back a column.
