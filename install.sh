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
command -v jq >/dev/null 2>&1 || fail "jq is required (command 'jq' not found)"

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
# Merged into whatever shell.json already exists (via lib/build-shell-
# json.sh), not a wholesale `cat > shell.json` overwrite -- direct
# review finding ("Preserve existing shell.json instead of replacing
# the entire user config": a user with their own bar widgets, plugin
# entries, or idle settings shouldn't lose them just because Ruixen
# installed). See that script's own comment for exactly what survives
# a merge and what Ruixen always owns.
if [[ -e "$shell_json" ]]; then
  jq empty "$shell_json" >/dev/null 2>&1 \
    || fail "existing $shell_json isn't valid JSON -- fix or remove it by hand and run install.sh again (nothing has been changed)"
  cp "$shell_json" "${shell_json}.bak.${stamp}"
  printf '  backed up existing shell.json -> shell.json.bak.%s\n' "$stamp"

  # Stable "what shell.json looked like the first time Ruixen ever
  # touched this machine" snapshot -- distinct from the timestamped
  # .bak.* above, which piles up across every reinstall/update and
  # stops being reliably "the pre-Ruixen state" after the first one.
  # Only written once; a real uninstall restore is a separate issue,
  # this just makes sure the one true reference still exists by then.
  pristine_snapshot="$state_dir/shell.json.pre-ruixen"
  [[ -e "$pristine_snapshot" ]] || cp "$shell_json" "$pristine_snapshot"
  shell_json_input="$shell_json"
else
  shell_json_input=/dev/null
fi

# Written to a temp file in the same directory first, then renamed into
# place -- an atomic swap, not an in-place overwrite, so a killed/failed
# build can never leave shell.json half-written.
tmp_shell_json="$(mktemp "${shell_json}.XXXXXX")"
{ [[ "$shell_json_input" == /dev/null ]] && printf '{}' || cat "$shell_json_input"; } \
  | "$script_dir/lib/build-shell-json.sh" > "$tmp_shell_json" \
  || { rm -f "$tmp_shell_json"; fail "failed to build shell.json -- nothing has been changed"; }

mv "$tmp_shell_json" "$shell_json"
printf '  wrote %s (unrelated plugins/settings, if any, were preserved)\n' "$shell_json"

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
