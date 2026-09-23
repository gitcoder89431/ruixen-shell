#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugins_dir="$HOME/.config/omarchy/plugins"
shell_json="$HOME/.config/omarchy/shell.json"
# Every ruixen.* source directory in this checkout, wherever it actually
# lives -- bar-family plugins moved under bars/v1/ (a clean split from
# the repo root for a future bars/v2/, per direct request: "instead of
# having them on root, can we put them in bars and then v1 or v2"), the
# rest (launcher/settings/wallpaper) stay at the root. ONE array, not a
# literal glob repeated at every call site (5 in this file alone) -- a
# future bars/v2/ or any other reshuffle only ever needs this one line
# touched. A glob with no match expands to itself (the literal pattern
# string) when nullglob is off, so each site below still needs its own
# `[[ -d "$dir" ]] || continue` guard -- this array can't guarantee
# every element is real.
plugin_source_dirs=("$script_dir"/ruixen.*/ "$script_dir"/bars/*/ruixen.*/)
# Nanosecond, not `date +%s` -- direct review finding ("Add an
# install/update/uninstall lock and collision-safe run identifiers",
# #16): plain epoch-seconds backup/run names could collide between two
# installs started in the same second (the UI's Update button and a
# manually-run install.sh, say). The lock acquired below already makes
# that specific race impossible in practice (only one lifecycle op can
# be mutating state at a time), but a collision-safe identity is cheap
# and correct on its own regardless of the lock, so both fixes land
# together as the issue asks.
stamp="$(date +%s%N)"

fail() {
  printf 'ruixen-shell install: %s\n' "$*" >&2
  exit 1
}

command -v omarchy >/dev/null 2>&1 || fail "Omarchy is required (command 'omarchy' not found)"
command -v jq >/dev/null 2>&1 || fail "jq is required (command 'jq' not found)"

