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

# --------------------------------------------------------------------
# Rollback -- direct review finding ("Make install/update transactional
# with validation and rollback"): the old single-pass plugin loop
# validated and deployed each plugin in the SAME iteration, so a
# validation failure partway through could leave earlier plugins
# already replaced while later ones were never even checked -- a mixed
# install. And any LATER step (shell.json, looknfeel) failing after
# plugins had already been deployed left new plugin files paired with
# an old config that might not even enable them (see #3's own bug).
#
# Rather than the heavier stage-everything-in-a-parallel-directory-
# then-swap design the review suggested, this tracks what's ACTUALLY
# been changed so far this run and, on any failure anywhere, unwinds
# exactly that in reverse -- so a failure at any point leaves the
# previous working installation intact, never a mix of old and new.
# `set -Eeuo pipefail`'s ERR trap fires for a failing command
# regardless of whether it's inside a function or a plain `A || fail
# "..."` top-level statement (confirmed, not assumed -- fail()'s own
# `exit 1` really does trigger it), so every existing `|| fail "..."`
# call site in this script gets rollback for free, no per-call-site
# changes needed.
DEPLOYED_PLUGIN_IDS=()
SHELL_JSON_TOUCHED=0
SHELL_JSON_HAD_BACKUP=0
LOOKNFEEL_TOUCHED=0
LOOKNFEEL_HAD_BACKUP=0

