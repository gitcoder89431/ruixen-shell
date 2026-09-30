#!/usr/bin/env bash
set -Eeuo pipefail

shell_json="$HOME/.config/omarchy/shell.json"

fail() {
  printf 'ruixen-bar-style: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: ruixen-bar-style <notch|fullbar|status>

  notch    Current Ruixen island/notch skin, with center space reserved for
           ruixen.notch.
  fullbar  Saved full-width statusline skin. Hides ruixen.notch and lets the
           bar use the center space again.
  status   Print the current style.
EOF
}

current() {
  [[ -f "$shell_json" ]] || { echo "notch (no shell.json yet)"; return; }
  python3 -c "
import json
d = json.load(open('$shell_json'))
print('fullbar' if d.get('bar', {}).get('style') == 'fullbar' else 'notch')
"
}

set_style() {
  local style="$1"
  [[ "$style" == "notch" || "$style" == "fullbar" ]] || fail "unknown style: $style"
  [[ -f "$shell_json" ]] || fail "$shell_json not found -- run ./install.sh first"
  python3 -c "
import json
path = '$shell_json'
d = json.load(open(path))
d.setdefault('bar', {})['style'] = '$style'
json.dump(d, open(path, 'w'), indent=2)
"
  omarchy-shell shell reloadConfig >/dev/null
}

command="${1:-}"
case "$command" in
  notch)
    set_style "notch"
    echo "Switched to notch style"
    ;;
  fullbar)
    set_style "fullbar"
    echo "Switched to fullbar style"
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
