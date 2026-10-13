#!/usr/bin/env bash
# Video/GIF are real rotation candidates now, not excluded -- direct
# ask: "but that doesnt get rid of the video not working. so like how
# do we shuffle a video". Two real deadlocks were found and fixed while
# building this, both confirmed live, not just reasoned about:
#
# 1. ruixen.wallpaper/Service.qml pauses rotation while ANY video/GIF
#    is playing, and neither ever naturally "finishes" (MediaPlayer
#    .Infinite / AnimatedImage's own native loop) -- so if rotation
#    picked one, nothing would ever un-pause it again. Fixed by only
#    pausing for a video/GIF that is NOT what rotation itself just
#    applied (WallpaperRotation.qml's own lastAppliedPath).
# 2. Routing rotation's own playVideo/playGif/stop calls through a REAL
#    numeric generation bumped Service.qml's cross-IPC
#    root.selectGeneration -- the same property WallpaperRotation's own
#    selectionEpoch is bound to -- which looked exactly like an
#    external pick superseding rotation's own in-flight apply and
#    killed it mid-command every single time (confirmed live: every
#    successful apply still reported "Unable to apply artwork"). Fixed
#    by passing a non-numeric "rotation" generation, which
#    GenerationGuard.acceptGeneration already treats as trusted but
#    inert (applies the action, leaves the tracked generation
#    untouched) -- a real external pick still provides its own real
#    generation and still correctly pre-empts rotation.
# 3. A shell restart while rotation was sitting on a video/GIF it had
#    picked left the freshly recreated WallpaperRotation instance's own
#    lastAppliedPath empty, making the resumed video look exactly like
#    a foreign manual pick and re-triggering deadlock #1 every restart.
#    Fixed by having resumeProc also set rotation.lastAppliedPath after
#    replaying a video/GIF.
#
# Can't drive a real Quickshell instance or an actual video/GIF
# playback cycle here (no compositor in CI), so this is a static
# invariant check against the actual source, same style as
# tests/workspaces-pill-strict.sh's own pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
rotation_qml="$repo_dir/ruixen.wallpaper/WallpaperRotation.qml"
service_qml="$repo_dir/ruixen.wallpaper/Service.qml"
rotation_py="$repo_dir/ruixen.wallpaper/wallpaper-rotation.py"

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

check "next_artwork's candidate extensions include gif and the real video set" \
  "$(grep -c "'.avif','.gif','.mp4','.mkv','.webm','.mov','.m4v'" "$rotation_py")" "1"

check "rotation dispatches video through ruixen.wallpaper's own playVideo IPC, not the plain bg-setter" \
  "$(grep -c '"omarchy-shell", "ruixen.wallpaper", "playVideo", result.path, "rotation"' "$rotation_qml")" "1"

check "rotation dispatches gif through ruixen.wallpaper's own playGif IPC" \
  "$(grep -c '"omarchy-shell", "ruixen.wallpaper", "playGif", result.path, "rotation"' "$rotation_qml")" "1"

check "rotation's own IPC calls use a non-numeric generation, not a real counter (would self-trigger the cross-IPC guard)" \
  "$(grep -c 'rotationGeneration' "$rotation_qml")" "0"

check "the service's pause binding compares against rotation's own lastAppliedPath, not a blanket video/GIF check" \
  "$(grep -A5 'paused: (root.videoPath' "$service_qml" | grep -c 'rotation.lastAppliedPath')" "2"

check "resumeProc also seeds rotation.lastAppliedPath after replaying a video/GIF (deadlock #3)" \
  "$(grep -A2 'rotation.lastAppliedPath = p' "$service_qml" | grep -c 'resumeProc\|rotation.lastAppliedPath = p')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
