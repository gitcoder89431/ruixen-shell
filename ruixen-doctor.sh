#!/usr/bin/env bash
# Read-only diagnostic report -- makes zero changes to anything. Built
# for exactly the situation that motivated it: a tester's update
# looked like it didn't take effect, and walking them through several
# separate commands one at a time over chat was slow and error-prone.
# This runs all of it in one shot and prints a single block they can
# paste back, with no filesystem paths, hostnames, or config content
# that would identify them -- only ids, versions, counts, and
# relative timestamps.
#
# Usage: from an existing ruixen-shell checkout, same as update.sh:
#   ./ruixen-doctor.sh
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
state_dir="$HOME/.local/state/ruixen"
# Same shared-array reasoning as install.sh's own plugin_source_dirs --
# bar-family plugins live under bars/v1/, the rest at the root.
plugin_source_dirs=("$script_dir"/ruixen.*/ "$script_dir"/bars/*/ruixen.*/)

human_ago() {
  local seconds="$1"
  if (( seconds < 60 )); then printf '%ds' "$seconds"
  elif (( seconds < 3600 )); then printf '%dm' "$((seconds / 60))"
  elif (( seconds < 86400 )); then printf '%dh' "$((seconds / 3600))"
  else printf '%dd' "$((seconds / 86400))"
  fi
}
plugins_dir="$HOME/.config/omarchy/plugins"

printf '=== Ruixen Shell Doctor ===\n\n'

# --- Omarchy itself -----------------------------------------------
printf -- '-- Omarchy --\n'
if command -v omarchy >/dev/null 2>&1; then
  printf 'version: %s\n' "$(omarchy version 2>/dev/null || echo unknown)"
else
  printf 'version: omarchy command not found\n'
fi
printf '\n'

# --- Dependencies -- confirms the external tools this script and
# ruixen.launcher's own Search Files rely on are actually present,
# rather than a missing one silently reading as "no results"/"no
# thumbnail" with zero diagnostic trail, or (for jq below) a cryptic
# mid-script crash under this script's own `set -e` instead of a clear
# answer up front. fd is a real Omarchy base package (confirmed
# directly against /usr/share/omarchy/install/omarchy-base.packages),
# so its absence means something removed it, not a stock gap. ffmpeg/
# ffprobe are pulled in as a dependency of several default Omarchy-
# adjacent packages (mpv, gpu-screen-recorder, obs-studio) -- same
# "should always be there" expectation, checked rather than assumed.
printf -- '-- Dependencies --\n'
for tool in fd ffmpeg ffprobe jq; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '%-10s found\n' "$tool"
  else
    printf '%-10s NOT FOUND\n' "$tool"
  fi
done
# Package, not command -- qt6-multimedia has no binary of its own to
# check for. See the dedicated section below for the full "why this
# matters" -- checked here too so it shows up in the same at-a-glance
# list as the other dependencies, not just its own section.
if pacman -Qi qt6-multimedia >/dev/null 2>&1; then
  printf '%-10s found\n' "qt6-multimedia"
else
  printf '%-10s NOT FOUND -- see Video/GIF wallpaper backend section below\n' "qt6-multimedia"
fi
printf '\n'

