#!/usr/bin/env bash
# Reverses lib/apply-looknfeel.sh: restores $1 (target path, e.g.
# ~/.config/hypr/looknfeel.lua) to whatever state was recorded under
# $2 (the same pristine dir apply-looknfeel.sh wrote to on first
# install), falling back to Omarchy's own default template at $3 if no
# pristine record exists at all (e.g. Ruixen was installed by a
# version of install.sh that predates this record -- see
# uninstall.sh's own caller for the older-heuristic fallback in that
# case).
#
# Only ever acts if $1 is currently a symlink -- the caller already
# guards this too, kept here since this script has real filesystem
# side effects and shouldn't touch a file that was never Ruixen's.
#
# Prints one machine-readable status word to stdout so the caller can
# choose its own message / fallback without parsing prose:
#   symlink:<target>    restored the user's original symlink
#   file                restored the user's original regular file
#   omarchy-default      nothing existed before Ruixen -- installed
#                         Omarchy's own default template
#   no-default-available  nothing existed before Ruixen, and no
#                          Omarchy default template was found either
#   no-pristine-record    no record at all (pre-dates this mechanism)
#   not-a-symlink          $1 wasn't a Ruixen symlink, nothing done
set -Eeuo pipefail

target="$1"
pristine_dir="$2"
omarchy_default="$3"

if [[ ! -L "$target" ]]; then
  printf 'not-a-symlink\n'
  exit 0
fi

rm -f "$target"

if [[ -e "$pristine_dir/target" ]]; then
  link_target="$(cat "$pristine_dir/target")"
  ln -s "$link_target" "$target"
  printf 'symlink:%s\n' "$link_target"
elif [[ -e "$pristine_dir/looknfeel.lua" ]]; then
  cp -a "$pristine_dir/looknfeel.lua" "$target"
  printf 'file\n'
elif [[ -e "$pristine_dir/absent" ]]; then
  if [[ -f "$omarchy_default" ]]; then
    cp "$omarchy_default" "$target"
    printf 'omarchy-default\n'
  else
    printf 'no-default-available\n'
  fi
else
  printf 'no-pristine-record\n'
fi
