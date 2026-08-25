#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
target="$HOME/.config/hypr/looknfeel.lua"

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
    apply "on (rounded + blur)" "$script_dir/looknfeel.ruixen.lua"
    ;;
  off)
    apply "off (stock Omarchy)" "$script_dir/looknfeel.default.lua"
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
