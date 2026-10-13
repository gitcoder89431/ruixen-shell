#!/usr/bin/env bash
# Direct ask: "ahh so if i manually select something as the wallpaper,
# then the live que breaks?" -- it did: applySelected()/select() in all
# three manual-pick surfaces only ever flipped currentBackground, never
# touched the persisted order, so the queue stayed stale until
# rotation's own timer happened to fire again (or never, if it was
# off). Fixed with a markCurrent IPC action
# (ruixen-wallpaper-rotation markCurrent <filename>) that runs the same
# round-robin rotate_to() does for its own picks, fired from every
# manual-pick call site right alongside its existing apply IPC.
#
# This file exists because that wiring broke once already in a way
# none of the other static checks caught: the QML call sites called
# "mark-current" (matching the Python CLI's own action name) while the
# exposed IpcHandler function is markCurrent -- omarchy-shell's own
# dispatch matches by exact function name, not a CLI-style alias, so
# the mismatch failed silently at the IPC layer (confirmed live:
# "Function not found", exit 1) while qmllint/plugin-validate/
# tests/wallpaper-rotation.py's own unit tests all stayed green, since
# none of them actually drive the IPC call end-to-end. This file pins
# literal exact-name agreement between the handler and every caller so
# that specific class of drift can't silently reappear.
#
# Can't drive a real Quickshell instance or an actual IPC round-trip
# here (no compositor in CI), so this is a static invariant check
# against the actual source, same style as
# tests/wallpaper-rotation-video.sh's own pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
rotation_qml="$repo_dir/ruixen.wallpaper/WallpaperRotation.qml"
rotation_py="$repo_dir/ruixen.wallpaper/wallpaper-rotation.py"
shuffle_qml="$repo_dir/ruixen.launcher/extensions/wallpaper-shuffle/WallpaperShuffleContent.qml"
launcher_wallpapers_qml="$repo_dir/ruixen.launcher/extensions/wallpapers/WallpapersContent.qml"
notch_wallpapers_qml="$repo_dir/bars/widgets/ruixen.notch/WallpapersContent.qml"

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

check "the IPC surface exposes markCurrent, matching the exact name every caller below must use" \
  "$(grep -Fc 'function markCurrent(path: string): void' "$rotation_qml")" "1"

check "a manual pick also stamps lastAppliedPath, so Service.qml's pause binding clears immediately instead of sticking forever" \
  "$(grep -A2 'function markCurrent(path) {' "$rotation_qml" | grep -Fc 'root.lastAppliedPath = path')" "1"

check "rotate_to() exists in the Python helper, doing the same round-robin next_artwork() does" \
  "$(grep -c '^def rotate_to' "$rotation_py")" "1"

check "the mark-current CLI action is wired to rotate_to()" \
  "$(grep -Fc "elif action=='mark-current': rotate_to" "$rotation_py")" "1"

for pair in \
  "Wallpaper Shuffle's Set as wallpaper action:$shuffle_qml" \
  "the launcher Wallpapers grid's own picker:$launcher_wallpapers_qml" \
  "the notch Wallpapers grid's own picker:$notch_wallpapers_qml"
do
  label="${pair%%:*}"
  file="${pair#*:}"
  check "$label calls the IPC handler by its exact exposed name (markCurrent, not mark-current)" \
    "$(grep -Fc '"ruixen-wallpaper-rotation", "markCurrent"' "$file")" "1"
  check "$label never calls the mismatched hyphenated form that silently no-ops at the IPC layer" \
    "$(grep -Fc '"ruixen-wallpaper-rotation", "mark-current"' "$file")" "0"
  check "$label passes the full resolved path, not a stripped filename (markCurrent needs the full path to stamp lastAppliedPath)" \
    "$(grep -c '"ruixen-wallpaper-rotation", "markCurrent", .*\.substring(' "$file")" "0"
done

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
