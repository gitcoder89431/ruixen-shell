#!/usr/bin/env bash
# Covers a direct report from another user: Super+Shift+Space (stock
# Omarchy's bind_toggle "bar", which runs omarchy-toggle-bar) hides
# ruixen.bar's own left/right pill groups fine, but "the notch is
# different" -- it stayed on screen. Root cause: ruixen.notch is a
# completely separate PanelWindow/surface from ruixen.bar, so
# ruixen.bar's own barHiddenProbe (watching the on-disk
# ~/.local/state/omarchy/toggles/bar-off flag omarchy-toggle-bar
# flips) never told this window anything at all.
#
# Fix: ported the exact same flag-watching Process + FileView pair
# into ruixen.notch/Overlay.qml, reading the exact same on-disk file
# ruixen.bar already does -- not a second, competing toggle mechanism.
# Both surfaces just read the one real piece of state Omarchy's own
# toggle script writes.
#
# Can't drive a real Quickshell instance here (no compositor in CI), so
# this is a static invariant check against the actual QML source, same
# style as tests/bar-popup-clearance.sh's own pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
bar_qml="$repo_dir/ruixen.bar/Bar.qml"
overlay_qml="$repo_dir/ruixen.notch/Overlay.qml"

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

bar_flag_path='$HOME/.local/state/omarchy/toggles/bar-off'

check "ruixen.bar itself still watches the real bar-off flag (the source of truth this test pins against)" \
  "$(grep -c -- "-f $bar_flag_path" "$bar_qml" || true)" "1"

check "ruixen.notch declares its own barHidden property" \
  "$(grep -c 'property bool barHidden: false' "$overlay_qml" || true)" "1"

check "ruixen.notch watches the EXACT SAME on-disk flag path as ruixen.bar, not a second one" \
  "$(grep -c -- "-f $bar_flag_path" "$overlay_qml" || true)" "1"

check "ruixen.notch watches the parent toggles directory (FileView can't observe a file that does not exist yet)" \
  "$(grep -c 'path: Quickshell.env("HOME") + "/.local/state/omarchy/toggles"' "$overlay_qml" || true)" "1"

check "the notch's own PanelWindow visibility now also depends on barHidden, not fullscreen alone" \
  "$(grep -c 'visible: !root.fullscreenActive && !root.barHidden' "$overlay_qml" || true)" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