# Issue #31: a completely separate, early code path -- not a
# conditional threaded through the real mutation logic below, for the
# same reason uninstall.sh's own --dry-run branch gives (see its own
# comment): the safety guarantee is simple to verify (exits before the
# lifecycle lock is even acquired, let alone any mutating command)
# rather than trusting every future edit to the real path also
# remembers to check a flag. Reuses lib/build-shell-json.sh completely
# as-is -- the exact same pure function [4/6] below calls -- so the
# shell.json preview and the real merge cannot drift on what would
# actually change (see [4/7] below). Plugin manifest validation is run
# for REAL here (omarchy plugin validate never mutates anything), not
# simulated, so "invalid configs/manifests still fail validation in
# dry-run" is literally true rather than approximated.
if [[ "${1:-}" == "--dry-run" ]]; then
  printf '=== Ruixen Install -- dry run, nothing will be changed ===\n\n'

  omarchy_version="$(omarchy version 2>/dev/null || true)"
  omarchy_major="${omarchy_version%%.*}"
  if [[ -z "$omarchy_version" ]]; then
    printf 'Omarchy version: could not determine\n'
  else
    printf 'Omarchy version: %s' "$omarchy_version"
    [[ ! "$omarchy_major" =~ ^[0-9]+$ || "$omarchy_major" -ne 4 ]] \
      && printf ' (developed against 4.x -- things may not work as expected)'
    printf '\n'
  fi

  printf '\nOptional dependencies:\n'
  for pair in "ffmpeg:video/gif wallpaper poster generation" "curl:weather data and avatar download" \
    "python3:the bar's docked-mode toggle" "fastfetch:extra system-info detail" \
    "cava:the Desktop audio visualizer"; do
    cmd="${pair%%:*}"; feature="${pair#*:}"
    if command -v "$cmd" >/dev/null 2>&1; then
      printf '  %-10s present\n' "$cmd"
    else
      printf '  %-10s MISSING -- %s will be unavailable\n' "$cmd" "$feature"
    fi
  done
  # Package, not command -- see the real (non-dry-run) warn_optional_pkg
  # below for the full "why this one is a package check" explanation.
  if pacman -Qi qt6-multimedia >/dev/null 2>&1; then
    printf '  %-10s present\n' "qt6-multimedia"
  else
    printf '  %-10s MISSING -- video AND gif wallpaper playback will both silently fail to start (not just video)\n' "qt6-multimedia"
  fi

  printf '\nPlugin validation (run for real -- read-only):\n'
  validation_failed=0
  for dir in "${plugin_source_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    id="$(basename "$dir")"
    if omarchy plugin validate "$dir" >/dev/null 2>&1; then
      printf '  %-24s OK\n' "$id"
    else
      printf '  %-24s FAILS VALIDATION -- a real install would abort here, nothing else would be touched\n' "$id"
      validation_failed=1
    fi
  done

  printf '\nPlugins that would be installed/replaced:\n'
  for dir in "${plugin_source_dirs[@]}"; do
    [[ -d "$dir" ]] || continue
    id="$(basename "$dir")"
    if [[ -e "$plugins_dir/$id" ]]; then
      printf '  %-24s replace existing (backed up first)\n' "$id"
    else
      printf '  %-24s install fresh\n' "$id"
    fi
  done

  printf '\nshell.json:\n'
  if [[ -e "$shell_json" ]]; then
    if ! jq empty "$shell_json" >/dev/null 2>&1; then
      printf '  existing shell.json is not valid JSON -- a real install would abort here, nothing would be touched\n'
    else
      merged="$("$script_dir/lib/build-shell-json.sh" <"$shell_json" 2>/dev/null || echo '')"
      if [[ -z "$merged" ]]; then
        printf '  could not compute the merge preview (build-shell-json.sh failed)\n'
      elif [[ "$(jq -S . <"$shell_json")" == "$(jq -S . <<<"$merged")" ]]; then
        printf '  would merge into the existing file -- no actual changes (already up to date)\n'
      else
        current_bar_id="$(jq -r '.bar.id // "(none)"' "$shell_json")"
        if [[ "$current_bar_id" != "ruixen.bar" ]]; then
          printf '  bar host: %s -> ruixen.bar (some other bar is currently active)\n' "$current_bar_id"
        else
          printf '  bar host: ruixen.bar (already owns the bar slot -- your own layout/docked/settings are preserved, not replaced)\n'
        fi
        added_plugins="$(jq -r --slurpfile a <(jq -c '[.plugins[]?.id]' <<<"$merged") --slurpfile b <(jq -c '[.plugins[]?.id]' "$shell_json") -n '$a[0] - $b[0] | .[]' 2>/dev/null || true)"
        if [[ -n "$added_plugins" ]]; then
          printf '  plugins[] entries that would be added:\n'
          while IFS= read -r id; do [[ -n "$id" ]] && printf '    %s\n' "$id"; done <<<"$added_plugins"
        fi
      fi
    fi
  else
    printf '  would be created fresh from this checkout own canonical layout\n'
  fi

  printf '\nHyprland window look:\n'
  looknfeel_target="$HOME/.config/hypr/looknfeel.lua"
  looknfeel_data_dir_preview="$HOME/.local/share/ruixen-shell/hyprland"
  # Same preserve-the-current-choice logic as the real install step
  # below (see its own comment) -- a dry-run that claimed "off" would
  # flip back to "on" was itself part of the bug, since it matched
  # what the OLD unconditional code actually did.
  looknfeel_preview_variant=""
  if [[ -L "$looknfeel_target" ]]; then
    looknfeel_preview_link="$(readlink "$looknfeel_target")"
    case "$looknfeel_preview_link" in
      "$looknfeel_data_dir_preview"/*) looknfeel_preview_variant="$(basename "$looknfeel_preview_link")" ;;
    esac
  fi
  looknfeel_src="$script_dir/hyprland/${looknfeel_preview_variant:-looknfeel.ruixen.lua}"
  if [[ -L "$looknfeel_target" ]]; then
    link_target="$(readlink -f "$looknfeel_target" 2>/dev/null || true)"
    if [[ -n "$link_target" ]] && cmp -s "$link_target" "$looknfeel_src" 2>/dev/null; then
      if [[ "$looknfeel_preview_variant" == "looknfeel.default.lua" ]]; then
        printf '  already Ruixen own symlink (stock look, off), matches this checkout -- no change\n'
      else
        printf '  already Ruixen own symlink, matches this checkout -- no change\n'
      fi
    elif [[ -n "$looknfeel_preview_variant" ]]; then
      printf '  would refresh the deployed asset -- your current choice (%s) is kept, not reset to the default look\n' \
        "${looknfeel_preview_variant%.lua}"
    else
      printf '  would back up the current looknfeel.lua and point it at this checkout own version\n'
    fi
  elif [[ -e "$looknfeel_target" ]]; then
    printf '  a real file (not a symlink) exists -- would be backed up, then replaced with a Ruixen-managed symlink\n'
  else
    printf '  nothing exists yet -- would be created fresh\n'
  fi

  printf '\nTheme overlays:\n'
  theme_overlay_preview_dirs=("$script_dir"/theme-overlays/*/)
  if [[ -d "$script_dir/theme-overlays" && -d "${theme_overlay_preview_dirs[0]}" ]]; then
    dry_run_current_theme_slug="$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)"
    for theme_preview_dir in "${theme_overlay_preview_dirs[@]}"; do
      [[ -d "$theme_preview_dir" ]] || continue
      theme_preview_name="$(basename "$theme_preview_dir")"
      preview_file_list=()
      for preview_file in "$theme_preview_dir"*; do
        [[ -f "$preview_file" ]] && preview_file_list+=("$(basename "$preview_file")")
      done
      if [[ "$theme_preview_name" == "$dry_run_current_theme_slug" ]]; then
        printf '  %s: %s -- currently active, would be re-applied immediately\n' \
          "$theme_preview_name" "${preview_file_list[*]}"
      else
        printf '  %s: %s\n' "$theme_preview_name" "${preview_file_list[*]}"
      fi
    done
  else
    printf '  none in this checkout\n'
  fi

  printf '\nState files:\n'
  [[ -e "$HOME/.local/state/ruixen/shell.json.pre-ruixen" ]] \
    && printf '  pre-Ruixen bar snapshot: already recorded, left untouched\n' \
    || printf '  pre-Ruixen bar snapshot: would be recorded (first time Ruixen takes the bar slot)\n'
  [[ -e "$HOME/.local/state/ruixen/repo-path" ]] \
    && printf '  repo-path: already recorded, would be updated to this checkout\n' \
    || printf '  repo-path: would be recorded, pointing at this checkout\n'

  printf '\nNo files changed.\n'
  [[ "$validation_failed" -eq 1 ]] && exit 1
  exit 0