# --- Video/GIF wallpaper backend -- direct answer to real reports of
# "selecting an mp4 shows it as current but never actually displays
# it". Root cause, confirmed directly against this exact repo, not
# guessed: ruixen.wallpaper/Service.qml has an unconditional `import
# QtMultimedia` at the top of the file. qt6-multimedia is NOT part of
# Omarchy's own base package set and is not a dependency of quickshell
# or omarchy itself (confirmed via pacman -Qi on both) -- on a stock
# install it is only present if some unrelated app (a video editor,
# say) happened to pull it in. When it's missing, the ENTIRE
# Service.qml file fails to load, not just its video-specific code --
# confirmed directly against a throwaway QML file with an unresolvable
# import ("Did not load any objects, exiting."), which is standard QML
# behavior: a failed top-level import is fatal for the whole file, with
# no partial-load fallback. That takes video, gif, AND the static-
# background-switch safety net down together, since all three live in
# the same file behind the same import -- the IPC handler itself never
# comes into existence. WallpapersContent.qml's own picker marks a tile
# "current" the instant it's clicked (deliberately optimistic
# client-side UI, see that file's own comment on currentBackground),
# regardless of whether the service ever receives -- let alone acts on
# -- that click, which is exactly why the picker can look like it
# worked while the desktop itself never changes. Live-tested end to end
# on a machine that DOES have this package: video wallpaper works
# correctly (real ffmpeg-backed decode, layer surface renders), ruling
# out a Service.qml regression as the cause.
printf -- '-- Video/GIF wallpaper backend --\n'
if pacman -Qi qt6-multimedia >/dev/null 2>&1; then
  printf 'qt6-multimedia: installed\n'
  backend="none"
  pacman -Qi qt6-multimedia-ffmpeg >/dev/null 2>&1 && backend="qt6-multimedia-ffmpeg (hardware-accelerated)"
  [[ "$backend" == "none" ]] && pacman -Qi qt6-multimedia-gstreamer >/dev/null 2>&1 && backend="qt6-multimedia-gstreamer"
  printf 'backend: %s\n' "$backend"
  if [[ "$backend" == "none" ]]; then
    printf 'WARNING: qt6-multimedia is installed but no backend package was found -- should not be possible under normal pacman dependency resolution (qt6-multimedia depends on the virtual qt6-multimedia-backend), so something unusual happened here\n'
  fi
  if command -v omarchy-shell >/dev/null 2>&1 && status_json="$(OMARCHY_SHELL_IPC_TIMEOUT=1s omarchy-shell ruixen.wallpaper status 2>/dev/null)"; then
    # .active | tostring, not `.active // "?"` -- jq's // operator
    # treats a real `false` value as absent (same as null), which
    # silently printed "?" for the exact "not currently playing
    # anything" case this check exists to report correctly. Caught live
    # by actually running this against the real IPC while inactive, not
    # assumed.
    active="$(jq -r '.active | tostring' <<<"$status_json" 2>/dev/null || echo "?")"
    printf 'ruixen.wallpaper IPC: responding (currently active: %s)\n' "$active"
  else
    printf 'ruixen.wallpaper IPC: NOT responding -- unexpected given qt6-multimedia is present; try omarchy restart shell\n'
  fi
else
  printf 'qt6-multimedia: NOT INSTALLED -- this is almost certainly why video/gif wallpaper does not work here (not just video -- gif is affected too, for the same reason)\n'
  printf 'fix: pacman -S --needed qt6-multimedia-ffmpeg\n'
fi
printf '\n'

# --- Cava desktop visualizer -- same "many possible causes, tedious to
# untangle over chat" shape as the wallpaper section above, for a
# feature with its own distinct failure modes, none of which are a
# Service-file-wide crash this time (CavaFeed.qml has no risky
# top-level import like Service.qml's own QtMultimedia one -- it's
# plain QtQuick + Quickshell.Io, both guaranteed present). Instead:
# cava's own pipewire input is the only backend that works here
# (confirmed directly, see CavaFeed.qml's own comment -- the pulse
# backend can't connect even with pipewire-pulse up), the overlay
# deliberately goes invisible while any window is fullscreen
# (Overlay.qml's own fullscreenActive gate -- easy to mistake for "it's
# broken" if you're testing from inside a fullscreen video/game), and
# CavaFeed.qml already latches cavaAvailable false the instant a spawn
# confirms the binary is missing (its own exit code 42) rather than
# retrying forever. So "settings say enabled but nothing is showing"
# has several genuinely different honest explanations -- worth telling
# them apart here instead of guessing back and forth over chat.
printf -- '-- Cava desktop visualizer --\n'
if command -v cava >/dev/null 2>&1; then
  printf 'cava: installed\n'
else
  printf 'cava: NOT INSTALLED -- the overlay just stays flat/invisible by design, no error anywhere -- pacman -S cava\n'
fi
if pgrep -x pipewire >/dev/null 2>&1; then
  printf 'pipewire: running\n'
else
  printf 'pipewire: NOT RUNNING -- cava only has a pipewire input path here, no pulse fallback, so it would have nothing to analyze even with cava itself installed\n'
fi

