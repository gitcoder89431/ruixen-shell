#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/uninstall-failures.sh
source "$script_dir/lib/uninstall-failures.sh"

fail() {
  printf 'ruixen-shell uninstall: %s\n' "$*" >&2
  exit 1
}

command -v omarchy >/dev/null 2>&1 || fail "Omarchy is required (command 'omarchy' not found)"
command -v jq >/dev/null 2>&1 || fail "jq is required (command 'jq' not found)"

# Same lock install.sh takes, and for the same reason ("Add an
# install/update/uninstall lock and collision-safe run identifiers",
# #16) -- an uninstall racing a concurrent install/update could
# interleave with it (remove a plugin install.sh is mid-writing, race
# the bar restore against a live shell.json rewrite, etc). One shared
# lock file means install and uninstall can never run at the same time
# either, not just two installs. Released automatically the instant
# this process exits, same as install.sh's own copy of this comment
# explains in full.
state_dir="$HOME/.local/state/ruixen"
mkdir -p "$state_dir"
lock_file="$state_dir/install.lock"
exec {lock_fd}>"$lock_file"
flock -n "$lock_fd" \
  || fail "another Ruixen install/update/uninstall appears to be running (lock: $lock_file) -- wait for it to finish and try again"

# Direct review finding ("Make full uninstall best-effort and report
# partial cleanup failures", #19): every step below used to be a bare
# statement under set -Eeuo pipefail -- one failed plugin removal, or a
# single failed restore, aborted the WHOLE script immediately, leaving
# whatever hadn't run yet (later plugins, looknfeel restore, the shell
# restart) never even attempted. Every independently-recoverable action
# below is now wrapped in an if/|| that calls record_failure (see
# lib/uninstall-failures.sh) instead of letting set -e abort the
# script, so a full uninstall makes a best effort at every phase
# regardless of what already failed, and reports exactly what didn't
# work at the end. set -e is still on and still catches genuinely
# unexpected bugs elsewhere in this script -- it's only these specific,
# already-anticipated failure points that are deliberately shielded
# from it.
bar_restored=0
looknfeel_restored=0

printf '\n[1/4] Restoring your pre-Ruixen shell configuration\n'
# ruixen.bar reports canDisable: false while it's the ACTIVE bar (confirmed
# via `omarchy plugin list --json`) -- it can't be removed until something
# else is active, so something has to take over the bar slot before step
# [2/4] can remove it either way.
#
# Direct review finding ("Make full uninstall restore the user's
# pre-Ruixen shell configuration"): unconditional `omarchy bar reset` +
# `omarchy bar defaults` always landed on Omarchy's own stock default
# bar, discarding whatever the user had actually customized -- their
# own bar choice, widget layout, position, transparency -- if any of
# that existed before Ruixen was ever installed. Now restores from
# install.sh's own pristine snapshot instead
# (~/.local/state/ruixen/shell.json.pre-ruixen, #1) when a usable one
# exists: the EXACT bar object recorded the first time Ruixen ever
# touched shell.json.
#
# Written via `commit`, the exact same atomic-write-then-live-reload
# primitive Omarchy's own bar reset/defaults/use commands use
# internally (confirmed by reading omarchy-bar + omarchy-shell-config
# directly) -- not a second, competing way of mutating shell.json.
# That's what actually resolves the original concern this script used
# to have about hand-editing the file racing the shell's own in-memory
# state: `commit` IS the safe, first-party way to do that edit, we
# were just avoiding it out of caution before knowing it existed.
pristine_shell_json="$HOME/.local/state/ruixen/shell.json.pre-ruixen"
if pristine_bar="$("$script_dir/lib/pick-pristine-bar.sh" "$pristine_shell_json")"; then
  # shellcheck disable=SC1091
  if source omarchy-shell-config \
    && commit "$NORMALIZE | .bar = \$pristineBar" --argjson pristineBar "$pristine_bar"; then
    printf '  restored your pre-Ruixen bar (%s)\n' "$(jq -r '.id' <<<"$pristine_bar")"
    bar_restored=1
  else
    record_failure "restoring your pre-Ruixen bar failed -- shell.json's bar may still be ruixen.bar"
  fi
else
  # No usable pristine bar -- a fresh install with nothing before
  # Ruixen, a missing/corrupt snapshot (this install predates #1's
  # fix, say), or the recorded bar was somehow already ruixen.bar.
  # Falls back to Omarchy's own real stock default exactly like
  # before, rather than failing the whole uninstall over it.
  if omarchy bar reset && omarchy bar defaults; then
    printf '  no usable pre-Ruixen bar found -- restored the built-in Omarchy bar instead\n'
    bar_restored=1
  else
    record_failure "no usable pre-Ruixen bar found, and falling back to Omarchy's stock bar also failed -- shell.json's bar may still be ruixen.bar"
  fi
fi