fi

# $state_dir itself is needed early (the lock file below lives under
# it, same as the pristine snapshots and plugin backups further down)
# -- but NOT the repo-path file, see the [6/6] success block at the end
# of this script for where and why that gets written instead.
state_dir="$HOME/.local/state/ruixen"
mkdir -p "$state_dir"

# Direct review finding ("Add an install/update/uninstall lock and
# collision-safe run identifiers", #16): install.sh/update.sh/
# uninstall.sh all make coordinated changes across plugin directories,
# shell.json, rollback backups, and looknfeel with no process-level
# lock -- two lifecycle operations racing (the Settings UI's Update
# button while a user also runs install.sh by hand, say) could
# interleave their filesystem mutations. Released automatically the
# instant this process exits for any reason (success, `fail`, an
# uncaught error under set -e, or a signal) -- see
# lib/acquire-lifecycle-lock.sh's own comment for exactly why and how.
#
# Direct follow-up review finding ("Hold the lifecycle lock while
# update.sh changes the source checkout", #21): update.sh used to
# deliberately take no lock of its own so its child install.sh call
# could never self-deadlock against a lock its own parent already
# held -- but that also meant update.sh's own `git pull --ff-only`,
# which rewrites the SOURCE checkout this install.sh reads plugins
# from, ran completely unprotected. A manual install.sh could read a
# torn mix of pre-pull/post-pull files from that same checkout mid-
# pull. acquire_lifecycle_lock is idempotent: it acquires for real on a
# standalone run, or trusts an already-locked caller (update.sh, now)
# without re-locking and self-contending -- same lock, same
# guarantee, no parent/child deadlock either way.
# shellcheck source=lib/acquire-lifecycle-lock.sh
source "$script_dir/lib/acquire-lifecycle-lock.sh"
# Not routed through fail() -- acquire_lifecycle_lock already prints
# its own clear message to stderr. Calling it any other way (e.g.
# capturing its output via `$(...)` to hand to fail()) would run it in
# a SUBSHELL, where the exec/export inside it would be lost the instant
# that subshell exits -- the lock would appear to succeed but never
# actually stay held for the rest of this script.
acquire_lifecycle_lock "$state_dir" || exit 1

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
printf '\n[1/7] Checking optional dependencies\n'
optional_dep_warned=0
warn_optional_dep() {
  local cmd="$1" feature="$2"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    printf '  NOTE: %s not found -- %s\n' "$cmd" "$feature" >&2
    optional_dep_warned=1
  fi
}
# Package, not command -- qt6-multimedia has no binary of its own to
# `command -v` for. Confirmed directly (not assumed): it is NOT part of
# Omarchy's own base package set and is not a dependency of quickshell
# or omarchy itself, so on a stock install it is only present if some
# unrelated app (a video editor, say) happened to pull it in. Its
# absence is far more serious than the ffmpeg gap below: ruixen.
# wallpaper/Service.qml has an unconditional `import QtMultimedia` at
# the top of the file, and a QML file with an unresolvable import
# fails to load ENTIRELY (confirmed directly against a throwaway QML
# file: "Did not load any objects, exiting.") -- not just its video
# code. That takes the whole service down with it: video, gif, and the
# static-background-switch safety net all silently no-op, with no
# per-feature degradation. This is the actual root cause behind reports
# of "selecting an mp4 shows it as current but never actually displays
# it" -- the picker's own "current" highlight is optimistic client-side
# UI state set the instant you click, before the (silently failing)
# service ever gets a chance to do anything real.
warn_optional_pkg() {
  local pkg="$1" feature="$2"
  if ! pacman -Qi "$pkg" >/dev/null 2>&1; then
    printf '  NOTE: %s not installed -- %s\n' "$pkg" "$feature" >&2
    optional_dep_warned=1
  fi
}
warn_optional_dep ffmpeg "video/gif wallpaper POSTER generation will be unavailable (current/background and the lock screen won't reflect the active video/gif; the moving wallpaper itself is unaffected by this specific dependency)"
warn_optional_pkg qt6-multimedia "video AND gif wallpaper playback will both silently fail to start (ruixen.wallpaper's whole backend fails to load without this, not just video) -- pacman -S --needed qt6-multimedia-ffmpeg pulls this in with hardware-accelerated decode"
warn_optional_dep curl "weather data and avatar image download in Settings will be unavailable"
warn_optional_dep python3 "the bar's docked-mode toggle will silently no-op"
warn_optional_dep fastfetch "the health page's system-info panel will show less detail"
warn_optional_dep cava "the Desktop audio visualizer will be unavailable; the rest of Ruixen remains usable"
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