cava_state="$state_dir/cava-visualizer.json"
if [[ -f "$cava_state" ]] && jq empty "$cava_state" >/dev/null 2>&1; then
  enabled="$(jq -r '.enabled | tostring' "$cava_state" 2>/dev/null || echo "?")"
  style="$(jq -r '.style // "?"' "$cava_state" 2>/dev/null || echo "?")"
  position="$(jq -r '.position // "?"' "$cava_state" 2>/dev/null || echo "?")"
  bands="$(jq -r '.bands // "?"' "$cava_state" 2>/dev/null || echo "?")"
  mirror="$(jq -r '.mirror | tostring' "$cava_state" 2>/dev/null || echo "?")"
  printf 'settings: enabled=%s style=%s position=%s bands=%s mirror=%s\n' "$enabled" "$style" "$position" "$bands" "$mirror"

  live_running=0
  pgrep -x cava >/dev/null 2>&1 && live_running=1
  if [[ "$enabled" == "true" && "$live_running" -eq 0 ]]; then
    printf 'MISMATCH: settings say enabled, but no cava process is running right now -- check the cava/pipewire lines above, or a fullscreen window may simply be active (the overlay intentionally hides for one, see the note below)\n'
  elif [[ "$enabled" == "false" && "$live_running" -eq 1 ]]; then
    printf 'NOTE: a cava process is running but settings say disabled -- likely mid-shutdown (Quickshell SIGTERMs it on toggle-off, briefly still exiting) or a leftover from a prior crash\n'
  fi
else
  printf 'settings: no state file found (visualizer never enabled here, or this predates the feature)\n'
fi

if command -v hyprctl >/dev/null 2>&1; then
  fullscreen="$(hyprctl activewindow -j 2>/dev/null | jq -r 'if .fullscreen and .fullscreen != 0 then "yes" else "no" end' 2>/dev/null || echo "?")"
  [[ "$fullscreen" == "yes" ]] && printf 'note: the active window is currently fullscreen -- the visualizer (and the notch itself) is DESIGNED to hide in this state, so "not showing" right now may be expected, not broken\n'
fi
printf '\n'

# --- This checkout ---------------------------------------------------
printf -- '-- This checkout --\n'
if [[ -d "$script_dir/.git" ]]; then
  branch="$(git -C "$script_dir" rev-parse --abbrev-ref HEAD 2>/dev/null || echo unknown)"
  commit="$(git -C "$script_dir" rev-parse --short HEAD 2>/dev/null || echo unknown)"
  commit_date="$(git -C "$script_dir" log -1 --format=%cd --date=relative 2>/dev/null || echo unknown)"
  printf 'branch: %s\n' "$branch"
  printf 'commit: %s (%s)\n' "$commit" "$commit_date"

  if [[ -n "$(git -C "$script_dir" status --porcelain 2>/dev/null)" ]]; then
    dirty_count="$(git -C "$script_dir" status --porcelain 2>/dev/null | wc -l | tr -d ' ')"
    printf 'local changes: yes (%s file(s) modified -- update.sh will refuse to run until this is clean)\n' "$dirty_count"
  else
    printf 'local changes: none\n'
  fi

  # A REAL fetch, not --dry-run -- direct correction after --dry-run
  # was found to never refresh the local origin/<branch> tracking ref
  # at all, so this comparison could silently run against whatever
  # that ref last happened to be (potentially from days ago), reporting
  # "up to date" based on stale information rather than the actual
  # current state of the remote. This is the one check in the whole
  # report that reaches the network -- everything else is local-only.
  if git -C "$script_dir" fetch --quiet origin "$branch" >/dev/null 2>&1; then
    ahead_behind="$(git -C "$script_dir" rev-list --left-right --count HEAD...origin/"$branch" 2>/dev/null || echo "? ?")"
    ahead="$(awk '{print $1}' <<<"$ahead_behind")"
    behind="$(awk '{print $2}' <<<"$ahead_behind")"
    if [[ "$behind" == "0" ]]; then
      printf 'vs origin/%s: up to date (just fetched)\n' "$branch"
    else
      printf 'vs origin/%s: %s commit(s) behind -- run git pull, or ./update.sh\n' "$branch" "$behind"
    fi
    [[ "$ahead" != "0" ]] && printf 'vs origin/%s: %s local commit(s) not on origin\n' "$branch" "$ahead"
  else
    printf 'vs origin: could not reach remote (offline?) -- this check needs real network access, everything else in this report is local-only\n'
  fi
else
  printf 'not a git checkout -- update.sh and this doctor script both need one\n'
fi

recorded_path="$(cat "$state_dir/repo-path" 2>/dev/null || echo "")"
if [[ -z "$recorded_path" ]]; then
  printf 'last successful install ran from: no record found (install.sh predates this, or never completed)\n'
elif [[ "$recorded_path" == "$script_dir" ]]; then
  printf 'last successful install ran from: this same checkout\n'
