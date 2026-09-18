# AGENTS.md — Ruixen development contract

This is the repo-wide rulebook for any agent (or human) editing Ruixen. It's
a map, not a tutorial — deeper detail already lives in `README.md`,
`COMPATIBILITY.md`, `docs/CONTROL.md`, `docs/LAUNCHER.md`, `docs/KEYBINDS.md`,
and the tests themselves. Read those when you need specifics; read this
first to know which rules exist at all.

If a future incident reveals a new repo-wide rule, add it here — this file
should grow from real mistakes, not speculative ones.

## 1. Runtime / Omarchy plugin contract

- Ruixen runs as plugins **inside Omarchy's existing long-lived Quickshell
  process**. Don't spin up a standalone Quickshell instance for a normal
  feature.
- Plugin entry points are `Item`s per the Omarchy manifest contract, not
  standalone `ShellRoot`s.
- Panel/overlay/menu entry points expose the lifecycle methods the host
  expects (`open(payloadJson)`, `close()`, `toggle(payloadJson)`) — see
  `ruixen.settings/Settings.qml` or `ruixen.launcher/Launcher.qml` for the
  proven shape before writing a new one from scratch.
- Prefer whatever interface the host actually injects/scopes for a plugin
  over walking Omarchy's private internals (`/usr/share/omarchy/shell/**`
  is a real, readable reference for understanding what's available and
  why — but never a dependency target, and never an edit target).

## 2. Preferred dependency order for a new feature

Work down this list; stop at the first option that actually solves it.

1. Public Quickshell API (`Quickshell.DesktopEntries`, `Quickshell.Wayland`,
   etc.)
2. Normal Linux/system APIs (a CLI tool, a proc/sysfs read, a system
   service)
3. Public Omarchy CLI / IPC (`omarchy-shell`, `omarchy plugin`, `omarchy
   menu`, `omarchy bar`)
4. Ruixen-owned IPC or persisted state (our own `IpcHandler`, our own
   state file)
5. A scoped Omarchy plugin capability (`bar.shell.firstPartyServiceFor()`,
   `bar.barWidgetRegistry`, etc.) — only when nothing above covers it

**Avoid building a new dependency on:**
- another plugin's live `Service.qml` object (Omarchy doesn't guarantee
  this stays reachable across versions — see #38)
- private Omarchy QObject traversal
- hardcoded `/usr/share/omarchy/shell/...` paths in plugin code (fine to
  *read* while investigating; never to depend on at runtime)
