#!/usr/bin/env bash
# Covers the acceptance criteria of "[P0] Preserve existing shell.json
# instead of replacing the entire user config": exercises
# lib/build-shell-json.sh directly with synthetic shell.json fixtures.
# No fake $HOME needed -- that script is a pure stdin -> stdout
# function with no filesystem/omarchy dependency of its own, so these
# are plain input/output assertions. Run directly: ./tests/shell-json-merge.sh
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
build="$script_dir/../lib/build-shell-json.sh"

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

# --- Case 1: no existing config at all -----------------------------
out1="$(printf '{}' | "$build")"
check "no existing config: bar.id is ruixen.bar" \
  "$(jq -r '.bar.id' <<<"$out1")" "ruixen.bar"
check "no existing config: plugins has exactly the 5 ruixen ids" \
  "$(jq -c '[.plugins[].id] | sort' <<<"$out1")" \
  '["ruixen.frame-widget","ruixen.media","ruixen.notch","ruixen.settings","ruixen.wallpaper"]'
check "no existing config: default idle applied" \
  "$(jq -c '.idle' <<<"$out1")" '{"lock":300,"screensaver":150}'

# --- Case 2: customized config -- the actual regression this issue is about
customized='{
  "version": 1,
  "some_future_top_level_key": "left alone",
  "bar": { "id": "some-other-bar", "position": "bottom" },
  "plugins": [
    { "id": "third-party.widget", "hidden": [] },
    { "id": "ruixen.notch" }
  ],
  "idle": { "lock": 900, "screensaver": 600 }
}'
out2="$(printf '%s' "$customized" | "$build")"
check "customized: unrelated top-level key survives" \
  "$(jq -r '.some_future_top_level_key' <<<"$out2")" "left alone"
check "customized: unrelated plugin entry survives with its own fields" \
  "$(jq -c '.plugins[] | select(.id == "third-party.widget")' <<<"$out2")" \
  '{"id":"third-party.widget","hidden":[]}'
check "customized: ruixen plugin ids present exactly once each (idempotent, not duplicated)" \
  "$(jq -c '[.plugins[].id] | sort' <<<"$out2")" \
  '["ruixen.frame-widget","ruixen.media","ruixen.notch","ruixen.settings","ruixen.wallpaper","third-party.widget"]'
check "customized: user's own idle values are preserved, not overwritten" \
  "$(jq -c '.idle' <<<"$out2")" '{"lock":900,"screensaver":600}'
check "customized: bar is replaced with ruixen's own (some OTHER bar was active -- installing ruixen.bar means owning the bar slot)" \
  "$(jq -r '.bar.id' <<<"$out2")" "ruixen.bar"

# --- Case 3: re-running the merge on its own prior output is a no-op
out3="$(printf '%s' "$out2" | "$build")"
check "re-merging already-merged output is idempotent" "$out3" "$out2"

# --- Case 4: real regression found while testing against this
# machine's own live shell.json -- ruixen-bar-mode.sh and Settings.qml
# write bar.docked directly, and bar widgets can be reordered/hidden
# via `omarchy bar move`/Settings, both living inside the SAME object
# the merge would otherwise replace wholesale. Once ruixen.bar already
# owns the bar slot, none of that may be touched on a reinstall/update.
already_ruixen='{
  "version": 1,
  "bar": {
    "id": "ruixen.bar",
    "position": "top",
    "transparent": true,
    "centerAnchor": "omarchy.clock",
    "docked": true,
    "layout": {
      "left": [{ "id": "ruixen.workspaces" }],
      "center": [],
      "right": [{ "id": "ruixen.tray", "hidden": ["some.app"] }]
    }
  },
  "plugins": [
    { "id": "ruixen.notch", "someFutureField": true },
    { "id": "ruixen.settings" }
  ]
}'
out5="$(printf '%s' "$already_ruixen" | "$build")"
check "already ruixen.bar: docked toggle survives a reinstall" \
  "$(jq -r '.bar.docked' <<<"$out5")" "true"
check "already ruixen.bar: reordered/hidden layout survives a reinstall (pinnedapps/pluginpins inserted alongside, not replacing anything)" \
  "$(jq -c '.bar.layout' <<<"$out5")" \
  '{"left":[{"id":"ruixen.workspaces"},{"id":"ruixen.pinnedapps"}],"center":[],"right":[{"id":"ruixen.tray","hidden":["some.app"]},{"id":"ruixen.pluginpins"}]}'
check "already ruixen.bar: existing ruixen plugin entry's extra field survives" \
  "$(jq -c '.plugins[] | select(.id == "ruixen.notch")' <<<"$out5")" \
  '{"id":"ruixen.notch","someFutureField":true}'