else
  printf 'last successful install ran from: a DIFFERENT checkout than this one -- you may have more than one ruixen-shell folder on disk\n'
fi
printf '\n'

# --- Deployed plugin FILES vs this checkout own source ---------------
# Direct correction after a real report proved this wrong: comparing
# manifest.json "version" strings looked reassuring ("all OK") while
# the actual deployed Bar.qml was hours of commits behind, because
# most plugin edits that whole night never bumped that version field
# at all -- a version match said nothing real about whether the file
# CONTENT matched. This hashes every real file in each plugin
# directory instead (recursive, sorted so enumeration order never
# matters, manifest.json included) -- a single changed byte anywhere,
# bumped version or not, shows up here.
dir_hash() {
  local dir="$1"
  [[ -d "$dir" ]] || { echo "(missing)"; return; }
  # cd into the directory first, not `find "$dir"` -- sha256sum's own
  # output includes the path it hashed, and source/deployed live at
  # two different absolute locations by design. Hashing absolute paths
  # would make every single plugin report a false mismatch regardless
  # of content (caught live: it did, for all fifteen, before this fix).
  # Relative paths from inside each tree are identical when the
  # content and structure actually match.
  (cd "$dir" && find . -type f -print0 | sort -z | xargs -0 sha256sum 2>/dev/null) | sha256sum | awk '{print $1}'
}
printf -- '-- Plugin files (source in this checkout vs deployed, by content hash) --\n'
mismatch_count=0
for dir in "${plugin_source_dirs[@]}"; do
  [[ -d "$dir" ]] || continue
  id="$(basename "$dir")"
  source_version="$(jq -r '.version // "?"' "$dir/manifest.json" 2>/dev/null || echo "?")"

  if [[ ! -e "$plugins_dir/$id" ]]; then
    printf '%-24s v%-8s deployed MISSING (never installed here)\n' "$id" "$source_version"
    mismatch_count=$((mismatch_count + 1))
  else
    source_hash="$(dir_hash "$dir")"
    deployed_hash="$(dir_hash "$plugins_dir/$id")"
    if [[ "$source_hash" == "$deployed_hash" ]]; then
      printf '%-24s v%-8s -- OK, file contents match exactly\n' "$id" "$source_version"
    else
      printf '%-24s v%-8s -- CONTENT MISMATCH (deployed files differ from this checkout, regardless of version number -- install.sh did not update this one)\n' "$id" "$source_version"
      mismatch_count=$((mismatch_count + 1))
    fi
  fi
done
if [[ "$mismatch_count" -eq 0 ]]; then
  printf '(every plugin file exactly matches this checkout own source)\n'
fi
printf '\n'

# --- Hyprland look'n'feel FILES vs this checkout own source -----------
# Same real gap the plugin-files section above was built to catch, for
# a completely separate deploy path: hyprland/*.lua ships via
# ruixen-lookfeel.sh/install.sh into
# ~/.local/share/ruixen-shell/hyprland/, never through plugins_dir --
# nothing in the section above would ever flag this directory as stale,
# even though a shared value living here (gaps_out, border_size, an
# animation curve) silently not reaching a real machine looks
# identical to a real bug from the outside ("it works here, not on his
# machine"). This at least rules staleness in or out directly instead
# of guessing.
#
# *.lua only, not a plain dir_hash() of the whole directory -- this
# folder also holds ruixen-lookfeel.sh itself (a helper meant to be run
# FROM the checkout, never copied to the deployed directory at all, see
# its own comment), which would otherwise permanently read as a false
# "mismatch" for every single install regardless of the real .lua
# content, defeating the whole point of this check. Caught live on
# this exact machine before it shipped: the very first real run of this
# new section reported a mismatch that turned out to be exactly this.
lua_dir_hash() {
  local dir="$1"
  [[ -d "$dir" ]] || { echo "(missing)"; return; }
  (cd "$dir" && find . -maxdepth 1 -type f -name '*.lua' -print0 | sort -z | xargs -0 sha256sum 2>/dev/null) | sha256sum | awk '{print $1}'
}
looknfeel_dir="$HOME/.local/share/ruixen-shell/hyprland"
printf -- '-- Hyprland look'"'"'n'"'"'feel files (source in this checkout vs deployed, by content hash) --\n'
if [[ -d "$script_dir/hyprland" ]]; then
  looknfeel_source_hash="$(lua_dir_hash "$script_dir/hyprland")"
  looknfeel_deployed_hash="$(lua_dir_hash "$looknfeel_dir")"
  if [[ "$looknfeel_deployed_hash" == "(missing)" ]]; then
    printf 'hyprland/*.lua deployed MISSING (never installed here)\n'
  elif [[ "$looknfeel_source_hash" == "$looknfeel_deployed_hash" ]]; then
    printf 'hyprland/*.lua -- OK, file contents match exactly\n'
  else
    printf 'hyprland/*.lua -- CONTENT MISMATCH (deployed files differ from this checkout -- install.sh/ruixen-lookfeel.sh did not update this)\n'
  fi
