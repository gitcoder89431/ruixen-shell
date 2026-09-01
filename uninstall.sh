#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf 'ruixen-shell uninstall: %s\n' "$*" >&2
  exit 1
}

command -v omarchy >/dev/null 2>&1 || fail "Omarchy is required (command 'omarchy' not found)"
command -v jq >/dev/null 2>&1 || fail "jq is required (command 'jq' not found)"

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
  source omarchy-shell-config
  # $NORMALIZE (bash variable, unescaped) is interpolated into the jq
  # program text itself; \$pristineBar (escaped) stays a literal jq
  # variable reference for --argjson to fill in -- same convention
  # omarchy-bar's own cmd_* functions use. Caught live, not assumed: a
  # single-quoted version of this line left $NORMALIZE un-interpolated
  # by bash, so jq saw the literal text "$NORMALIZE" and failed with
  # "$NORMALIZE is not defined."
  commit "$NORMALIZE | .bar = \$pristineBar" --argjson pristineBar "$pristine_bar"
  printf '  restored your pre-Ruixen bar (%s)\n' "$(jq -r '.id' <<<"$pristine_bar")"
else
  # No usable pristine bar -- a fresh install with nothing before
  # Ruixen, a missing/corrupt snapshot (this install predates #1's
  # fix, say), or the recorded bar was somehow already ruixen.bar.
  # Falls back to Omarchy's own real stock default exactly like
  # before, rather than failing the whole uninstall over it.
  omarchy bar reset
  omarchy bar defaults
  printf '  no usable pre-Ruixen bar found -- restored the built-in Omarchy bar instead\n'
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
plugin_ids=$(omarchy plugin list --json | jq -r '.[] | select(.id | startswith("ruixen.")) | .id')
if [[ -z "$plugin_ids" ]]; then
  printf '  no ruixen.* plugins installed\n'
else
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    omarchy plugin remove "$id" --yes
    printf '  removed %s\n' "$id"
  done <<<"$plugin_ids"
fi

for backup in "$plugins_dir"/.ruixen.*.bak.*; do
  [[ -e "$backup" ]] || continue
  rm -rf "$backup"
  printf '  deleted backup %s\n' "$(basename "$backup")"
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
restore_result="$("$script_dir/lib/restore-looknfeel.sh" "$looknfeel_target" "$looknfeel_pristine_dir" "$omarchy_default")"
case "$restore_result" in
  symlink:*)
    printf '  restored your own looknfeel.lua symlink -> %s\n' "${restore_result#symlink:}"
    hyprctl reload >/dev/null 2>&1 || true
    ;;
  file)
    printf '  restored your own looknfeel.lua\n'
    hyprctl reload >/dev/null 2>&1 || true
    ;;
  omarchy-default)
    printf "  restored Omarchy's own default looknfeel.lua (nothing existed before Ruixen)\n"
    hyprctl reload >/dev/null 2>&1 || true
    ;;
  no-default-available)
    printf '  WARNING: nothing existed before Ruixen, and no Omarchy default was found at %s -- leaving looknfeel.lua unset, Hyprland reload will error until you restore one manually\n' "$omarchy_default" >&2
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
      mv "$latest_backup" "$looknfeel_target"
      printf '  restored looknfeel.lua from %s (no pristine record found -- best guess)\n' "$latest_backup"
    elif [[ -f "$omarchy_default" ]]; then
      cp "$omarchy_default" "$looknfeel_target"
      printf "  restored Omarchy's own default looknfeel.lua (no backup or pristine record found)\n"
    else
      printf '  WARNING: no backup and no Omarchy default found at %s -- leaving looknfeel.lua unset, Hyprland reload will error until you restore one manually\n' "$omarchy_default" >&2
    fi
    hyprctl reload >/dev/null 2>&1 || true
    ;;
  not-a-symlink)
    printf '  looknfeel.lua is not a Ruixen symlink -- leaving it alone\n'
    ;;
esac

# Direct review finding ("Decouple deployed Hyprland looknfeel from the
# git checkout path", #15): install.sh deploys both looknfeel variants
# to this Ruixen-owned data dir, used for nothing else -- by the time
# the case above has run, whatever looknfeel.lua now points at (the
# restored original, or left alone entirely for the not-a-symlink
# case) no longer depends on it, so a full uninstall removing it too is
# the same "don't leave Ruixen's own files behind" cleanup [2/4] above
# already does for plugin backups, just for this data dir instead.
rm -rf "$HOME/.local/share/ruixen-shell"

printf '\n[4/4] Restarting Omarchy shell\n'
omarchy restart shell

# Only reached once every restoration step above has actually succeeded
# (set -Eeuo pipefail aborts the whole script on any earlier failure) --
# direct review finding ("Reset pristine install snapshots after a
# successful full uninstall", #13): the pristine baseline install.sh
# records on first install is never refreshed on a later reinstall, so
# without this, a second install->uninstall cycle on the same machine
# would silently restore THIS uninstall's pre-Ruixen state again next
# time, even after the user changed their setup in between. See
# lib/reset-pristine-baseline.sh's own comment for exactly what this
# does and does not remove -- launcher favorites and other real state
# under ~/.local/state/ruixen/ are left alone.
"$script_dir/lib/reset-pristine-baseline.sh" "$HOME/.local/state/ruixen"

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
