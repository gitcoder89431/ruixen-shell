#!/usr/bin/env bash
# Same investigation as tests/ruixen-doctor-state-dir.sh (a chroot
# install, no live Hyprland session to reload), different symptom:
# notification popups rendering with square corners and no blur
# instead of Ruixen's own rounded look'n'feel. install.sh's own
# `hyprctl reload` at the end of that step is wrapped in `|| true`
# specifically so a chroot install (nothing there to reload) doesn't
# fail the whole install -- it just means the config on disk may not
# match what's actually live yet. Guards the new
# "-- Hyprland look'n'feel --" section of ruixen-doctor.sh.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
doctor_sh="$repo_dir/ruixen-doctor.sh"

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

fake_home="$(mktemp -d)"
trap 'rm -rf "$fake_home"' EXIT
mkdir -p "$fake_home/.config/hypr" "$fake_home/.local/share/ruixen-shell/hyprland"
for variant in ruixen default half square; do
  printf -- '-- fake %s --\n' "$variant" > "$fake_home/.local/share/ruixen-shell/hyprland/looknfeel.$variant.lua"
done

# --- each real variant is correctly identified by its symlink target -
ln -sf "$fake_home/.local/share/ruixen-shell/hyprland/looknfeel.ruixen.lua" "$fake_home/.config/hypr/looknfeel.lua"
out="$(HOME="$fake_home" bash "$doctor_sh" 2>&1)"
check "ruixen variant: identified as on (rounded + blur)" \
  "$(printf '%s\n' "$out" | grep -c 'variant: on (rounded + blur)')" "1"

ln -sf "$fake_home/.local/share/ruixen-shell/hyprland/looknfeel.default.lua" "$fake_home/.config/hypr/looknfeel.lua"
out="$(HOME="$fake_home" bash "$doctor_sh" 2>&1)"
check "default variant: identified as off (stock Omarchy)" \
  "$(printf '%s\n' "$out" | grep -c 'variant: off (stock Omarchy)')" "1"

# --- broken symlink (target deleted/never deployed) -------------------
ln -sf "$fake_home/.local/share/ruixen-shell/hyprland/looknfeel.missing.lua" "$fake_home/.config/hypr/looknfeel.lua"
out="$(HOME="$fake_home" bash "$doctor_sh" 2>&1)"
check "broken symlink: flagged by name, with the fix command named" \
  "$(printf '%s\n' "$out" | grep -c 'BROKEN SYMLINK.*ruixen-lookfeel.sh on|off|half|square')" "1"

# --- no looknfeel.lua at all (stock Hyprland, never applied) ----------
rm -f "$fake_home/.config/hypr/looknfeel.lua"
out="$(HOME="$fake_home" bash "$doctor_sh" 2>&1)"
check "no looknfeel.lua: reported plainly as stock Hyprland, not an error" \
  "$(printf '%s\n' "$out" | grep -c 'no looknfeel.lua at all -- stock Hyprland defaults')" "1"

# --- plain file, not a symlink (pre-#15 migration) ---------------------
printf -- '-- not a symlink --\n' > "$fake_home/.config/hypr/looknfeel.lua"
out="$(HOME="$fake_home" bash "$doctor_sh" 2>&1)"
check "plain file: distinguished from both the symlink and the missing-file cases" \
  "$(printf '%s\n' "$out" | grep -c 'variant: plain file, not a symlink')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
