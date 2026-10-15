#!/usr/bin/env bash
# Keep the ENTIRE GUI update alive when deployment reloads Settings, not
# just install.sh's final restart. Only this waiting relay belongs to QML.
set -Eeuo pipefail

repo_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
state_dir="$HOME/.local/state/ruixen"
mkdir -p "$state_dir"

# A reloaded Settings instance can click Update again while the first
# worker is still alive. Preserve its log; the normal lifecycle lock
# inside update.sh still protects against CLI install/update/uninstall.
exec 9>"$state_dir/settings-update.lock"
if ! flock -n 9; then
  echo 'A Settings update is already running; wait for it to finish.' >&2
  exit 1
fi

log_file="$state_dir/settings-update.log"
# New session AND independent stdio: losing the QML Process must neither
# kill the worker's process group nor give it SIGPIPE on its next print.
# shellcheck disable=SC2016 # $1 expands in the independent child shell.
setsid bash -c 'cd -- "$1" && exec ./update.sh --acknowledge-interrupted' \
  -- "$repo_dir" </dev/null >"$log_file" 2>&1 &
worker_pid=$!
status=0
wait "$worker_pid" || status=$?
if (( status != 0 )); then
  tail -n 20 "$log_file" >&2
fi
exit "$status"
