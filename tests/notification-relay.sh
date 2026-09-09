#!/usr/bin/env bash
# Covers the ruixen-shell issue #42/#38 fix: Omarchy v4.0.3 restricts
# shell.firstPartyServiceFor() to a fixed 4-item allowlist of Omarchy's
# own services, and only for the plugin declaring manifest kind "bar" --
# ruixen.notch (kind: ["overlay","service"]) was never going to have bar
# capabilities to use it even for "omarchy.notifications", which IS
# nominally in that allowlist.
#
# Verified directly against
# /usr/share/omarchy/shell/plugins/notifications/Service.qml (not
# guessed): DND is persisted at ~/.local/state/omarchy/notifications.json
# ({"version":3,"dnd":bool}, atomicWrites: true) and controlled through
# the real "notifications" IpcHandler target's own dndState/toggleDnd/
# setDnd/isDnd functions; every notification the real service shows or
# silences is mirrored to a plain single-line JSON file, one per live
# on-screen popup directly under ~/.local/state/omarchy/notifications/,
# moved into its history/ subdirectory the moment it leaves the screen.
#
# DND now reads that state file directly (FileView, watchChanges: true,
# same pattern as the stay-awake flag file in issue #43) and toggles via
# the real IPC target. The notch's own notification-history card
# (NotificationService.qml) now sweeps both of those real directories on
# a timer instead of listening to the in-process popupModel, reusing the
# exact same NotificationModel.parseHistory() parser already proven
# against the history directory alone.
#
# Static QML checks only, plus the JS model's own existing test coverage
# (js-model-tests.sh already exercises NotificationModel.js). Live
# end-to-end verification (DND toggle via the real IPC target reflected
# in ~2s through the watched file; a real notify-send notification
# ingested by the new sweep within one 3s tick) was done manually against
# the actual 4.0.2 install this session -- not repeated here since it
# needs a live notification to arrive, not something a CI fixture can
# synthesize cheaply.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
overlay_qml="$repo_dir/ruixen.notch/Overlay.qml"
dashboard_qml="$repo_dir/ruixen.notch/DashboardContent.qml"
service_qml="$repo_dir/ruixen.notch/NotificationService.qml"

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

check "Overlay.qml has no leftover firstPartyServiceFor(\"omarchy.notifications\") call" \
  "$(grep -c 'firstPartyServiceFor("omarchy\.notifications")' "$overlay_qml" || true)" "0"
check "NotificationService.qml has no leftover firstPartyServiceFor(\"omarchy.notifications\") call, not even in a comment" \
  "$(grep -c 'firstPartyServiceFor("omarchy\.notifications")' "$service_qml" || true)" "0"
check "NotificationService.qml has no leftover source.popupModel read" \
  "$(grep -c 'source\.popupModel' "$service_qml" || true)" "0"
check "DashboardContent.qml has no leftover notificationService prop" \
  "$(grep -c 'property var notificationService' "$dashboard_qml" || true)" "0"

# --- DND: real on-disk state file, watched reactively -------------------

# "2" -- once in this migration's own explanatory comment, once in the
# real FileView path.
check "Overlay.qml watches the real Omarchy notifications settings file" \
  "$(grep -c '\.local/state/omarchy/notifications\.json' "$overlay_qml")" "2"
check "the DND FileView watches for live changes (an external toggle reflects immediately)" \
  "$(grep -A5 'id: dndStateFile' "$overlay_qml" | grep -c 'watchChanges: true')" "1"
check "DND is parsed from the real {version,dnd} shape, not guessed" \
  "$(grep -c 'parsed\.dnd === true' "$overlay_qml")" "1"
check "a load failure defaults dnd to false rather than leaving it stale" \
  "$(grep -c 'onLoadFailed: root\.dnd = false' "$overlay_qml")" "1"

# --- DND control: the real IPC target -----------------------------------

check "the collapsed bell toggles DND via the real IPC target" \
  "$(grep -c 'root\.sendDndAction("toggleDnd")' "$overlay_qml")" "1"
check "the dashboard card's own bell also toggles DND via the passthrough" \
  "$(grep -c 'root\.sendDndAction("toggleDnd")' "$dashboard_qml")" "1"
check "sendDndAction calls the real \"notifications\" IPC target, not a first-party service handle" \
  "$(grep -c 'command = \["omarchy-shell", "notifications", String(action)\]' "$overlay_qml")" "1"
check "DashboardContent.qml threads sendDndAction down instead of a raw service handle" \
  "$(grep -c 'property var sendDndAction: null' "$dashboard_qml")" "1"
check "Overlay.qml passes sendDndAction to DashboardContent" \
  "$(grep -c 'sendDndAction: root\.sendDndAction' "$overlay_qml")" "1"

# --- history/entries: real on-disk directories, swept on a timer --------

check "NotificationService.qml reads the real live-popup directory" \
  "$(grep -c 'omarchyStateDir: home + "/\.local/state/omarchy/notifications/"' "$service_qml")" "1"
check "NotificationService.qml reads the real history directory, derived from the live-popup one" \
  "$(grep -c 'historyDir: omarchyStateDir + "history/"' "$service_qml")" "1"
# shellcheck disable=SC2016 # deliberately literal: this is the exact,
# unexpanded $1/$2 bash-positional-parameter text grepped for inside the
# QML source below, not something meant to expand in this test script.
check "the sweep reads both directories in one pass" \
  "$(grep -cF 'awk 1 \"$1\"/*.json \"$2\"/*.json' "$service_qml")" "1"
check "the sweep runs on a recurring timer, not gated on a broken doNotDisturb read" \
  "$(grep -c 'onTriggered: service\.sweepNotifications()' "$service_qml")" "1"
check "the recurring sweep is gated on storeLoaded (not spawning processes before the store is ready)" \
  "$(grep -B6 'onTriggered: service\.sweepNotifications()' "$service_qml" | grep -c 'running: service\.storeLoaded')" "1"
check "no leftover doNotDisturb property on NotificationService.qml (DND now lives on Overlay.qml alone)" \
  "$(grep -c 'property.*doNotDisturb\|readonly property bool doNotDisturb' "$service_qml" || true)" "0"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
