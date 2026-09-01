#!/usr/bin/env bash
set -Eeuo pipefail

target="$HOME/.config/hypr/looknfeel.lua"
# The stable path install.sh deploys both variants to, NOT this
# checkout -- direct review finding ("Decouple deployed Hyprland
# looknfeel from the git checkout path", #15): pointing at
# $script_dir/looknfeel.*.lua directly meant toggling look'n'feel
# (or just re-reading which one is active) stopped working the moment
# the checkout that ran install.sh was moved or deleted, same failure
# this issue fixed for the actual post-install symlink target.
looknfeel_data_dir="$HOME/.local/share/ruixen-shell/hyprland"

fail() {
  printf 'ruixen-lookfeel: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ruixen-lookfeel <on|off|status>

  on      Apply Ruixen's window look'n'feel (rounded corners matching the
          frame/bar's radius, plus blur) to Hyprland.
  off     Restore Hyprland's stock look'n'feel (square corners, no blur).
  status  Print which variant is currently active.
EOF
}

current() {
  if [[ -L "$target" ]]; then
    readlink -f "$target"
  else
    printf '%s\n' "$target"
  fi
}

apply() {
  local variant="$1" src="$2"
  [[ -f "$src" ]] || fail "missing $src"

  if [[ -e "$target" && ! -L "$target" ]]; then
    mv "$target" "${target}.bak.$(date +%s)"
    printf 'Backed up existing %s\n' "$target"
  fi

  ln -sf "$src" "$target"
  hyprctl reload >/dev/null
  printf 'Applied Ruixen look'"'"'n'"'"'feel: %s\n' "$variant"
}

command="${1:-}"
case "$command" in
  on)
    apply "on (rounded + blur)" "$looknfeel_data_dir/looknfeel.ruixen.lua"
    ;;
  off)
    apply "off (stock Omarchy)" "$looknfeel_data_dir/looknfeel.default.lua"
    ;;
  status)
    current
    ;;
  -h|--help|"")
    usage
    ;;
  *)
    fail "unknown command: $command"
    ;;
esac
