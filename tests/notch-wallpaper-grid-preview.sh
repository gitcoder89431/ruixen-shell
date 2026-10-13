#!/usr/bin/env bash
# The notch's wallpaper grid doubles as Transition's live preview surface
# now -- hover an image tile and it plays the selected transition from the
# current wallpaper into that one, right in the grid, instead of a
# separate dropdown + preview box (the direction we chose over PR #99's
# approach, see that PR's own comment thread). Reuses the same
# WallpaperEffectPreview.qml component and preview primitives the
# launcher's Wallpapers extension already ships, ported into this plugin
# and kept byte-identical by tests/wallpaper-effects.py's own parity
# check.
#
# Can't drive a real Quickshell instance or simulate a mouse hover here
# (no compositor in CI), so this is a static invariant check against the
# actual QML source, same style as tests/workspaces-pill-strict.sh's own
# pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
notch_dir="$repo_dir/bars/widgets/ruixen.notch"
content_qml="$notch_dir/WallpapersContent.qml"

pass=0
fail_count=0
check() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   - %s\n' "$desc"
    pass=$((pass + 1))
  else
    printf 'FAIL - %s\n       got:  %s\n       want: %s\n' "$desc" "$got" "$want"
    fail_count=$((fail_count + 1))
  fi
}

for asset in WallpaperAmbient.qml WallpaperGlitch.qml WallpaperTransitionMask.qml WallpaperEffectPreview.qml WallpaperEffectModel.js GLITCH-LICENSE.txt shaders/glitch.frag shaders/glitch.frag.qsb shaders/ambient.frag shaders/ambient.frag.qsb; do
  check "notch carries its own copy of $asset" \
    "$([[ -f "$notch_dir/$asset" ]] && echo yes || echo no)" "yes"
done

check "preview only activates for image tiles, never video/gif (the renderer never transitions into one)" \
  "$(grep -c 'tile.modelData.kind === "image"' "$content_qml")" "1"

check "the current wallpaper's own tile previews against another real image, not itself (mask effects show nothing on a same-image crossfade)" \
  "$(grep -c 'EffectModel.nextPreviewArtwork(root.currentBackground, root.wallpaperPaths)' "$content_qml")" "1"

check "preview never activates with an empty preview target (e.g. only one wallpaper in the folder)" \
  "$(grep -A12 'Loader {' "$content_qml" | grep -Fc 'tile.previewTarget !== ""')" "1"

check "preview is gated on a real transition actually being selected, not just hover" \
  "$(grep -A12 'Loader {' "$content_qml" | grep -c 'appearanceState.rendererEnabled && appearanceState.transitionOn')" "1"

check "the preview is a Loader (at most one live instance across the whole grid), not an always-on item" \
  "$(grep -c 'sourceComponent: WallpaperEffectPreview' "$content_qml")" "1"

check "preview plays from the real current wallpaper path, not a tile's own path" \
  "$(grep -c 'fromPath: root.currentBackground' "$content_qml")" "1"

check "preview target is tile.previewTarget (another real image for the current tile, the hovered tile's own image otherwise)" \
  "$(grep -c 'toPath: tile.previewTarget' "$content_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
