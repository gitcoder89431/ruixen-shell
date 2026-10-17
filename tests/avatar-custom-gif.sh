#!/usr/bin/env bash
# Guards the custom avatar GIF path. Animated GIFs can store each frame
# as an offset rectangle inside a larger logical canvas; ImageMagick
# must coalesce those frames before writing the Ruixen-owned animated
# avatar file or the avatar appears off-center even though the source
# GIF is valid. The OS-facing ~/.face.icon stays a static first-frame
# fallback because Qt's animated decoder is not reliable with that
# extensionless path.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
launcher_settings_qml="$repo_dir/ruixen.launcher/extensions/settings/SettingsContent.qml"
# Issue #102 phase 6: the avatar preview card's own visual markup moved
# out of SettingsContent.qml into pages/ProfilePage.qml -- the
# conversion entry point/Process command construction (checked above
# against launcher_settings_qml) stayed put.
profile_page_qml="$repo_dir/ruixen.launcher/extensions/settings/pages/ProfilePage.qml"
notch_qml="$repo_dir/bars/widgets/ruixen.notch/Overlay.qml"
# The avatar RENDERING (AnimatedImage, frame extraction/timer,
# MultiEffect mask swap) lives in NotchWindow.qml now -- the state
# itself (avatarAnimated = !!p.animated, reading the JSON) stays on
# Overlay.qml's own root, genuinely singleton.
notch_window_qml="$repo_dir/bars/widgets/ruixen.notch/NotchWindow.qml"
metrics_qml="$repo_dir/bars/widgets/ruixen.notch/MetricsContent.qml"

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

check "launcher settings has the same custom avatar conversion entry point" \
  "$(grep -cF '"ruixen-avatar-custom", filePath, target, root.avatarGifPath' "$launcher_settings_qml")" "1"
check "launcher settings coalesces GIF frame geometry before resize" \
  "$(grep -cF -- '-coalesce' "$launcher_settings_qml")" "2"
check "launcher settings forces animated custom avatars to loop forever" \
  "$(grep -cF -- '-loop 0' "$launcher_settings_qml")" "2"
check "launcher settings writes animated custom avatars to the real gif path" \
  "$(grep -cF "GIF:\$gif" "$launcher_settings_qml")" "1"
check "launcher settings writes PNG face-icon fallbacks for custom avatars" \
  "$(grep -cF "PNG:\$target" "$launcher_settings_qml")" "2"
check "launcher settings persists whether the active avatar is animated" \
  "$(grep -cF 'animated: root.avatarAnimated' "$launcher_settings_qml")" "1"
check "launcher settings preview switches to extracted frame sources when avatar state is animated" \
  "$(grep -cF 'settingsRoot.avatarFrameDir' "$profile_page_qml")" "1"
check "launcher settings preview advances extracted avatar frames with a timer" \
  "$(grep -cF 'settingsRoot.avatarFrameCount > 1' "$profile_page_qml")" "1"
check "launcher settings preview renders animated avatars directly instead of through MultiEffect" \
  "$(grep -cF 'visible: settingsRoot.avatarAnimated' "$profile_page_qml")" "1"
check "launcher settings preview keeps the MultiEffect mask for static avatars only" \
  "$(grep -cF 'visible: !settingsRoot.avatarAnimated' "$profile_page_qml")" "2"
check "notch avatar uses AnimatedImage so a valid GIF can animate" \
  "$(grep -c 'AnimatedImage {' "$notch_window_qml")" "1"
check "notch reads avatar state to decide whether the active avatar is animated" \
  "$(grep -cF 'root.avatarAnimated = !!p.animated' "$notch_qml")" "1"
check "notch switches to extracted frame sources when avatar state is animated" \
  "$(grep -cF 'notchRoot.avatarFrameDir' "$notch_window_qml")" "2"
check "notch advances extracted avatar frames with a timer" \
  "$(grep -cF 'notchRoot.avatarFrameCount > 1' "$notch_window_qml")" "1"
check "notch renders animated avatars directly instead of through MultiEffect" \
  "$(grep -cF 'visible: panel.notchRoot.avatarAnimated' "$notch_window_qml")" "1"
check "notch keeps the MultiEffect mask for static avatars only" \
  "$(grep -cF 'visible: !panel.notchRoot.avatarAnimated' "$notch_window_qml")" "2"
check "expanded health page receives animated avatar state from the notch" \
  "$(grep -cF 'avatarAnimated: panel.notchRoot.avatarAnimated' "$notch_window_qml")" "1"
check "expanded health page switches to extracted frame sources when avatar state is animated" \
  "$(grep -cF 'root.avatarFrameDir' "$metrics_qml")" "1"
check "expanded health page advances extracted avatar frames with a timer" \
  "$(grep -cF 'root.avatarFrameCount > 1' "$metrics_qml")" "1"
check "expanded health page renders animated avatars directly instead of through MultiEffect" \
  "$(grep -cF 'visible: root.avatarAnimated' "$metrics_qml")" "1"
check "expanded health page keeps fallback and MultiEffect static-only" \
  "$(grep -cF 'visible: !root.avatarAnimated' "$metrics_qml")" "2"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
