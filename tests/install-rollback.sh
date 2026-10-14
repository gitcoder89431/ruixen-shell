#!/usr/bin/env bash
# Covers "[P1] Make install/update transactional with validation and
# rollback": runs the REAL install.sh against a throwaway fake $HOME
# with the omarchy/hyprctl stubs from fixtures/fake-bin/, proving the
# rollback mechanism actually restores prior state on failure -- not
# just reasoning about the code. Two distinct failure points, per the
# issue's own acceptance criteria ("Automated tests simulate at least
# two failure points"):
#   1. A plugin validation failure aborts before ANY plugin is
#      deployed (already covered at a lighter level by
#      install-lifecycle.sh; reinforced here with a stronger
#      "plugins dir has nothing new in it at all" assertion).
#   2. A failure at the LAST step that is still safely reversible
#      ([6/7] theme overlays), forced by making the already-deployed
#      per-theme data directory under ~/.local/share/ruixen-shell/
#      theme-overlays/ read-only -- by that point plugins, shell.json,
#      AND looknfeel.lua have all genuinely been touched,
#      so this is the real end-to-end proof that rollback_all() puts
#      all three back exactly as they were. Deliberately NOT forced via
#      FAKE_OMARCHY_FAIL_RESTART (omarchy restart shell) any more: a
#      forced restart failure used to abort install.sh here too, but
#      direct report ("omarchy restart shell had to be manually pressed
#      to get the reloaded update") traced that to install.sh treating
#      omarchy-restart-shell's own short readiness-poll timeout as fatal
#      -- by the time THAT command returns at all, the old shell is
#      already killed and the new one already dispatched, so rolling
#      the just-deployed plugin files back out from under it was actively
#      making the symptom worse, not recovering from a real failure.
#      install.sh now tolerates that one command failing (with a retry);
#      see tests/install-restart-detached-tail.sh for that contract.
#
# Also covers "[P1] Make repo-path state part of the successful install
# transaction" (#14), reusing these exact same two failure points plus
# a genuine second-checkout success case: a failed install run from a
# DIFFERENT checkout than the one currently installed must never move
# repo-path onto the failed checkout, and a SUCCESSFUL install from a
# different checkout must.
#
# Also covers "[P1] Roll back deployed Hyprland assets when install/
# update fails" (#20), the same way -- reuses failure point 2's already-
# working baseline + checkout_b failing run (checkout_b's own
# looknfeel.*.lua content is mutated first, so a real content
# difference proves rollback restored the OLD deployed asset rather
# than coincidentally matching), plus a dedicated first-install-failure
# case for #20's other acceptance criterion (nothing left behind when
# there was no prior deployed asset to roll back to in the first
# place).
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'install-rollback: jq is required (command "jq" not found)\n' >&2
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
cleanup() { rm -rf "${homes[@]}" "${checkout_b:-}"; }
trap cleanup EXIT

# A second, distinct checkout -- a plain copy of this repo at a
# different path -- so repo-path tests can tell "still pointing at the
# checkout that was actually installed" apart from "happens to be the
# same path either way" (#14).
checkout_b="$(mktemp -d)"
cp -r "$repo_dir"/. "$checkout_b"/

# --- Failure point 1: validation failure touches nothing at all ----
home1="$(mktemp -d)"
homes+=("$home1")

# A prior working install's repo-path, from a checkout other than
# repo_dir -- this run's failure must leave it exactly as-is (#14).
mkdir -p "$home1/.local/state/ruixen"
printf '%s\n' "/prior/working/checkout" > "$home1/.local/state/ruixen/repo-path"

if ( HOME="$home1" PATH="$fake_bin:$PATH" FAKE_OMARCHY_FAIL_VALIDATE_FOR="ruixen.weather" "$repo_dir/install.sh" ) \
  >"$home1/install.out" 2>&1; then
  status1=0
else
  status1=$?
fi
if [[ "$status1" -eq 0 ]]; then
  printf 'FAIL - a failing plugin validation should abort install.sh\n'
  fail_count=$((fail_count + 1))
else
  printf 'ok   - failing plugin validation aborts install.sh (exit non-zero)\n'
  pass=$((pass + 1))
