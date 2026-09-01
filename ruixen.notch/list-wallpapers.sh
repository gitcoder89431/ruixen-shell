#!/usr/bin/env bash
# Wallpaper discovery + poster caching pipeline -- the SAME
# implementation the live picker (WallpapersContent.qml's listProc) and
# tests/wallpaper-discovery-format.sh both run, extracted here so
# neither can silently drift from the other. Direct review finding
# ("Extract wallpaper discovery into shared production code so tests
# cannot drift", #17): this used to live only as an inline
# Process.command string in WallpapersContent.qml, with the test suite
# keeping its own "faithful copy" that had to be hand-kept in sync --
# a real risk (a production change landing while the test's copy
# silently stayed correct-looking and still passed CI).
#
# Deliberately the one exception in this repo to "plugin shell snippets
# stay inline as Process.command strings, never a separate shipped
# file" -- that convention exists because nothing else here needed the
# exact same shell logic runnable from two different places (a live
# Process AND a test) at once; this is the first thing that genuinely
# does. Lives inside ruixen.notch/ itself, not lib/, specifically so it
# deploys as part of the plugin's own `cp -r` in install.sh with no
# separate deploy step needed -- same "a deployed thing must not depend
# on the checkout persisting" reasoning as #15's looknfeel fix, just
# solved here by colocating the script with its one real consumer
# instead of a stable data path.
#
# No arguments; reads $HOME directly, exactly like the Process it
# replaces did. Prints one newline-separated record per wallpaper found:
#   kind<US>display<US>real
# where kind is image / gif / video, display and real are the same path
# for image/gif, and display is the cached poster JPEG for video (real
# stays the actual video file, used for playback).
#
# <US> is ASCII Unit Separator (0x1F), not "|" -- a legal Linux filename
# containing | would otherwise break this record, and 0x1F is the
# standard non-printable field-separator control character a real
# filename would have to go out of its way to contain.
#
# No `set -e` -- deliberately, matching the original inline version:
# ffmpeg failing on a corrupt/undecodable video is an EXPECTED, tolerated
# outcome here (see the video case below, which just skips printing a
# record when no poster resulted), not a script-aborting error. Adding
# strict mode here would repeat the exact bug
# tests/gif-poster-fallback.sh's own comment already documents catching
# once this session in a different script's test double.
set -uo pipefail

theme=$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null)
mkdir -p "$HOME/Pictures/ruixen-wallpapers" "$HOME/.cache/ruixen/wallpaper-posters"
US=$'\x1f'

# Classifies each NUL-delimited path read from stdin: a plain image
# prints image<US>path<US>path (display and real are the same thing); a
# gif prints gif<US>path<US>path too (no poster needed -- Image already
# renders a gif's own first frame directly, same as any other static
# image); a video ensures its poster exists (same md5-of-real-path
# cache naming ruixen.wallpaper's own Service.qml uses for its own
# poster lookups, so both sides agree on the same cache file with
# neither one telling the other its path) then prints
# video<US>poster<US>path -- a video with no decodable first frame
# (corrupt file, unsupported codec) is silently skipped rather than
# printing a record for a broken tile.
#
# Poster staleness: the ffmpeg extraction re-runs when the source video
# is newer than its cached poster (-nt, bash's built-in mtime
# comparison), not just when the poster is entirely missing -- replacing
# a video with new content at the same path would otherwise keep the
# old cached poster indefinitely. Deliberately compares mtimes rather
# than baking mtime into the cache filename itself: a changed filename
# would orphan the old poster file forever with nothing to ever clean
# it up, where overwriting the same filename in place needs no separate
# pruning step at all.
process() {
  while IFS= read -r -d '' f; do
    case "${f,,}" in
      *.mp4 | *.mkv | *.webm | *.mov | *.m4v)
        hash=$(printf '%s' "$f" | md5sum | cut -d' ' -f1)
        poster="$HOME/.cache/ruixen/wallpaper-posters/$hash.jpg"
        if [[ ! -f "$poster" ]] || [[ "$f" -nt "$poster" ]]; then
          ffmpeg -y -loglevel quiet -i "$f" -vframes 1 -q:v 3 "$poster" 2>/dev/null
        fi
        [[ -f "$poster" ]] && printf 'video%s%s%s%s\n' "$US" "$poster" "$US" "$f"
        ;;
      *.gif)
        printf 'gif%s%s%s%s\n' "$US" "$f" "$US" "$f"
        ;;
      *)
        printf 'image%s%s%s%s\n' "$US" "$f" "$US" "$f"
        ;;
    esac
  done
}

# Theme wallpapers (the exact same two directories/extensions
# omarchy-theme-bg-switcher passes to the stock image-picker overlay)
# THEN the user's own persistent folder, appended after. Two
# find | sort | process pipelines run back to back, specifically so the
# two groups stay in that order in the output -- a single sort across
# all three directories would interleave user wallpapers alphabetically
# among the theme ones instead of keeping them after.
#
# find/sort/read are all NUL-delimited (-print0/-z/-d '') so a filename
# is never split on its own bytes during discovery, no matter what
# characters it legally contains.
#
# ~/Pictures/ruixen-wallpapers is plain filesystem state (not
# ~/.local/state/ruixen/ like this repo's other persisted settings) on
# purpose -- Pictures is where a person would actually go drop image
# files in with a file manager, and it's never touched by Omarchy's own
# theme switching (unlike the two directories above, which are
# theme-scoped and change contents whenever the active theme does), so
# it survives every theme change untouched. Created with mkdir -p above
# on every run so it's there and ready even before the user has dropped
# anything into it.
find -L "$HOME/.local/state/omarchy/current/theme/backgrounds" "$HOME/.config/omarchy/backgrounds/$theme" \
  -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.webp" \
  -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.mov" -o -iname "*.m4v" \) \
  -print0 2>/dev/null | sort -z | process
find -L "$HOME/Pictures/ruixen-wallpapers" \
  -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.webp" \
  -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.mov" -o -iname "*.m4v" \) \
  -print0 2>/dev/null | sort -z | process
