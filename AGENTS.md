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
  `ruixen.launcher/Launcher.qml` for the proven shape before writing a new
  one from scratch.
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
  (`PluginBarFacade` in `bars/v2/ruixen.bar/Bar.qml`) — never Ruixen's own
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

Don't reinvent this from scratch. `ruixen.launcher/search/WorkerPool.js` (see
`tests/js/WorkerPool.test.js`) and `ruixen.wallpaper/GenerationGuard.js`
(see `tests/js/GenerationGuard.test.js`) are the existing, unit-tested
building blocks — reuse or extend them before writing a new variant.

## 6. Installer / lifecycle safety

- Preserve unrelated user Omarchy config and third-party plugins — never
  delete or overwrite state just because it happens to sit near
  Ruixen-owned config.
- Install/update/uninstall must be idempotent and ownership-aware (safe
  to re-run, and only ever touches what Ruixen actually owns).
- **Install and uninstall must stay symmetric about user data.** Any
  "preserve the user's foreign X" rule one side learns, the other side
  needs too. Real incident: `#26` taught *uninstall* to carry third-party
  bar-layout entries across (`lib/merge-uninstall-bar.sh`), but install
  kept replacing the whole `bar` object on first takeover, so a stock
  omarchy bar's third-party widgets silently stopped being placed — the
  plugins stayed installed and enabled, nothing errored, they just
  vanished from the bar. Fixed in `lib/build-shell-json.sh`'s
  `$ownedBar`. When adding a lifecycle preservation rule, ask what the
  opposite operation does with the same data, and give both sides a test.
- A fixture that omits the field under test proves nothing. Every
  foreign-bar fixture in the suite was layout-*less*, which is exactly
  why the above survived a green `run-all.sh` for that long.
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
- [ ] Specifically watch for `"<Type> is not a type"`, `"Type <X>
      unavailable"`, or `"bar option ruixen.bar failed to load, falling
      back to omarchy.bar"` after ANY change that adds or moves a file
      using a QML type (a new sibling file, an extracted component,
      newly-added debug scaffolding). Neither `omarchy plugin validate`
      nor this repo's own grep-based test suite catches a missing
      `import` — both check text patterns and manifest shape, neither
      actually compiles the QML. A missing import (confirmed directly,
      issue #78 Phase 6 stage 7: `BarPanel.qml` used `MultiEffect`
      without `import QtQuick.Effects`) makes the WHOLE plugin fail to
      load and silently fall back to stock `omarchy.bar` — every other
      widget still renders (via the stock bar instead), so a quick
      glance at a screenshot can look completely normal while the
      entire custom plugin isn't actually running. The only reliable
      signal is the journal line itself, checked after every real
      `omarchy restart shell`, not just once at the end of a work
      session -- this failure mode is also intermittent across restarts
      (qmlcache can paper over it on some runs), so a single clean
      restart does not clear it as a suspect.
- [ ] Don't bump `COMPATIBILITY.md`'s `reviewed_omarchy`/
      `reviewed_quickshell` until that target version has actually been
      reviewed per its own ledger rules — bumping it is a claim of
      verification, not a formality.

## 9. Coupled visual surfaces: frame / notch / docked bar

