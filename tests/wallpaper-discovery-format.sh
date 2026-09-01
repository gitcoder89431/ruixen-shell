#!/usr/bin/env bash
# Covers "[P2] Harden wallpaper discovery/state serialization and poster
# cache invalidation": exercises the SAME discovery logic
# ruixen.notch/WallpapersContent.qml's own listProc runs, against a
# throwaway directory tree with real, exotic-named files.
#
# The discovery logic lives only as an inline bash -c string inside
# that QML file (no plugin in this repo ships a separate .sh helper --
# every other ruixen.* plugin keeps its shell/python snippets inline
# too, so this follows the same established convention rather than
# introducing a new one). That means the `process()` function below is
# a literal, faithful COPY of the one in WallpapersContent.qml's own
# listProc command, not a shared file -- if that script's discovery
# logic ever changes, this copy needs updating too. Kept intentionally
# small and directly comparable line-for-line to make that easy to
# notice in review.
set -Eeuo pipefail

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

# --- Discovery, faithfully copied from WallpapersContent.qml's listProc
run_discovery() {
  US=$'\x1f'
  process() { while IFS= read -r -d '' f; do
    case "${f,,}" in
      *.mp4|*.mkv|*.webm|*.mov|*.m4v)
        hash=$(printf '%s' "$f" | md5sum | cut -d' ' -f1)
        poster="$HOME/.cache/ruixen/wallpaper-posters/$hash.jpg"
        if [[ ! -f "$poster" ]] || [[ "$f" -nt "$poster" ]]; then
          ffmpeg -y -loglevel quiet -i "$f" -vframes 1 -q:v 3 "$poster" 2>/dev/null
        fi
        [[ -f "$poster" ]] && printf 'video%s%s%s%s\n' "$US" "$poster" "$US" "$f"
        ;;
      *.gif) printf 'gif%s%s%s%s\n' "$US" "$f" "$US" "$f" ;;
      *) printf 'image%s%s%s%s\n' "$US" "$f" "$US" "$f" ;;
    esac
  done; }
  find -L "$HOME/Pictures/ruixen-wallpapers" \
    -maxdepth 1 -type f \( -iname "*.jpg" -o -iname "*.jpeg" -o -iname "*.png" -o -iname "*.gif" -o -iname "*.bmp" -o -iname "*.webp" \
    -o -iname "*.mp4" -o -iname "*.mkv" -o -iname "*.webm" -o -iname "*.mov" -o -iname "*.m4v" \) \
    -print0 2>/dev/null | sort -z | process
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

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
