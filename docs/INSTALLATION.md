# Installing and maintaining Ruixen

Everything about getting Ruixen onto your machine, keeping it current, and
getting back out again. For the two-minute version, see the
[README](../README.md#quick-install). Back to the [manual index](README.md).

## Install

Ruixen targets Omarchy `4.0.0-1` and has been live-verified through
Omarchy `4.0.4-1`.
Install from source:

```bash
git clone https://github.com/gitcoder89431/ruixen-shell.git
cd ruixen-shell
./install.sh
```

An AUR package is planned but not yet published — cloning from source is the
only install path right now.

The installer copies each plugin into `~/.config/omarchy/plugins/`, backs up
anything it would overwrite, merges Ruixen's bar/plugin config into your
existing `shell.json` rather than replacing it outright (any unrelated bar
widgets, plugins, or idle settings you already had survive), applies a
matching Hyprland window look (rounded corners + blur, see below — also
backed up if you already have a `looknfeel.lua`), and restarts the Omarchy
shell.

After installing, add a keybind of your own for opening the Ruixen Launcher
command palette (nothing opens it out of the box — the installer
deliberately doesn't touch your Hyprland config), Ruixen Settings, or
anything else — the app launcher, jumping straight to one settings page. See
[`docs/KEYBINDS.md`](KEYBINDS.md) for ready-to-use recipes, e.g.:

```lua
o.bind("SUPER + R", "Ruixen Launcher", "omarchy-shell shell toggle ruixen.launcher")
```

If you want the recommended keybinds installed automatically, use the opt-in
flag:

```bash
./install.sh --with-launcher-keybind
```

That flag only appends keys that are free: `SUPER+R` for Ruixen Launcher,
`SUPER+SHIFT+R` for Ruixen Settings, `SUPER+CTRL+SPACE` for the wallpapers
picker and `SUPER+D` for the Shelf. If a key is already bound, the installer
leaves that key untouched and prints the current binding.

Want to see exactly what it would do first, without changing anything?

```bash
./install.sh --dry-run
```

Reports Omarchy version/dependency status, plugin manifest validation
(run for real, read-only), which plugins would install fresh vs. replace
an existing copy, whether `shell.json` would be created or merged (and
what would actually change), and the Hyprland look'n'feel plan — then
exits having touched nothing.

### If a previous run was interrupted

An ordinary failure (a bad plugin, `omarchy restart shell` erroring out)
already rolls back cleanly on its own — you'll see that reported and don't
need to do anything special. A hard interruption is different: a closed
terminal, `kill -9`, a crash, or power loss skips that rollback entirely,
since there's no chance for it to run. If `install.sh`, `update.sh` (which
hands off to `install.sh`) or `uninstall.sh`
detects that its own previous run never reached the end, it refuses to
proceed and tells you exactly which step it had reached:

```
refusing to proceed: a previous install run appears to have been interrupted before finishing.
  started: 2026-09-30T03:15:00Z
  reached: 4/7 applying shell layout
```

This is almost always safe to just continue from — every plugin is fully
re-copied from source on each run, and `shell.json`/looknfeel writes are
atomic, so nothing can be left half-written. Run `./ruixen-doctor.sh`
first if you want to double-check (read-only, reports plugin drift and
runtime health), then re-run the same command with
`--acknowledge-interrupted` to continue. All of `install.sh`, `update.sh`
and `uninstall.sh` accept it, and reject any option they don't recognize
(`--help` lists what each takes).

## Updating

```bash
./update.sh
```

`./update.sh --dry-run` previews it first: current vs. candidate revision,
then the same install plan above for whatever is currently on disk
(pulling itself is skipped, so it can't preview code not yet checked out —
noted explicitly in its own output).

Pulls the latest changes and reinstalls — same backup-then-merge
behavior as `install.sh` itself, so it's always safe to re-run. Only
works from your existing cloned checkout (it just wraps `git pull` +
`./install.sh`), so don't delete the folder after installing.

If something looks like it didn't update, or a plugin looks out of
date:

```bash
./ruixen-doctor.sh
```

A read-only diagnostic report — checks nothing changes. Prints your
git status vs the remote, whether each deployed plugin's actual file
content matches this checkout's own source byte-for-byte (catches an
update that silently didn't finish, even when nothing's version number
changed), backup history, the current bar layout (ids only), basic
runtime health, and whether Omarchy's clipboard capture is alive (useful when
Clipboard History shows old entries but never new copies). Safe to paste the output anywhere — no paths,
hostnames, or personal config values are ever printed.