The screen border (`ruixen.bar/Bar.qml`'s `FrameWindow`), the notch
(`ruixen.notch/Overlay.qml`), and the docked bar's merged shoulder strip
(`leftDockedBg`/`rightDockedBg`/their wing pieces, also in `Bar.qml`) are
visually **one continuous surface** by design — "growing out of the
frame" is the whole point. They're separate windows/plugins with no live
object link between them (per rule #4/#38), but they still have to move
together whenever that surface's own look changes (color, corner radius,
shadow). This bit hard during the frame-color/docked-shadow work
(2026-09-24) and will bite again on any future glass-surface pass — read
this before touching any of the three.

- **Shared color state, independent resolution.** All three read the same
  `~/.local/state/ruixen/frame-appearance.json` (`{"mode":"theme"|"black"}`),
  but each keeps its own copy of the resolve logic (`frameColorMode`/
  `frameColor` in `Bar.qml`, `resolvedFrameColor` in `notch/Overlay.qml`) —
  intentional, not an oversight (rule #4). Adding a mode or field means
  editing the load/fallback function in every consumer, not just one.
- **Two different colors, on purpose.** A surface that hosts icon/text
  content directly (the notch's own UI, `leftDockedBg`/`leftShoulderWing`
  in docked mode, since `GroupPill { visible: !root.docked }` hides each
  pill's own background there) needs the **luminance-clamped** color —
  falls back to black whenever the resolved theme color reads too light,
  or content becomes unreadable on a light theme. A surface that exists
  purely to blend into the frame's own border with no content on it
  (`leftFrameHemWing`/`rightFrameHemWing`, `BarPanel`'s own seam-cover
  pieces) must use the **unclamped** color instead, matching the frame's
  real border exactly — the "paint the same color as the thing
  underneath" seam trick only works when the colors are actually
  identical. Giving a seam piece the clamped color (done once, reverted
  in `f146a14`) makes it visibly diverge from the frame on any theme
  where the clamp actually triggers.
- **A rounded piece only covers its own inscribed disk.** It never
  reaches the sharp corner of its own bounding square. Anything meant to
  fully hide what's behind a rounded corner (the frame's own shadow,
  wallpaper, another surface) needs an explicit **square** backing patch
  at that corner too (see the `dockedBarColor`-filled squares added in
  `9249621`) — no amount of repositioning or resizing the rounded shape
  itself fixes this, it's structural.
- **Exclude shadow by direction (clip), not by piece.** A multi-piece
  L-shaped surface (docked strip = DockedBg + ShoulderWing + FrameHemWing)
  should shadow-duplicate the FULL real shape and let an asymmetric clip
  (flush on the frame-touching sides, expanded on the open sides) trim
  the shadow directionally. Leaving a whole piece out of the duplicate
  because "it touches the frame" is wrong when that piece has its own
  open-facing edge too (`e7101e8` — excluding `FrameHemWing` entirely
  first removed a real, wanted shadow along its own curve).
- **An asymmetric clip shifts its own coordinate origin.** Expanding a
  clip `Item` outward on the side where it's normally flush-anchored (e.g.
  flush-right, expanded left) moves that Item's own `x`/`y` in its
  parent's frame — children positioned at a real sibling's absolute `x`/
  `y` land in the wrong place unless you subtract the clip's own `x`/`y`
  first (`e7101e8`'s `rightShoulderShadowClip` fix). Only the flush-
  origin case (e.g. flush top-left, expanded right+bottom) needs no
  compensation.
- When debugging *which* piece a visual artifact belongs to, temporarily
  hardcoding a loud, distinct color per suspect piece and doing one real
  `omarchy restart shell` + screenshot is much faster than reasoning from
  code/comments alone — comments in this area have gone stale before
  (`leftFrameTaper`/`dockedSeamCover` are old names for pieces later
  renamed to `leftFrameHemWing`/etc., with the comment never updated).
- **One shadow recipe across the whole surface, copied on purpose.** The
  notch's own shadow (`notchShadowBlur` in `notch/Overlay.qml`: `opacity:
  0.9` on the shape + a plain `blurEnabled`/`blurMax: 32`/`blur: 0.6`
  `MultiEffect`, no directional offset) was tuned once, live, against the
  frame's own hand-rolled ring shadow. When the docked-bar shoulder strip
  got its own shadow later the same session, it reused `GroupPill`'s
  *different* recipe (`shadowEnabled`/tight `shadowBlur: 0.15`/a
  directional `shadowVerticalOffset` — a deliberately close, hard pill-
  lift effect) instead, just because it was also mask-safe and
  convenient to copy. Direct correction: "why does it need to be
  different at all? why cant they act as one continuous shadow?" It
  didn't — fixed in `7cc7af7` by copying `notchShadowBlur`'s own recipe
  byte-for-byte instead. The lesson: when adding a shadow to a new piece
  of this same surface, copy the recipe that's already been tuned
  against the others (`notchShadowBlur`), not whatever other mask-safe
  example happens to be nearby in the file.
- **A `Connections` block watching a derived property can fire once and
  then go silent, even while the underlying data keeps updating
  correctly.** The chrome-surface refactor (#81) split the docked bar's
  visual chrome into its own frame-owned Canvas, fed by geometry
  published from `BarPanel`'s own widget row into a per-screen metrics
  map (`dockChromeMetricsByScreen`). Two Canvases each watched a small
  `Item`'s own derived `readonly property int leftWidth/rightX/
  rightWidth` (themselves bound to that published metrics object) via
  `Connections { target: dockChrome; function onRightWidthChanged() {
  requestPaint() } }` — syntactically ordinary, and it DID paint once,
  right when the chrome first became visible. But every metrics update
  after that point (pinned widgets/launcher icons growing the bar's own
  content live) never triggered another repaint, even though a live
  debug trace confirmed the published metrics themselves kept updating
  correctly the whole time — the background chrome just silently
  stopped tracking, leaving newer icons rendering on bare wallpaper past
  its own frozen edge. A live report ("as i add more stuff to the pin
  plugin... the dock size isnt like moving or getting larger anymore,
  its like static bar") is what surfaced it; a full-width Canvas visibly
  short of its own content, on an otherwise-correct build, is the
  signature to watch for. Root-caused with a live debug trace (temp
  `FileView` logging every publish/read/paint with timestamps —
  `omarchy restart shell` + `cat` the log beats guessing here) rather
  than more static reading once the metrics-vs-render mismatch was
  visually confirmed. Fixed by pointing the `Connections` at the one
  signal already proven reliable across every update in that same trace
  (`frameWindow`'s own `dockChromeMetricsChanged`) instead of the
  derived `Item`'s own per-property change signals one layer downstream
  — don't assume a `Connections` block "should" work just because it
  compiles and fires once; when something intermittently stops updating
  live, verify the *specific* signal it's listening to is the one
  that's actually still firing on every change, not just the first.
- **Two separate surface-identity systems, deliberately not unified**
  (issue #78 raised this as an open "Option A vs. Option B" question;
  resolved as Option A — kept independent). `frameColorMode`/
  `barSurfaceMaterial` (`Bar.qml`) govern the bar/frame/notch's own
  surface — Black vs. Theme color, Solid vs. Glass fill — while
  `glassTintMode` and the Glass Effect profile
  (`ruixen.launcher/extensions/settings/SettingsContent.qml`) govern the launcher window's
  own material. These are not the same kind of thing: the bar/frame
  surface is decorative chrome painted inside a window that's always
  present, while the launcher's glass is the actual Hyprland-blurred
  compositor material of a window that opens and closes on demand.
  Forcing both through one shared state file would mean a single stored
  value secretly means two different things depending on which plugin
  reads it. Don't add a third, unifying state file for this — if a
  future feature needs bar/frame and launcher to visually match, resolve
  that with a read-only derived mapping in one direction, not a merged
  state file both sides write to.

## 10. Keeping this file useful

- Keep it concise enough that an agent will actually read the whole thing.
- Link to `README.md`/`COMPATIBILITY.md`/`docs/*.md`/tests/source instead
  of duplicating their content here.
- Prefer durable architectural rules over implementation trivia.
- Update it when a future incident reveals a new repo-wide rule — don't
  let the lesson live only in an issue thread or a commit message.
