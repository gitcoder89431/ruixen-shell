# Agent entry point — what you can drive on this machine

Everything here is one IPC call:

```bash
omarchy-shell <target> <function> [args...]
```

That's the same Quickshell `IpcHandler` primitive Omarchy's own panels are
built on — nothing to install, no "agent mode", no separate API. Whatever
the panel's own buttons do, you can do by command, because it's literally
the same function. (`qs ipc call <target> <fn> ...` is the lower-level
equivalent; prefer `omarchy-shell`.)

Board/plugin state is plain JSON under `~/.local/state/ruixen/` — readable
by anything, but **read it back over IPC, not off disk** (see gotcha 5).

## Cross-cutting rules — read these before trusting any output

1. **Arity is enforced, exactly.** Signatures are typed and strict. A call
   with too few or too many args is *refused with an error* and changes
   nothing (`Too few arguments provided (3 required but 2 were provided).`).
   Check the arg count in the table below — "optional" means optional in
   the model, not over IPC.
2. **A bracketed JSON array does not survive the IPC boundary.** It arrives
   torn into N separate arguments and is refused, or silently adds nothing.
   Pass newline-delimited values instead, or repeat the call once per value.
3. **Returns are JSON strings.** Pipe to `jq`. A `{"ok":false}` return is a
   *successful call that did nothing* — check the body, not just the exit
   code.
4. **Silent no-ops vs. hard errors.** Unknown enum values usually fall back
   (bad column → `todo`, bad priority → `medium`) instead of failing. A
   typo'd argument can look like it worked. Verify with a read-back.
5. **State files lag ~400ms** (debounced saves). Adding a card then
   `cat`ing the JSON can miss it. Every `…list`/`status` call below reads
   live in-memory state and is immediate.
6. **Don't write state files directly.** `watchChanges` is off, so it won't
   appear live — and the next panel save silently overwrites it.
7. **Bulk-clears are unfiltered and irreversible.** `kanbanClearDone`
   wipes the whole Done column; `ruixen.shelf clear` drops everything.
   Prefer the per-id `…Remove` calls unless the user really means "all".

## `ruixen.notch` — panels and tabs

The notch at the top-center of the bar. 4 dashboard tabs: `widgets`,
`wallpapers`, `metrics`, `kanban`.

| Call | Notes |
|---|---|
| `openDashboardTab <widgets\|wallpapers\|metrics\|kanban>` | Jump straight to one tab and open. |
| `openDashboard` / `closeDashboard` / `toggleDashboard` | The dashboard itself. Always resets to Widgets. |
| `openLauncher` / `closeLauncher` / `toggleLauncher` | The quick app launcher. |
| `toggleWallpapers` | Wallpapers tab. |
| `refreshAvatar` | Re-read the avatar image. |

## `ruixen.notch` — Kanban board

Fixed 3 columns, ids are permanent: **`todo` / `in-progress` / `done`**
(only the display label is renameable). Priorities: `high`, `medium`, `low`
— that order *is* the sort rank, then oldest-first within a priority. Card
order is computed, never stored.

| Call | Notes |
|---|---|
| `kanbanListCards` | Whole board as JSON. **The read-back.** |
| `kanbanAddCard "<title>" <column> <priority>` | **All 3 args required.** Returns the new card's id — capture it. |
| `kanbanMoveCard <id> <column>` | Absolute move. |
| `kanbanAdvanceCard <id>` / `kanbanRegressCard <id>` | One step, clamped at each end (no wraparound). |
| `kanbanRemoveCard <id>` | Delete one. |
| `kanbanSetPriority <id> <high\|medium\|low>` | |
| `kanbanRenameCard <id> "<title>"` | Blank title = silent no-op. |
| `kanbanSetDueDate <id> <date>` | Anything `Date.parse()` reads (`2026-10-05`). `""` clears; unparseable = no-op. |
| `kanbanSetLabel <id> "<label>"` | One free-text word, not tags. `""` clears. |
| `kanbanSetDescription <id> "<text>"` | Second line, always elided. `""` clears. |
| `kanbanClearDone` | ⚠️ Wipes the entire Done column. No undo, no filter. |
| `kanbanRenameColumn <id> "<label>"` | Label only, never the id. |

```bash
id=$(omarchy-shell ruixen.notch kanbanAddCard "Fix the launcher crash" todo high)
omarchy-shell ruixen.notch kanbanSetLabel "$id" "Bug"
omarchy-shell ruixen.notch kanbanSetDueDate "$id" 2026-10-05
omarchy-shell ruixen.notch kanbanAdvanceCard "$id"    # todo -> in-progress -> done
omarchy-shell ruixen.notch kanbanListCards | jq -r '.cards[]|"\(.column)\t\(.priority)\t\(.title)"'
```

