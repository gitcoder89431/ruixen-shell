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

# Direct review finding ("Add runtime dependency/version preflight and
# safer release update behavior"): the README stated broad Omarchy
# requirements but nothing here ever told a user WHICH specific
# feature would be unavailable if an optional dependency was missing
# -- they'd only find out later, by a feature silently not working
# with no explanation (see WallpapersContent.qml's own comment for
# exactly this happening with ffmpeg). Required deps (omarchy, jq,
# above) still fail the install outright, before anything is touched
# -- these aren't optional, most of install.sh cannot function without
# them. Everything below is a real feature dependency, not a hard
# requirement, so a warning here plus the install continuing is the
# correct behavior, not a failure.
printf '\n[1/6] Checking optional dependencies\n'
optional_dep_warned=0
warn_optional_dep() {
  local cmd="$1" feature="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf '  NOTE: %s not found -- %s\n' "$cmd" "$feature" >&2
    optional_dep_warned=1
  fi
}
warn_optional_dep ffmpeg "video wallpaper support (posters/playback) will be unavailable"
warn_optional_dep curl "weather data and avatar image download in Settings will be unavailable"
warn_optional_dep python3 "the bar's docked-mode toggle will silently no-op"
warn_optional_dep fastfetch "the health page's system-info panel will show less detail"
if [[ "$optional_dep_warned" -eq 0 ]]; then
  printf '  all optional dependencies present\n'
fi

# Warns, doesn't fail -- can't be CERTAIN a version outside this range
# won't work, only that it's untested. `omarchy version` prints a bare
# "X.Y.Z-rel" (confirmed by running it directly), so a simple major-
# version compare against what the README documents ("4.0.0-1 or a
# nearby build of the same shell generation") is enough to catch the
# real case this guards against: a much older or much newer Omarchy
# whose shell internals may have moved out from under this repo's own
# assumptions (the reload-path bugs and IPC conventions this repo
# already depends on directly, for instance).
omarchy_version="$(omarchy version 2>/dev/null || true)"
omarchy_major="${omarchy_version%%.*}"
if [[ -z "$omarchy_version" ]]; then
  printf '  NOTE: could not determine Omarchy version (omarchy version produced no output) -- proceeding anyway\n' >&2
elif [[ ! "$omarchy_major" =~ ^[0-9]+$ || "$omarchy_major" -ne 4 ]]; then
  printf '  WARNING: this checkout is developed against Omarchy 4.x; detected %s -- things may not work as expected\n' "$omarchy_version" >&2
fi

mkdir -p "$plugins_dir"

# $state_dir itself is needed early (pristine snapshots, plugin backups
# below all live under it) -- but NOT the repo-path file, see the
# [6/6] success block at the end of this script for where and why that
# gets written instead.
state_dir="$HOME/.local/state/ruixen"
mkdir -p "$state_dir"

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

printf '\n[2/6] Validating plugins\n'
# Every manifest is checked before ANYTHING is deployed -- a failure
# here never touches a single already-installed plugin.
for dir in "$script_dir"/ruixen.*/; do
  [[ -d "$dir" ]] || continue
  id="$(basename "$dir")"
  omarchy plugin validate "$dir" || fail "plugin failed validation: $id -- nothing has been changed"
done
printf '  all plugins passed validation\n'

printf '\n[3/6] Installing plugins\n'
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

printf '\n[4/6] Applying shell layout\n'
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

printf '\n[5/6] Matching Hyprland window look to the frame/bar\n'
# See lib/apply-looknfeel.sh's own comment for the full "why" -- in
# short, a pre-existing looknfeel.lua SYMLINK (a dotfiles setup, say)
# used to get silently overwritten with no backup at all, and a
# reinstall/update had no way to tell "the real original" apart from
# "Ruixen's own symlink from last time."
#
# Direct review finding ("Decouple deployed Hyprland looknfeel from the
# git checkout path", #15): ~/.config/hypr/looknfeel.lua used to be
# symlinked straight into THIS checkout ($script_dir/hyprland/...) --
# moving or deleting the clone after a successful install broke every
# future Hyprland reload, since Lua's own require() has no fallback for
# a target whose symlink now points at nothing. Both looknfeel variants
# are copied to a stable data path first, and the symlink points there
# instead -- deploy-then-link, the same shape install.sh already uses
# for plugins, just with one file instead of a directory. Copied fresh
# on every install/update run (not write-once like the pristine
# snapshots -- this is a deployed ASSET meant to track the checkout's
# current content, not a rollback baseline), written to a temp file in
# the same directory first and renamed into place so a killed/failed
# run can never leave a half-written asset behind.
looknfeel_data_dir="$HOME/.local/share/ruixen-shell/hyprland"
mkdir -p "$looknfeel_data_dir"
for variant in looknfeel.ruixen.lua looknfeel.default.lua; do
  tmp_variant="$(mktemp "$looknfeel_data_dir/.${variant}.XXXXXX")"
  cp "$script_dir/hyprland/$variant" "$tmp_variant"
  mv "$tmp_variant" "$looknfeel_data_dir/$variant"
