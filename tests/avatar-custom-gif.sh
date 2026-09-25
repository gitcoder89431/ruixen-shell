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
settings_qml="$repo_dir/ruixen.settings/Settings.qml"
general_qml="$repo_dir/ruixen.settings/GeneralContent.qml"
notch_qml="$repo_dir/bars/widgets/ruixen.notch/Overlay.qml"

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

check "custom avatar conversion uses ImageMagick directly, not shell interpolation for the picked path" \
  "$(grep -cF '"ruixen-avatar-custom", filePath, target, root.avatarGifPath' "$settings_qml")" "1"
check "custom avatar conversion coalesces GIF frame geometry before resize" \
  "$(grep -cF -- '-coalesce' "$settings_qml")" "2"
check "custom avatar conversion still strips metadata" \
  "$(grep -cF -- '-strip' "$settings_qml")" "3"
check "custom avatar conversion still preserves the shrink-only 512px cap" \
  "$(grep -cF "512x512>" "$settings_qml")" "3"
check "animated custom avatars are written to a real gif path, not extensionless ~/.face.icon" \
  "$(grep -cF 'GIF:$gif' "$settings_qml")" "1"
check "animated custom avatars still write a static ~/.face.icon fallback frame" \
  "$(grep -cF 'PNG:$target' "$settings_qml")" "1"
check "avatar state persists whether the active avatar is animated" \
  "$(grep -cF 'animated: root.avatarAnimated' "$settings_qml")" "1"
check "non-custom avatar branches remove stale animated avatar files" \
  "$(grep -cF 'rm -f \"$2\"' "$settings_qml")" "2"
check "failed avatar conversion reverts the selected collection instead of silently pretending it worked" \
  "$(grep -c 'root.avatarCollection = root.avatarPreviousCollection' "$settings_qml")" "1"
check "failed avatar conversion sends a visible desktop notification" \
  "$(grep -c 'Avatar update failed' "$settings_qml")" "1"
check "settings preview uses AnimatedImage so a valid GIF can animate" \
  "$(grep -c 'AnimatedImage {' "$general_qml")" "1"
check "settings preview switches to the real gif source when avatar state is animated" \
  "$(grep -cF 'settingsRoot.avatarGifPath' "$general_qml")" "1"
check "settings preview renders animated avatars directly instead of through MultiEffect" \
  "$(grep -cF 'visible: settingsRoot.avatarAnimated' "$general_qml")" "1"
check "settings preview keeps the MultiEffect mask for static avatars only" \
  "$(grep -cF 'visible: !settingsRoot.avatarAnimated' "$general_qml")" "1"
check "notch avatar uses AnimatedImage so a valid GIF can animate" \
  "$(grep -c 'AnimatedImage {' "$notch_qml")" "1"
check "notch reads avatar state to decide whether the active avatar is animated" \
  "$(grep -cF 'root.avatarAnimated = !!p.animated' "$notch_qml")" "1"
check "notch switches to the real gif source when avatar state is animated" \
  "$(grep -cF 'root.avatarGifPath' "$notch_qml")" "1"
check "notch renders animated avatars directly instead of through MultiEffect" \
  "$(grep -cF 'visible: root.avatarAnimated' "$notch_qml")" "1"
check "notch keeps the MultiEffect mask for static avatars only" \
  "$(grep -cF 'visible: !root.avatarAnimated' "$notch_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