check "already ruixen.bar: missing ruixen ids (frame-widget, wallpaper, media) still get appended" \
  "$(jq -c '[.plugins[].id] | sort' <<<"$out5")" \
  '["ruixen.frame-widget","ruixen.media","ruixen.notch","ruixen.settings","ruixen.wallpaper"]'

# --- Case 6: real regression -- an existing install (bar.id already
# "ruixen.bar") with a stale ruixen.media entry in its own bar.layout
# from before it was locked in ruixen.settings with no toggle left to
# remove it by hand. Direct follow-up ("the installer and update, it
# will make sure ruixen media is hidden right... these NEVER SHOW UP"):
# an existing owner's bar is otherwise preserved completely untouched
# (Case 4 above), so without this explicit strip the stale entry would
# survive every future update forever. omarchy.clock is protected (see
# Case 7 below) and must survive untouched here regardless, proving
# this is a targeted single-id strip, not the separate migration.
stale_media='{
  "version": 1,
  "bar": {
    "id": "ruixen.bar",
    "layout": {
      "left": [{ "id": "ruixen.applauncher" }, { "id": "ruixen.workspaces" }, { "id": "ruixen.pinnedapps" }],
      "center": [{ "id": "omarchy.clock" }, { "id": "ruixen.media" }, { "id": "ruixen.weather" }],
      "right": [{ "id": "ruixen.tray" }, { "id": "ruixen.pluginpins" }, { "id": "ruixen.media", "hidden": [] }]
    }
  },
  "plugins": []
}'
out6="$(printf '%s' "$stale_media" | "$build")"
check "existing install with stale ruixen.media in layout: stripped from every section" \
  "$(jq -c '.bar.layout' <<<"$out6")" \
  '{"left":[{"id":"ruixen.applauncher"},{"id":"ruixen.workspaces"},{"id":"ruixen.pinnedapps"}],"center":[{"id":"omarchy.clock"},{"id":"ruixen.weather"}],"right":[{"id":"ruixen.tray"},{"id":"ruixen.pluginpins"}]}'
check "existing install with stale ruixen.media in layout: still gets the plugins[] entry" \
  "$(jq -c '[.plugins[].id] | sort' <<<"$out6")" \
  '["ruixen.frame-widget","ruixen.media","ruixen.notch","ruixen.settings","ruixen.wallpaper"]'

# --- Case 7 (issue #36): legacy foreign/optional bar-widgets stuck in
# "center" from before ruixen.pluginpins existed get migrated into
# "right", where pluginPinsPill actually knows how to present them --
# center has no legitimate catch-all of its own (only weather/clock
# have a dedicated home there). Preserves the full entry object
# (inline settings survive); a duplicate of an id already correctly on
# the right is dropped, not doubled. omarchy.menu is DELIBERATELY
# EXCLUDED from this fixture's "migrates to right" expectation --
# direct follow-up after reviewing #36's first pass: Ruixen replaced
# that bar icon with ruixen.applauncher on purpose, so unlike a genuine
# third-party widget, omarchy.menu must never render on the bar at
# all, not even via Plugin Pins. It gets the same unconditional strip
# as ruixen.media instead (see Case 10 below), not this migration.
#
# "left" is DELIBERATELY left untouched by this fixture's own
# expectations -- direct follow-up after ruixen.pluginpins gained a
# real left-side twin (Bar.qml's leftPluginPinsPill): a non-protected
# id in "left" is no longer automatically a mistake, so this migration
# no longer sweeps that section at all (see Case 7b below for the
# fixture proving that directly).
legacy_foreign='{
  "version": 1,
  "bar": {
    "id": "ruixen.bar",
    "layout": {
      "left": [
        { "id": "ruixen.applauncher" },
        { "id": "ruixen.workspaces" },
        { "id": "ruixen.pinnedapps" },
        { "id": "ruixen.settingsbutton" }
      ],
      "center": [{ "id": "omarchy.menu" }, { "id": "ruixen.weather" }, { "id": "omarchy.clock" }, { "id": "thirdparty.foo", "opacity": 0.5 }],
      "right": [{ "id": "ruixen.tray" }, { "id": "ruixen.pluginpins" }, { "id": "already.pinned" }]
    }
  },
  "plugins": []
}'
out7="$(printf '%s' "$legacy_foreign" | "$build")"
check "issue #36: left region is untouched (nothing to migrate here anymore)" \
  "$(jq -c '.bar.layout.left' <<<"$out7")" \
  '[{"id":"ruixen.applauncher"},{"id":"ruixen.workspaces"},{"id":"ruixen.pinnedapps"},{"id":"ruixen.settingsbutton"}]'
