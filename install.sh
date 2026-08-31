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

# Records where this checkout lives so the deployed ruixen.settings
# plugin (running from $plugins_dir, a plain copy, not this git repo)
# can find update.sh to run later -- otherwise the settings app's own
# Update button would have no way to know this path on a machine where
# Claude/the user hasn't told it directly. Rewritten on every install/
# update run, so it always tracks the checkout actually in use.
state_dir="$HOME/.local/state/ruixen"
mkdir -p "$state_dir"
printf '%s\n' "$script_dir" > "$state_dir/repo-path"

printf '\n[1/4] Validating and installing plugins\n'
# Backups go under $state_dir, never inside $plugins_dir -- real bug
# hit live ("i did the update button on plugs in page, did that
# messed it up lol"): the old `mv "$target" "${target}.bak.${stamp}"`
# left the previous copy sitting right next to the fresh one, inside
# the exact directory Omarchy's plugin loader scans. Its manifest.json
# still declares the same id (e.g. "ruixen.settings"), so the loader
# picked up two competing instances of the same plugin -- confirmed
# live via the journal (a stale ruixen.settings.bak.<timestamp>/
# BluetoothContent.qml throwing warnings, and this settings app's own
# debug IPC target silently failing to resolve, most likely because a
# second, older instance was also registered under the same id).
plugin_backup_dir="$state_dir/backups/plugins"
mkdir -p "$plugin_backup_dir"
for dir in "$script_dir"/ruixen.*/; do
  [[ -d "$dir" ]] || continue
  id="$(basename "$dir")"

  omarchy plugin validate "$dir" || fail "plugin failed validation: $id"

  target="$plugins_dir/$id"
  if [[ -e "$target" ]]; then
    mv "$target" "$plugin_backup_dir/$id.bak.$stamp"
    printf '  backed up existing %s -> %s/%s.bak.%s\n' "$id" "$plugin_backup_dir" "$id" "$stamp"
  fi

  cp -r "$dir" "$target"
  printf '  installed %s\n' "$id"
done

printf '\n[2/4] Applying shell layout\n'
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
                { "id": "omarchy.power" },
                { "id": "ruixen.settingsbutton" }
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

printf '\n[3/4] Matching Hyprland window look to the frame/bar\n'
looknfeel_target="$HOME/.config/hypr/looknfeel.lua"
looknfeel_src="$script_dir/hyprland/looknfeel.ruixen.lua"
if [[ -e "$looknfeel_target" && ! -L "$looknfeel_target" ]]; then
  mv "$looknfeel_target" "${looknfeel_target}.bak.${stamp}"
  printf '  backed up existing looknfeel.lua -> looknfeel.lua.bak.%s\n' "$stamp"
fi
mkdir -p "$(dirname "$looknfeel_target")"
ln -sf "$looknfeel_src" "$looknfeel_target"
hyprctl reload >/dev/null 2>&1 || true
printf '  applied rounded corners + blur matching the frame (24px)\n'
printf '  toggle any time with: %s/hyprland/ruixen-lookfeel.sh off\n' "$script_dir"

printf '\n[4/4] Restarting Omarchy shell\n'
omarchy restart shell

cat <<EOF

Ruixen Shell is installed.

One manual step left: add a keybind of your own for Ruixen Settings, since
this installer deliberately doesn't touch your Hyprland keybindings. In
~/.config/hypr/bindings.lua:

  o.bind("SUPER + R", "Ruixen Settings", "omarchy-shell shell toggle ruixen.settings")

Pick any other unbound key if you'd rather -- run \`omarchy menu keybindings --print\` to see what's taken.

Want Hyprland's default window look back instead? Run:

  $script_dir/hyprland/ruixen-lookfeel.sh off

Want to try the bar's docked mode (merged pills, flush with the frame)?
Run:

  $script_dir/ruixen-bar-mode.sh docked

Pulling new changes later? Run:

  $script_dir/update.sh

All three only work from this checkout -- keep it around after
installing (don't delete the cloned folder), or note its path above.

EOF