printf '\n[2/4] Removing Ruixen Shell plugins\n'
# Curated to "ruixen." ids only, same scoping the Plugins settings page
# itself uses -- this script has no business touching anyone else's
# plugins. `omarchy plugin remove --yes` already calls setPluginEnabled
# false first for anything still enabled (confirmed by reading
# omarchy-plugin-remove directly), which is the same live IPC path
# `omarchy plugin disable` uses -- so this alone correctly clears both
# bar-widget entries and the top-level "plugins" overlay array (ruixen.
# notch/frame-widget/settings) without this script hand-editing
# shell.json itself, which would risk racing the shell's own in-memory
# state (the exact reason omarchy-bar's own cmd_defaults gives for
# keeping bar resets to one atomic mutation).
#
# omarchy-plugin-remove itself doesn't delete a cp -r'd plugin outright
# though -- it mv's it to a hidden .{id}.bak.<timestamp> folder next to
# the live ones (confirmed by reading it directly). Fine for a one-off
# `omarchy plugin remove`, but direct follow-up: "i think people want
# like a full uninstall" -- an "uninstall everything" action leaving a
# dozen hidden multi-MB backup folders behind forever, undiscoverable
# unless you already know the naming scheme, isn't a real uninstall.
# Deleted explicitly below once every plugin's own remove has run.
plugins_dir="$HOME/.config/omarchy/plugins"
if plugin_list_json="$(omarchy plugin list --json 2>&1)"; then
  plugin_ids="$(jq -r '.[] | select(.id | startswith("ruixen.")) | .id' <<<"$plugin_list_json")"
  if [[ -z "$plugin_ids" ]]; then
    printf '  no ruixen.* plugins installed\n'
  else
    # Each plugin's removal is independent of every other's -- one
    # failing (locked file, a plugin already half-removed by hand,
    # whatever) must not stop the rest from being attempted (#19).
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      if omarchy plugin remove "$id" --yes; then
        printf '  removed %s\n' "$id"
      else
        record_failure "removing plugin $id failed -- it may still be installed"
      fi
    done <<<"$plugin_ids"
  fi
else
  record_failure "could not list installed plugins (omarchy plugin list --json failed) -- no ruixen.* plugins were removed"
fi

for backup in "$plugins_dir"/.ruixen.*.bak.*; do
  [[ -e "$backup" ]] || continue
  if rm -rf "$backup"; then
    printf '  deleted backup %s\n' "$(basename "$backup")"
  else
    record_failure "deleting plugin backup $(basename "$backup") failed"
  fi
done

printf '\n[3/4] Restoring Hyprland window look\n'
# Not a bare `rm -f` on the symlink -- confirmed by reading hyprland.lua
# and bootstrap.lua directly: `require("hypr.looknfeel")` has no fallback
# if ~/.config/hypr/looknfeel.lua is simply missing (Lua's package.path
# only searches ~/.local/state, ~/.config, and $OMARCHY_PATH -- none of
# which have a bare hypr/looknfeel.lua outside the user's own config), so
# deleting it with nothing in its place would break every future Hyprland
# reload.
#
# Restores from lib/apply-looknfeel.sh's own pristine record (absent /
# regular file / symlink + exact target) rather than guessing from the
# newest looknfeel.lua.bak.* -- direct review finding ("uninstall
# restores the exact original state... symlink target is restored as
# a symlink, not copied as a regular file"): once install.sh has run
# more than once, the "newest" .bak.* is Ruixen's OWN prior symlink,
# not the user's real original, so picking it blindly would restore
# the wrong thing. The old newest-.bak.* scan is kept as a fallback
# ONLY for a machine whose Ruixen install predates this record.
looknfeel_target="$HOME/.config/hypr/looknfeel.lua"
looknfeel_pristine_dir="$HOME/.local/state/ruixen/looknfeel-pristine"
omarchy_default="${OMARCHY_PATH:-/usr/share/omarchy}/default/hypr/looknfeel.lua"
if restore_result="$("$script_dir/lib/restore-looknfeel.sh" "$looknfeel_target" "$looknfeel_pristine_dir" "$omarchy_default")"; then
  case "$restore_result" in
    symlink:*)
      printf '  restored your own looknfeel.lua symlink -> %s\n' "${restore_result#symlink:}"
      looknfeel_restored=1
      hyprctl reload >/dev/null 2>&1 \
        || record_failure "hyprctl reload after restoring looknfeel.lua failed -- reload manually to pick it up"
      ;;
    file)
      printf '  restored your own looknfeel.lua\n'
      looknfeel_restored=1
      hyprctl reload >/dev/null 2>&1 \
        || record_failure "hyprctl reload after restoring looknfeel.lua failed -- reload manually to pick it up"
      ;;
    omarchy-default)
      printf "  restored Omarchy's own default looknfeel.lua (nothing existed before Ruixen)\n"
      looknfeel_restored=1
      hyprctl reload >/dev/null 2>&1 \
        || record_failure "hyprctl reload after restoring looknfeel.lua failed -- reload manually to pick it up"
      ;;
    no-default-available)
      record_failure "nothing existed before Ruixen, and no Omarchy default was found at $omarchy_default -- looknfeel.lua left unset, Hyprland reload will error until you restore one manually"
      ;;
    no-pristine-record)
      # Pre-dates this record -- fall back to the old newest-.bak.*
      # heuristic rather than leaving looknfeel.lua gone with nothing in
      # its place.
      latest_backup=""
      for f in "$HOME"/.config/hypr/looknfeel.lua.bak.*; do
        [[ -e "$f" ]] || continue
        if [[ -z "$latest_backup" || "$f" -nt "$latest_backup" ]]; then
          latest_backup="$f"
        fi
      done
      if [[ -n "$latest_backup" ]]; then
        if mv "$latest_backup" "$looknfeel_target"; then
          printf '  restored looknfeel.lua from %s (no pristine record found -- best guess)\n' "$latest_backup"
          looknfeel_restored=1
        else
          record_failure "restoring looknfeel.lua from backup $latest_backup failed"
        fi
      elif [[ -f "$omarchy_default" ]]; then
        if cp "$omarchy_default" "$looknfeel_target"; then
          printf "  restored Omarchy's own default looknfeel.lua (no backup or pristine record found)\n"
          looknfeel_restored=1
        else
          record_failure "copying Omarchy's default looknfeel.lua failed"
        fi
      else
        record_failure "no backup and no Omarchy default found at $omarchy_default -- looknfeel.lua left unset, Hyprland reload will error until you restore one manually"
      fi
      if [[ "$looknfeel_restored" -eq 1 ]]; then
        hyprctl reload >/dev/null 2>&1 \
          || record_failure "hyprctl reload after restoring looknfeel.lua failed -- reload manually to pick it up"
      fi
      ;;
    not-a-symlink)
      printf '  looknfeel.lua is not a Ruixen symlink -- leaving it alone\n'
      looknfeel_restored=1
      ;;
  esac