check "issue #36: center keeps only the protected weather/clock, omarchy.menu stripped (not migrated), thirdparty.foo migrates out" \
  "$(jq -c '.bar.layout.center' <<<"$out7")" \
  '[{"id":"ruixen.weather"},{"id":"omarchy.clock"}]'
check "issue #36: real foreign entries land on the right, inline settings preserved, already-pinned ids untouched, omarchy.menu absent" \
  "$(jq -c '.bar.layout.right' <<<"$out7")" \
  '[{"id":"ruixen.tray"},{"id":"ruixen.pluginpins"},{"id":"already.pinned"},{"id":"thirdparty.foo","opacity":0.5}]'

# --- Case 7b (issue #36 follow-up): a non-protected id deliberately
# pinned to "left" via ruixen.pluginpins' own left/right click (see
# ruixen.pluginpins/BarWidget.qml's setPinSide) must survive an update
# untouched -- it is a real, intentional placement now, not legacy
# debris. Direct scenario this guards: someone right-clicks a pin to
# send it to the new left-side group, then updates -- their choice
# must not silently get moved back to "right".
left_pinned='{
  "version": 1,
  "bar": {
    "id": "ruixen.bar",
    "layout": {
      "left": [{ "id": "ruixen.applauncher" }, { "id": "ruixen.workspaces" }, { "id": "ruixen.pinnedapps" }, { "id": "deliberately.left", "opacity": 0.7 }],
      "center": [],
      "right": [{ "id": "ruixen.tray" }, { "id": "ruixen.pluginpins" }]
    }
  },
  "plugins": []
}'
out7b_deliberate="$(printf '%s' "$left_pinned" | "$build")"
check "issue #36 follow-up: a deliberately left-pinned foreign widget survives an update untouched, settings intact" \
  "$(jq -c '.bar.layout.left' <<<"$out7b_deliberate")" \
  '[{"id":"ruixen.applauncher"},{"id":"ruixen.workspaces"},{"id":"ruixen.pinnedapps"},{"id":"deliberately.left","opacity":0.7}]'
check "issue #36 follow-up: it does not also get duplicated onto the right" \
  "$(jq -c '.bar.layout.right' <<<"$out7b_deliberate")" \
  '[{"id":"ruixen.tray"},{"id":"ruixen.pluginpins"}]'

# --- Case 8 (issue #36): a foreign id stuck in "center" AND already
# correctly pinned on the right must not end up duplicated -- the
# stale center-side copy is dropped, the right-side copy (already in
# its intended home) wins. "left" is a separate, real placement now
# (Case 7b above), so this dedup case is scoped to center, the only
# section the migration still sweeps.
dup_foreign='{
  "version": 1,
  "bar": {
    "id": "ruixen.bar",
    "layout": {
      "left": [{ "id": "ruixen.applauncher" }, { "id": "ruixen.workspaces" }, { "id": "ruixen.pinnedapps" }],
      "center": [{ "id": "already.pinned" }],
      "right": [{ "id": "ruixen.tray" }, { "id": "ruixen.pluginpins" }, { "id": "already.pinned", "extra": "settings-that-should-win" }]
    }
  },
  "plugins": []
}'
out8="$(printf '%s' "$dup_foreign" | "$build")"
check "issue #36: a foreign id already pinned on the right is not duplicated when also stuck in center" \
  "$(jq -c '.bar.layout.right' <<<"$out8")" \
  '[{"id":"ruixen.tray"},{"id":"ruixen.pluginpins"},{"id":"already.pinned","extra":"settings-that-should-win"}]'
check "issue #36: the stale center-side copy of an already-pinned id is dropped, not left behind" \
  "$(jq -c '.bar.layout.center' <<<"$out8")" \
  '[]'

# --- Case 9 (issue #36): running the merge again on its own migrated
# output must be a no-op -- nothing left in left/center to migrate a
# second time.
out7b="$(printf '%s' "$out7" | "$build")"
check "issue #36: re-running the migration on its own output changes nothing (idempotent)" \
  "$out7b" "$out7"