done

looknfeel_target="$HOME/.config/hypr/looknfeel.lua"
looknfeel_src="$looknfeel_data_dir/looknfeel.ruixen.lua"
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

printf '\n[6/6] Restarting Omarchy shell\n'
omarchy restart shell

# Direct review finding ("Make repo-path state part of the successful
# install transaction", #14): this used to be written right at the top
# of the script, before plugin validation/deployment even started -- so
# a failed install from a checkout B, run on top of a working install
# from checkout A, left repo-path pointing at B (the failed one) even
# though every other piece of state correctly rolled back to A.
# Settings' own Update button would then be running update.sh out of a
# checkout that was never actually the one currently installed.
#
# Written here instead -- after the restart above, the last step that
# can still fail -- so repo-path only ever identifies the checkout that
# actually produced the currently installed state, matching every other
# piece of this install's rollback coverage.
printf '%s\n' "$script_dir" > "$state_dir/repo-path"

# Success -- disarm the rollback trap before the summary below, so a
# cosmetic failure in the `cat` heredoc itself (there isn't one, but in
# principle) could never be mistaken for an install failure and trigger
# an unnecessary rollback of a genuinely successful install.
trap - ERR

# Backup retention -- direct review finding ("Backup retention is
# bounded or cleaned so repeated updates do not accumulate unlimited
# plugin snapshots"). Every install/update run leaves a fresh
# timestamped backup behind for each of the plugins/shell.json/
# looknfeel.lua (real, useful recovery copies -- not staging files, so
# not something rollback_all above cleans up, and not touched at all
# unless we get here, past every earlier failure point). Left
# unbounded, a machine that updates daily accumulates one of these per
# plugin per day forever. Runs only after a fully successful install,
# never mid-run: this run's own backups (the ones rollback_all might
# still need) are always exempt just by virtue of being the newest.
prune_backups() {
  local keep="$1"
  shift
  local pattern
  for pattern in "$@"; do
    local matches=()
    # Oldest-first: our timestamps are unix epoch seconds baked
    # straight into the filename, so a plain lexical sort is already
    # chronological order. compgen -G takes the pattern as a normal
    # quoted argument -- no unquoted shell-level glob expansion needed
    # the way `find $pattern` required, which is what CI's ShellCheck
    # (never available on the dev machine this was first written and
    # tested on, confirmed only after the fact) correctly flagged as
    # SC2086. Plain newline-delimited reading is fine here, not NUL-
    # delimited like the wallpaper discovery script needed: every name
    # matching these patterns is one this script generated itself
    # (<plugin-id>.bak.<epoch>), never arbitrary user input.
    while IFS= read -r f; do [[ -n "$f" ]] && matches+=("$f"); done < <(compgen -G "$pattern" | sort)
    local total=${#matches[@]}
    if (( total > keep )); then
      local i
      for (( i = 0; i < total - keep; i++ )); do
        rm -rf "${matches[$i]}"
      done
    fi
  done
}
backup_retain_count=5
for dir in "$script_dir"/ruixen.*/; do
  [[ -d "$dir" ]] || continue
  prune_backups "$backup_retain_count" "$plugin_backup_dir/$(basename "$dir").bak.*"
done
prune_backups "$backup_retain_count" "${shell_json}.bak.*"
prune_backups "$backup_retain_count" "${looknfeel_target}.bak.*"

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

ruixen-bar-mode.sh and update.sh only work from this checkout -- keep it
around after installing (don't delete the cloned folder), or note its
path above. ruixen-lookfeel.sh itself is also run from here, but the
actual Hyprland look it applies is copied to a stable path first, so
moving or deleting this checkout later won't break your active
Hyprland config.

EOF
