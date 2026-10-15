#!/usr/bin/env bash
# Exercise the GUI relay with a real detached worker, then destroy its
# launching process group BEFORE the fake install reaches its restart.
set -Eeuo pipefail
repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
checkout="$tmp/repo with a ' quote"
mkdir -p "$checkout/lib" "$tmp/home"
cp "$repo_dir/lib/settings-update.sh" "$checkout/lib/"
export HOME="$tmp/home"
cat >"$checkout/update.sh" <<'WORKER'
#!/usr/bin/env bash
set -Eeuo pipefail
[[ "$1" == --acknowledge-interrupted ]]
echo 'worker output before Settings reload'
touch "$HOME/started"
for ((i=0; i<200; i++)); do
  if [[ -e "$HOME/release" ]]; then
    echo 'restart and cleanup completed after Settings reload'
    touch "$HOME/completed"
    exit 0
  fi
  sleep 0.05
done
exit 1
WORKER
chmod +x "$checkout/update.sh"

wait_for() {
  local i
  for ((i=0; i<200; i++)); do
    [[ -e "$1" ]] && return 0
    sleep 0.05
  done
  echo "FAIL - timed out waiting for $1" >&2
  return 1
}

setsid bash "$checkout/lib/settings-update.sh" >"$tmp/relay.out" 2>&1 &
relay_pid=$!
wait_for "$HOME/started"
# A replacement Settings instance must not overwrite the active log.
if bash "$checkout/lib/settings-update.sh" >"$tmp/second.out" 2>&1; then
  echo 'FAIL - concurrent GUI update was accepted' >&2
  exit 1
fi
grep -q 'already running' "$tmp/second.out"
grep -q 'worker output before' "$HOME/.local/state/ruixen/settings-update.log"
echo 'ok - concurrent GUI update refused without truncating the worker log'

kill -TERM -- "-$relay_pid"
wait "$relay_pid" 2>/dev/null || true
touch "$HOME/release"
wait_for "$HOME/completed"
grep -q 'restart and cleanup completed' "$HOME/.local/state/ruixen/settings-update.log"
echo 'ok - worker survives losing its launching process group and output listener'

# A failure before reload must still reach the existing QML error handler.
cat >"$checkout/update.sh" <<'WORKER'
#!/usr/bin/env bash
echo 'simulated git pull failure' >&2
exit 23
WORKER
# The marker precedes worker exit by a few instructions; wait for its lock.
for ((i=0; i<200; i++)); do
  if flock -n "$HOME/.local/state/ruixen/settings-update.lock" true; then break; fi
  sleep 0.05
done
status=0
bash "$checkout/lib/settings-update.sh" >"$tmp/failure.out" 2>&1 || status=$?
[[ "$status" == 23 ]]
grep -q 'simulated git pull failure' "$tmp/failure.out"
grep -q 'simulated git pull failure' "$HOME/.local/state/ruixen/settings-update.log"
echo 'ok - worker exit status and failure output reach the GUI relay and persistent log'
