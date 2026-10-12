# Wallpaper change audit

Scope: all wallpaper changes against upstream `8ce127a`, including native renderer,
rotation, both picker surfaces, shared controls/shaders, state helpers, docs,
assets, and lifecycle fixtures. This is a source and live-runtime audit, not a
claim of independent third-party review.

## Findings resolved

- Removed the external renderer dependency. `ruixen.background` is bundled,
  disabled by default, and uses public Quickshell layer-shell APIs plus Omarchy's
  supported replacement-plugin lifecycle. No private Omarchy QML imports or
  foreign live service references were added.
- Enabling refuses a competing background clone. Disabling/uninstalling restores
  the stock renderer only when the host recorded ownership of that suppression.
  Existing plugin entries and unrelated disabled widgets survive reinstall and
  uninstall; lifecycle fixtures cover the new renderer.
- Encoded image URLs and decoded helper paths, supporting spaces, Unicode, and
  literal `#`/`%` characters. Limited decoded images to viewport dimensions.
- Previews wait for images, restart at zero on duration changes, support instant
  duration, and stop when inactive. Desktop shaders also wait for valid textures;
  finishing retains the incoming frame while the final canonical image loads.
- Added rendering bounds and strict, versioned JSON validation for known settings,
  finite numbers, booleans, and nested effect controls. Atomic writes preserve
  unrelated appearance keys; invalid input leaves files unchanged. Malformed
  state remains intact and reports an error rather than hiding its controls.
- Added stale-read protection to the renderer; rotation rejects stale discovery
  results after configuration/manual selection changes. Folder scans are bounded
  and run outside the UI thread. Shuffle avoids immediate repeats.
- Made media placement explicit above the native background rather than depending
  on load order. Rotation, zoom/glow, and background animation pause during media.
- Added per-effect controls and accessible slider names; effect panels scroll
  independently with a fixed section header so the artwork grid remains usable.
- Retained MIT attribution, GLSL sources, and compiled Qt shader assets. Tests
  enforce parity among the separately packaged renderer/picker copies.

## Verification

- `bash tests/run-all.sh`: passed.
- `bash tests/host-contract-regression.sh`: 16 passed against the repository's
  pinned reviewed Omarchy source; this does not assert compatibility with latest.
- Focused appearance, rotation, preview-selection, rendering-model, config-merge,
  and uninstall clone-restore tests passed. Install/uninstall dry runs passed.
- Qt `qsb --qt6` compiled both shaders; installed plugin validation passed.
- Clean shell restarts loaded the native renderer and both picker controls.
  Native signal-tear, datamosh, VHS, and code-bleed transitions completed without
  new wallpaper QML/shader errors. Same-theme palette handoff completed.
- Public enable/disable cycles restored stock state and accepted subsequent native
  background IPC. The host can log transient duplicate-registration warnings
  while swapping implementations; a clean startup had one background renderer.
- Generated video/GIF fixtures reported active playback, paused rotation and
  ambient effects, and resumed afterward. Original artwork/preferences restored.
- Clean demo assets show only the wallpaper picker on an empty workspace. The
  six-fps GIF demonstrates effects; it does not measure production frame rate.

## Preliminary resource sample

Five seconds per background mode on a 1920×1080 desktop, with zoom/glow disabled.
These are whole-Quickshell CPU percentages of one core and whole-GPU busy readings;
other desktop applications, blur, and compositor activity influence them. They
are not isolated plugin measurements or a performance guarantee.

| Background | CPU, one core | Whole GPU busy |
| --- | ---: | ---: |
| None | 4.39% | 39.6% |
| Static CRT | 4.20% | 37.2% |
| Matrix rain | 6.99% | 52.4% |

Matrix is opt-in, renders to a 640-pixel texture, and updates at 10 fps. CRT has
no animation timer. Individual transition costs and physical monitor hotplug,
multiple displays, and every theme have not been exhaustively measured/tested.
