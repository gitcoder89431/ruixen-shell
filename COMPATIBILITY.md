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
`tests/host-contract-regression.sh` reads the newest `reviewed_omarchy_commit`
entry and fetches that exact commit from `github.com/basecamp/omarchy` to
verify the host contracts below still exist there in the expected shape
(see "CI contract regression gate" below).

## Entries

| Ruixen commit | reviewed_omarchy | reviewed_omarchy_commit | reviewed_quickshell | date accepted | notes |
|---|---|---|---|---|---|
| `13f747a` | `4.0.4-1` | `c668141e9c42b13c80c9ca4ea108e11708c5e8a5` | (bundled with Omarchy, not independently versioned by this repo) | 2026-09-24 | Live-verified on the dev machine after a fresh `git pull --ff-only` and `./install.sh`: dry-run passed, all plugin manifests validated, install completed, `omarchy-shell shell ping` returned `ok`, `ruixen-doctor.sh` reported every deployed plugin matching this checkout by content hash, active bar was `ruixen.bar`, expected Ruixen service plugins were enabled, Hyprland look matched `looknfeel.ruixen.lua`, and theme overlays applied. Optional `cava` was not installed, which only disables the desktop audio visualizer by design. `reviewed_omarchy_commit` backfilled later (issue #34's own CI gate): the commit `basecamp/omarchy`'s own `v4.0.4` tag pointed to at the time this row's `omarchy version` (`4.0.4-1`) was reviewed, confirmed via `gh api repos/basecamp/omarchy/git/refs/tags/v4.0.4` and cross-checked against `gh api repos/basecamp/omarchy/commits/<sha>`'s own commit message, not guessed. |
| `55e9bab` | `4.0.3-1` | (not backfilled — this row predates the CI gate) | (bundled with Omarchy, not independently versioned by this repo) | 2026-09-08 | Issue #38's remediation, all 7 sub-issues (#39-#45): moved every `shell.firstPartyServiceFor()`/`shell.appLibrary`/`bar.shell.pluginRegistry` call site this repo had onto real on-disk state files, the real `omarchy-shell` IPC surface, `bar.barWidgetRegistry`, or `Quickshell.DesktopEntries` instead. Each fix was live-verified twice: once on 4.0.2 before the update existed to test against, and again after actually running `omarchy update` + reboot onto real 4.0.3 on the dev machine — journal clean, state files fresh, bar/notch/pinned-apps/media/DND all screenshotted working. The host contracts this ledger's own review checklist calls out (`ToplevelManager`, `BarWidgetRegistry`, the `omarchy-shell`/`omarchy plugin` CLI surfaces) were re-checked directly on the new version, not assumed carried over. |
| `a84907e` | `4.0.2-1` | (not backfilled — this row predates the CI gate) | (bundled with Omarchy, not independently versioned by this repo) | 2026-09-05 | Baseline entry — the version this whole session's own work (issue #7 through #36 and their follow-ups) was built and live-verified against on the actual dev machine. |
| — | `4.0.0-1` | (not backfilled — this row predates the CI gate) | — | — | README's own documented minimum ("targets Omarchy 4.0.0-1, also confirmed working on 4.0.1-1") — carried forward here rather than re-verified fresh, since nothing in this session touched anything that would invalidate it. |

## Updating this ledger

Bumping `reviewed_omarchy`/`reviewed_omarchy_commit`/`reviewed_quickshell`
to a new value is itself a compatibility review, not a formality — per the
issue's own acceptance criteria, do so only after actually checking the
host contracts this repo depends on directly still hold on the new
version:

- `Quickshell.Wayland`'s `ToplevelManager` API (`ruixen.notch`'s
  fullscreen/active-window detection) — Quickshell's own contract, not
  Omarchy's; not covered by `tests/host-contract-regression.sh` below
  since that script only pins `basecamp/omarchy` source, not Quickshell's
- Omarchy's own bar-widget registry contract (`BarWidgetRegistry.qml`,
  `PluginRegistry.qml`'s `isEnabled`/`inBar`/`findBarLocation`/
  `defaultBarWidgetSection` — every `ruixen.pluginpins`/migration fix
  tonight reads these directly)
- `omarchy-shell` IPC surface (`shell ping`, `shell listPlugins`,
  `shell setPluginEnabled`, `shell toggle <id>`)
- `omarchy plugin list/enable/disable/remove --json` CLI contract
- `WidgetButton.qml`'s own `wheelMoved`/click signal shape (every stock
  bar-widget's scroll-to-adjust behavior depends on this)

To find the commit a given Omarchy release tag actually points to (for
`reviewed_omarchy_commit`):

```bash
gh api repos/basecamp/omarchy/git/refs/tags/v<X.Y.Z> --jq '.object.sha'
```

Cross-check the result against `gh api repos/basecamp/omarchy/commits/<sha>`'s
own commit message before trusting it — a lightweight tag's ref object can
in principle be force-moved later, so the commit's own message/content is
the thing actually worth confirming, not just the tag name.

## Previously incompatible versions (now resolved)

| Omarchy version | Status | Notes |
|---|---|---|
| `4.0.3-1` | **Resolved as of `55e9bab`** | Confirmed via direct source diff (not just release notes) to break `shell.firstPartyServiceFor`/`shell.appLibrary` for third-party plugins outside a narrow allowlist — broke the app launcher, notification history, media/dashboard integration, the peripherals battery widget, plugin pins, idle/nightlight toggles, and the bar↔notch geometry sync in this repo specifically. Omarchy's own manual documents the tradeoff as intended, not a bug. Issue #38 (all 7 sub-issues, #39-#45) replaced every affected call site; live-verified against the real, updated 4.0.3 install, not just the pre-update research. See the ledger entry above and issue #38 for the full breakdown. |

## CI contract regression gate

`tests/host-contract-regression.sh` implements the issue's own remaining
acceptance criterion: it fetches the exact `reviewed_omarchy_commit`
pinned above from `github.com/basecamp/omarchy` (via `gh api`, no full
clone) and verifies each host contract named in "Updating this ledger"
above (except `ToplevelManager`, a Quickshell contract this script has no
reach into) still exists in that source in the expected shape — a
function/signal signature renamed or removed there fails the check.

Deliberately **not** wired into `tests/run-all.sh`'s own suite list.
Every other test in this directory is a pure static-file grep with no
network dependency; this one needs real network access and GitHub API
auth, so a plain offline `./tests/run-all.sh` should never fail because
of it. `.github/workflows/ci.yml` runs it as its own dedicated step,
where `GITHUB_TOKEN` is already available.

Bumping `reviewed_omarchy_commit` to a new value, without also doing the
actual contract review described above, would make this gate pass
vacuously against a newer source tree nobody has actually checked — the
whole point is that moving the pin IS the review, not a substitute for
it.
