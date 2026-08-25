#!/usr/bin/env bash
set -Eeuo pipefail

shell_json="$HOME/.config/omarchy/shell.json"

fail() {
  printf 'ruixen-bar-mode: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ruixen-bar-mode <docked|floating|status>

  docked    Merge the left/right pill groups into one continuous shape
            per side, flush with ruixen.frame-widget's corners.
  floating  Restore the default floating pill layout (each group its
            own separate pill, inset from the frame).
  status    Print which mode is currently active.
EOF
}

current() {
  [[ -f "$shell_json" ]] || { echo "floating (no shell.json yet)"; return; }
  python3 -c "
import json
d = json.load(open('$shell_json'))
print('docked' if d.get('bar', {}).get('docked') is True else 'floating')
"
}

set_docked() {
  local value="$1"
  [[ -f "$shell_json" ]] || fail "$shell_json not found -- run ./install.sh first"
  python3 -c "
import json
path = '$shell_json'
d = json.load(open(path))
d.setdefault('bar', {})['docked'] = $value
json.dump(d, open(path, 'w'), indent=2)
"
  omarchy-shell shell reloadConfig >/dev/null
}

command="${1:-}"
case "$command" in
  docked)
    set_docked "True"
    echo "Switched to docked mode"
    ;;
  floating)
    set_docked "False"
    echo "Switched to floating mode"
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
