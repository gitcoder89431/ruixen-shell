#!/usr/bin/env bash
# Covers "[P0/P1] Use a static fallback poster for GIF wallpapers to
# avoid Omarchy ImageMagick memory blowups": exercises the exact
# poster-extraction + background-set logic from
# ruixen.wallpaper/Service.qml's own playGif() -- a faithful copy, for
# the same reason tests/wallpaper-discovery-format.sh already
# documents (this repo keeps plugin shell snippets inline in QML
# rather than as separate shipped files, so there's no single script
# both production and this test could import instead).
#
# `omarchy-theme-bg-set` is stubbed (fixtures/fake-bin/omarchy-theme-
# bg-set) to record its argument to a file rather than actually
# touching this machine's real background -- the whole point of this
# suite is confirming it's called with a POSTER, never the raw
# animated file, without needing a real Omarchy install to verify
# that against.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v ffmpeg >/dev/null 2>&1 || {
  printf 'gif-poster-fallback: ffmpeg is required (command "ffmpeg" not found)\n' >&2
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
mkdir -p "$HOME/.cache/ruixen/wallpaper-posters"

# --- The exact logic from playGif()'s own posterAndSetProc.command --
# No `set -e` in the inner script -- deliberately, faithfully matching
# production: Service.qml's own bash -c string doesn't use strict mode
# either, so ffmpeg failing on a corrupt input must NOT abort the rest
# of the script (it needs to reach the `if [[ -f "$poster" ]]` check
# below and correctly find no poster there). Real bug caught by this
# test file itself, not production: an earlier version of this
# reproduction added `set -Eeuo pipefail` here as a general test-
# hygiene habit, which aborted on ffmpeg's own non-zero exit for the
# corrupt-gif case before ever reaching that check -- a mismatch
# between the test and the real code, not a real bug in either.
play_gif() {
  local path="$1"
  bash -c '
    hash=$(printf "%s" "$1" | md5sum | cut -d" " -f1)
    poster="$HOME/.cache/ruixen/wallpaper-posters/$hash.jpg"
    if command -v ffmpeg >/dev/null 2>&1; then
      if [[ ! -f "$poster" ]] || [[ "$1" -nt "$poster" ]]; then
        ffmpeg -y -loglevel quiet -i "$1" -vframes 1 -q:v 3 "$poster" 2>/dev/null
      fi
    fi
    if [[ -f "$poster" ]]; then
      omarchy-theme-bg-set "$poster"
      printf "%s" "$poster"
    fi
  ' "_" "$path"
}

poster_path_for() {
  local hash
  hash=$(printf '%s' "$1" | md5sum | cut -d' ' -f1)
  printf '%s/.cache/ruixen/wallpaper-posters/%s.jpg' "$HOME" "$hash"
}

# --- Case 1: selecting a real GIF sets the POSTER, not the raw file -
gif="$HOME/test.gif"
ffmpeg -y -loglevel quiet -f lavfi -i color=c=blue:size=32x32:duration=1 "$gif" 2>/dev/null
poster="$(poster_path_for "$gif")"

PATH="$fake_bin:$PATH" play_gif "$gif" >/dev/null
check "gif selected: poster file was actually created" "$([[ -f "$poster" ]] && echo yes)" "yes"
check "gif selected: omarchy-theme-bg-set was called with the POSTER, not the raw gif" \
  "$(cat "$HOME/.local/state/ruixen-test/bg-set-arg" 2>/dev/null)" "$poster"

# --- Case 2: re-selecting the same unchanged gif reuses the poster --
poster_mtime_before="$(stat -c '%Y' "$poster")"
sleep 1.1
PATH="$fake_bin:$PATH" play_gif "$gif" >/dev/null
poster_mtime_after="$(stat -c '%Y' "$poster")"
check "unchanged gif: poster was NOT regenerated" "$poster_mtime_after" "$poster_mtime_before"

# --- Case 3: touching/replacing the gif refreshes the poster --------
sleep 1.1
touch "$gif"
PATH="$fake_bin:$PATH" play_gif "$gif" >/dev/null
poster_mtime_touched="$(stat -c '%Y' "$poster")"
check "touched gif: poster WAS regenerated (newer mtime)" \
  "$([[ "$poster_mtime_touched" -gt "$poster_mtime_before" ]] && echo yes)" "yes"

# --- Case 4: a corrupt gif never gets set as the background ---------
corrupt="$HOME/corrupt.gif"
printf 'this is not a real gif file' > "$corrupt"
corrupt_poster="$(poster_path_for "$corrupt")"
rm -f "$HOME/.local/state/ruixen-test/bg-set-arg"
PATH="$fake_bin:$PATH" play_gif "$corrupt" >/dev/null
check "corrupt gif: no poster was produced" "$([[ -f "$corrupt_poster" ]] && echo yes || echo no)" "no"
check "corrupt gif: omarchy-theme-bg-set was never called (nothing to fall back to the raw file with)" \
  "$([[ -f "$HOME/.local/state/ruixen-test/bg-set-arg" ]] && echo called || echo "not called")" "not called"

# --- Case 5: ffmpeg missing -- degrades gracefully, no crash --------
minimal_bin="$work/minimal-bin"
mkdir -p "$minimal_bin"
for tool in bash md5sum cat printf mkdir rm stat sleep touch cut command; do
  real="$(command -v "$tool" 2>/dev/null)"
  [[ -n "$real" ]] && ln -sf "$real" "$minimal_bin/$tool"
done
cp "$fake_bin/omarchy-theme-bg-set" "$minimal_bin/omarchy-theme-bg-set"
another_gif="$HOME/another.gif"
ffmpeg -y -loglevel quiet -f lavfi -i color=c=red:size=32x32:duration=1 "$another_gif" 2>/dev/null
another_poster="$(poster_path_for "$another_gif")"
rm -f "$HOME/.local/state/ruixen-test/bg-set-arg"
if PATH="$minimal_bin" play_gif "$another_gif" >/dev/null 2>"$work/case5.err"; then
  status5=0
else
  status5=$?
fi
check "ffmpeg missing: does not crash" "$status5" "0"
check "ffmpeg missing: no poster produced (nothing to extract with)" \
  "$([[ -f "$another_poster" ]] && echo yes || echo no)" "no"
check "ffmpeg missing: omarchy-theme-bg-set never called (never falls back to the raw animated file)" \
  "$([[ -f "$HOME/.local/state/ruixen-test/bg-set-arg" ]] && echo called || echo "not called")" "not called"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
