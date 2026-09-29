#!/usr/bin/env bash
# Theme discovery for the notch Wallpapers tab's own Theme mode (the
# WALLPAPER/THEME sliding tab) -- same extraction rationale as
# list-wallpapers.sh's own header: the live
# picker (WallpapersContent.qml's themeListProc) and the test
# (tests/notch-theme-switcher.sh) both run THIS exact file, so there is
# only one implementation to keep correct. Lives inside ruixen.notch/
# itself so it deploys as part of the plugin's own `cp -r` in
# install.sh, same as its wallpaper sibling.
#
# No arguments; reads $HOME and $OMARCHY_PATH directly. Prints one
# newline-separated record per theme found:
#   name<US>display<US>preview
# where name is the theme directory's basename (the exact string
# omarchy-theme-set accepts -- it re-normalizes case/dashes itself, so
# this script deliberately does NOT pre-title-case the value that gets
# applied), display is the human-readable label (same sed transform
# omarchy-theme-list uses), and preview is an absolute path to a
# representative image for the tile, or an empty third field when the
# theme ships none (the tile falls back to rendering the name).
#
# <US> is ASCII Unit Separator (0x1f), same record convention as
# list-wallpapers.sh -- a legal filename containing | would otherwise
# break the record.
#
# Preview lookup copies omarchy-theme-switcher's own find_preview
# (read directly, not guessed): preview.png/jpg/jpeg/webp/gif/bmp at
# the theme dir's top level, else the alphabetically-first image in its
# backgrounds/ subdirectory. A user theme with no preview of its own
# falls back to the same-name system theme's preview, matching the
# switcher's own behavior for the common "user symlinks a theme dir
# but only the system copy ships images" case.
#
# No `set -e` -- deliberately, matching list-wallpapers.sh: a theme
# dir with an unreadable/odd shape is an expected, tolerated outcome
# here (the find just yields nothing for it), not an abort.
set -uo pipefail

USER_THEMES_PATH="$HOME/.config/omarchy/themes"
OMARCHY_THEMES_PATH="${OMARCHY_PATH:-/usr/share/omarchy}/themes"
US=$'\x1f'

find_preview() {
  local theme_path="$1"
  local preview preview_name

  for preview_name in preview.png preview.jpg preview.jpeg preview.webp preview.gif preview.bmp; do
    preview=$(find -L "$theme_path" -maxdepth 1 -type f -iname "$preview_name" -print -quit 2>/dev/null)
    if [[ -n $preview ]]; then
      printf '%s\n' "$preview"
      return
    fi
  done

  if [[ -d "$theme_path/backgrounds" ]]; then
    find -L "$theme_path/backgrounds" -maxdepth 1 -type f \
      \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.gif' -o -iname '*.bmp' -o -iname '*.webp' \) \
      -print 2>/dev/null | sort | head -n 1
  fi
}

# User themes (dirs or symlinks, matching omarchy-theme-list's own
# -type d -o -type l) then system themes (dirs only, same as there),
# deduped by name with the user copy taking precedence for the preview
# lookup -- the exact same two-source union omarchy-theme-set resolves
# against, so everything this lists is applyable and nothing applyable
# is missing.
{
  find -L "$USER_THEMES_PATH" -mindepth 1 -maxdepth 1 \( -type d -o -type l \) -printf '%f\n' 2>/dev/null
  find "$OMARCHY_THEMES_PATH" -mindepth 1 -maxdepth 1 -type d -printf '%f\n' 2>/dev/null
} | sort -u | while IFS= read -r name; do
  [[ -n "$name" ]] || continue
  # Dot-dirs are not themes -- omarchy-theme-set itself rejects names
  # starting with "." ("Invalid theme name"), so listing one would only
  # produce a tile whose click can never apply.
  [[ "$name" != .* ]] || continue
  if [[ -d "$USER_THEMES_PATH/$name" || -L "$USER_THEMES_PATH/$name" ]]; then
    theme_path="$USER_THEMES_PATH/$name"
  else
    theme_path="$OMARCHY_THEMES_PATH/$name"
  fi
  preview=$(find_preview "$theme_path")
  if [[ -z "$preview" && "$theme_path" != "$OMARCHY_THEMES_PATH/$name" ]]; then
    preview=$(find_preview "$OMARCHY_THEMES_PATH/$name")
  fi
  display=$(printf '%s' "$name" | sed -E 's/(^|-)([a-z])/\1\u\2/g; s/-/ /g')
  printf '%s%s%s%s%s\n' "$name" "$US" "$display" "$US" "$preview"
done
