#!/usr/bin/env bash
# Covers the ruixen-shell issue #39/#38 fix: Omarchy v4.0.3 restricts
# shell.firstPartyServiceFor() to a fixed 4-item allowlist of Omarchy's
# own services ("omarchy.idle"/"omarchy.media"/"omarchy.nightlight"/
# "omarchy.notifications"), and only for the plugin declaring manifest
# kind "bar" -- "ruixen.media" was never going to be in that allowlist
# regardless of caller, and ruixen.notch/ruixen.media's own BarWidget.qml
# are both separate QML instances from Service.qml with no shell property
# of their own, only ever handed whatever ruixen.bar's own ModuleSlot
# injects.
#
# ruixen.media/Service.qml now mirrors its own statusJson() to
# ~/.local/state/ruixen/media-state.json (same FileView/atomicWrites
# pattern KanbanService.qml's own persistence and
# ruixen.peripherals/Service.qml's own state relay already use); control
# (play/pause/next/previous) goes through Service.qml's own existing
# "ruixen-media" IpcHandler target instead, via a new parameterized
# runAction(action, showFeedback) function.
#
# Static QML checks only -- no synthetic-data harness needed here (unlike
# peripherals-status.sh's own Python helper tests), since this is pure
# QML/JS wiring, not a separate parsed data pipeline. Live end-to-end
# verification (a real mpv+mpv-mpris MPRIS source, read + control both
# confirmed working) was done manually against the actual 4.0.2 install
# this session -- not repeated here since it needs a real MPRIS player
# running, not something a CI fixture can synthesize cheaply.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
service_qml="$repo_dir/ruixen.media/Service.qml"
media_widget_qml="$repo_dir/ruixen.media/BarWidget.qml"
overlay_qml="$repo_dir/ruixen.notch/Overlay.qml"
dashboard_qml="$repo_dir/ruixen.notch/DashboardContent.qml"

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

# --- Service.qml: the writer side ---------------------------------------

check "Service.qml writes the shared media state file" \
  "$(grep -c 'media-state\.json' "$service_qml")" "2"
check "Service.qml's state file writer uses atomic writes" \
  "$(grep -c 'atomicWrites: true' "$service_qml")" "1"
check "statusJson() includes length/position (needed for the progress bar, missing before this fix)" \
  "$(grep -c 'length: p ? Math\.max(0, Number(p\.length' "$service_qml")" "1"
check "statusJson()'s artUrl is gated on hasMedia (the zombie-MPRIS-registration guard, moved here from ruixen.notch)" \
  "$(grep -c 'artUrl: root\.hasMedia && p && p\.trackArtUrl' "$service_qml")" "1"
check "the IpcHandler exposes a parameterized runAction for in-process callers needing showFeedback: false" \
  "$(grep -c 'function runAction(action: string, showFeedback: bool): string' "$service_qml")" "1"

# --- ruixen.notch/Overlay.qml: one of the two readers -------------------

# "1", not "0" -- the only surviving mention is this migration's own
# explanatory comment, not a real leftover call.
check "no leftover shell.firstPartyServiceFor(\"ruixen.media\") call in Overlay.qml (one explanatory comment mention is expected)" \
  "$(grep -c 'shell\.firstPartyServiceFor("ruixen\.media")' "$overlay_qml" || true)" "1"
check "Overlay.qml reads the shared media state file" \
  "$(grep -c 'media-state\.json' "$overlay_qml")" "1"
check "Overlay.qml's media state FileView watches for live changes" \
  "$(grep -A4 'id: mediaStateFile' "$overlay_qml" | grep -c 'watchChanges: true')" "1"
check "Overlay.qml sends media actions through the ruixen-media IPC target, not a live service call" \
  "$(grep -c 'omarchy-shell", "ruixen-media", "runAction"' "$overlay_qml")" "1"
check "no leftover activePlayer property (replaced by plain state-fed properties)" \
  "$(grep -c 'property var activePlayer' "$overlay_qml" || true)" "0"

# --- ruixen.notch/DashboardContent.qml: the other reader -----------------

check "DashboardContent.qml calls sendMediaAction, not mediaService.runAction" \
  "$(grep -c 'root\.sendMediaAction(' "$dashboard_qml")" "3"
check "no leftover mediaService property on DashboardContent.qml" \
  "$(grep -c 'property var mediaService' "$dashboard_qml" || true)" "0"

# --- ruixen.media/BarWidget.qml: its own bar widget, a separate broken
# call site from the table in issue #38 (bar.shell.firstPartyServiceFor,
# not shell.firstPartyServiceFor -- same fix, same root cause) ----------

# "1", not "0" -- same reasoning as above, one explanatory comment mention.
check "no leftover bar.shell.firstPartyServiceFor call in ruixen.media's own BarWidget.qml (one explanatory comment mention is expected)" \
  "$(grep -c 'firstPartyServiceFor' "$media_widget_qml" || true)" "1"
check "ruixen.media's own BarWidget.qml reads the same shared state file" \
  "$(grep -c 'media-state\.json' "$media_widget_qml")" "1"
check "ruixen.media's own BarWidget.qml sends actions through the IPC target too" \
  "$(grep -c 'omarchy-shell", "ruixen-media", "runAction"' "$media_widget_qml")" "1"
check "no raw pasted glyph characters anywhere in ruixen.media's own BarWidget.qml" \
  "$(python3 -c "
print('yes' if any(ord(c) > 0x2000 and c != chr(0x2014) for c in open('$media_widget_qml', encoding='utf-8').read()) else 'no')
")" "no"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
