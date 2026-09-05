#!/usr/bin/env bash
# Applies Ruixen's Hyprland look-and-feel at $1 (target path, e.g.
# ~/.config/hypr/looknfeel.lua) by pointing it at $2 (Ruixen's own
# looknfeel.ruixen.lua), recording enough state under $3 (a
# Ruixen-owned "pristine" directory) to reverse it later. $4 is the
# timestamp suffix used for the human-readable backup copy.
#
# Real filesystem side effects, not a pure function like
# build-shell-json.sh (mv/cp -a/readlink/symlinks have no meaningful
# stdin/stdout shape) -- tests/looknfeel-preserve.sh exercises this
# against a throwaway directory tree instead of a real $HOME.
#
# Direct review finding ("Preserve pre-existing Hyprland looknfeel.lua
# files and symlinks"): the old inline version only backed up when the
# target `-e && ! -L` (a plain regular file) -- a user with dotfiles
# who already had `looknfeel.lua` symlinked elsewhere got that symlink
# silently overwritten with NO backup of any kind, since the guard
# skipped the whole branch for a symlink. `mv` on a symlink renames the
# symlink itself without following it (confirmed directly, not
# assumed), so the actual fix is just widening that guard to cover
# symlinks too.
#
# The other real fix: a pristine record -- absent / regular file /
# symlink + exact target -- written ONCE, not on every reinstall/
# update. By the second run $target is Ruixen's OWN symlink, and
# re-recording it here would silently throw away the real original
# captured on first install. Same one-time-snapshot pattern as
# shell.json.pre-ruixen (#1).
set -Eeuo pipefail

target="$1"
src="$2"
pristine_dir="$3"
stamp="$4"

pristine_recorded=0
[[ -e "$pristine_dir/target" || -e "$pristine_dir/absent" ]] && pristine_recorded=1

if [[ -e "$target" || -L "$target" ]]; then
  if [[ "$pristine_recorded" -eq 0 ]]; then
    mkdir -p "$pristine_dir"
    if [[ -L "$target" ]]; then
      existing_link_target="$(readlink "$target")"
      case "$existing_link_target" in
        # Real bug, found live: if $target is ALREADY a Ruixen-managed
        # symlink the very first time this ever runs (an earlier,
        # unofficial setup, or a prior uninstall/reinstall cycle
        # outside these scripts), recording it as "pristine" captures
        # Ruixen's own look as if it were the user's real original --
        # restore-looknfeel.sh would then "restore" it right back on
        # uninstall instead of actually reverting anything. Recorded
        # as absent instead -- the honest answer here is "no real
        # pre-Ruixen state is known", and restore-looknfeel.sh's own
        # omarchy-default fallback for that case is a genuinely safe
        # one, unlike trusting this record would be.
        */ruixen-shell/*) : > "$pristine_dir/absent" ;;
        *) printf '%s\n' "$existing_link_target" > "$pristine_dir/target" ;;
      esac
    else
      cp -a "$target" "$pristine_dir/looknfeel.lua"
    fi
  fi
  mv "$target" "${target}.bak.${stamp}"
elif [[ "$pristine_recorded" -eq 0 ]]; then
  mkdir -p "$pristine_dir"
  : > "$pristine_dir/absent"
fi

mkdir -p "$(dirname "$target")"
ln -sf "$src" "$target"