# Issue #34: a bare major-version compare only catches large breaks --
# Ruixen depends on specific host contracts (bar-widget registry
# shape, IPC surface, WidgetButton's own wheelMoved signal, etc, see
# COMPATIBILITY.md's own list) that can shift within the same major
# release. This is a reviewed-vs-detected NOTE, not a second gate:
# COMPATIBILITY.md is a ledger of what has actually been checked, not
# a claim that every unreviewed nearby build is broken, so an exact
# match beyond major.minor is not required to proceed quietly.
# shellcheck disable=SC2016 # the backticks here are literal markdown
# code-span markers being matched in COMPATIBILITY.md's own text, not
# an accidental unexpanded command substitution.
reviewed_omarchy="$(grep -m1 -oE '`[0-9]+\.[0-9]+\.[0-9]+-[0-9]+`' "$script_dir/COMPATIBILITY.md" 2>/dev/null | head -1 | tr -d '`')"
if [[ -n "$omarchy_version" && -n "$reviewed_omarchy" && "$omarchy_version" != "$reviewed_omarchy" ]]; then
  printf '  NOTE: last reviewed against Omarchy %s (see COMPATIBILITY.md), detected %s -- likely fine, just not specifically reviewed yet\n' "$reviewed_omarchy" "$omarchy_version" >&2
fi

mkdir -p "$plugins_dir"

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

# Same reasoning as plugin_backup_dir above, for the stable deployed
# looknfeel assets #20 adds rollback coverage for (see
# rollback_looknfeel_data below) -- declared up here alongside the
# other backup dirs, populated down in [5/6] where the deploy actually
# happens.
looknfeel_data_backup_dir="$state_dir/backups/looknfeel-data"
mkdir -p "$looknfeel_data_backup_dir"

# Same reasoning again, for theme-overlays/<name>/* (per-theme shell.toml/
# icons.theme/etc. overrides -- see [7/8] below). Direct real-world
# report: a separate install showed generic "unknown app" box icons for
# every third-party app in the launcher/pinned-apps ("his icons... show
# up as square unknown boxes"), on the White theme specifically -- root-
# caused earlier THIS SAME theme's own icons.theme names an icon-theme
# variant ("Yaru-grey") that yaru-icon-theme never actually ships,
# falling back to hicolor's own sparse coverage for anything not built
# in. Fixed for this dev machine by hand at the time (a symlink straight
# into the checkout) -- never wired into install/update, so every OTHER
# install of this repo still has the untouched stock bug. This closes
# that gap: any theme-overlays/<name>/ directory in this checkout now
# deploys automatically, the same way plugins/looknfeel already do.
theme_overlay_backup_dir="$state_dir/backups/theme-overlays"
mkdir -p "$theme_overlay_backup_dir"

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
# id -> its own source dir (could be "$script_dir/ruixen.X" or
# "$script_dir/bars/v1/ruixen.X") -- the post-deploy hash verification
# below needs the REAL source path back, not "$script_dir/$id" rebuilt
# from the id alone (that assumption broke the moment bars/v1/ moved
# plugins out of a flat root layout: every verify would have hashed a
# now-nonexistent directory and failed every install).
declare -A PLUGIN_SOURCE_DIR_FOR_ID
SHELL_JSON_TOUCHED=0
SHELL_JSON_HAD_BACKUP=0
LOOKNFEEL_TOUCHED=0
LOOKNFEEL_HAD_BACKUP=0
# Direct review finding ("Roll back deployed Hyprland assets when
# install/update fails", #20): #15 moved looknfeel.ruixen.lua/
# looknfeel.default.lua out to a stable deployed path
# (~/.local/share/ruixen-shell/hyprland/), overwritten unconditionally
# in [5/6] with no backup and nothing in rollback_all to undo it --  a
# failure at the final restart step left the NEW checkout's assets
# deployed even though plugins/shell.json/the looknfeel.lua symlink all
# correctly rolled back to the previous working install. Same
# bookkeeping shape as the plugin backups above: keyed by variant name
# (only ever "looknfeel.ruixen.lua"/"looknfeel.default.lua" today, an
# associative array rather than two near-duplicate flat vars since the
# deploy loop already treats both variants identically).
LOOKNFEEL_DATA_TOUCHED=0
LOOKNFEEL_DATA_ROOT_PREEXISTED=0
declare -A LOOKNFEEL_DATA_HAD_BACKUP

