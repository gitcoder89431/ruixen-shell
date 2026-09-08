#!/usr/bin/env bash
# Covers the ruixen-shell issue #43/#38 fix: Omarchy v4.0.3 restricts
# shell.firstPartyServiceFor() to a fixed 4-item allowlist of Omarchy's
# own services, and only for the plugin declaring manifest kind "bar" --
# ruixen.notch (kind: ["overlay","service"]) was never going to have bar
# capabilities to use it, even for "omarchy.nightlight"/"omarchy.idle",
# both of which ARE nominally in that allowlist.
#
# Both are now read/controlled via omarchy-shell's own real "nightlight"/
# "idle" IPC targets instead, confirmed directly against
# /usr/share/omarchy/shell/plugins/services/{nightlight,idle}/Service.qml
# and verified empirically live (not just by reading source): idle's own
# `enable`/`disable` IPC methods are INVERTED relative to the "Stay
# Awake" toggle's own meaning (idleEnabled is defined as
# `stayAwakeStateLoaded && !stayAwake` in Omarchy's own source) --
# confirmed by actually calling `omarchy-shell idle enable` on the real
# dev machine and watching stayAwake flip to false, not true.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
dashboard_qml="$repo_dir/ruixen.notch/DashboardContent.qml"
overlay_qml="$repo_dir/ruixen.notch/Overlay.qml"

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

# --- no leftover restricted API calls -----------------------------------

check "no leftover shell.firstPartyServiceFor(\"omarchy.nightlight\") call, not even in a comment" \
  "$(grep -c 'firstPartyServiceFor("omarchy\.nightlight")' "$dashboard_qml" || true)" "0"
check "no leftover shell.firstPartyServiceFor(\"omarchy.idle\") call, not even in a comment" \
  "$(grep -c 'firstPartyServiceFor("omarchy\.idle")' "$dashboard_qml" || true)" "0"

# --- idle/stay-awake: real on-disk flag file, watched reactively -------

# "2" -- once in this migration's own explanatory comment, once in the
# real FileView path.
check "watches the real Omarchy stay-awake flag file path" \
  "$(grep -c '\.local/state/omarchy/indicators/stay-awake' "$dashboard_qml")" "2"
check "the stay-awake FileView watches for live changes (external toggles reflect immediately)" \
  "$(grep -A5 'id: stayAwakeFlagFile' "$dashboard_qml" | grep -c 'watchChanges: true')" "1"
check "file existing sets stayAwakeEnabled true, not false (presence IS the on-state)" \
  "$(grep -c 'onLoaded: root\.stayAwakeEnabled = true' "$dashboard_qml")" "1"
check "file missing sets stayAwakeEnabled false" \
  "$(grep -c 'onLoadFailed: root\.stayAwakeEnabled = false' "$dashboard_qml")" "1"

# --- idle control: the empirically-confirmed inverted mapping ----------

check "wanting stay-awake ON calls the idle IPC target's own \"disable\" (the empirically-confirmed inversion), not \"enable\"" \
  "$(grep -c 'wantStayAwake ? "disable" : "enable"' "$dashboard_qml")" "1"
check "the toggle click site asks for the NEW state (negation), not a stale-value trick" \
  "$(grep -c 'root\.sendIdleAction(!root\.stayAwakeEnabled)' "$dashboard_qml")" "1"

# --- nightlight: no on-disk state, so polled instead --------------------

check "nightlight status is polled via the real omarchy-shell IPC target" \
  "$(grep -c '\["omarchy-shell", "nightlight", "status"\]' "$dashboard_qml")" "1"
check "the nightlight poll is gated on panelExpanded (only pay the cost while the dashboard is actually open)" \
  "$(grep -A3 'command: \["omarchy-shell", "nightlight", "status"\]' "$dashboard_qml" | grep -c 'running: false' || grep -B2 -A6 'id: nightlightStatusProc' "$dashboard_qml" | grep -c 'root\.panelExpanded')" "1"
check "the toggle click sends the real nightlight IPC action, not a stale-value trick" \
  "$(grep -c 'root\.sendNightlightAction("toggle")' "$dashboard_qml")" "1"
check "an action refreshes status immediately afterward rather than waiting up to 5s for the next poll" \
  "$(grep -A8 'id: nightlightActionProc' "$dashboard_qml" | grep -c 'nightlightStatusProc\.running = true')" "1"

# --- panelExpanded prop threading ----------------------------------------

check "DashboardContent.qml declares panelExpanded" \
  "$(grep -c 'property bool panelExpanded: false' "$dashboard_qml")" "1"
check "Overlay.qml wires panelExpanded from the real panel.expanded" \
  "$(grep -c 'panelExpanded: panel\.expanded' "$overlay_qml")" "1"

# --- no leftover debug scaffolding ---------------------------------------

check "no leftover debug IpcHandler (used only to verify this fix live, removed before commit)" \
  "$(grep -c 'target: "debug\.dashboard"' "$dashboard_qml" || true)" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
