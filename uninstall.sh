#!/usr/bin/env bash
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

fail() {
  printf 'ruixen-shell uninstall: %s\n' "$*" >&2
  exit 1
}

command -v omarchy >/dev/null 2>&1 || fail "Omarchy is required (command 'omarchy' not found)"
command -v jq >/dev/null 2>&1 || fail "jq is required (command 'jq' not found)"

printf '\n[1/4] Switching back to the built-in Omarchy bar\n'
# ruixen.bar reports canDisable: false while it's the ACTIVE bar (confirmed
# via `omarchy plugin list --json`) -- it can't be removed until something
# else is active. `reset` switches to omarchy.bar under the hood (confirmed
# by reading omarchy-bar directly: reset == `cmd_use omarchy.bar`);
# `defaults` then restores the default widget layout on top of it.
omarchy bar reset
omarchy bar defaults

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
# reload. Restores whatever real file install.sh backed up when it first
# ran, or falls back to Omarchy's own real default template if this is a
# fresh install with no prior backup.
looknfeel_target="$HOME/.config/hypr/looknfeel.lua"
if [[ -L "$looknfeel_target" ]]; then
  rm -f "$looknfeel_target"
  latest_backup=""
  for f in "$HOME"/.config/hypr/looknfeel.lua.bak.*; do
    [[ -e "$f" ]] || continue
    if [[ -z "$latest_backup" || "$f" -nt "$latest_backup" ]]; then
      latest_backup="$f"
    fi
  done
  if [[ -n "$latest_backup" ]]; then
    mv "$latest_backup" "$looknfeel_target"
    printf '  restored your own looknfeel.lua from %s\n' "$latest_backup"
  else
    omarchy_default="${OMARCHY_PATH:-/usr/share/omarchy}/default/hypr/looknfeel.lua"
    if [[ -f "$omarchy_default" ]]; then
      cp "$omarchy_default" "$looknfeel_target"
      printf "  restored Omarchy's own default looknfeel.lua (no prior backup found)\n"
    else
      printf '  WARNING: no backup and no Omarchy default found at %s -- leaving looknfeel.lua unset, Hyprland reload will error until you restore one manually\n' "$omarchy_default" >&2
    fi
  fi
  hyprctl reload >/dev/null 2>&1 || true
else
  printf '  looknfeel.lua is not a Ruixen symlink -- leaving it alone\n'
fi

printf '\n[4/4] Restarting Omarchy shell\n'
omarchy restart shell

cat <<EOF

Ruixen Shell has been uninstalled -- back to the built-in Omarchy bar and
look, every plugin's files actually removed (not left behind as a hidden
backup folder).

This checkout ($script_dir) is untouched -- delete it yourself if you don't
want it around anymore. State files under ~/.local/state/ruixen/ (like
launcher favorites) are also left in place in case you reinstall later; the
repo path marker there just won't resolve to anything until you do.

EOF
