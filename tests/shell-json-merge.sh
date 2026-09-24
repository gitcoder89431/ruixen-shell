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
check "no existing config: plugins has exactly the 7 ruixen ids" \
  "$(jq -c '[.plugins[].id] | sort' <<<"$out1")" \
  '["ruixen.cava","ruixen.launcher","ruixen.media","ruixen.notch","ruixen.settings","ruixen.wallpaper"]'
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
  '["ruixen.cava","ruixen.launcher","ruixen.media","ruixen.notch","ruixen.settings","ruixen.wallpaper","third-party.widget"]'
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
check "already ruixen.bar: missing ruixen ids (wallpaper, media, launcher, cava) still get appended" \
  "$(jq -c '[.plugins[].id] | sort' <<<"$out5")" \
  '["ruixen.cava","ruixen.launcher","ruixen.media","ruixen.notch","ruixen.settings","ruixen.wallpaper"]'

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
  '["ruixen.cava","ruixen.launcher","ruixen.media","ruixen.notch","ruixen.settings","ruixen.wallpaper"]'

# --- Case 7 (issue #36, revised): "center" is no longer swept for an
# ordinary foreign id, mirroring the "left" decision below -- direct
# review finding from a third-party clock author after #27 gave
# "center" its own real generic catch-all (clockPill's own comment: no
# allowlist of known third-party ids): sweeping a non-protected id out
# of "center" into "right" on every install/update silently relocated
# a deliberate placement (their own custom clock plugin) with nothing
# ever surfacing the move, since the widget still rendered fine either
# way. thirdparty.foo here now stays exactly where it was placed,
# settings intact, same as an ordinary id already sitting in "left"
# (Case 7b below). omarchy.menu is still stripped unconditionally
# (this is the SEPARATE strip mechanism used for ruixen.media too, see
# Case 10 below) -- unlike a genuine third-party widget, Ruixen
# replaced that bar icon with ruixen.applauncher on purpose, so it must
# never render at all, not even left in place.
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
check "center is no longer swept: thirdparty.foo stays in center, settings intact, omarchy.menu still stripped" \
  "$(jq -c '.bar.layout.center' <<<"$out7")" \
  '[{"id":"ruixen.weather"},{"id":"omarchy.clock"},{"id":"thirdparty.foo","opacity":0.5}]'
check "center is no longer swept: right is untouched, thirdparty.foo does not land here" \
  "$(jq -c '.bar.layout.right' <<<"$out7")" \
  '[{"id":"ruixen.tray"},{"id":"ruixen.pluginpins"},{"id":"already.pinned"}]'

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

# --- Case 8 (revised): now that "center" is no longer swept, a foreign
# id sitting in BOTH "center" and "right" at once is left exactly as
# given in each section -- no cross-section dedup, same as "left" and
# "right" already have no dedup between them today. Whichever config
# produced both copies is the caller's own to resolve; this script only
# ever touches weather/clock across sections (the dedicated rescue
# migration, Case 13/13b), never an ordinary id.
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
check "center is no longer swept: the right-side copy is untouched" \
  "$(jq -c '.bar.layout.right' <<<"$out8")" \
  '[{"id":"ruixen.tray"},{"id":"ruixen.pluginpins"},{"id":"already.pinned","extra":"settings-that-should-win"}]'
check "center is no longer swept: the center-side copy is left in place too, not dropped" \
  "$(jq -c '.bar.layout.center' <<<"$out8")" \
  '[{"id":"already.pinned"}]'

