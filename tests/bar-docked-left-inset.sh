#!/usr/bin/env bash
# Covers a direct live report: in docked mode, the app-icon group at the
# far left ("A", ruixen.applauncher, hosted in menuPill) sat too close to
# the screen edge -- "needs to be relaxed just a bit with padding so it's
# not too close to the dock edge".
#
# menuPill's own leftMargin (12) was deliberately trimmed down from an
# original 20 for floating mode specifically: floating's own per-pill
# GroupPill background gives the icon visual separation from
# ruixen.frame-widget's rounded corner on its own, so bare content needs
# less raw clearance. Docked mode doesn't have that cushion -- its own
# GroupPill is hidden (visible: !root.docked) and replaced by one
# continuous leftDockedBg shape flush with the frame's own corner, so the
# reasoning that justified the smaller floating value never applied
# there. Fixed by making the margin mode-aware: back to the original,
# already-tuned 20 specifically when docked, unchanged 12 when floating.
#
# Can't drive a real Quickshell instance here (no compositor in CI), so
# this is a static invariant check against the actual QML source instead
# -- same style as tests/lint-shell.sh's own pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
bar_qml="$repo_dir/ruixen.bar/Bar.qml"

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

margin_line="$(grep -m1 'anchors.leftMargin: root.docked ? 20 : 12' "$bar_qml")"
check "menuPill's own leftMargin is mode-aware: 20 docked, 12 floating" \
  "$margin_line" '          anchors.leftMargin: root.docked ? 20 : 12'

# leftDockedBg's own outer bounds must stay anchored to the true screen
# edge (x: 0) regardless of this -- the fix is meant to be purely
# internal padding for the icon, not a shift of the merged background
# shape itself.
left_docked_bg_x="$(grep -A2 'id: leftDockedBg$' "$bar_qml" | grep -c 'x: 0$' || true)"
check "leftDockedBg's own x stays 0 (fix is internal padding only, not a background shift)" \
  "$left_docked_bg_x" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
