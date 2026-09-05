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
#   self-referential-record  the recorded "pristine" target itself
#                             points at a Ruixen-managed path (see
#                             below) -- ignored, falls back to
#                             omarchy-default/no-default-available
#                             the same as if no record existed at all
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
  # Direct real bug, found live on the actual dev machine: a pristine
  # record that itself points at a Ruixen-managed path (the checkout's
  # own hyprland/looknfeel.*.lua, or the stable deployed copy under
  # ~/.local/share/ruixen-shell/) is not a real "before Ruixen" state
  # at all -- apply-looknfeel.sh's own "record once" guard means this
  # can only happen if the target was ALREADY a Ruixen symlink the
  # very first time install.sh ever ran on this machine (some earlier,
  # unofficial setup, or a prior uninstall/reinstall cycle outside
  # these scripts). Trusting it "restores" Ruixen's own rounded-
  # corners/blur look right back, which is exactly what a real user
  # hit: "uninstall didnt reset the looknfeel... hyprland stuff".
  # Treated the same as no record at all -- Omarchy's own real default
  # is a genuinely safe fallback; blindly trusting a self-referential
  # record is not.
  case "$link_target" in
    */ruixen-shell/*)
      if [[ -f "$omarchy_default" ]]; then
        cp "$omarchy_default" "$target"
        printf 'self-referential-record\n'
      else
        printf 'no-default-available\n'
      fi
      ;;
    *)
      ln -s "$link_target" "$target"
      printf 'symlink:%s\n' "$link_target"
      ;;
  esac
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