# --- Case 8b: direct third-party report -- a real custom clock plugin
# (their own words: "Bar.qml already supports this... a custom clock in
# center renders fine. The problem is lib/build-shell-json.sh: it
# sweeps any center id not in protected_bar_ids out to right... a
# custom clock cant survive an update.") Exact before/after they gave
# as their own repro, minus the plugin's real name (kept generic here
# since this fixture only needs to prove the mechanism, not identify
# any specific third-party plugin).
third_party_clock='{
  "version": 1,
  "bar": {
    "id": "ruixen.bar",
    "layout": {
      "left": [{ "id": "ruixen.applauncher" }, { "id": "ruixen.workspaces" }, { "id": "ruixen.pinnedapps" }],
      "center": [{ "id": "ruixen.weather" }, { "id": "thirdparty.clock", "timezone": "UTC" }],
      "right": [{ "id": "ruixen.tray" }, { "id": "ruixen.pluginpins" }, { "id": "omarchy.power" }]
    }
  },
  "plugins": []
}'
out8b="$(printf '%s' "$third_party_clock" | "$build")"
check "third-party clock survives an update: stays in center, settings intact" \
  "$(jq -c '.bar.layout.center' <<<"$out8b")" \
  '[{"id":"ruixen.weather"},{"id":"thirdparty.clock","timezone":"UTC"}]'
check "third-party clock survives an update: right is untouched, the clock does not land here" \
  "$(jq -c '.bar.layout.right' <<<"$out8b")" \
  '[{"id":"ruixen.tray"},{"id":"ruixen.pluginpins"},{"id":"omarchy.power"}]'
check "third-party clock survives an update: re-running on its own output is idempotent" \
  "$(printf '%s' "$out8b" | "$build")" "$out8b"

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
check "structural gap: ruixen.pluginpins inserted right after ruixen.tray on the right, nothing else added" \
  "$(jq -c '.bar.layout.right' <<<"$out11")" \
  '[{"id":"ruixen.tray","hidden":["some.app"]},{"id":"ruixen.pluginpins"},{"id":"ruixen.stayawake"},{"id":"ruixen.settingsbutton"}]'
check "structural gap: unrelated entries/settings/order elsewhere survive untouched (docked, center, plugins)" \
  "$(jq -c '{docked: .bar.docked, center: .bar.layout.center, plugins: [.plugins[].id]}' <<<"$out11")" \
  '{"docked":true,"center":[{"id":"ruixen.weather"},{"id":"omarchy.clock","format":"HH:mm"}],"plugins":["ruixen.notch","ruixen.settings","ruixen.wallpaper","ruixen.media","ruixen.launcher","ruixen.cava"]}'
check "structural gap: re-running on its own output is idempotent (already present, not inserted twice)" \
  "$(printf '%s' "$out11" | "$build")" "$out11"

# --- Case 12: ruixen.peripherals is deliberately NOT structural --
# regression test for the reversal (direct follow-up, to reduce
# clutter: "its not that important for me to always see it right now").
# It used to force-insert here via the exact same structural-gap
# mechanism Case 11 above still uses for pinnedapps/pluginpins (see git
# history) -- removed from $requiredStructural once it became an
# ordinary ruixen.pluginpins-pinnable widget again, so an install
# missing it now just... keeps missing it, same as any other optional
# widget nobody has pinned yet. A future change accidentally putting it
# back in $requiredStructural should fail loudly here, not silently
# start force-adding it again.
old_missing_peripherals='{
  "version": 1,
  "bar": {
    "id": "ruixen.bar",
    "layout": {
      "left": [{ "id": "ruixen.applauncher" }, { "id": "ruixen.workspaces" }, { "id": "ruixen.pinnedapps" }],
      "center": [{ "id": "ruixen.weather" }, { "id": "omarchy.clock" }],
      "right": [{ "id": "ruixen.tray" }, { "id": "ruixen.pluginpins" }, { "id": "omarchy.power" }, { "id": "ruixen.quickactions" }, { "id": "ruixen.settingsbutton" }]
    }
  },
  "plugins": []
}'
out12="$(printf '%s' "$old_missing_peripherals" | "$build")"
check "ruixen.peripherals is NOT force-inserted for an install missing it" \
  "$(jq -c '.bar.layout.right' <<<"$out12")" \
  '[{"id":"ruixen.tray"},{"id":"ruixen.pluginpins"},{"id":"omarchy.power"},{"id":"ruixen.quickactions"},{"id":"ruixen.settingsbutton"}]'
check "ruixen.peripherals: pinnedapps/pluginpins already present are not touched or duplicated" \
  "$(jq -c '.bar.layout.left' <<<"$out12")" \
  '[{"id":"ruixen.applauncher"},{"id":"ruixen.workspaces"},{"id":"ruixen.pinnedapps"}]'
