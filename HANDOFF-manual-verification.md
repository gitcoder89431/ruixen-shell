# Manual verification before merging `claude/modest-dijkstra-dhf701`

TEMPORARY FILE — delete it before merging. It exists because this branch was
written in a cloud container with no Omarchy, Quickshell, Hyprland or
display: everything below passed the unit/static test suite
(`./tests/run-all.sh`) but has **never run in a live shell**. Follow
`AGENTS.md` §8 for the general routine; this lists what is specific here.

## 0. Setup

1. `git fetch && git checkout claude/modest-dijkstra-dhf701`
2. `./tests/run-all.sh` (should be green), `omarchy plugin validate ruixen.launcher`
3. Full `omarchy restart shell` (not hot reload). Confirm a new PID with
   `ps aux | grep quickshell`.
4. `journalctl --user -b 0 | tail -100` — look for `is not a type`,
   `Type <X> unavailable`, `TypeError`, binding loops, and
   `bar option ruixen.bar failed to load, falling back to omarchy.bar`.
   New QML files this branch adds: `ClipboardActionRow.qml`
   (`ClipboardActionButton.qml` was deleted). Repeat the journal check after a
   second restart (qmlcache can hide a missing import on some runs).

## 1. Clipboard extension (`ruixen.launcher/extensions/clipboard/`)

Open it: `omarchy-shell shell toggle ruixen.launcher '{"extension":"clipboard"}'`

Unverified assumptions — check each, and fix the code if wrong:

- [ ] **History schema.** `jq '[.[].type] | unique' ~/.local/state/omarchy/clipboard-history.json`
      — code only understands `text` and `image`; anything else is silently
      dropped. Report/handle any other type found.
- [ ] **Paste actually lands in the previous window.** Enter on a text and an
      image entry. The launcher may need to close/release focus before the
      paste helper runs — nothing in the extension closes it today. Likely
      the first thing to fix if it fails.
- [ ] **`--history-index` correctness.** Copy something *while the launcher is
      open*, then paste the highlighted row: it must paste what is shown
      (selection is re-found by identity on reload, but the paste helper still
      takes a positional index).
- [ ] **Delete vs. Omarchy's clipboard daemon.** Alt+D twice on an entry;
      it must disappear *and stay gone* after copying something new and after
      the daemon next writes. The code edits `clipboard-history.json`
      directly (atomic rewrite). If the daemon keeps its own copy and
      rewrites the file, switch to Omarchy's own delete command if one exists
      (`ls $(dirname $(which omarchy-clipboard-open))` / `omarchy-clipboard-*`).
      Also check deleting an image removes its file under `clipboard-images/`
      only when no other entry uses it.
- [ ] **Alt shortcuts reach the launcher** (Alt+C copy, O open, P paste path,
      D delete, R reveal secret) and are not eaten by a Hyprland bind. Alt
      must still do nothing in other launcher modes/extensions.
- [ ] **Open** for: link (`omarchy-clipboard-open`), file path and email
      (`xdg-open`), plain text.
- [ ] **Panel height.** The details panel now stacks preview + metadata rows +
      5 action rows (+ color swatch). Check nothing is clipped on a small
      launcher window, for each kind: text, link, image, color, path, email,
      JSON, secret.
- [ ] **Chip row** (Type filter / Recent / By Type): looks right next to the
      theme browser's chips; By Type section headers render; the Type chip
      resets if its kind disappears; decide whether chip state should reset
      each time the launcher reopens (currently sticky while loaded).
- [ ] **Secret masking** false positives/negatives against your real history
      (heuristic in `looksLikeSecret`, `ClipboardHistory.js`). Alt+R reveals.
- [ ] **Image rows**: dimensions labels appear, "File missing" shows for a
      deleted image, no lag with a long history (probe is capped at 40
      paths/run, cache 300).
- [ ] Path "Status" row shows File/size, directory, or "Not found".

## 2. Lifecycle scripts (issue #90, `update.sh` / `uninstall.sh`)

Covered by `tests/lifecycle-flag-parsing.sh` against stubs; verify on the real
machine **in dry-run first**:

- [ ] `./update.sh --help`, `./uninstall.sh --help`, `./install.sh --help` print
      usage and exit 0 without touching anything.
- [ ] `./uninstall.sh --dryrun` (typo) now errors instead of uninstalling.
      (Do NOT test this against the original script on a real install.)
- [ ] `./update.sh --dry-run` and `./update.sh --check-json` still behave as
      before (Settings → Plugins "check for updates" parses `--check-json`).
- [ ] With a planted stale `~/.local/state/ruixen/lifecycle-journal.json`:
      `./update.sh` refuses, `./update.sh --acknowledge-interrupted` proceeds.

## 3. Before merging

- [ ] Delete this file.
- [ ] Don't bump `COMPATIBILITY.md` reviewed versions (no new Omarchy review
      happened here).