fi
check "validation failure: shell.json was never written" \
  "$([[ -e "$home1/.config/omarchy/shell.json" ]] && echo exists || echo absent)" "absent"
check "validation failure: no plugin directory was created at all" \
  "$([[ -d "$home1/.config/omarchy/plugins" ]] && find "$home1/.config/omarchy/plugins" -mindepth 1 -maxdepth 1 | wc -l || echo 0)" "0"
check "validation failure: looknfeel.lua was never touched" \
  "$([[ -e "$home1/.config/hypr/looknfeel.lua" ]] && echo exists || echo absent)" "absent"
check "validation failure: repo-path still points at the previously working checkout (#14)" \
  "$(cat "$home1/.local/state/ruixen/repo-path")" "/prior/working/checkout"

# --- Failure point 2: a later-step failure rolls back everything ---
# already touched this run -- plugins, shell.json, AND looknfeel.
home2="$(mktemp -d)"
homes+=("$home2")

# Establish a genuinely working baseline first (a real successful
# install), so the second, failing run has real prior state to roll
# back TO, not just "nothing existed."
if ( HOME="$home2" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) >"$home2/install-1.out" 2>&1; then
  baseline_status=0
else
  baseline_status=$?
fi
if [[ "$baseline_status" -ne 0 ]]; then
  printf 'FAIL - baseline install for rollback test itself failed, cannot continue this case\n'
  cat "$home2/install-1.out" >&2
  fail_count=$((fail_count + 1))
