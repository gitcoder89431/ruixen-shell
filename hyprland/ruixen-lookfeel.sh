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
Usage: ruixen-lookfeel <on|off|square|status>

  on      Apply Ruixen's window look'n'feel (rounded corners matching the
          frame/bar's radius, plus blur) to Hyprland.
  off     Restore Hyprland's stock look'n'feel (square corners, no blur,
          stock 2px border).
  square  Ruixen's look'n'feel (thin border, blur, shadow, animations)
          but with square corners instead of rounded -- direct request:
          someone wanted the stock square-corner look without giving up
          everything else `on` adds.
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
  # Full shell restart, not just `hyprctl reload` -- real bug, found
  # while adding the square variant above: ruixen.frame-widget's own
  # screen-frame corner mask reads which variant is active at its own
  # startup and never again, so switching look'n'feel without also
  # restarting Quickshell left the frame's corner rounding stuck at
  # whatever it was when the shell last started, mismatched against
  # the real window corners -- live report: "the buttom corner will
  # clip under the shell frame". `hyprctl reload` only reloads
  # Hyprland's own config, a completely separate process from
  # Quickshell, so it could never have picked this up on its own.
  omarchy restart shell >/dev/null 2>&1 || true
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
  square)
    apply "square (blur + shadow, no rounding)" "$looknfeel_data_dir/looknfeel.square.lua"
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
