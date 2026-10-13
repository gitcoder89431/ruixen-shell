#!/usr/bin/env bash
# Direct report: "the shuffle chip on the expanded notch wallpaper
# panel is abit tight compared to the effect, we can like make it
# more not as compact". Root cause: the Effect chip's own value
# segment (backgroundEffectChip) is a fixed width, always reserving
# room for "Matrix" regardless of what's actually showing -- the
# Shuffle chip's own value segment (rotationChip) instead shrink-
# wrapped whatever label was currently showing (often just "Off"),
# so it visibly shrank and grew as the interval cycled and read as
# tighter than Effect at a glance even though both used the same
# per-pixel padding constant. Fixed by giving rotationChip the same
# FontMetrics-based fixed-width technique backgroundEffectChip
# already uses.
#
# Can't drive a real Quickshell instance here (no compositor in CI),
# so this is a static invariant check against the actual source, same
# style as tests/wallpaper-sidebar-style.sh's own pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
wallpapers_qml="$repo_dir/bars/widgets/ruixen.notch/WallpapersContent.qml"

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

check "the Shuffle chip's value segment is a fixed width, same technique the Effect chip's own value segment already uses" \
  "$(grep -Fc 'readonly property real valueSegmentWidth: Math.max(' "$wallpapers_qml")" "2"

check "the fixed width covers all five interval values (Off/5m/15m/30m/60m), not just the current one" \
  "$(grep -A10 'id: rotationValueMetrics' "$wallpapers_qml" | grep -c 'advanceWidth("Off")\|advanceWidth("5m")\|advanceWidth("15m")\|advanceWidth("30m")\|advanceWidth("60m")')" "5"

check "the value segment Rectangle actually uses the computed fixed width, not the label's own implicitWidth any more" \
  "$(grep -Fc 'width: rotationChip.valueSegmentWidth' "$wallpapers_qml")" "1"

check "the old shrink-to-fit width expression is gone from the value segment" \
  "$(grep -Fc 'width: rotationValueLabel.implicitWidth + 14' "$wallpapers_qml")" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
