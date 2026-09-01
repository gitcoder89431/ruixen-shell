#!/usr/bin/env bash
# Covers "[P2] Harden wallpaper discovery/state serialization and poster
# cache invalidation", "[P2] Extract wallpaper discovery into shared
# production code so tests cannot drift" (#17), and now "[P2] Keep GIF
# wallpaper CURRENT state in sync with its static poster fallback"
# (#23): runs the REAL ruixen.notch/list-wallpapers.sh -- the exact
# script WallpapersContent.qml's own listProc invokes -- against a
# throwaway directory tree with real, exotic-named files.
#
# This used to keep its own hand-copied "faithful reproduction" of the
# discovery logic, with a comment warning that a production change
# would need the copy updated too -- a real risk: a bug landing in
# production while this copy stayed old-and-passing. Now there is only
# one implementation, and this file just exercises it.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
list_wallpapers="$repo_dir/ruixen.notch/list-wallpapers.sh"

command -v ffmpeg >/dev/null 2>&1 || {
  printf 'wallpaper-discovery-format: ffmpeg is required (command "ffmpeg" not found)\n' >&2
  exit 1
}

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

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
export HOME="$work"
mkdir -p "$HOME/Pictures/ruixen-wallpapers" "$HOME/.cache/ruixen/wallpaper-posters"

# The real script also scans $HOME/.local/state/omarchy/current/theme/
# backgrounds and $HOME/.config/omarchy/backgrounds/<theme> -- neither
# exists under this throwaway $HOME, so `find -L ... 2>/dev/null` on
# them silently contributes nothing, same as the old Pictures-only
# test double did. Every case below is scoped to
# ~/Pictures/ruixen-wallpapers on purpose, exactly like before.
run_discovery() {
  "$list_wallpapers"
}

# --- Case 1: exotic filenames survive discovery intact --------------
touch "$HOME/Pictures/ruixen-wallpapers/normal.png" \
      "$HOME/Pictures/ruixen-wallpapers/with space.png" \
      "$HOME/Pictures/ruixen-wallpapers/pipe|char.png" \
      "$HOME/Pictures/ruixen-wallpapers/apostrophe's.png" \
      "$HOME/Pictures/ruixen-wallpapers/日本語ファイル.png" \
      "$HOME/Pictures/ruixen-wallpapers/-leading-dash.png"

output="$(run_discovery)"
line_count=$(printf '%s\n' "$output" | grep -c .)
check "exotic filenames: all 6 files discovered, one record each" "$line_count" "6"

for name in "with space.png" "pipe|char.png" "apostrophe's.png" "日本語ファイル.png" "-leading-dash.png"; do
  full="$HOME/Pictures/ruixen-wallpapers/$name"
  # Parse each line the same way the QML side does: split on the field
  # separator, take the 3rd field (real), compare byte-for-byte.
  found=$(printf '%s\n' "$output" | awk -F'\x1f' -v want="$full" '$3 == want { print "found"; exit }')
  check "exotic filename survives intact: $name" "$found" "found"
done

# --- Case 2: poster regenerates when the source video is newer ------
video="$HOME/Pictures/ruixen-wallpapers/test-video.mp4"
ffmpeg -y -loglevel quiet -f lavfi -i color=c=blue:size=32x32:duration=1 -r 1 "$video" 2>/dev/null
run_discovery >/dev/null

hash=$(printf '%s' "$video" | md5sum | cut -d' ' -f1)
poster="$HOME/.cache/ruixen/wallpaper-posters/$hash.jpg"
check "video: poster generated on first discovery" "$([[ -f "$poster" ]] && echo yes)" "yes"

poster_mtime_before=$(stat -c '%Y' "$poster")
sleep 1.1
touch "$video"
run_discovery >/dev/null
poster_mtime_after_touch=$(stat -c '%Y' "$poster")
check "video: poster regenerated after source video changed (newer mtime)" \
  "$([[ "$poster_mtime_after_touch" -gt "$poster_mtime_before" ]] && echo yes)" "yes"

poster_mtime_stable=$(stat -c '%Y' "$poster")
sleep 1.1
run_discovery >/dev/null
poster_mtime_after_norun=$(stat -c '%Y' "$poster")
check "video: poster NOT regenerated when source video is unchanged" \
  "$poster_mtime_after_norun" "$poster_mtime_stable"

# --- Case 3: a corrupt/unsupported video is skipped, not fatal ------
corrupt="$HOME/Pictures/ruixen-wallpapers/corrupt.mp4"
printf 'this is not a real video file' > "$corrupt"
output2="$(run_discovery)"
corrupt_line=$(printf '%s\n' "$output2" | grep -F "$corrupt" || true)
check "corrupt video: silently produces no record (no crash, no broken line)" "$corrupt_line" ""
still_there=$(printf '%s\n' "$output2" | grep -c "normal.png" || true)
check "corrupt video: the rest of the library is still discovered" "$still_there" "1"

# --- Case 4 (#23): a GIF's identity field (the one root.currentBackground
# gets compared against, not display) is the same poster-hash path
# ruixen.wallpaper/Service.qml's own playGif() independently computes
# for that exact gif path -- verified against the SAME hash formula
# lifted directly from Service.qml's own source, not just "matches
# itself." Also confirms discovery never generates the poster file for
# a gif that's never been selected (no ffmpeg cost paid just for
# browsing the picker), unlike video's eager poster generation.
gif="$HOME/Pictures/ruixen-wallpapers/test-anim.gif"
ffmpeg -y -loglevel quiet -f lavfi -i color=c=red:size=8x8:duration=1 -r 1 "$gif" 2>/dev/null
gif_hash=$(printf '%s' "$gif" | md5sum | cut -d' ' -f1)
expected_identity="$HOME/.cache/ruixen/wallpaper-posters/$gif_hash.jpg"

output3="$(run_discovery)"
gif_line=$(printf '%s\n' "$output3" | grep -F "$gif" | head -1)
check "gif: display is the raw .gif (tile still renders it directly)" \
  "$(awk -F'\x1f' '{print $2}' <<<"$gif_line")" "$gif"
check "gif: real is the raw .gif (playback target unchanged)" \
  "$(awk -F'\x1f' '{print $3}' <<<"$gif_line")" "$gif"
check "gif: identity matches Service.qml's own playGif() poster-hash formula (#23)" \
  "$(awk -F'\x1f' '{print $4}' <<<"$gif_line")" "$expected_identity"
check "gif: no poster file was generated just for discovery (no ffmpeg cost until actually selected)" \
  "$([[ -f "$expected_identity" ]] && echo present || echo absent)" "absent"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