If doctor finds drift, fix it directly:

```bash
./ruixen-repair.sh --dry-run   # report what's broken, change nothing
./ruixen-repair.sh             # actually fix it
```

Detects any plugin whose deployed files don't match this checkout
(missing entirely or content mismatch) and a dangling `looknfeel.lua`
symlink, then fixes them by running `install.sh` itself — the same
deploy path every install/update already uses, so `shell.json` and any
third-party bar entries are preserved exactly as they always are.

## Disabling / going back to Omarchy defaults

Nothing here is a one-way door.

**Turn individual plugins off, keep everything installed:**

```bash
omarchy plugin disable ruixen.notch
omarchy plugin disable ruixen.shelf
# same for any of the tray widgets: ruixen.tray, ruixen.weather, etc.

omarchy plugin enable ruixen.notch   # turns it back on
```

If a plugin stops updating after toggling it a few times, run
`omarchy restart shell` — a full restart always clears it.

**Switch the bar back to stock Omarchy:**

```bash
omarchy bar defaults
```

Use `omarchy bar defaults`, not `omarchy plugin enable omarchy.bar` — that
command only swaps the bar engine and leaves Ruixen's widget layout in
place, which looks broken rather than default. `omarchy bar defaults`
resets everything (id, layout, position, transparency) in one shot.

To bring Ruixen's own bar back afterward, just run `./install.sh` again.

**Fully remove a plugin's files:**

```bash
omarchy plugin remove ruixen.bar
```

Backs the plugin up rather than deleting it outright (to
`~/.config/omarchy/plugins/.<id>.bak.<timestamp>`) — disable/enable and the
bar reset just flip settings, this is the only step that touches files at
all.

**Uninstall everything in one shot:**

```bash
./uninstall.sh
```

Switches back to the built-in Omarchy bar, removes every Ruixen plugin's
files for real (unlike a bare `omarchy plugin remove`, which just backs a
plugin up instead of deleting it — see above; this deletes those backups
too, so nothing lingers), restores your original Hyprland window look (or
Omarchy's own default if you never had one), and restarts the shell. Only
works from your existing cloned checkout, same as `update.sh` — the
checkout itself is left alone, delete it yourself afterward if you don't
want it around. Same in-app path also lives in Ruixen Settings' own
Plugins page, behind a typed confirmation.

`./uninstall.sh --dry-run` previews exactly what would happen first: the
bar host it would restore, which of your own widgets it would preserve,
which Ruixen plugin files it would remove, any leftover Ruixen entry it
would sweep out of `shell.json`'s `plugins[]` array, and the look'n'feel
restore plan — nothing is changed.

## Requirements

- Omarchy `4.0.0-1` (or a nearby build of the same shell generation) --
  `install.sh` checks this and warns (doesn't block) if it detects
  something outside that range
- Quickshell, as provided by Omarchy
- `jq` -- the installer itself needs it to merge into your existing
  `shell.json` rather than overwrite it

`install.sh` also checks a few optional, feature-specific dependencies
and warns (without failing) if any are missing, so you know up front
rather than discovering it later when a feature quietly doesn't work:

| Missing | What's unavailable |
|---|---|
| `ffmpeg` | Video/gif wallpaper poster generation (current/background and the lock screen won't reflect the active video/gif; the moving wallpaper itself is unaffected by this one) |
| `qt6-multimedia` (package, not command -- install a backend with it, e.g. `qt6-multimedia-ffmpeg`) | Video AND gif wallpaper playback both fail silently to start -- not part of Omarchy's own base install, only present if some other app happened to pull it in |
| `curl` | Weather data, avatar image download in Settings |
| `python3` | The bar's docked-mode toggle |
| `fastfetch` | Less detail on the health page's system-info panel |
| `cava` | The Desktop audio visualizer; the rest of Ruixen remains usable |
