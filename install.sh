#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugins_dir="$HOME/.config/omarchy/plugins"
shell_json="$HOME/.config/omarchy/shell.json"
stamp="$(date +%s)"

fail() {
  printf 'ruixen-shell install: %s\n' "$*" >&2
  exit 1
}

command -v omarchy >/dev/null 2>&1 || fail "Omarchy is required (command 'omarchy' not found)"

mkdir -p "$plugins_dir"

printf '\n[1/3] Validating and installing plugins\n'
for dir in "$script_dir"/ruixen.*/; do
  [[ -d "$dir" ]] || continue
  id="$(basename "$dir")"

  omarchy plugin validate "$dir" || fail "plugin failed validation: $id"

  target="$plugins_dir/$id"
  if [[ -e "$target" ]]; then
    mv "$target" "${target}.bak.${stamp}"
    printf '  backed up existing %s -> %s.bak.%s\n' "$id" "$id" "$stamp"
  fi

  cp -r "$dir" "$target"
  printf '  installed %s\n' "$id"
done

printf '\n[2/3] Applying shell layout\n'
if [[ -e "$shell_json" ]]; then
  cp "$shell_json" "${shell_json}.bak.${stamp}"
  printf '  backed up existing shell.json -> shell.json.bak.%s\n' "$stamp"
fi

cat > "$shell_json" <<'EOF'
{
    "version": 1,
    "bar": {
        "id": "ruixen.bar",
        "position": "top",
        "transparent": true,
        "centerAnchor": "omarchy.clock",
        "layout": {
            "left": [
                { "id": "ruixen.settingsbutton" },
                { "id": "ruixen.applauncher" },
                { "id": "ruixen.workspaces" }
            ],
            "center": [
                { "id": "ruixen.workspaces" },
                { "id": "omarchy.menu" },
                { "id": "ruixen.media" },
                { "id": "ruixen.weather" },
                {
                    "id": "omarchy.clock",
                    "format": "HH:mm",
                    "formatAlt": "d MMMM 'W'ww yyyy",
                    "verticalFormat": "HH\n—\nmm"
                }
            ],
            "right": [
                { "id": "omarchy.keyboard-layout" },
                { "id": "omarchy.system-update" },
                { "id": "ruixen.tray", "hidden": [] },
                { "id": "ruixen.stayawake" },
                { "id": "ruixen.quickactions" },
                { "id": "omarchy.agents" },
                { "id": "omarchy.bluetooth" },
                { "id": "omarchy.network" },
                { "id": "omarchy.audio" },
                { "id": "omarchy.monitor" },
                { "id": "omarchy.power" }
            ]
        }
    },
    "plugins": [
        { "id": "ruixen.frame-widget" },
        { "id": "ruixen.notch" },
        { "id": "ruixen.settings" }
    ],
    "idle": {
        "lock": 300,
        "screensaver": 150
    }
}
EOF
printf '  wrote %s\n' "$shell_json"

printf '\n[3/3] Restarting Omarchy shell\n'
omarchy restart shell

cat <<'EOF'

Ruixen Shell is installed.

One manual step left: add a keybind of your own for Ruixen Settings, since
this installer deliberately doesn't touch your Hyprland config. In
~/.config/hypr/bindings.lua:

  bind("SUPER", "comma", "exec", "omarchy-shell shell toggle ruixen.settings")

EOF