else
  # Distinguishing markers the SUCCESS path would never produce, so a
  # later assertion that they're back proves real restoration
  # happened, not just "nothing needed to change."
  marker="$home2/.config/omarchy/plugins/ruixen.notch/ROLLBACK_MARKER.txt"
  printf 'pre-existing content that must survive a rolled-back reinstall\n' > "$marker"

  dummy_looknfeel_target="$home2/dummy-dotfiles-looknfeel.lua"
  printf 'a symlink target install.sh must restore exactly\n' > "$dummy_looknfeel_target"
  rm -f "$home2/.config/hypr/looknfeel.lua"
  ln -s "$dummy_looknfeel_target" "$home2/.config/hypr/looknfeel.lua"

  before_shell_json="$(jq -S . "$home2/.config/omarchy/shell.json")"

  # Deployed stable looknfeel assets from the baseline install above --
  # "asset A" (#20). Captured before checkout_b's content is mutated
  # below, so the later assertion proves rollback restored THIS exact
  # content, not just "some file exists there."
  looknfeel_data_dir="$home2/.local/share/ruixen-shell/hyprland"
  asset_a_ruixen="$(cat "$looknfeel_data_dir/looknfeel.ruixen.lua")"
  asset_a_default="$(cat "$looknfeel_data_dir/looknfeel.default.lua")"

  # checkout_b's own looknfeel files are mutated here ("asset B") --
  # this is the throwaway copy, safe to change. A real content
  # difference from asset A is what makes the rollback assertion below
  # actually prove something, rather than passing coincidentally
  # because both checkouts started out byte-identical.
  printf '\n-- asset B marker, checkout_b only --\n' >> "$checkout_b/hyprland/looknfeel.ruixen.lua"
  printf '\n-- asset B marker, checkout_b only --\n' >> "$checkout_b/hyprland/looknfeel.default.lua"

  # Forces [6/7] (theme overlays) to fail for real: the baseline install
  # above already deployed every theme overlay's DATA directory under
  # ~/.local/share/ruixen-shell/theme-overlays/<theme>/, so locking each
  # one means this run's own mktemp (writing the freshly redeployed
  # copy there, before anything touches the ~/.config/omarchy/themes/
  # symlink side at all) genuinely cannot create its temp file -- a
  # real permission failure, not a simulated one. Locking the DATA side
  # specifically (not the ~/.config/omarchy/themes symlink side) matters
  # here: that failure happens BEFORE this theme's key is ever recorded
  # into THEME_OVERLAY_TOUCHED_KEYS, so rollback_theme_overlays never
  # tries to touch this same now-locked directory during cleanup --
  # locking the symlink side instead was tried first and made the
  # RECOVERY's own `rm -f`/`ln -sf` on that identical entry fail too,
  # which (from inside the ERR trap itself) aborted rollback_all()
  # partway through, before it ever got to plugins/looknfeel. This
  # failure point runs strictly AFTER plugins, shell.json, and
  # looknfeel.lua (both the symlink and its deployed data) have already
  # succeeded this run -- exactly the "everything that matters has been
  # touched, then a real late failure" shape this test needs, with no
  # production-code fault hook required.
  for theme_data_dir in "$home2/.local/share/ruixen-shell/theme-overlays"/*/; do
    chmod 555 "$theme_data_dir"
  done

  # The failing second run comes from checkout_b, a DIFFERENT checkout
  # than the baseline install above (repo_dir) -- proves repo-path
  # isn't just coincidentally the same value before and after (#14).
  if ( HOME="$home2" PATH="$fake_bin:$PATH" "$checkout_b/install.sh" ) \
    >"$home2/install-2.out" 2>&1; then
    status2=0
  else
    status2=$?
  fi
  for theme_data_dir in "$home2/.local/share/ruixen-shell/theme-overlays"/*/; do
    chmod 755 "$theme_data_dir"
  done
  if [[ "$status2" -eq 0 ]]; then
    printf 'FAIL - a forced late failure should abort install.sh\n'
    fail_count=$((fail_count + 1))
  else
    printf 'ok   - forced late failure aborts install.sh (exit non-zero)\n'
    pass=$((pass + 1))
  fi

  check "rollback: plugin directory (marker included) was restored from its backup" \
    "$([[ -f "$marker" ]] && cat "$marker")" "pre-existing content that must survive a rolled-back reinstall"
  check "rollback: looknfeel.lua symlink was restored to its exact pre-run target" \
    "$(readlink "$home2/.config/hypr/looknfeel.lua")" "$dummy_looknfeel_target"
  check "rollback: shell.json is byte-for-byte unchanged from right before this run" \
    "$(jq -S . "$home2/.config/omarchy/shell.json")" "$before_shell_json"
  check "rollback: this run's own plugin backup was consumed, not left behind" \
    "$(find "$home2/.local/state/ruixen/backups/plugins" -maxdepth 1 -iname 'ruixen.notch.bak.*' 2>/dev/null | wc -l)" "0"
  check "rollback: repo-path still points at the working checkout (repo_dir), not the failed checkout_b (#14)" \
    "$(cat "$home2/.local/state/ruixen/repo-path")" "$repo_dir"
  check "rollback: deployed looknfeel.ruixen.lua is asset A again, not checkout_b's asset B (#20)" \
    "$(cat "$looknfeel_data_dir/looknfeel.ruixen.lua")" "$asset_a_ruixen"
  check "rollback: deployed looknfeel.default.lua is asset A again, not checkout_b's asset B (#20)" \
    "$(cat "$looknfeel_data_dir/looknfeel.default.lua")" "$asset_a_default"
  check "rollback: this run's own looknfeel-data backup was consumed, not left behind" \
    "$(find "$home2/.local/state/ruixen/backups/looknfeel-data" -maxdepth 1 -iname 'looknfeel.ruixen.lua.bak.*' 2>/dev/null | wc -l)" "0"
fi