# Same shape as LOOKNFEEL_DATA_* above, keyed by "themename/filename"
# instead of a fixed variant list -- theme-overlays/ can hold any number
# of themes with any number of files each. THEME_OVERLAY_HAD_BACKUP
# covers the stable deployed copy under ~/.local/share/ruixen-shell/;
# THEME_OVERLAY_CONFIG_HAD_BACKUP covers a real (non-ours) pre-existing
# file at the ~/.config/omarchy/themes/<name>/ target, so a user's own
# hand-written overlay for the same theme/filename is never silently
# discarded. THEME_OVERLAY_CONFIG_PREEXISTED_AS_OURS covers the third
# case -- already our own symlink from a prior run, needing neither a
# backup NOR "leave it deleted" on rollback, but "recreate the symlink"
# instead (see its own comment at the deploy site below).
THEME_OVERLAYS_TOUCHED=0
THEME_OVERLAY_TOUCHED_KEYS=()
declare -A THEME_OVERLAY_HAD_BACKUP
declare -A THEME_OVERLAY_CONFIG_HAD_BACKUP
declare -A THEME_OVERLAY_CONFIG_PREEXISTED_AS_OURS

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

rollback_looknfeel_data() {
  [[ "$LOOKNFEEL_DATA_TOUCHED" -eq 1 ]] || return 0
  local variant
  for variant in looknfeel.ruixen.lua looknfeel.square.lua looknfeel.default.lua; do
    rm -f "$looknfeel_data_dir/$variant"
    if [[ "${LOOKNFEEL_DATA_HAD_BACKUP[$variant]:-0}" -eq 1 ]]; then
      mv "$looknfeel_data_backup_dir/$variant.bak.$stamp" "$looknfeel_data_dir/$variant" \
        || printf '  warning: could not restore %s from its backup\n' "$variant" >&2
    fi
  done
  # A genuine first install leaves the whole ~/.local/share/ruixen-shell
  # root gone again, not just its two files with an empty directory
  # tree left behind -- rmdir only ever succeeds on an empty directory,
  # so this is a no-op (silenced) if a reinstall's own pre-existing
  # asset was restored into it above instead.
  if [[ "$LOOKNFEEL_DATA_ROOT_PREEXISTED" -eq 0 ]]; then
    rmdir "$looknfeel_data_dir" "$HOME/.local/share/ruixen-shell" 2>/dev/null || true
  fi
}

