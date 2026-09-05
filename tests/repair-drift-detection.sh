#!/usr/bin/env bash
# Covers issue #33's `repair` half: ruixen-repair.sh's own drift
# detection and fix path. Reuses the exact same fake $HOME + fake-bin
# sandbox tests/install-lifecycle.sh already established for driving
# the REAL install.sh/repair scripts without a real Omarchy/Hyprland
# environment -- not a reimplementation of that fixture.
#
# Covers: a healthy install reports healthy and exits 0; a corrupted
# deployed plugin is detected; --dry-run changes nothing at all; a
# real (non-dry-run) repair run actually fixes the corruption via
# install.sh's own already-hardened deploy path.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
fake_bin="$script_dir/fixtures/fake-bin"

command -v jq >/dev/null 2>&1 || {
  printf 'repair-drift-detection: jq is required (command "jq" not found)\n' >&2
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

fake_home="$(mktemp -d)"
trap 'rm -rf "$fake_home"' EXIT

run_install() {
  ( HOME="$fake_home" PATH="$fake_bin:$PATH" "$repo_dir/install.sh" ) >"$fake_home/install.out" 2>&1
}
run_repair() {
  ( HOME="$fake_home" PATH="$fake_bin:$PATH" "$repo_dir/ruixen-repair.sh" "$@" )
}

# --- Case 1: a genuinely clean, just-installed state is healthy ------
run_install || { cat "$fake_home/install.out" >&2; exit 1; }
out1="$(run_repair --dry-run)"
check "healthy install: repair --dry-run reports healthy" \
  "$(grep -c 'Healthy -- every plugin file matches' <<<"$out1")" "1"
check "healthy install: repair --dry-run exits 0" "$?" "0"

# --- Case 2: corrupt one deployed plugin file, confirm detection -----
deployed_weather="$fake_home/.config/omarchy/plugins/ruixen.weather/BarWidget.qml"
original_content="$(cat "$deployed_weather")"
printf '%s\n// corrupted for this test\n' "$original_content" > "$deployed_weather"

out2="$(run_repair --dry-run)"
check "corrupted plugin: detected by name" \
  "$(grep -c 'ruixen.weather -- deployed files missing or do not match' <<<"$out2")" "1"
check "corrupted plugin: dry run explicitly says nothing changed" \
  "$(grep -c 'Dry run -- nothing changed' <<<"$out2")" "1"

# --- Case 3: --dry-run truly makes no changes -------------------------
check "dry run: the corrupted file is byte-for-byte untouched afterward" \
  "$(cat "$deployed_weather")" "$(printf '%s\n// corrupted for this test\n' "$original_content")"

# --- Case 4: a missing plugin directory entirely is also detected ----
tray_dir="$fake_home/.config/omarchy/plugins/ruixen.tray"
rm -rf "$tray_dir"
out4="$(run_repair --dry-run)"
check "missing plugin directory: detected alongside the corrupted one" \
  "$(grep -c 'ruixen.tray -- deployed files missing or do not match' <<<"$out4")" "1"

# --- Case 5: a real (non-dry-run) repair fixes both, via install.sh ---
run_repair >"$fake_home/repair.out" 2>&1 || { cat "$fake_home/repair.out" >&2; exit 1; }
check "real repair: corrupted plugin content restored exactly" \
  "$(cat "$deployed_weather")" "$original_content"
check "real repair: missing plugin directory restored" \
  "$([[ -d "$tray_dir" ]] && echo yes || echo no)" "yes"

out5="$(run_repair --dry-run)"
check "after real repair: a follow-up dry-run reports healthy again" \
  "$(grep -c 'Healthy -- every plugin file matches' <<<"$out5")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