# --- Case 2b: a first-install failure leaves NO stable looknfeel
# assets behind (#20's other acceptance criterion -- nothing existed
# before, so rollback must remove what THIS run created, not "restore"
# something that never had a prior version). Fresh $HOME, no baseline,
# forced failure at the same late-but-still-reversible step as above. -
home2b="$(mktemp -d)"
homes+=("$home2b")
# All three of theme overlays' own target roots are pre-created and
# locked (not just the symlink side) -- [6/7]'s own `mkdir -p "$data_dir"
# "$config_dir" "$backup_dir"` is one call with three arguments, and a
# plain mkdir keeps trying the later arguments even after an earlier one
# fails, so locking only one of the three still lets the OTHER two get
# created for real -- empty, genuinely orphaned, since nothing records
# them as touched when the step fails before that point. Locking all
# three up front means none of them are ever created at all.
#
# One side effect worth calling out: pre-creating
# ~/.local/share/ruixen-shell/theme-overlays here makes the PARENT
# ~/.local/share/ruixen-shell look pre-existing to looknfeel's own
# [5/7] check (LOOKNFEEL_DATA_ROOT_PREEXISTED), which runs earlier in
# the SAME install and shares that exact root -- so looknfeel's own
# rollback correctly (by its own rule: never rmdir a root this run did
# not create) leaves that shared root in place. That is a real, narrow,
# pre-existing gap in rollback_theme_overlays' own cleanup for a
# partially-successful multi-arg mkdir -p -- unrelated to today's
# actual fix (the restart-shell tolerance + rollback_all re-entrancy
# guard above) and not something this case was ever meant to exercise,
# so the assertion below checks looknfeel's OWN files specifically
# rather than the whole shared root.
mkdir -p "$home2b/.config/omarchy/themes" \
  "$home2b/.local/share/ruixen-shell/theme-overlays" \
  "$home2b/.local/state/ruixen/backups/theme-overlays"
chmod 555 "$home2b/.config/omarchy/themes" \
  "$home2b/.local/share/ruixen-shell/theme-overlays" \
  "$home2b/.local/state/ruixen/backups/theme-overlays"
if ( HOME="$home2b" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) \
  >"$home2b/install.out" 2>&1; then
  status2b=0
else
  status2b=$?
fi
chmod 755 "$home2b/.config/omarchy/themes" \
  "$home2b/.local/share/ruixen-shell/theme-overlays" \
  "$home2b/.local/state/ruixen/backups/theme-overlays" 2>/dev/null || true
check "first-install failure: exits non-zero" "$([[ "$status2b" -ne 0 ]] && echo yes)" "yes"
# Checks looknfeel's own deployed asset files specifically, not the
# whole shared ~/.local/share/ruixen-shell root -- see this case's own
# comment above for why asserting the whole root would actually be
# pinning an unrelated, pre-existing gap in theme-overlays' cleanup
# instead of what this case is meant to cover.
check "first-install failure: no stable looknfeel data assets left behind (#20)" \
  "$([[ -e "$home2b/.local/share/ruixen-shell/hyprland/looknfeel.ruixen.lua" ]] && echo present || echo absent)" "absent"

# --- Case 3: a SUCCESSFUL install from a different checkout DOES
# update repo-path -- the other half of #14's acceptance criteria, that
# this isn't just "repo-path never changes again after the first
# install." Reuses home2's already-working baseline (repo_dir) from
# above; this run succeeds normally (no FAKE_OMARCHY_FAIL_* set).
if [[ "$baseline_status" -eq 0 ]]; then
  if ( HOME="$home2" PATH="$fake_bin:$PATH" "$checkout_b/install.sh" ) >"$home2/install-3.out" 2>&1; then
    status3=0
  else
    status3=$?
    cat "$home2/install-3.out" >&2
  fi
  check "successful install from a new checkout: exits 0" "$status3" "0"
  check "successful install from a new checkout: repo-path updates to checkout_b (#14)" \
    "$(cat "$home2/.local/state/ruixen/repo-path")" "$checkout_b"
  # A successful install/update still refreshes both deployed assets
  # (#20's other acceptance criterion) -- checkout_b's own files were
  # mutated with an "asset B" marker earlier in this file, so this
  # confirms the deployed copy now reflects that, not the stale asset A
  # this same $HOME had from its earlier baseline install.
  check "successful install from a new checkout: deployed looknfeel.ruixen.lua refreshed to checkout_b's content (#20)" \
    "$(cat "$looknfeel_data_dir/looknfeel.ruixen.lua")" "$(cat "$checkout_b/hyprland/looknfeel.ruixen.lua")"
  check "successful install from a new checkout: deployed looknfeel.default.lua refreshed to checkout_b's content (#20)" \
    "$(cat "$looknfeel_data_dir/looknfeel.default.lua")" "$(cat "$checkout_b/hyprland/looknfeel.default.lua")"
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
