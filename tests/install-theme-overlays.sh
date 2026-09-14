#!/usr/bin/env bash
# Covers wiring theme-overlays/<name>/* into install.sh -- direct real-
# world report: a separate install of this repo showed generic "unknown
# app" box icons for third-party apps in the launcher/pinned-apps on
# the White theme ("his icons... show up as square unknown boxes"),
# because the fix for that (theme-overlays/white/icons.theme,
# shell.toml) only ever existed as a manual symlink on the dev machine
# that diagnosed it -- nothing in install.sh/update.sh actually
# deployed it for anyone else. This proves the deploy step itself,
# using the REAL install.sh against a throwaway fake $HOME with the
# omarchy/hyprctl stubs from fixtures/fake-bin/, not just reasoning
# about the code:
#   1. A fresh install deploys every theme-overlays/<name>/<file> to a
#      stable path and symlinks it into
#      ~/.config/omarchy/themes/<name>/, same deploy-then-link shape
#      looknfeel.lua already uses (#15) and for the same reason --
#      moving/deleting the checkout later can't break the symlink.
#   2. The currently-active theme (matched via
#      ~/.local/state/omarchy/current/theme.name) gets re-applied live
#      so a fix like this takes effect immediately, not just next time
#      the user happens to switch themes away and back.
#   3. A user's own real (non-Ruixen) file at the same config path is
#      backed up, never silently clobbered, and restored correctly on
#      rollback.
#   4. A SECOND run (this run's own symlink already in place, so no
#      backup was taken) that fails later still leaves the symlink
#      correctly restored on rollback, not deleted -- the specific gap
#      a first pass at this rollback function missed (see
#      rollback_theme_overlays's own comment on
#      THEME_OVERLAY_CONFIG_PREEXISTED_AS_OURS).
#   5. A fresh machine with no theme.name at all (never selected a
#      theme) still deploys without erroring on the "re-apply live"
#      step.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'install-theme-overlays: jq is required (command "jq" not found)\n' >&2
  exit 1
}

[[ -d "$repo_dir/theme-overlays/white" ]] || {
  printf 'install-theme-overlays: expected fixture theme-overlays/white/ not found in this checkout\n' >&2
  exit 1
}

pass=0
fail_count=0
check() {
  local desc="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    printf 'ok   - %s\n' "$desc"
    pass=$((pass + 1))
  else
    printf 'FAIL - %s\n       got:  %s\n       want: %s\n' "$desc" "$got" "$want"
    fail_count=$((fail_count + 1))
  fi
}

homes=()
cleanup() { rm -rf "${homes[@]}"; }
trap cleanup EXIT

set_active_theme() {
  mkdir -p "$1/.local/state/omarchy/current"
  printf '%s\n' "$2" > "$1/.local/state/omarchy/current/theme.name"
}

run_install() {
  local home="$1"
  shift
  # `env NAME=val...` here, not a bare "${@:2}" prefix -- a NAME=val
  # word only gets parsed as an environment assignment by bash at
  # PARSE time, before any expansion; substituting one in through an
  # array/"$@" produces a plain word bash tries to run as a command
  # instead (confirmed live: "FAKE_OMARCHY_FAIL_RESTART=1: command not
  # found", silently exit-127ing before install.sh ever ran -- every
  # assertion after that point was trivially "passing" against
  # whatever state already existed, not proving rollback did anything).
  ( HOME="$home" PATH="$fake_bin:$PATH" env "$@" "$repo_dir/install.sh" )
}

# --- Case 1: fresh install, White theme active -------------------------
home1="$(mktemp -d)"
homes+=("$home1")
set_active_theme "$home1" white

out1="$(run_install "$home1" 2>&1)"
exit1=$?
check "fresh install: exits 0" "$exit1" "0"
check "fresh install: reports the overlay as applied" \
  "$(grep -c '^  applied: white$' <<<"$out1")" "1"
check "fresh install: reports the active theme re-applied live" \
  "$(grep -c 're-applied the active theme (white)' <<<"$out1")" "1"

# The re-apply step is best-effort, not `... && printf ...` (the exact
# bare-compound-statement bug this project already hit once in
# prune-poster-cache.sh) -- a failing `omarchy theme set` must still
# let the REST of the install succeed, just skip the "immediately"
# nicety, not abort/roll back the whole run.
home1c="$(mktemp -d)"
homes+=("$home1c")
set_active_theme "$home1c" white
out1c="$(run_install "$home1c" FAKE_OMARCHY_FAIL_THEME_SET=white 2>&1)"
exit1c=$?
check "'theme set' failing live: install still exits 0 (not aborted)" "$exit1c" "0"
check "'theme set' failing live: reports the graceful fallback message" \
  "$(grep -c 'could not re-apply the active theme (white) live' <<<"$out1c")" "1"
check "'theme set' failing live: the overlay itself was still deployed" \
  "$([[ -L "$home1c/.config/omarchy/themes/white/shell.toml" ]] && echo yes || echo no)" "yes"

