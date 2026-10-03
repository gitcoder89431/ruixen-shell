# Developing Ruixen

For people changing Ruixen rather than using it: where things live, how it
plugs into Omarchy, the dev scripts, and how to test. The repo-wide rules for
humans and coding agents are in [`AGENTS.md`](../AGENTS.md) at the repository
root: read that first, it is deliberately short. User-facing docs are in
[`docs/`](../docs/README.md).

## How Ruixen plugs into Omarchy

Ruixen is a set of plugins that load **inside Omarchy's existing, long-lived
Quickshell process**. Nothing here starts its own shell. Each plugin is a
directory with a `manifest.json` (an Omarchy plugin id such as `ruixen.bar`)
and a QML entry point that is an `Item`, not a standalone `ShellRoot`.
Overlay-kind plugins (launcher, shelf) expose the lifecycle the host expects:
`open(payloadJson)`, `close()`, `toggle(payloadJson)`.

Control goes over `omarchy-shell <target> <method>` (see
[`docs/CONTROL.md`](../docs/CONTROL.md)); shared state lives in small
versioned files under `~/.local/state/ruixen/`. `AGENTS.md` §1-§4 holds the
actual rules, including which Omarchy internals not to depend on.

## Repository layout

```text
bars/v2/ruixen.bar/        the bar, the screen frame, docked chrome
bars/widgets/ruixen.*/     bar widgets and the notch (ruixen.notch)
ruixen.launcher/           launcher, Search Files, Settings, Clipboard, Theme browser
ruixen.shelf/              the drop-pocket overlay
ruixen.wallpaper/          video wallpaper support
ruixen.cava/               audio visualizer overlay
hyprland/                  window look'n'feel variants + ruixen-lookfeel.sh
theme-overlays/            per-theme tweaks applied on install
lib/                       installer helpers (shell.json merge, restore, lock, journal)
install.sh update.sh       lifecycle scripts (all have --dry-run)
uninstall.sh
ruixen-doctor.sh           read-only diagnostic report
ruixen-repair.sh           redeploys drifted plugins via install.sh
dev/                       developer helper scripts (below)
tests/                     contract, model and lifecycle tests; run-all.sh
docs/                      user manual
preview/                   README images
```

Where a given feature lives: the **bar** and **frame** in
`bars/v2/ruixen.bar/` (`Bar.qml`, `BarPanel.qml`, `FrameWindow.qml`); the
**notch** and its Kanban/wallpapers/health tabs in
`bars/widgets/ruixen.notch/Overlay.qml`; the **launcher** in
`ruixen.launcher/Launcher.qml` with each extension under
`ruixen.launcher/extensions/`; the **Settings** app in
`ruixen.launcher/extensions/settings/`; the **Shelf** in `ruixen.shelf/`.
The bar, notch and Shelf are one visual surface by design: read `AGENTS.md`
§9 before touching any of them.

## Dev scripts

| Script | What it does |
|---|---|
| `dev/ruixen-bar-mode.sh docked\|floating\|status` | Switch the bar between merged (docked) and separate (floating) pills; live, no restart |
| `dev/ruixen-bar-style.sh notch\|fullbar\|status` | Switch between the notch skin and the full-width statusline skin |
| `hyprland/ruixen-lookfeel.sh on\|half\|square\|off\|status` | Window corner/blur variants |
| `./ruixen-doctor.sh` | Read-only report: git state, plugin drift by content hash, bar layout, runtime health, clipboard capture |
| `./ruixen-repair.sh [--dry-run]` | Redeploy plugins that drifted from this checkout |

The first two are described for users in
[`docs/CUSTOMIZATION.md`](../docs/CUSTOMIZATION.md).

## Local workflow

1. Edit in a checkout, run `./install.sh --dry-run` to see what a deploy
   would change, then `./install.sh` to deploy it.
2. For runtime, QML or IPC changes do a real `omarchy restart shell`
   rather than trusting hot reload, and check
   `journalctl --user -b 0` for `is not a type`, `Type ... unavailable`,
   `TypeError` and binding loops. Neither `omarchy plugin validate` nor the
   test suite compiles QML, so a missing `import` only shows up there.
3. `omarchy plugin validate <plugin>` after manifest or structure changes.
4. Run the tests (below) before pushing.

The full checklist, with the incidents behind each item, is `AGENTS.md` §8.

## Compatibility

[`COMPATIBILITY.md`](../COMPATIBILITY.md) is the ledger of which Omarchy and
Quickshell versions have actually been reviewed. Don't bump its reviewed
versions until that version has really been reviewed; a bump is a claim of
verification.

## Running tests

```bash
./tests/run-all.sh
```

Runs almost everything CI runs (`.github/workflows/ci.yml`) in one go:
shell script lint (`bash -n` + ShellCheck, when installed), plugin
manifest validation, the JS model tests, and the installer lifecycle/
config/uninstall-restore tests. Each suite can also be run on its own --
see `tests/*.sh`, every file has its own header comment explaining
what it covers.

CI runs one additional step this doesn't: `tests/host-contract-
regression.sh` (issue #34), which fetches real source from
`github.com/basecamp/omarchy` at the exact commit `COMPATIBILITY.md`
records as reviewed and checks it still matches the host contracts this
repo depends on. Deliberately excluded from `run-all.sh` since it needs
network access and GitHub API auth that a local run shouldn't require --
run it directly (`./tests/host-contract-regression.sh`) if you want to
check it yourself.

The installer tests (`tests/install-lifecycle.sh`, `tests/shell-json-
merge.sh`, `tests/looknfeel-preserve.sh`, `tests/uninstall-bar-
restore.sh`) run against a throwaway fake `$HOME`/directory tree, never
your real config, so they're safe to run anywhere including this repo's
own checkout.

### Live checks

`tests/live-shelf-ipc.sh` drives the Shelf's real IPC boundary against a
running shell, so it is outside `run-all.sh` and CI (it skips itself when no
shell is running). Run it after a real `omarchy restart shell` when you
change the Shelf.

### Manual QA: the Desktop audio visualizer

`tests/cava-*.sh` cover the visualizer's own state/lifecycle wiring
statically, but a few things only really show up live. A couple of
minutes, not a long soak:

```
1. Off -> Bars -> Segments -> Wave
2. switch 64 <-> 96 bands
3. pause/resume audio
4. enable/disable a few times
5. enter/exit fullscreen
6. kill cava once and confirm only one replacement process appears
```