- generic cross-plugin service access (`bar.shell.serviceFor()` for a
  plugin that isn't your own — this is an intentionally restricted
  boundary, not an oversight; see #67)

## 3. Replacement-bar / hosted third-party widget rule

Ruixen's own `ruixen.bar` visually hosts third-party bar widgets. The
current, correct contract (post-#67):

- Every hosted widget gets a **per-widget scoped facade**
  (`PluginBarFacade` in `bars/v1/ruixen.bar/Bar.qml`) — never Ruixen's own
  top-level `bar = root` object.
- Don't work around Omarchy's service boundary by exposing an unrestricted
  `serviceFor()` or building a generic foreign-service factory. If a
  hosted widget can't reach its own co-installed service, that's Omarchy's
  trust boundary (only the trusted built-in bar can mint a fully-scoped,
  service-capable facade — see `#11949`/`omacom/omarchy` PR `#11970`,
  unmerged, blocked on a real cross-plugin security regression), not
  something to route around locally.
- Service-backed third-party parity stays an upstream capability
  limitation. Consume a safe, owner-bound API from Omarchy if/when they
  ship one — don't build our own privilege-widening shim in the meantime.

## 4. IPC / state conventions

- `omarchy-shell` is the canonical shell IPC entry point — prefer it over
  a hand-rolled socket/path convention.
- Give a Ruixen plugin a stable, plugin-owned IPC target when another
  component needs to control it (see any `IpcHandler` already in the
  repo for the pattern).
- For state shared across plugin reloads or processes, prefer a small
  versioned state file over live object sharing — it survives a plugin
  being torn down and recreated independently, which a live reference
  doesn't.
- Keep writes atomic where corruption or loss would actually hurt
  (write-temp-then-rename, not an in-place partial write).

## 5. Async / process safety

Ruixen has hit real stale-process races more than once. The house rules:

- **Last action wins** for user-triggered async work (a second search/
  request supersedes the first; the first's late result must not
  overwrite it).
- A stale generation must never publish. Compare an identity/generation
  token before applying a result, not just "did this process exit
  successfully."
- A cancelled worker isn't reusable until its real exit is observed —
  don't reassign a slot out from under a process that's still alive.
- Never block the QML/UI thread with filesystem search, content search,
  media probing, or network calls — always via `Process`/async, never a
  synchronous call on the render thread.
- Bound search/output/cache work — no unbounded scans, unbounded output
  buffers, or unbounded cache growth.

Don't reinvent this from scratch. `ruixen.launcher/WorkerPool.js` (see
`tests/js/WorkerPool.test.js`) and `ruixen.wallpaper/GenerationGuard.js`
(see `tests/js/GenerationGuard.test.js`) are the existing, unit-tested
building blocks — reuse or extend them before writing a new variant.

## 6. Installer / lifecycle safety

- Preserve unrelated user Omarchy config and third-party plugins — never
  delete or overwrite state just because it happens to sit near
  Ruixen-owned config.
- Install/update/uninstall must be idempotent and ownership-aware (safe
  to re-run, and only ever touches what Ruixen actually owns).
- Use the existing transactional/manifest/rollback paths in `install.sh`/
  `update.sh`/`uninstall.sh` rather than inventing parallel lifecycle
  logic.
- All three scripts have a dry-run mode — use it when changing lifecycle
  behavior, and check the relevant `tests/install-*.sh`/`uninstall-*.sh`/
  `update-*.sh` fixtures still pass.

## 7. QML / glyph editing safety

- Avoid whole-file rewrites of glyph-heavy QML when a targeted `Edit` is
  enough — we've had a real launcher regression from Nerd Font/PUA glyphs
  getting silently mangled in a full-file rewrite. This is not
  theoretical.
- Preserve UTF-8/private-use-area glyphs exactly as they appear; don't
  "clean up" or retype them by hand.
- When inserting a glyph programmatically, use an explicit Unicode
  codepoint (`""`, not a pasted character) so the source stays
  unambiguous under any editor/locale.

## 8. Verification checklist

Before calling non-trivial work done:

- [ ] Run the most relevant focused test(s) first.
- [ ] Run `./tests/run-all.sh` — must stay green.
- [ ] Run `omarchy plugin validate <plugin>` when plugin metadata or QML
      structure changed.
- [ ] For runtime/QML/IPC changes, do a real `omarchy restart shell`
      verification — don't rely on hot reload alone to prove correctness.
      This is not a style preference: confirmed live (ruixen-shell#67
      follow-up) that the file-watcher hot-reload path can leave stale
      widget/facade instances alive in memory — clearing
      `~/.cache/quickshell/qmlcache` and seeing "Local plugin changed,
      reloading" in the journal does NOT guarantee existing object
      instances were recreated from the new code. This cost hours of
      debugging a popup-positioning fix that looked deployed-and-correct
      (correct source, clean journal, `omarchy plugin validate` passing)
      but silently kept running against a pre-fix object, throwing
      `TypeError: ... is not a function` on methods that definitely
      existed in the source on disk. If a fix looks right on paper and
      in the diff but a live test says it "didn't work," do a full
      `omarchy restart shell` (not just a qmlcache clear) before
      concluding the fix itself is wrong — confirm a genuinely new PID
      via `ps aux | grep quickshell` first.
- [ ] Check the journal (`journalctl --user -b 0`) for anything new:
      QML binding loops, TypeErrors, duplicate IPC registrations,
      deleted-object warnings.
- [ ] Don't bump `COMPATIBILITY.md`'s `reviewed_omarchy`/
      `reviewed_quickshell` until that target version has actually been
      reviewed per its own ledger rules — bumping it is a claim of
      verification, not a formality.

## 9. Keeping this file useful

- Keep it concise enough that an agent will actually read the whole thing.
- Link to `README.md`/`COMPATIBILITY.md`/`docs/*.md`/tests/source instead
  of duplicating their content here.
- Prefer durable architectural rules over implementation trivia.
- Update it when a future incident reveals a new repo-wide rule — don't
  let the lesson live only in an issue thread or a commit message.
