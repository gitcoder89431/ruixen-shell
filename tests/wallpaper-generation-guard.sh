#!/usr/bin/env bash
# Direct QA report: switching back and forth between the notch's own
# Wallpapers tab and the launcher's Wallpapers/Wallpaper Shuffle
# extensions eventually left ONE of them permanently unresponsive to
# clicks -- no visible error, the picker just stopped changing the
# wallpaper, only fixed by a full shell restart.
#
# Root cause traced through the actual code: all three pickers keep a
# LOCAL selectGeneration, seeded once from Date.now() at the instance's
# own creation, then bumped with a plain `+= 1` on every click and sent
# to ruixen.wallpaper/Service.qml's shared, process-lifetime
# acceptsGeneration() gate (GenerationGuard.js: a candidate older than
# the last one the service accepted is silently rejected, no error).
# The notch's own WallpapersContent is never recreated once the shell
# starts (same "alive for the whole session" shape as its sibling
# DashboardContent), so its local counter is frozen wherever its own
# last click left it. A run of clicks in a DIFFERENT picker pushes the
# service's shared threshold up past that frozen value; every later
# click in the first picker then does +1 off its own now-stale local
# number and can never clear the threshold again -- permanently
# rejected until the whole shell restart reseeds that one property.
#
# Fix: nextGeneration() = Math.max(Date.now(), selectGeneration + 1)
# in all three pickers, replacing the plain `+= 1`. Still strictly
# increasing within one picker for two rapid clicks (so a slow older
# reply still can't stomp a newer one that already landed -- the
# original #22 guarantee this whole mechanism exists for), but a click
# after any idle stretch jumps back up to the real current timestamp
# instead of crawling up one at a time from a stale baseline, so an
# idle picker catches back up to whichever sibling was just used on its
# very next click.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
notch_qml="$repo_dir/bars/widgets/ruixen.notch/WallpapersContent.qml"
launcher_qml="$repo_dir/ruixen.launcher/extensions/wallpapers/WallpapersContent.qml"
shuffle_qml="$repo_dir/ruixen.launcher/extensions/wallpaper-shuffle/WallpaperShuffleContent.qml"
run_all="$repo_dir/tests/run-all.sh"

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

for f in "$notch_qml" "$launcher_qml" "$shuffle_qml"; do
  name="$(basename "$(dirname "$f")")/$(basename "$f")"

  check "$name: nextGeneration() exists and is the real wall-clock-floor fix, not a plain counter" \
    "$(grep -A2 'function nextGeneration() {' "$f" | grep -c 'return Math.max(Date.now(), root.selectGeneration + 1)')" "1"

  check "$name: no leftover plain '+= 1' bump on selectGeneration anywhere" \
    "$(grep -c 'selectGeneration += 1' "$f")" "0"
done

check "notch WallpapersContent: exactly two call sites (select, applyTheme) route through nextGeneration()" \
  "$(grep -c 'root.selectGeneration = root.nextGeneration()' "$notch_qml")" "2"
check "launcher Wallpapers extension: select() routes through nextGeneration()" \
  "$(grep -c 'root.selectGeneration = root.nextGeneration()' "$launcher_qml")" "1"
check "launcher Wallpaper Shuffle extension: applySelected() routes through nextGeneration()" \
  "$(grep -c 'root.selectGeneration = root.nextGeneration()' "$shuffle_qml")" "1"

check "suite is registered in run-all.sh" \
  "$(grep -c 'wallpaper-generation-guard\.sh' "$run_all")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