# --- Case 10 (issue #36 follow-up): omarchy.menu must never render on
# the bar at all, regardless of which section a stale copy starts in
# -- Ruixen deliberately replaced that bar icon with
# ruixen.applauncher, so unlike an ordinary foreign widget it is
# stripped outright (same treatment as ruixen.media), never migrated
# to "right" through Plugin Pins. The underlying omarchy.menu
# functionality itself (Super+Space, stock menu IPC) is untouched by
# this -- only its own bar.layout entry is ever in scope here.
stale_menu='{
  "version": 1,
  "bar": {
    "id": "ruixen.bar",
    "layout": {
      "left": [{ "id": "ruixen.applauncher" }, { "id": "ruixen.workspaces" }, { "id": "ruixen.pinnedapps" }, { "id": "omarchy.menu" }],
      "center": [{ "id": "omarchy.menu" }, { "id": "ruixen.weather" }],
      "right": [{ "id": "ruixen.tray" }, { "id": "ruixen.pluginpins" }, { "id": "omarchy.menu" }]
    }
  },
  "plugins": []
}'
out10="$(printf '%s' "$stale_menu" | "$build")"
check "issue #36 follow-up: omarchy.menu stripped from left" \
  "$(jq -c '.bar.layout.left' <<<"$out10")" '[{"id":"ruixen.applauncher"},{"id":"ruixen.workspaces"},{"id":"ruixen.pinnedapps"}]'
check "issue #36 follow-up: omarchy.menu stripped from center" \
  "$(jq -c '.bar.layout.center' <<<"$out10")" '[{"id":"ruixen.weather"}]'
check "issue #36 follow-up: omarchy.menu stripped from right too, not just left/center" \
  "$(jq -c '.bar.layout.right' <<<"$out10")" '[{"id":"ruixen.tray"},{"id":"ruixen.pluginpins"}]'
out10b="$(printf '%s' "$out10" | "$build")"
check "issue #36 follow-up: re-running the strip on its own output is idempotent" \
  "$out10b" "$out10"

# --- Case 11: real tester gap, found via ruixen-doctor.sh -- a
# genuinely old install (predates ruixen.pinnedapps/ruixen.pluginpins
# entirely) stays missing both forever otherwise, even once every
# plugin file is current: git already up to date, every deployed
# plugin already matching source, yet bar.layout.left still read just
# [applauncher, workspaces]. Neither id has any way to be
# intentionally removed once present, so "missing entirely" can only
# mean "predates this feature". Inserted at a deterministic canonical
# neighbor (right after the anchor id) rather than rebuilding the
# region array -- unrelated entries, order, and settings elsewhere
# must survive untouched.
old_pre_pluginpins='{
  "version": 1,
  "bar": {
    "id": "ruixen.bar",
    "docked": true,
    "layout": {
      "left": [{ "id": "ruixen.applauncher" }, { "id": "ruixen.workspaces" }],
      "center": [{ "id": "ruixen.weather" }, { "id": "omarchy.clock", "format": "HH:mm" }],
      "right": [{ "id": "ruixen.tray", "hidden": ["some.app"] }, { "id": "ruixen.stayawake" }, { "id": "ruixen.settingsbutton" }]
    }
  },
  "plugins": [{ "id": "ruixen.notch" }]
}'
out11="$(printf '%s' "$old_pre_pluginpins" | "$build")"
check "structural gap: ruixen.pinnedapps inserted right after ruixen.workspaces on the left" \
  "$(jq -c '.bar.layout.left' <<<"$out11")" \
  '[{"id":"ruixen.applauncher"},{"id":"ruixen.workspaces"},{"id":"ruixen.pinnedapps"}]'
check "structural gap: ruixen.pluginpins inserted right after ruixen.tray on the right" \
  "$(jq -c '.bar.layout.right' <<<"$out11")" \
  '[{"id":"ruixen.tray","hidden":["some.app"]},{"id":"ruixen.pluginpins"},{"id":"ruixen.stayawake"},{"id":"ruixen.settingsbutton"}]'
check "structural gap: unrelated entries/settings/order elsewhere survive untouched (docked, center, plugins)" \
  "$(jq -c '{docked: .bar.docked, center: .bar.layout.center, plugins: [.plugins[].id]}' <<<"$out11")" \
  '{"docked":true,"center":[{"id":"ruixen.weather"},{"id":"omarchy.clock","format":"HH:mm"}],"plugins":["ruixen.notch","ruixen.frame-widget","ruixen.settings","ruixen.wallpaper","ruixen.media"]}'
check "structural gap: re-running on its own output is idempotent (already present, not inserted twice)" \
  "$(printf '%s' "$out11" | "$build")" "$out11"

# --- Case 5: invalid JSON input is rejected, not silently swallowed
if printf 'not json at all' | "$build" >/dev/null 2>&1; then
  printf 'FAIL - invalid JSON input should not succeed\n'
  fail_count=$((fail_count + 1))
else
  printf 'ok   - invalid JSON input fails loudly\n'
  pass=$((pass + 1))
fi

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