for f in shell.toml icons.theme; do
  data_target="$home1/.local/share/ruixen-shell/theme-overlays/white/$f"
  config_target="$home1/.config/omarchy/themes/white/$f"
  check "fresh install: $f deployed to the stable data path" \
    "$([[ -f "$data_target" ]] && echo yes || echo no)" "yes"
  check "fresh install: $f content matches this checkout's source" \
    "$(cmp -s "$data_target" "$repo_dir/theme-overlays/white/$f" && echo same || echo different)" "same"
  check "fresh install: config target is a symlink to the stable data path" \
    "$(readlink "$config_target" 2>/dev/null || echo '(missing)')" "$data_target"
done

# --- Case 2: no theme-overlays regression on a NON-overlaid theme ------
home2="$(mktemp -d)"
homes+=("$home2")
set_active_theme "$home2" gruvbox

out2="$(run_install "$home2" 2>&1)"
check "non-overlaid active theme: install still exits 0" "$?" "0"
check "non-overlaid active theme: white overlay still deployed (independent of what's active)" \
  "$([[ -L "$home2/.config/omarchy/themes/white/shell.toml" ]] && echo yes || echo no)" "yes"
check "non-overlaid active theme: no 're-applied live' claim for a theme with no overlay" \
  "$(grep -c 're-applied the active theme' <<<"$out2")" "0"

# --- Case 3: fresh machine, no theme.name file at all ------------------
home3="$(mktemp -d)"
homes+=("$home3")

out3="$(run_install "$home3" 2>&1)"
check "no active theme recorded at all: install still exits 0" "$?" "0"
check "no active theme recorded at all: overlay still deployed" \
  "$([[ -L "$home3/.config/omarchy/themes/white/shell.toml" ]] && echo yes || echo no)" "yes"

# --- Case 4a: a user's own real file gets backed up, not discarded ----
home4a="$(mktemp -d)"
homes+=("$home4a")
mkdir -p "$home4a/.config/omarchy/themes/white"
printf '# my own custom shell.toml\n' > "$home4a/.config/omarchy/themes/white/shell.toml"

run_install "$home4a" >/dev/null 2>&1
check "user's own file: replaced with our symlink" \
  "$([[ -L "$home4a/.config/omarchy/themes/white/shell.toml" ]] && echo yes || echo no)" "yes"
backup4a="$(compgen -G "$home4a/.local/state/ruixen/backups/theme-overlays/white/shell.toml.config.bak.*" | head -1)"
check "user's own file: backed up, not discarded" \
  "$([[ -n "$backup4a" && -f "$backup4a" ]] && echo yes || echo no)" "yes"
check "user's own file: backup content matches the original" \
  "$(grep -c 'my own custom shell.toml' "$backup4a" 2>/dev/null || echo 0)" "1"

# --- Case 4b: a SINGLE run's own rollback restores that same file -----
# Deliberately a fresh $HOME, not a second run against 4a's -- a later
# run's rollback only ever undoes THAT run's own changes, never a
# PRIOR run's already-committed success (4a's own symlink, once
# installed, is the new legitimate state -- correctly proven by case 5
# below, not a bug to route around here). This isolates "does one run
# back up and restore the file it itself just touched."
home4b="$(mktemp -d)"
homes+=("$home4b")
mkdir -p "$home4b/.config/omarchy/themes/white"
printf '# my own custom shell.toml\n' > "$home4b/.config/omarchy/themes/white/shell.toml"

run_install "$home4b" FAKE_OMARCHY_FAIL_RESTART=1 >/dev/null 2>&1 || true
check "user's own file: a failing run's rollback restores the real file (not our symlink)" \
  "$([[ -L "$home4b/.config/omarchy/themes/white/shell.toml" ]] && echo symlink || echo realfile)" "realfile"
check "user's own file: a failing run's rollback restores its exact original content" \
  "$(cat "$home4b/.config/omarchy/themes/white/shell.toml")" "# my own custom shell.toml"

# --- Case 5: second run's own symlink survives a later rollback --------
# The tricky one: run 1 deploys our symlink normally (no backup taken,
# since nothing else was there). Run 2 finds that same symlink already
# in place (still no backup -- it's already ours), then fails later.
# Naively, rollback would restore the stable data copy but delete the
# now-orphaned symlink pointing to it, leaving the theme with NO
# overlay at all -- worse than before run 2 started.
home5="$(mktemp -d)"
homes+=("$home5")
set_active_theme "$home5" white

run_install "$home5" >/dev/null 2>&1
check "second-run setup: run 1 succeeded" "$?" "0"
data_before="$(readlink "$home5/.config/omarchy/themes/white/shell.toml")"

run_install "$home5" FAKE_OMARCHY_FAIL_RESTART=1 >/dev/null 2>&1 || true
check "already-ours symlink: still present after a later rollback" \
  "$([[ -L "$home5/.config/omarchy/themes/white/shell.toml" ]] && echo yes || echo no)" "yes"
check "already-ours symlink: points at the (restored) stable data path again" \
  "$(readlink "$home5/.config/omarchy/themes/white/shell.toml" 2>/dev/null)" "$data_before"
check "already-ours symlink: restored data content still matches this checkout" \
  "$(cmp -s "$data_before" "$repo_dir/theme-overlays/white/shell.toml" && echo same || echo different)" "same"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