rollback_plugins() {
  local idx id target backup
  for (( idx=${#DEPLOYED_PLUGIN_IDS[@]}-1; idx>=0; idx-- )); do
    id="${DEPLOYED_PLUGIN_IDS[$idx]}"
    target="$plugins_dir/$id"
    backup="$plugin_backup_dir/$id.bak.$stamp"
    rm -rf "$target"
    if [[ -e "$backup" ]]; then
      mv "$backup" "$target" || printf '  warning: could not restore %s from its backup\n' "$id" >&2
    fi
  done
}

rollback_shell_json() {
  [[ "$SHELL_JSON_TOUCHED" -eq 1 ]] || return 0
  if [[ "$SHELL_JSON_HAD_BACKUP" -eq 1 ]]; then
    mv "${shell_json}.bak.${stamp}" "$shell_json" \
      || printf '  warning: could not restore shell.json from its backup\n' >&2
  else
    rm -f "$shell_json"
  fi
}

rollback_looknfeel() {
  [[ "$LOOKNFEEL_TOUCHED" -eq 1 ]] || return 0
  rm -f "$looknfeel_target"
  if [[ "$LOOKNFEEL_HAD_BACKUP" -eq 1 ]]; then
    mv "${looknfeel_target}.bak.${stamp}" "$looknfeel_target" \
      || printf '  warning: could not restore looknfeel.lua from its backup\n' >&2
  fi
}

rollback_all() {
  trap - ERR
  if [[ ${#DEPLOYED_PLUGIN_IDS[@]} -eq 0 && "$SHELL_JSON_TOUCHED" -eq 0 && "$LOOKNFEEL_TOUCHED" -eq 0 ]]; then
    # Failed before anything was actually changed (e.g. plugin
    # validation) -- fail()'s own message already explained why,
    # nothing to undo.
    return 0
  fi
  printf '\ninstall failed -- rolling back changes made this run...\n' >&2
  rollback_looknfeel
  rollback_shell_json
  rollback_plugins
  printf 'rollback complete -- your previous installation should be unchanged.\n' >&2
}
trap rollback_all ERR

printf '\n[1/5] Validating plugins\n'
# Every manifest is checked before ANYTHING is deployed -- a failure
# here never touches a single already-installed plugin.
for dir in "$script_dir"/ruixen.*/; do
  [[ -d "$dir" ]] || continue
  id="$(basename "$dir")"
  omarchy plugin validate "$dir" || fail "plugin failed validation: $id -- nothing has been changed"
done
printf '  all plugins passed validation\n'

printf '\n[2/5] Installing plugins\n'
for dir in "$script_dir"/ruixen.*/; do
  [[ -d "$dir" ]] || continue
  id="$(basename "$dir")"

  target="$plugins_dir/$id"
  if [[ -e "$target" ]]; then
    mv "$target" "$plugin_backup_dir/$id.bak.$stamp"
    printf '  backed up existing %s -> %s/%s.bak.%s\n' "$id" "$plugin_backup_dir" "$id" "$stamp"
  fi

  # Tracked BEFORE the actual copy, not after -- so a `cp -r` that
  # fails partway (disk full, say) still gets its own partial target
  # cleaned up by rollback_plugins, not just the plugins that fully
  # completed before it.
  DEPLOYED_PLUGIN_IDS+=("$id")
  cp -r "$dir" "$target"
  printf '  installed %s\n' "$id"
done

printf '\n[3/5] Applying shell layout\n'
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
  SHELL_JSON_HAD_BACKUP=1
  printf '  backed up existing shell.json -> shell.json.bak.%s\n' "$stamp"

  # Stable "what shell.json looked like the first time Ruixen ever
  # touched this machine" snapshot -- distinct from the timestamped
  # .bak.* above, which piles up across every reinstall/update and
  # stops being reliably "the pre-Ruixen state" after the first one.
  # Only written once; used by uninstall.sh's own restore logic.
  pristine_snapshot="$state_dir/shell.json.pre-ruixen"
  [[ -e "$pristine_snapshot" ]] || cp "$shell_json" "$pristine_snapshot"
  shell_json_input="$shell_json"
else
  shell_json_input=/dev/null
fi
SHELL_JSON_TOUCHED=1

# Written to a temp file in the same directory first, then renamed into
# place -- an atomic swap, not an in-place overwrite, so a killed/failed
# build can never leave shell.json half-written.
tmp_shell_json="$(mktemp "${shell_json}.XXXXXX")"
{ [[ "$shell_json_input" == /dev/null ]] && printf '{}' || cat "$shell_json_input"; } \
  | "$script_dir/lib/build-shell-json.sh" > "$tmp_shell_json" \
  || { rm -f "$tmp_shell_json"; fail "failed to build shell.json"; }

mv "$tmp_shell_json" "$shell_json"
printf '  wrote %s (unrelated plugins/settings, if any, were preserved)\n' "$shell_json"

printf '\n[4/5] Matching Hyprland window look to the frame/bar\n'
# See lib/apply-looknfeel.sh's own comment for the full "why" -- in
# short, a pre-existing looknfeel.lua SYMLINK (a dotfiles setup, say)
# used to get silently overwritten with no backup at all, and a
# reinstall/update had no way to tell "the real original" apart from
# "Ruixen's own symlink from last time."
looknfeel_target="$HOME/.config/hypr/looknfeel.lua"
looknfeel_src="$script_dir/hyprland/looknfeel.ruixen.lua"
looknfeel_pristine_dir="$state_dir/looknfeel-pristine"
LOOKNFEEL_TOUCHED=1
"$script_dir/lib/apply-looknfeel.sh" "$looknfeel_target" "$looknfeel_src" "$looknfeel_pristine_dir" "$stamp"
if [[ -e "${looknfeel_target}.bak.${stamp}" ]]; then
  LOOKNFEEL_HAD_BACKUP=1
  printf '  backed up existing looknfeel.lua -> looknfeel.lua.bak.%s\n' "$stamp"
fi
hyprctl reload >/dev/null 2>&1 || true
printf '  applied rounded corners + blur matching the frame (24px)\n'
printf '  toggle any time with: %s/hyprland/ruixen-lookfeel.sh off\n' "$script_dir"

printf '\n[5/5] Restarting Omarchy shell\n'
omarchy restart shell

# Success -- disarm the rollback trap before the summary below, so a
# cosmetic failure in the `cat` heredoc itself (there isn't one, but in
# principle) could never be mistaken for an install failure and trigger
# an unnecessary rollback of a genuinely successful install.
trap - ERR

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