check "ruixen.peripherals: re-running on its own output is idempotent" \
  "$(printf '%s' "$out12" | "$build")" "$out12"

# --- Case 13: direct live report -- a real drag-and-drop bug let
# ruixen.weather/omarchy.clock be dragged out of "center" onto any
# other protected slot, scattering either into "left"/"right" with no
# ordinary way to drag it back. Unlike the general foreign-widget
# migration (Case 7), which deliberately leaves "left" alone, weather/
# clock have no legitimate home anywhere but "center" -- this sweeps
# BOTH sides. Preserves the full entry object (omarchy.clock's own
# format survives); a stale center-side copy of an id already correctly
# placed is dropped, not doubled.
scattered_center_special='{
  "version": 1,
  "bar": {
    "id": "ruixen.bar",
    "layout": {
      "left": [
        { "id": "ruixen.applauncher" },
        { "id": "ruixen.workspaces" },
        { "id": "ruixen.pinnedapps" }
      ],
      "center": [{ "id": "omarchy.clock", "format": "HH:mm" }],
      "right": [
        { "id": "ruixen.weather" },
        { "id": "ruixen.tray" },
        { "id": "ruixen.pluginpins" }
      ]
    }
  },
  "plugins": []
}'
out13="$(printf '%s' "$scattered_center_special" | "$build")"
check "center rescue: ruixen.weather moves back into center, alongside omarchy.clock" \
  "$(jq -c '.bar.layout.center' <<<"$out13")" \
  '[{"id":"omarchy.clock","format":"HH:mm"},{"id":"ruixen.weather"}]'
check "center rescue: ruixen.weather no longer present in right" \
  "$(jq -c '.bar.layout.right' <<<"$out13")" \
  '[{"id":"ruixen.tray"},{"id":"ruixen.pluginpins"}]'
check "center rescue: left is untouched" \
  "$(jq -c '.bar.layout.left' <<<"$out13")" \
  '[{"id":"ruixen.applauncher"},{"id":"ruixen.workspaces"},{"id":"ruixen.pinnedapps"}]'
check "center rescue: re-running on its own output is idempotent" \
  "$(printf '%s' "$out13" | "$build")" "$out13"

# --- Case 13b: weather scattered to the right AND a stale center-side
# copy of clock already present alongside a SECOND, stranded copy of
# clock (with settings) stuck in "left" too -- simulating a config
# caught mid-drag. Same precedent as the general foreign-widget
# migration's own dedup (Case 8: "the stale CENTER-side copy is
# dropped" in favor of an already-correctly-placed one) applied in the
# opposite direction here -- center IS the correct home for this
# migration, so the copy already there wins and the stranded duplicate
# (settings included) is dropped, not merged or preferred.
both_scattered='{
  "version": 1,
  "bar": {
    "id": "ruixen.bar",
    "layout": {
      "left": [{ "id": "ruixen.applauncher" }, { "id": "omarchy.clock", "format": "HH:mm" }],
      "center": [{ "id": "omarchy.clock" }],
      "right": [{ "id": "ruixen.weather" }, { "id": "ruixen.tray" }]
    }
  },
  "plugins": []
}'
out13b="$(printf '%s' "$both_scattered" | "$build")"
check "center rescue: weather rescued, clock keeps its already-in-center copy (the stranded duplicate is dropped)" \
  "$(jq -c '.bar.layout.center' <<<"$out13b")" \
  '[{"id":"omarchy.clock"},{"id":"ruixen.weather"}]'
check "center rescue: left keeps everything else, the stranded clock duplicate removed" \
  "$(jq -c '.bar.layout.left' <<<"$out13b")" \
  '[{"id":"ruixen.applauncher"},{"id":"ruixen.pinnedapps"}]'
check "center rescue: right keeps everything else, weather removed" \
  "$(jq -c '.bar.layout.right' <<<"$out13b")" \
  '[{"id":"ruixen.tray"},{"id":"ruixen.pluginpins"}]'

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
