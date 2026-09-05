# Compatibility ledger

Issue #34: records exactly what Omarchy + Quickshell releases this repo has
actually been reviewed and tested against, rather than only warning at the
bare major-version level. This is a ledger of what has been checked, not a
claim that every nearby build is broken — an unreviewed host still runs,
just with a clearer "unreviewed, not necessarily broken" message instead of
silence up to a hard major-version mismatch.

`install.sh` reads the newest `reviewed_omarchy` entry below and compares
it against the live `omarchy version` output, printing a reviewed-vs-
detected note when they differ (see its own `[0/6]` step).

## Entries

| Ruixen commit | reviewed_omarchy | reviewed_quickshell | date accepted | notes |
|---|---|---|---|---|
| `a84907e` | `4.0.2-1` | (bundled with Omarchy, not independently versioned by this repo) | 2026-09-05 | Baseline entry — the version this whole session's own work (issue #7 through #36 and their follow-ups) was built and live-verified against on the actual dev machine. |
| — | `4.0.0-1` | — | — | README's own documented minimum ("targets Omarchy 4.0.0-1, also confirmed working on 4.0.1-1") — carried forward here rather than re-verified fresh, since nothing in this session touched anything that would invalidate it. |

## Updating this ledger

Bumping `reviewed_omarchy`/`reviewed_quickshell` to a new value is itself a
compatibility review, not a formality — per the issue's own acceptance
criteria, do so only after actually checking the host contracts this repo
depends on directly still hold on the new version:

- `Quickshell.Wayland`'s `ToplevelManager` API (`ruixen.notch`'s
  fullscreen/active-window detection)
- Omarchy's own bar-widget registry contract (`BarWidgetRegistry.qml`,
  `PluginRegistry.qml`'s `isEnabled`/`inBar`/`findBarLocation`/
  `defaultBarWidgetSection` — every `ruixen.pluginpins`/migration fix
  tonight reads these directly)
- `omarchy-shell` IPC surface (`shell ping`, `shell listPlugins`,
  `shell setPluginEnabled`, `shell toggle <id>`)
- `omarchy plugin list/enable/disable/remove --json` CLI contract
- `WidgetButton.qml`'s own `wheelMoved`/click signal shape (every stock
  bar-widget's scroll-to-adjust behavior depends on this)

## Known scope not covered here

A full CI-level contract regression gate — pinning an immutable Omarchy
source revision, running automated checks against it in CI, and failing a
build when a specific host contract fixture is renamed/removed — is real,
valuable follow-up work the original issue also asked for, but is a
separate, larger CI-infrastructure investment (fetching and diffing
against external pinned source inside CI) rather than something to bundle
into this ledger file. Left open on issue #34 rather than attempted here.
