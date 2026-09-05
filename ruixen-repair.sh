#!/usr/bin/env bash
# Issue #33's `repair` half -- `status` is already covered by
# ruixen-doctor.sh (version/revision, plugin content-hash drift, bar
# layout, runtime health); this is the genuinely missing piece: fixing
# what doctor only reports. Reuses doctor's own detection (same
# dir_hash content check, not a version-string comparison) and, when
# something is actually wrong, install.sh's own already-hardened
# deploy path (content-hash verification + qmlcache clear, see its own
# recent history) to fix it -- not a separate reimplementation. Repair
# only ever repairs Ruixen-owned files (its own plugin directories,
# looknfeel); it never touches shell.json directly, and never touches
# a third-party plugin.
#
# Usage: from an existing ruixen-shell checkout, same as update.sh:
#   ./ruixen-repair.sh --dry-run   # report what would be fixed, change nothing
#   ./ruixen-repair.sh             # actually fix it
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
plugins_dir="$HOME/.config/omarchy/plugins"
dry_run=0

for arg in "$@"; do
  case "$arg" in
    --dry-run) dry_run=1 ;;
    -h|--help)
      printf 'Usage: %s [--dry-run]\n' "$(basename "$0")"
      exit 0
      ;;
    *)
      printf 'ruixen-repair: unknown option: %s\n' "$arg" >&2
      exit 1
      ;;
  esac
done

[[ -d "$script_dir/.git" ]] || {
  printf 'ruixen-repair: %s is not a git checkout -- clone the repo with git instead of copying files out of it\n' "$script_dir" >&2
  exit 1
}

# Same content-hash logic as ruixen-doctor.sh -- see that script's own
# comment for why this replaced a version-string comparison (most
# plugin edits never bump their manifest version at all, so a version
# match said nothing real about whether the file content matched).
dir_hash() {
  local dir="$1"
  [[ -d "$dir" ]] || { echo "(missing)"; return; }
  (cd "$dir" && find . -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null) | sha256sum | awk '{print $1}'
}

printf '=== Ruixen Repair ===\n\n'

broken_plugins=()
for dir in "$script_dir"/ruixen.*/; do
  [[ -d "$dir" ]] || continue
  id="$(basename "$dir")"
  if [[ ! -e "$plugins_dir/$id" ]] || [[ "$(dir_hash "$dir")" != "$(dir_hash "$plugins_dir/$id")" ]]; then
    broken_plugins+=("$id")
  fi
done

looknfeel_target="$HOME/.config/hypr/looknfeel.lua"
looknfeel_broken=0
if [[ -L "$looknfeel_target" ]]; then
  link_target="$(readlink -f "$looknfeel_target" 2>/dev/null || true)"
  [[ -n "$link_target" && -e "$link_target" ]] || looknfeel_broken=1
elif [[ ! -e "$looknfeel_target" ]]; then
  # Absent entirely is not automatically "broken" -- a user may run a
  # bar/window setup that never wanted Ruixen's own looknfeel at all
  # (see lib/apply-looknfeel.sh's own pristine-record handling). Only
  # a genuinely dangling symlink (the case above) is unambiguously a
  # repair target; report absence but do not "fix" a state that may be
  # entirely intentional.
  :
fi

if [[ "${#broken_plugins[@]}" -eq 0 && "$looknfeel_broken" -eq 0 ]]; then
  printf 'Healthy -- every plugin file matches this checkout, looknfeel.lua is not a dangling link. Nothing to repair.\n'
  exit 0
fi

printf 'Found drift:\n'
for id in "${broken_plugins[@]:-}"; do
  [[ -n "$id" ]] || continue
  printf '  %s -- deployed files missing or do not match this checkout\n' "$id"
done
[[ "$looknfeel_broken" -eq 1 ]] && printf '  looknfeel.lua -- symlink target is missing (dangling)\n'
printf '\n'

if [[ "$dry_run" -eq 1 ]]; then
  printf 'Dry run -- nothing changed. Re-run without --dry-run to fix the above.\n'
  printf 'Fixing runs this checkout own install.sh in full (its deploy loop\n'
  printf 'already unconditionally re-verifies every plugin, not just the\n'
  printf 'ones listed above) -- shell.json and any third-party layout\n'
  printf 'entries are preserved exactly as install.sh itself already\n'
  printf 'guarantees on every reinstall.\n'
  exit 0
fi

printf 'Repairing via this checkout own install.sh (preserves shell.json and\n'
printf 'any third-party layout entries exactly as every reinstall already does)...\n\n'
exec "$script_dir/install.sh"