rollback_theme_overlays() {
  [[ "$THEME_OVERLAYS_TOUCHED" -eq 1 ]] || return 0
  local idx key theme_name fname data_target config_target
  for (( idx=${#THEME_OVERLAY_TOUCHED_KEYS[@]}-1; idx>=0; idx-- )); do
    key="${THEME_OVERLAY_TOUCHED_KEYS[$idx]}"
    theme_name="${key%%/*}"
    fname="${key#*/}"
    data_target="$HOME/.local/share/ruixen-shell/theme-overlays/$theme_name/$fname"
    config_target="$HOME/.config/omarchy/themes/$theme_name/$fname"

    # Data copy restored FIRST -- the "already our own symlink" case
    # below needs it back in place before recreating a symlink to it.
    rm -f "$data_target"
    if [[ "${THEME_OVERLAY_HAD_BACKUP[$key]:-0}" -eq 1 ]]; then
      mv "$theme_overlay_backup_dir/$theme_name/$fname.bak.$stamp" "$data_target" \
        || printf '  warning: could not restore %s from its backup\n' "$data_target" >&2
    fi

    rm -f "$config_target"
    if [[ "${THEME_OVERLAY_CONFIG_HAD_BACKUP[$key]:-0}" -eq 1 ]]; then
      mv "$theme_overlay_backup_dir/$theme_name/$fname.config.bak.$stamp" "$config_target" \
        || printf '  warning: could not restore %s from its backup\n' "$config_target" >&2
    elif [[ "${THEME_OVERLAY_CONFIG_PREEXISTED_AS_OURS[$key]:-0}" -eq 1 && -e "$data_target" ]]; then
      # Was already our own symlink before this run (no backup taken,
      # nothing of the user's to lose) -- put that exact symlink back
      # now that the data copy it points to is restored too, rather
      # than leaving this theme with no overlay at all.
      ln -sf "$data_target" "$config_target"
    fi
    rmdir "$HOME/.config/omarchy/themes/$theme_name" 2>/dev/null || true
    rmdir "$HOME/.local/share/ruixen-shell/theme-overlays/$theme_name" 2>/dev/null || true
  done
  # Unconditional, not gated on "did this preexist" -- rmdir only ever
  # succeeds on a genuinely empty directory, so there's no preexistence
  # tracking actually needed here (unlike a FILE, where "was there
  # already" decides whether to back up/restore real content). Real
  # bug, found by this file's own tests/install-theme-overlays.sh (not
  # guessed): a flag WAS tracked here, but by the time this step's own
  # deploy runs, ~/.local/share/ruixen-shell already exists almost
  # every real run -- looknfeel's OWN deploy (the step immediately
  # before this one) already created it, in THIS SAME run, not some
  # prior install -- so the flag read "preexisted" even on a genuine
  # first install, and this cleanup silently never ran at all, leaving
  # an empty theme-overlays/ directory behind after every rollback.
  rmdir "$HOME/.local/share/ruixen-shell/theme-overlays" "$HOME/.local/share/ruixen-shell" 2>/dev/null || true
}

rollback_all() {
  trap - ERR
  if [[ ${#DEPLOYED_PLUGIN_IDS[@]} -eq 0 && "$SHELL_JSON_TOUCHED" -eq 0 && "$LOOKNFEEL_TOUCHED" -eq 0 && "$LOOKNFEEL_DATA_TOUCHED" -eq 0 && "$THEME_OVERLAYS_TOUCHED" -eq 0 ]]; then
    # Failed before anything was actually changed (e.g. plugin
    # validation) -- fail()'s own message already explained why,
    # nothing to undo.
    return 0
  fi
  printf '\ninstall failed -- rolling back changes made this run...\n' >&2
  rollback_theme_overlays
  rollback_looknfeel
  rollback_looknfeel_data
  rollback_shell_json
  rollback_plugins
  printf 'rollback complete -- your previous installation should be unchanged.\n' >&2
}
trap rollback_all ERR

printf '\n[2/7] Validating plugins\n'
# Every manifest is checked before ANYTHING is deployed -- a failure
# here never touches a single already-installed plugin.
for dir in "${plugin_source_dirs[@]}"; do
  [[ -d "$dir" ]] || continue
  id="$(basename "$dir")"
  omarchy plugin validate "$dir" || fail "plugin failed validation: $id -- nothing has been changed"
done
printf '  all plugins passed validation\n'

printf '\n[3/7] Installing plugins\n'
for dir in "${plugin_source_dirs[@]}"; do
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
  PLUGIN_SOURCE_DIR_FOR_ID["$id"]="$dir"
  cp -r "$dir" "$target"
  printf '  installed %s\n' "$id"
done

# Direct real-world report (issue #32's exact scenario): a hard
# interruption mid-run -- a closed terminal, a crash, "the screen cut
# off" -- can leave a mixed old/new plugin set with no ERR trap ever
# firing to catch it, since kill -9/power-loss/a closed window skips
# trap handling entirely. A LATER, fully-completed install run always
# fixes this on its own (the loop above unconditionally replaces every
# plugin from scratch, every time) -- the actual gap was that nothing
# ever confirmed a run genuinely finished clean, so a tester could
# reasonably re-run this several times and still not know whether it
# had ever actually succeeded. Verifying the copy immediately, not in
# a separate later diagnostic, catches a bad run at the moment it
# happens instead of leaving it to be rediscovered by chance. Content
# hash, not a version-string comparison -- see ruixen-doctor.sh's own
# comment for why that check is the one that actually matters (most
# plugin edits never bump their own manifest version at all).
verify_dir_hash() {
  local dir="$1"
  (cd "$dir" && find . -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null) | sha256sum | awk '{print $1}'
}
for id in "${DEPLOYED_PLUGIN_IDS[@]}"; do
  source_hash="$(verify_dir_hash "${PLUGIN_SOURCE_DIR_FOR_ID[$id]}")"
  deployed_hash="$(verify_dir_hash "$plugins_dir/$id")"
  [[ "$source_hash" == "$deployed_hash" ]] \
    || fail "$id was deployed but does not match this checkout's own source -- the copy did not complete cleanly (nothing else has been changed; safe to just run this again)"
done
printf '  verified: every deployed plugin exactly matches this checkout\n'

printf '\n[4/7] Applying shell layout\n'
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

printf '\n[5/7] Matching Hyprland window look to the frame/bar\n'
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
#
# Direct review finding ("Roll back deployed Hyprland assets when
# install/update fails", #20): that atomic-per-file write already
# protected against a HALF-written asset, but not against a failure
# LATER in this same run (the final restart, most likely) leaving a
# fully-written NEW asset in place while everything else correctly
# rolled back to the previous install. Backed up here, same
# "tracked BEFORE the actual copy" ordering as the plugin loop above,
# so a failure partway through this loop still gets whatever variant
# DID get backed up restored, not just the ones that fully completed.
LOOKNFEEL_DATA_TOUCHED=1
# Checked BEFORE mkdir -p below creates it -- a genuine first install
# (nothing under ~/.local/share/ruixen-shell/ yet) should leave that
# whole directory gone again on rollback, not just its two files with
# an empty shell left behind. A reinstall's already-existing directory
# is left alone either way; rollback_looknfeel_data only ever touches
# the files inside it.
[[ -e "$HOME/.local/share/ruixen-shell" ]] && LOOKNFEEL_DATA_ROOT_PREEXISTED=1 || LOOKNFEEL_DATA_ROOT_PREEXISTED=0
looknfeel_data_dir="$HOME/.local/share/ruixen-shell/hyprland"
mkdir -p "$looknfeel_data_dir"
for variant in looknfeel.ruixen.lua looknfeel.square.lua looknfeel.default.lua; do
  if [[ -e "$looknfeel_data_dir/$variant" ]]; then
    cp "$looknfeel_data_dir/$variant" "$looknfeel_data_backup_dir/$variant.bak.$stamp"
    LOOKNFEEL_DATA_HAD_BACKUP[$variant]=1
  fi
  tmp_variant="$(mktemp "$looknfeel_data_dir/.${variant}.XXXXXX")"
  cp "$script_dir/hyprland/$variant" "$tmp_variant"
  mv "$tmp_variant" "$looknfeel_data_dir/$variant"
done

looknfeel_target="$HOME/.config/hypr/looknfeel.lua"
# Preserve whichever variant is already active across a reinstall/
# update -- real bug, found live via direct report ("Looks and Feel
# turns back on after a restart"): this unconditionally pointed at the
# "on" (ruixen) variant on every run, silently overriding an explicit
# `ruixen-lookfeel.sh off` from a previous install the moment
# update.sh (which calls install.sh) ran again -- easy to describe as
# "after a restart" since update.sh itself ends with one. Read BEFORE
# the deployed-variant refresh loop above touches $looknfeel_target
# itself, so this still reflects whatever the user's install actually
# had going into this run. Only a target that ISN'T already one of
# Ruixen's own two deployed variants (a genuinely fresh install, or
# some unrelated file) falls back to "on", matching this project's own
# out-of-the-box look.
looknfeel_current_variant=""
if [[ -L "$looknfeel_target" ]]; then
  looknfeel_existing_link="$(readlink "$looknfeel_target")"
  case "$looknfeel_existing_link" in
    "$looknfeel_data_dir"/*) looknfeel_current_variant="$(basename "$looknfeel_existing_link")" ;;
  esac
fi
looknfeel_src="$looknfeel_data_dir/${looknfeel_current_variant:-looknfeel.ruixen.lua}"
looknfeel_pristine_dir="$state_dir/looknfeel-pristine"
LOOKNFEEL_TOUCHED=1
"$script_dir/lib/apply-looknfeel.sh" "$looknfeel_target" "$looknfeel_src" "$looknfeel_pristine_dir" "$stamp"
if [[ -e "${looknfeel_target}.bak.${stamp}" ]]; then
  LOOKNFEEL_HAD_BACKUP=1
  printf '  backed up existing looknfeel.lua -> looknfeel.lua.bak.%s\n' "$stamp"
fi
hyprctl reload >/dev/null 2>&1 || true
case "$looknfeel_current_variant" in
  looknfeel.default.lua)
    printf '  kept your existing choice: stock Omarchy look (square corners, no blur)\n'
    ;;
  looknfeel.square.lua)
    printf '  kept your existing choice: square corners, with the thin border/blur/shadow\n'
    ;;
  *)
    printf '  applied rounded corners + blur matching the frame (24px)\n'
    ;;
esac
printf '  toggle any time with: %s/hyprland/ruixen-lookfeel.sh off\n' "$script_dir"

printf '\n[6/7] Applying theme overlays\n'
# Per-theme overrides for stock Omarchy themes that ship a real bug or
# an assumption ruixen.bar breaks (see theme_overlay_backup_dir's own
# comment above for the White/icons.theme case this closes). Same
# deploy-then-symlink shape as looknfeel above: each file is copied to
# a stable path under ~/.local/share/ruixen-shell/ first, and
# ~/.config/omarchy/themes/<name>/<file> symlinks there -- never a
# symlink straight into this checkout, so moving/deleting the clone
# later can't break a theme apply the way #15 already fixed for
# looknfeel.lua.
theme_overlays_data_root="$HOME/.local/share/ruixen-shell/theme-overlays"
theme_overlays_applied=()
if [[ -d "$script_dir/theme-overlays" ]]; then
  for theme_src_dir in "$script_dir/theme-overlays"/*/; do
    [[ -d "$theme_src_dir" ]] || continue
    theme_name="$(basename "$theme_src_dir")"
    data_dir="$theme_overlays_data_root/$theme_name"
    config_dir="$HOME/.config/omarchy/themes/$theme_name"
    mkdir -p "$data_dir" "$config_dir" "$theme_overlay_backup_dir/$theme_name"

    for f in "$theme_src_dir"*; do
      [[ -f "$f" ]] || continue
      fname="$(basename "$f")"
      key="$theme_name/$fname"
      data_target="$data_dir/$fname"
      config_target="$config_dir/$fname"

      if [[ -e "$data_target" ]]; then
        cp "$data_target" "$theme_overlay_backup_dir/$theme_name/$fname.bak.$stamp"
        THEME_OVERLAY_HAD_BACKUP["$key"]=1
      fi
      # A real, non-Ruixen file already at the config target (a user's
      # own hand-written overlay for this exact theme/filename) is
      # backed up, never silently clobbered -- our own symlink from a
      # previous run just gets replaced, nothing of the user's to lose.
      if [[ -L "$config_target" && "$(readlink "$config_target")" == "$data_target" ]]; then
        # Already our own symlink from a prior run -- no backup needed,
        # but rollback still has to know a symlink belongs here at all
        # (not "nothing did"), or a failure later in THIS run would
        # roll the stable data copy back correctly while leaving the
        # config-side symlink simply deleted -- worse than before this
        # run started, not merely unchanged.
        THEME_OVERLAY_CONFIG_PREEXISTED_AS_OURS["$key"]=1
      elif [[ -e "$config_target" ]]; then
        cp -P "$config_target" "$theme_overlay_backup_dir/$theme_name/$fname.config.bak.$stamp"
        THEME_OVERLAY_CONFIG_HAD_BACKUP["$key"]=1
      fi

      tmp_target="$(mktemp "$data_dir/.${fname}.XXXXXX")"
      cp "$f" "$tmp_target"
      mv "$tmp_target" "$data_target"
      THEME_OVERLAYS_TOUCHED=1
      THEME_OVERLAY_TOUCHED_KEYS+=("$key")

      ln -sf "$data_target" "$config_target"
    done
    theme_overlays_applied+=("$theme_name")
  done
fi

if [[ ${#theme_overlays_applied[@]} -eq 0 ]]; then
  printf '  none in this checkout\n'
else
  printf '  applied: %s\n' "${theme_overlays_applied[*]}"
  # Re-apply the theme LIVE if it's the one currently active, same
  # immediacy as hyprctl reload above -- otherwise a fix like the White
  # icons.theme one sits deployed but inert until the user happens to
  # switch themes away and back. `omarchy theme set` re-reads
  # ~/.config/omarchy/themes/<name>/ (this run just populated it) and
  # re-runs every theme-set.d hook (gsettings icon-theme included).
  current_theme_slug="$(cat "$HOME/.local/state/omarchy/current/theme.name" 2>/dev/null || true)"
  if [[ -n "$current_theme_slug" ]]; then
    for theme_name in "${theme_overlays_applied[@]}"; do
      if [[ "$theme_name" == "$current_theme_slug" ]]; then
        # Best-effort, not `&& printf ...` -- that bare-statement shape
        # is exactly the bug #21's own prune-poster-cache.sh CI failure
        # already taught this project to avoid: under `set -e`, a
        # failing left side of a top-level `A && B` still trips the ERR
        # trap and rolls back the ENTIRE install for what should be a
        # skippable nicety (theme-set can legitimately no-op without a
        # live D-Bus session, same guard omarchy-theme-set-gnome's own
        # script already documents). `if` + explicit `|| true`, like
        # hyprctl reload above, swallows a failure here without ever
        # being the statement `set -e` reacts to.
        if omarchy theme set "$theme_name" >/dev/null 2>&1; then
          printf '  re-applied the active theme (%s) so this takes effect immediately\n' "$theme_name"
        else
          printf '  could not re-apply the active theme (%s) live -- will take effect next time it is (re)selected\n' "$theme_name"
        fi
        break
      fi
    done
  fi
fi

printf '\n[7/7] Restarting Omarchy shell\n'
# Direct real-world report: a tester's install/update completed with
# every plugin file genuinely deployed and up to date, yet the bar
# kept rendering old, pre-update layout after the restart -- a
# stale-QML-bytecode disk cache was the working theory that actually
# fixed it live (rm -rf + restart), confirmed against Quickshell's own
# real qmlcache directory on this dev machine (~/.cache/quickshell/
# qmlcache/*.qmlc). Qt's QML disk cache is SUPPOSED to invalidate
# automatically off each source file's mtime, but that is exactly the
# kind of check that can silently go wrong -- clearing it outright
# before every restart costs one cold-recompile (a few hundred ms) and
# removes an entire class of "the files are right but the screen is
# still wrong" reports, no need to root-cause the exact invalidation
# failure to be confident this is safe: it is purely compiled
# bytecode, never data, so deleting it can never lose anything.
rm -rf "$HOME/.cache/quickshell/qmlcache" 2>/dev/null || true
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
for dir in "${plugin_source_dirs[@]}"; do
  [[ -d "$dir" ]] || continue
  prune_backups "$backup_retain_count" "$plugin_backup_dir/$(basename "$dir").bak.*"
done
prune_backups "$backup_retain_count" "${shell_json}.bak.*"
prune_backups "$backup_retain_count" "${looknfeel_target}.bak.*"
# The new #20 backup location gets the same bounded retention as every
# other backup here -- left unbounded, it would just reintroduce the
# exact unbounded-accumulation problem #10 already fixed everywhere
# else, for a location that happens to be new instead of old.
for variant in looknfeel.ruixen.lua looknfeel.square.lua looknfeel.default.lua; do
  prune_backups "$backup_retain_count" "$looknfeel_data_backup_dir/$variant.bak.*"
done
# Same bounded retention, for theme-overlays/ backups -- prune_backups
# already sorts oldest-first and no-ops below the retain count, so a
# blanket two-level glob across every theme/file this checkout has ever
# shipped an overlay for is safe even though the exact set can grow or
# shrink between runs (unlike the fixed looknfeel variant list above).
prune_backups "$backup_retain_count" "$theme_overlay_backup_dir/*/*.bak.*"
prune_backups "$backup_retain_count" "$theme_overlay_backup_dir/*/*.config.bak.*"

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