- Free text is **silently trimmed, never rejected**: title 48, label 24,
  description 60 chars. A long title isn't an error, it just gets cut.
  This board is a glance surface — keep detail in your own context.
- Left-click advances / right-click regresses in the GUI too. Overdue
  (past due, not Done) renders red; Done cards never show as late.

## `ruixen.shelf` — the drop pocket

The panel that hangs from the frame at the notch's position; you drag files
into it from any app. It stores **paths only, never copies anything**.

| Call | Notes |
|---|---|
| `list` | `{"items":[{id,path,name,source,addedAt,exists,kind,size}]}` |
| `add <abs-path>` | `{"ok":true,"id":...}` or `{"ok":false,"error:...}` |
| `addMany <paths> <user\|agent>` | **Newline-delimited** — *not* a JSON array (gotcha 2). Returns `{ok,added,rejected}`. |
| `remove <id-or-path>` | By id from `list`, or by path. |
| `clear` | ⚠️ Drops everything. |
| `open` / `close` / `toggle` | The panel itself. |

```bash
omarchy-shell ruixen.shelf addMany "$(printf '%s\n' /abs/a.pdf /abs/b.png)" agent
omarchy-shell ruixen.shelf list | jq -r '.items[].path'
```

`source` is `user` or `agent` — it's metadata only (anything else is
treated as `user`), so don't invent values here.

## `ruixen-media` — music

Note the target is `ruixen-media` (hyphen), while the plugin is
`ruixen.media`. All of these return JSON.

| Call | Notes |
|---|---|
| `status` | `{hasPlayer,playing,title,artist,album,length,position,canSeek,...}`. The "what's playing?" call. |
| `playPause` / `play` / `pause` / `next` / `previous` | Return `ok`, or `unhandled` if the player refused. |
| `runAction <action> <showFeedback>` | `action` ∈ `playPause,play,pause,next,previous`. Anything else = no-op. `showFeedback` = bool. |
| `seek <seconds>` | Absolute position; only if `canSeek`. |
| `sourceNext` / `sourcePrevious` / `sourceSwitch` / `sourceSwitchPrevious` | Switch between multiple active players. |
| `ping` | Liveness check. |

Always `status` first — every action is conditional on what the player
reports it can do, and a refusal is a return value, not an error.

## `ruixen.wallpaper`

| Call | Notes |
|---|---|
| `status` | `{active, video, gif, poster}` |
| `playVideo <path> <generation>` | |
| `playGif <path> <generation>` | |
| `stop <generation>` | |

The service's own `syncPlayer()` is internal (wired to the player's
`playGeneration` signal) and is **not** reachable over IPC — there's
nothing to call for it here.

`generation` is a cross-IPC stale-guard: a call with an **older**
generation than one already accepted is rejected, so rapid calls are
last-action-wins. Pass an increasing number (`$(date +%s%N)`) when firing
several in a row; omit it for a one-off.

## `omarchy.weather` / `omarchy.power` — panels

Both register `omarchy.*` target names (not `ruixen.*` — that's the
plugins' own naming, don't "fix" it).

- Weather: `open` / `close` / `show` / `hide` / `toggle` / `edit`
  (opens the panel and starts editing the location).
- Power: `open` / `close` / `show` / `hide` / `toggle` / `togglePercentage`.

## Scripts

```bash
hyprland/ruixen-lookfeel.sh on|half|off|square|status   # corner rounding + blur
dev/ruixen-bar-mode.sh docked|floating                  # bar mode
./ruixen-doctor.sh                                      # read-only health report
./ruixen-repair.sh --dry-run                            # report what repair would fix
```

`ruixen-doctor.sh` changes nothing. `ruixen-repair.sh` **does** redeploy
plugins — dry-run it and show the user first. (`install.sh`,
`update.sh`, `uninstall.sh` also all take `--dry-run`.)

## More detail

- [`CONTROL.md`](CONTROL.md) — the full per-plugin reference and keybinds.
- [`KEYBINDS.md`](KEYBINDS.md) — binding any of the above to a key.
- Source of truth is the plugin's own `Overlay.qml`/`Service.qml`
  `IpcHandler` block — `grep -A40 'IpcHandler {'` on the plugin is always
  more current than any table above. If they disagree, the code wins and
  this file is what needs fixing.