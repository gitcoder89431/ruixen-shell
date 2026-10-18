#!/usr/bin/env bash
# Direct QA report: a user's bar and notch were stuck on Black/Mono no
# matter what they clicked in Ruixen Settings, after installing from a
# chroot (lots of commands run as root while repairing an unrelated
# boot issue). Traced through the actual save/load code: Settings
# writes its own in-memory property instantly either way, so the
# picker LOOKS like it responded, but a FileView.setText() against a
# file the real user can't write to (root-owned, from the chroot
# session) silently does nothing -- the bar/notch just keep re-reading
# whatever was last readable, forever. ruixen-doctor.sh had no check
# for this at all before this fix; this guards the new "-- Ruixen
# state directory --" section against regressing silently.
set -Eeuo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_dir="$(cd -- "$script_dir/.." && pwd)"
doctor_sh="$repo_dir/ruixen-doctor.sh"

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

# --- healthy: directory writable, both state files agree -------------
mkdir -p "$fake_home/.local/state/ruixen"
printf '{"version":1,"color":"theme","material":"glass"}\n' > "$fake_home/.local/state/ruixen/bar-surface.json"
printf '{"mode":"theme"}\n' > "$fake_home/.local/state/ruixen/frame-appearance.json"
out="$(HOME="$fake_home" bash "$doctor_sh" 2>&1)"

check "healthy: reports the directory as writable" \
  "$(printf '%s\n' "$out" | grep -c '^directory: writable')" "1"
check "healthy: reports every file as owned/writable" \
  "$(printf '%s\n' "$out" | grep -c 'all files under this directory: owned by')" "1"
check "healthy: bar-surface.json and frame-appearance.json reported as agreeing" \
  "$(printf '%s\n' "$out" | grep -c 'bar-surface.json / frame-appearance.json agree: theme')" "1"

# --- mismatch: a write that only landed in one of the two files ------
printf '{"version":1,"color":"black","material":"glass"}\n' > "$fake_home/.local/state/ruixen/bar-surface.json"
printf '{"mode":"theme"}\n' > "$fake_home/.local/state/ruixen/frame-appearance.json"
out="$(HOME="$fake_home" bash "$doctor_sh" 2>&1)"

check "mismatch: flagged with both values named, not silently ignored" \
  "$(printf '%s\n' "$out" | grep -c 'bar-surface.json (black) and frame-appearance.json (theme) DISAGREE')" "1"

# --- missing: nothing has ever written Ruixen state here -------------
fake_home2="$(mktemp -d)"
out2="$(HOME="$fake_home2" bash "$doctor_sh" 2>&1)"
rm -rf "$fake_home2"

check "missing directory: reported plainly, not as an error" \
  "$(printf '%s\n' "$out2" | grep -c 'directory: does not exist yet')" "1"

printf '\n%d passed, %d failed\n' "$pass" "$fail_count"
[[ "$fail_count" -eq 0 ]]
