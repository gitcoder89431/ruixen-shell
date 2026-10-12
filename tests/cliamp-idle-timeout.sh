#!/usr/bin/env bash
# Cliamp (the local radio daemon the launcher's Cliamp Radio extension
# spawns detached) has no lifecycle of its own once started -- direct
# ask: "how does cliamp know when to terminate instead of staying on
# pause... after like 5 minutes if on pause it turns off." Fixed with a
# watchdog in ruixen.media/Service.qml (the one piece of this plugin
# that's always loaded, keepLoaded: true, regardless of any UI being
# open) rather than in the launcher extension itself, since that
# extension's own status polling stops the moment its view closes.
#
# Can't drive a real Quickshell instance or live MPRIS player here (no
# compositor in CI), so this is a static invariant check against the
# actual QML source, same style as tests/workspaces-pill-strict.sh's
# own pattern-based guards.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
service_qml="$repo_dir/bars/widgets/ruixen.media/Service.qml"

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

check "idle timeout is 5 minutes (300000ms)" \
  "$(grep -c 'readonly property int cliampIdleTimeoutMs: 300000' "$service_qml")" "1"

check "cliamp is matched by dbusName substring, not identity (no desktopEntry over D-Bus)" \
  "$(grep -c "dbus.indexOf(\"cliamp\") !== -1" "$service_qml")" "1"

check "the idle timer is driven off the real MPRIS Paused state, not isPlaying" \
  "$(grep -c 'p.playbackState === MprisPlaybackState.Paused' "$service_qml")" "2"

check "termination goes through MPRIS Quit (graceful), not a raw process kill" \
  "$(grep -c 'p.canQuit) p.quit()' "$service_qml")" "1"

check "the watchdog is wired off cliampPlayer changing, so an already-paused player on service startup is covered" \
  "$(grep -c 'onCliampPlayerChanged: root.syncCliampIdleTimer()' "$service_qml")" "1"

check "the watchdog also re-syncs on every playbackStateChanged signal from the matched player" \
  "$(grep -c 'function onPlaybackStateChanged() { root.syncCliampIdleTimer() }' "$service_qml")" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
