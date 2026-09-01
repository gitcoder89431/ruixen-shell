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
check "no existing config: plugins has exactly the 4 ruixen ids" \
  "$(jq -c '[.plugins[].id] | sort' <<<"$out1")" \
  '["ruixen.frame-widget","ruixen.notch","ruixen.settings","ruixen.wallpaper"]'
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
  '["ruixen.frame-widget","ruixen.notch","ruixen.settings","ruixen.wallpaper","third-party.widget"]'
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
check "already ruixen.bar: reordered/hidden layout survives a reinstall" \
  "$(jq -c '.bar.layout' <<<"$out5")" \
  '{"left":[{"id":"ruixen.workspaces"}],"center":[],"right":[{"id":"ruixen.tray","hidden":["some.app"]}]}'
check "already ruixen.bar: existing ruixen plugin entry's extra field survives" \
  "$(jq -c '.plugins[] | select(.id == "ruixen.notch")' <<<"$out5")" \
  '{"id":"ruixen.notch","someFutureField":true}'
check "already ruixen.bar: missing ruixen ids (frame-widget, wallpaper) still get appended" \
  "$(jq -c '[.plugins[].id] | sort' <<<"$out5")" \
  '["ruixen.frame-widget","ruixen.notch","ruixen.settings","ruixen.wallpaper"]'

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
