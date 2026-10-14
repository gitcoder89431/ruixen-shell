#!/usr/bin/env bash
# Sourced (not executed) by install.sh and ruixen-repair.sh -- issue
# #105: WallpaperRotationState.qml and wallpaper-effects.py used to be
# hand-copied, byte-identical files duplicated across every picker UI
# that needs one (ruixen.notch, ruixen.launcher's Wallpapers and
# Wallpaper Shuffle extensions) -- real backend logic (appearance-
# settings validation, the renderer enable/disable lifecycle), not a
# rendering asset, with nothing enforcing the copies stayed in sync.
# ruixen.wallpaper/ is now the one hand-maintained copy of each.
#
# Extracted here rather than left inline in install.sh (where this
# started) once ruixen-repair.sh's own independent drift-detection
# hash needed the exact same "what does ruixen.launcher/ruixen.notch's
# deployed content actually include" answer -- duplicating fifteen
# lines of staging logic between two scripts is a much smaller, far
# less divergence-prone problem than the 231-line, real-backend-logic
# duplication this issue exists to remove; it would have been a little
# ironic to recreate a smaller version of it right here.
#
# Caller must already have `script_dir` set to the repo root (both
# callers do, from their own top-of-file setup). Relies on the
# caller's own `set -Eeuo pipefail` for error propagation -- this file
# has none of its own since it is never executed directly.

# Appended to by every call -- the caller is responsible for cleaning
# these up (install.sh: right after its own post-deploy hash
# verification, which still needs the staged dirs to exist; ruixen-
# repair.sh's --dry-run / detection-only path: right after hashing).
STAGED_TMP_DIRS=()

# shellcheck disable=SC2154 # script_dir: see this file's own header --
# always set by the caller (install.sh/ruixen-repair.sh) before sourcing.
inject_shared_wallpaper_files() {
  local id="$1" real_source="$2" parent staged
  parent="$(mktemp -d)"
  staged="$parent/$id"
  cp -r "$real_source" "$staged"
  case "$id" in
    ruixen.launcher)
      cp "$script_dir/ruixen.wallpaper/wallpaper-effects.py" "$staged/extensions/wallpapers/wallpaper-effects.py"
      cp "$script_dir/ruixen.wallpaper/WallpaperRotationState.qml" "$staged/extensions/wallpapers/WallpaperRotationState.qml"
      cp "$script_dir/ruixen.wallpaper/WallpaperRotationState.qml" "$staged/extensions/wallpaper-shuffle/WallpaperRotationState.qml"
      ;;
    ruixen.notch)
      cp "$script_dir/ruixen.wallpaper/wallpaper-effects.py" "$staged/wallpaper-effects.py"
      cp "$script_dir/ruixen.wallpaper/WallpaperRotationState.qml" "$staged/WallpaperRotationState.qml"
      ;;
  esac
  STAGED_TMP_DIRS+=("$parent")
  printf '%s' "$staged"
}