else
  printf '(this checkout has no hyprland/ directory)\n'
fi

# Informational, not a pass/fail -- confirms which of the three
# variants (ruixen.lua "Rounded", square.lua "Sharp", default.lua
# "Off") is actually active, independent of whether its own file
# content is current.
active_looknfeel_target="$(readlink "$HOME/.config/hypr/looknfeel.lua" 2>/dev/null || echo "")"
if [[ -z "$active_looknfeel_target" ]]; then
  printf 'active variant: no symlink found at ~/.config/hypr/looknfeel.lua\n'
else
  printf 'active variant: %s\n' "$(basename "$active_looknfeel_target")"
fi
printf '\n'

# --- Backups -- presence proves whether install.sh own copy step ever
# ran for a given plugin at all, regardless of what version it left
# behind. -----------------------------------------------------------
printf -- '-- Plugin backups (proves whether a reinstall/update actually touched each one) --\n'
any_backup=0
for dir in "${plugin_source_dirs[@]}"; do
  [[ -d "$dir" ]] || continue
  id="$(basename "$dir")"
  count=0
  newest=""
  for b in "$plugins_dir"/."$id".bak.*; do
    [[ -e "$b" ]] || continue
    count=$((count + 1))
    [[ -z "$newest" || "$b" -nt "$newest" ]] && newest="$b"
  done
  if [[ "$count" -gt 0 ]]; then
    any_backup=1
    age_seconds=$(( $(date +%s) - $(stat -c %Y "$newest" 2>/dev/null || echo 0) ))
    printf '%-24s %s backup(s), most recent %s ago\n' "$id" "$count" "$(human_ago "$age_seconds")"
  fi
done
[[ "$any_backup" -eq 0 ]] && printf '(no backups found for any ruixen.* plugin -- install.sh has never replaced an existing copy of any of them)\n'
printf '\n'

# --- Bar layout shape -- ids only, never inline settings values, so
# nothing personal (a custom clock format, a hidden app list) ever
# prints here. -------------------------------------------------------
printf -- '-- Bar layout (ids only) --\n'
shell_json="$HOME/.config/omarchy/shell.json"
if [[ -f "$shell_json" ]] && jq empty "$shell_json" >/dev/null 2>&1; then
  bar_id="$(jq -r '.bar.id // "(none set -- stock Omarchy default)"' "$shell_json")"
  printf 'active bar: %s\n' "$bar_id"
  if [[ "$bar_id" == "ruixen.bar" ]]; then
    printf 'docked: %s\n' "$(jq -r '.bar.docked // false' "$shell_json")"
    for section in left center right; do
      ids="$(jq -r --arg s "$section" '(.bar.layout[$s] // []) | map(.id) | join(", ")' "$shell_json")"
      printf '%-7s [%s]\n' "$section:" "$ids"
    done
  fi
else
  printf 'shell.json missing or not valid JSON\n'
fi
printf '\n'

# --- Runtime health ---------------------------------------------------
printf -- '-- Runtime --\n'
qs_count="$(pgrep -c -f '^quickshell -n' 2>/dev/null || echo 0)"
printf 'quickshell processes running: %s%s\n' "$qs_count" "$( [[ "$qs_count" -gt 1 ]] && echo ' (expected 1 -- an old instance may be stuck)' )"
if command -v omarchy-shell >/dev/null 2>&1 && OMARCHY_SHELL_IPC_TIMEOUT=1s omarchy-shell shell ping >/dev/null 2>&1; then
  printf 'shell IPC: responding\n'
else
  printf 'shell IPC: NOT responding -- try omarchy restart shell\n'
fi

printf '\n=== end of report -- safe to paste, contains no paths, hostnames, or personal config values ===\n'