else
  record_failure "restoring looknfeel.lua failed (lib/restore-looknfeel.sh did not complete)"
fi

# Direct review finding ("Decouple deployed Hyprland looknfeel from the
# git checkout path", #15): install.sh deploys both looknfeel variants
# to this Ruixen-owned data dir, used for nothing else -- by the time
# the case above has run, whatever looknfeel.lua now points at (the
# restored original, or left alone entirely for the not-a-symlink
# case) no longer depends on it, so a full uninstall removing it too is
# the same "don't leave Ruixen's own files behind" cleanup [2/4] above
# already does for plugin backups, just for this data dir instead.
if [[ -e "$HOME/.local/share/ruixen-shell" ]]; then
  rm -rf "$HOME/.local/share/ruixen-shell" \
    || record_failure "deleting the deployed looknfeel data dir (~/.local/share/ruixen-shell) failed"
fi

printf '\n[4/4] Restarting Omarchy shell\n'
omarchy restart shell \
  || record_failure "restarting the Omarchy shell failed -- run 'omarchy restart shell' manually to pick up the changes above"

# Only ever consumes the piece of pristine baseline metadata whose OWN
# restoration actually succeeded (#13, #19) -- "restore succeeded, so
# the record it depended on is safe to retire" is a per-step guarantee,
# not an all-or-nothing one, now that either step can independently
# fail. A retry (running uninstall.sh again) still has whatever record
# it needs for the piece that didn't succeed this time.
if [[ "$bar_restored" -eq 1 && "$looknfeel_restored" -eq 1 ]]; then
  "$script_dir/lib/reset-pristine-baseline.sh" "$HOME/.local/state/ruixen" both \
    || record_failure "clearing the pristine baseline metadata failed (harmless -- just means a future reinstall may see a stale baseline)"
elif [[ "$bar_restored" -eq 1 ]]; then
  "$script_dir/lib/reset-pristine-baseline.sh" "$HOME/.local/state/ruixen" bar \
    || record_failure "clearing the pristine bar snapshot failed (harmless -- just means a future reinstall may see a stale baseline)"
elif [[ "$looknfeel_restored" -eq 1 ]]; then
  "$script_dir/lib/reset-pristine-baseline.sh" "$HOME/.local/state/ruixen" looknfeel \
    || record_failure "clearing the pristine looknfeel snapshot failed (harmless -- just means a future reinstall may see a stale baseline)"
fi

if print_failure_summary; then
  cat <<EOF

Ruixen Shell has been uninstalled -- back to the built-in Omarchy bar and
look, every plugin's files actually removed (not left behind as a hidden
backup folder).

This checkout ($script_dir) is untouched -- delete it yourself if you don't
want it around anymore. Most state files under ~/.local/state/ruixen/ (like
launcher favorites) are also left in place in case you reinstall later; the
repo path marker there just won't resolve to anything until you do. The
pre-Ruixen baseline snapshot has been cleared, though, so a future
reinstall captures a fresh one instead of reusing this one.

EOF
else
  exit 1
fi
